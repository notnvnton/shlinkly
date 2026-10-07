import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import os

/// One short URL as it appears in the system search index: a plain, `Sendable`
/// snapshot of everything Spotlight is told about a link. Built by
/// ``SpotlightEntry/init(link:serverID:expirationDate:)`` and turned into a
/// `CSSearchableItem` only at the very edge (``SystemSearchableIndex``), so the
/// mapping rules can be tested without touching the real index.
struct SpotlightEntry: Sendable, Equatable {
    /// `"{server UUID}/{link id}"` — unique across servers, since a link's own
    /// id (domain + short code) is only unique within one server.
    let uniqueIdentifier: String
    /// The owning server's UUID string, so a whole server can be dropped at once.
    let domainIdentifier: String
    let title: String
    let contentDescription: String
    let keywords: [String]
    let expirationDate: Date

    init(link: ShortURL, serverID: UUID, expirationDate: Date) {
        let shortDisplay = Self.strippingScheme(link.shortUrl)
        let linkTitle = link.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.uniqueIdentifier = Self.uniqueIdentifier(linkID: link.id, serverID: serverID)
        self.domainIdentifier = serverID.uuidString
        let longDisplay = Self.strippingScheme(link.longUrl)
        if linkTitle.isEmpty {
            self.title = shortDisplay
            self.contentDescription = longDisplay
        } else {
            self.title = linkTitle
            self.contentDescription = "\(shortDisplay) · \(longDisplay)"
        }
        var keywords = link.tags
        keywords.append(link.shortCode)
        if let domain = link.domain { keywords.append(domain) }
        self.keywords = keywords
        self.expirationDate = expirationDate
    }

    static func uniqueIdentifier(linkID: String, serverID: UUID) -> String {
        "\(serverID.uuidString)/\(linkID)"
    }

    /// `https://doma.in/abc` → `doma.in/abc`. Anything without a scheme is
    /// returned untouched.
    static func strippingScheme(_ url: String) -> String {
        guard let range = url.range(of: "://") else { return url }
        return String(url[range.upperBound...])
    }
}

/// A Spotlight entry's unique identifier taken apart again: which server the
/// link lives on and how to ask that server for it. The inverse of
/// ``SpotlightEntry/uniqueIdentifier(linkID:serverID:)``.
struct SpotlightLinkReference: Sendable, Equatable {
    let serverID: UUID
    /// The link's domain, or `nil` for the server's default domain.
    let domain: String?
    let shortCode: String

    /// The link's ``ShortURL/id`` — the part of the identifier after the server.
    var linkID: String { ShortURL.identity(shortCode: shortCode, domain: domain) }

    init(serverID: UUID, domain: String?, shortCode: String) {
        self.serverID = serverID
        self.domain = domain
        self.shortCode = shortCode
    }

    /// Parses `"{server UUID}/{domain or DEFAULT}/{shortCode}"`. Only the first
    /// two slashes separate parts, so a multi-segment short code survives
    /// intact. Returns `nil` for anything malformed: a missing or empty part,
    /// or a server segment that isn't a UUID.
    init?(uniqueIdentifier: String) {
        let parts = uniqueIdentifier.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let serverID = UUID(uuidString: String(parts[0])),
              !parts[1].isEmpty,
              !parts[2].isEmpty else {
            return nil
        }
        self.serverID = serverID
        self.domain = parts[1] == "DEFAULT" ? nil : String(parts[1])
        self.shortCode = String(parts[2])
    }
}

/// The slice of `CSSearchableIndex` the indexer needs. A seam for tests: the
/// app uses ``SystemSearchableIndex``, tests substitute an in-memory fake.
protocol SearchableIndexing: Sendable {
    func index(_ entries: [SpotlightEntry]) async throws
    func deleteEntries(withDomainIdentifiers domainIdentifiers: [String]) async throws
    func deleteEntries(withIdentifiers identifiers: [String]) async throws
}

/// The real thing: the app's default Core Spotlight index.
struct SystemSearchableIndex: SearchableIndexing {
    func index(_ entries: [SpotlightEntry]) async throws {
        guard !entries.isEmpty else { return }
        let items = entries.map { entry in
            let attributes = CSSearchableItemAttributeSet(contentType: .url)
            attributes.title = entry.title
            attributes.contentDescription = entry.contentDescription
            attributes.keywords = entry.keywords
            let item = CSSearchableItem(
                uniqueIdentifier: entry.uniqueIdentifier,
                domainIdentifier: entry.domainIdentifier,
                attributeSet: attributes
            )
            item.expirationDate = entry.expirationDate
            return item
        }
        try await CSSearchableIndex.default().indexSearchableItems(items)
    }

    func deleteEntries(withDomainIdentifiers domainIdentifiers: [String]) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: domainIdentifiers)
    }

    func deleteEntries(withIdentifiers identifiers: [String]) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers)
    }
}

/// Carries a `UserDefaults` into the indexer's isolation. `UserDefaults` is
/// documented as thread-safe but isn't declared `Sendable`, hence the box.
struct SendableDefaults: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}

/// Mirrors the short URLs of every configured server into the system search
/// index (classic Core Spotlight) and keeps that mirror in step.
///
/// Each link is one entry, grouped per server through the entry's domain
/// identifier, so a server can be rebuilt or dropped wholesale. Two bits of
/// bookkeeping live in `UserDefaults`: when each server was last fully
/// reindexed, and which servers have anything in the index at all (so entries
/// of a server that vanished — e.g. removed on another device — can be found
/// and deleted).
///
/// Only the main app drives this, and only while it is open: there are no
/// background tasks. An `actor`, so the network walks and index writes it
/// awaits stay off the main actor.
public actor SpotlightIndexer {
    /// A server is fully reindexed when its last full reindex is older than this.
    static let reindexInterval: TimeInterval = 24 * 60 * 60
    /// How long an entry lives without being rewritten. Set explicitly rather
    /// than relying on the system default.
    static let entryLifetime: TimeInterval = 30 * 24 * 60 * 60
    /// Page size of the light top-up — the same page the list screen loads.
    static let recentPageSize = 30

    private static let lastReindexKey = "shlinkly.spotlight.lastReindex"
    private static let knownServersKey = "shlinkly.spotlight.knownServers"

    /// Every message starts with "Spotlight:" so the Xcode console filter finds
    /// the whole lifecycle. Servers appear only as ``shortID(_:)``; link texts
    /// are never logged.
    static let log = Logger(subsystem: "de.ahodge.shlinkly", category: "Spotlight")

    /// Whether the system says this device can index at all.
    public nonisolated static var isIndexingAvailable: Bool {
        CSSearchableIndex.isIndexingAvailable()
    }

    /// The activity type the system hands the app when a search result is
    /// tapped (`CSSearchableItemActionType`), re-exported so the app layer can
    /// subscribe without importing Core Spotlight.
    public nonisolated static var searchResultActivityType: String { CSSearchableItemActionType }

    /// Pulls the tapped entry's unique identifier out of a search-result
    /// activity, or `nil` (logged) when the activity isn't one or carries none.
    public nonisolated static func tappedIdentifier(from activity: NSUserActivity) -> String? {
        guard activity.activityType == CSSearchableItemActionType else { return nil }
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            log.error("Spotlight: tap received without an entry identifier")
            return nil
        }
        log.notice("Spotlight: tap received")
        return identifier
    }

    /// The first 8 characters of a server's UUID — how servers are named in the
    /// log, instead of their name or address.
    nonisolated static func shortID(_ serverID: UUID) -> String {
        String(serverID.uuidString.prefix(8))
    }

    /// What ``sync(sources:currentServerIDs:)`` needs to know about a server:
    /// its id and how to load its links. Closures rather than a client so tests
    /// can feed links without a network.
    struct ServerSource: Sendable {
        let id: UUID
        /// Every link on the server.
        let loadAll: @Sendable () async throws -> [ShortURL]
        /// The newest page of links only.
        let loadRecent: @Sendable () async throws -> [ShortURL]
    }

    private let index: SearchableIndexing
    private let defaults: SendableDefaults
    private let now: @Sendable () -> Date
    /// Servers with a full reindex in flight; their top-up is skipped meanwhile.
    private var reindexing: Set<UUID> = []

    /// - Parameter defaults: Where the bookkeeping lives. Injected for tests.
    public init(defaults: sending UserDefaults = .standard) {
        self.init(index: SystemSearchableIndex(), defaults: SendableDefaults(defaults))
    }

    init(
        index: SearchableIndexing,
        defaults: SendableDefaults,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.index = index
        self.defaults = defaults
        self.now = now
    }

    // MARK: - Sync

    /// One full pass: ``reconcile(currentServerIDs:)``, then each server in
    /// turn — a full reindex when it's due (see ``needsReindex(serverID:)``),
    /// otherwise a top-up of its newest links. A server's failure is logged and
    /// the pass moves on. Stops early if the surrounding task is cancelled.
    ///
    /// - Parameters:
    ///   - servers: Every server that has an API key, with a client for it.
    ///   - currentServerIDs: Every configured server, keyed or not.
    public func sync(servers: [(id: UUID, client: ShlinkClient)], currentServerIDs: [UUID]) async {
        let pageSize = Self.recentPageSize
        let sources = servers.map { server in
            ServerSource(
                id: server.id,
                loadAll: { try await server.client.allShortURLs() },
                loadRecent: {
                    try await server.client.shortURLs(page: 1, itemsPerPage: pageSize, orderBy: .newest).data
                }
            )
        }
        await sync(sources: sources, currentServerIDs: currentServerIDs)
    }

    func sync(sources: [ServerSource], currentServerIDs: [UUID]) async {
        await reconcile(currentServerIDs: currentServerIDs)
        for source in sources {
            let server = Self.shortID(source.id)
            guard !Task.isCancelled else {
                Self.log.notice("Spotlight: server \(server, privacy: .public): skipped — sync was cancelled")
                return
            }
            let last = lastReindex(for: source.id)
            let lastText = last.map { $0.formatted(.iso8601) } ?? "never"
            // Failures are logged where they happen (inside the two calls), so
            // the pass just moves on to the next server.
            if needsReindex(serverID: source.id) {
                let reason = last == nil ? "never reindexed" : "last full reindex is over 24h old"
                Self.log.notice("Spotlight: server \(server, privacy: .public): full reindex — \(reason, privacy: .public) (last: \(lastText, privacy: .public))")
                try? await fullReindex(serverID: source.id, load: source.loadAll)
            } else {
                Self.log.notice("Spotlight: server \(server, privacy: .public): top-up — full reindex is fresh (last: \(lastText, privacy: .public))")
                _ = try? await indexRecent(serverID: source.id, load: source.loadRecent)
            }
        }
        Self.log.notice("Spotlight: sync finished")
    }

    // MARK: - Per-server

    /// Rebuilds a server's entries from scratch: loads every link first, and
    /// only then deletes the server's old entries and writes the new ones — so
    /// search results don't go empty for the duration of the download, and a
    /// failed download leaves the existing entries alone. Records the time on
    /// success.
    public func fullReindex(serverID: UUID, client: ShlinkClient) async throws {
        try await fullReindex(serverID: serverID, load: { try await client.allShortURLs() })
    }

    func fullReindex(serverID: UUID, load: @Sendable () async throws -> [ShortURL]) async throws {
        reindexing.insert(serverID)
        defer { reindexing.remove(serverID) }

        let server = Self.shortID(serverID)
        do {
            let links = try await load()
            Self.log.notice("Spotlight: server \(server, privacy: .public): full reindex loaded \(links.count, privacy: .public) links")
            try Task.checkCancellation()
            let expiration = now().addingTimeInterval(Self.entryLifetime)
            let entries = links.map { SpotlightEntry(link: $0, serverID: serverID, expirationDate: expiration) }

            try await index.deleteEntries(withDomainIdentifiers: [serverID.uuidString])
            Self.log.notice("Spotlight: server \(server, privacy: .public): full reindex deleted the server's old entries")
            markKnown(serverID)
            try await index.index(entries)
            setLastReindex(now(), for: serverID)
            Self.log.notice("Spotlight: server \(server, privacy: .public): full reindex wrote \(entries.count, privacy: .public) entries")
        } catch {
            Self.log.error("Spotlight: server \(server, privacy: .public): full reindex failed — \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// The light top-up between full reindexes: upserts the server's newest
    /// page of links, so one created outside the app's own client (a Share
    /// Extension, a shortcut, another device) is searchable after the next
    /// sync instead of after the next full reindex. Skipped — returning
    /// `false` — while that server's full reindex is in flight.
    @discardableResult
    func indexRecent(serverID: UUID, load: @Sendable () async throws -> [ShortURL]) async throws -> Bool {
        let server = Self.shortID(serverID)
        guard !reindexing.contains(serverID) else {
            Self.log.notice("Spotlight: server \(server, privacy: .public): top-up skipped — full reindex in flight")
            return false
        }
        do {
            let links = try await load()
            // The reindex may have started while the page was loading.
            guard !reindexing.contains(serverID) else {
                Self.log.notice("Spotlight: server \(server, privacy: .public): top-up skipped — full reindex in flight (got \(links.count, privacy: .public) links)")
                return false
            }
            let expiration = now().addingTimeInterval(Self.entryLifetime)
            markKnown(serverID)
            try await index.index(links.map { SpotlightEntry(link: $0, serverID: serverID, expirationDate: expiration) })
            Self.log.notice("Spotlight: server \(server, privacy: .public): top-up got \(links.count, privacy: .public) links, wrote \(links.count, privacy: .public) entries")
            return true
        } catch {
            Self.log.error("Spotlight: server \(server, privacy: .public): top-up failed — \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    // MARK: - Point updates

    /// Adds or replaces one link's entry. Best-effort: a failure is logged.
    public func upsert(_ link: ShortURL, serverID: UUID) async {
        let entry = SpotlightEntry(
            link: link,
            serverID: serverID,
            expirationDate: now().addingTimeInterval(Self.entryLifetime)
        )
        markKnown(serverID)
        let server = Self.shortID(serverID)
        do {
            try await index.index([entry])
            Self.log.notice("Spotlight: server \(server, privacy: .public): upsert of 1 entry succeeded")
        } catch {
            Self.log.error("Spotlight: server \(server, privacy: .public): upsert failed — \(String(describing: error), privacy: .public)")
        }
    }

    /// Removes one link's entry, identified by the link's ``ShortURL/id``.
    /// Best-effort: a failure is logged.
    public func remove(linkID: String, serverID: UUID) async {
        let identifier = SpotlightEntry.uniqueIdentifier(linkID: linkID, serverID: serverID)
        let server = Self.shortID(serverID)
        do {
            try await index.deleteEntries(withIdentifiers: [identifier])
            Self.log.notice("Spotlight: server \(server, privacy: .public): remove of 1 entry succeeded")
        } catch {
            Self.log.error("Spotlight: server \(server, privacy: .public): remove failed — \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Servers

    /// Drops everything indexed for a server and forgets it: its entries, its
    /// last-reindex time and its place in the known-servers list. If deleting
    /// the entries fails the server stays known, so the next
    /// ``reconcile(currentServerIDs:)`` retries.
    public func removeServer(_ serverID: UUID) async {
        setLastReindex(nil, for: serverID)
        do {
            try await index.deleteEntries(withDomainIdentifiers: [serverID.uuidString])
            var known = knownServers
            known.remove(serverID.uuidString)
            knownServers = known
            Self.log.notice("Spotlight: server \(Self.shortID(serverID), privacy: .public): removed from the index")
        } catch {
            Self.log.error("Spotlight: server \(Self.shortID(serverID), privacy: .public): removing from the index failed — \(String(describing: error), privacy: .public)")
        }
    }

    /// Deletes the entries of every server that has something indexed but is no
    /// longer configured.
    public func reconcile(currentServerIDs: [UUID]) async {
        let current = Set(currentServerIDs.map(\.uuidString))
        let staleServers = knownServers.subtracting(current).sorted()
        if staleServers.isEmpty {
            Self.log.notice("Spotlight: reconcile — no stale servers (\(self.knownServers.count, privacy: .public) known)")
        } else {
            let names = staleServers.map { String($0.prefix(8)) }.joined(separator: ", ")
            Self.log.notice("Spotlight: reconcile — removing \(staleServers.count, privacy: .public) stale server(s): \(names, privacy: .public)")
        }
        for stale in staleServers {
            guard let id = UUID(uuidString: stale) else {
                var known = knownServers
                known.remove(stale)
                knownServers = known
                continue
            }
            await removeServer(id)
        }
    }

    /// Forgets when a server was last fully reindexed, so it's rebuilt on the
    /// next sync. Used after the server's details were edited.
    public func invalidate(serverID: UUID) {
        setLastReindex(nil, for: serverID)
    }

    /// Whether a server is due a full reindex: never done, or last done more
    /// than ``reindexInterval`` ago.
    public func needsReindex(serverID: UUID) -> Bool {
        guard let last = lastReindex(for: serverID) else { return true }
        return now().timeIntervalSince(last) > Self.reindexInterval
    }

    // MARK: - Bookkeeping

    private func lastReindex(for serverID: UUID) -> Date? {
        let stored = defaults.value.dictionary(forKey: Self.lastReindexKey) as? [String: Double]
        return stored?[serverID.uuidString].map(Date.init(timeIntervalSince1970:))
    }

    private func setLastReindex(_ date: Date?, for serverID: UUID) {
        var stored = defaults.value.dictionary(forKey: Self.lastReindexKey) as? [String: Double] ?? [:]
        stored[serverID.uuidString] = date?.timeIntervalSince1970
        defaults.value.set(stored, forKey: Self.lastReindexKey)
    }

    /// UUID strings of the servers something has been indexed for.
    private var knownServers: Set<String> {
        get { Set(defaults.value.stringArray(forKey: Self.knownServersKey) ?? []) }
        set { defaults.value.set(newValue.sorted(), forKey: Self.knownServersKey) }
    }

    private func markKnown(_ serverID: UUID) {
        var known = knownServers
        if known.insert(serverID.uuidString).inserted {
            knownServers = known
        }
    }
}
