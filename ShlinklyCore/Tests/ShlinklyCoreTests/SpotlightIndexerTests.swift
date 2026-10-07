import Foundation
import Testing
@testable import ShlinklyCore

/// In-memory ``SearchableIndexing`` for tests: no real Spotlight, but it keeps
/// the entries and an ordered log of every call so write order can be asserted.
private final class FakeIndex: SearchableIndexing, @unchecked Sendable {
    enum Call: Equatable {
        case index([String])
        case deleteDomains([String])
        case deleteIdentifiers([String])
    }

    private let lock = NSLock()
    private var storedEntries: [String: SpotlightEntry] = [:]
    private var loggedCalls: [Call] = []

    var entries: [String: SpotlightEntry] { lock.withLock { storedEntries } }
    var calls: [Call] { lock.withLock { loggedCalls } }

    func index(_ entries: [SpotlightEntry]) async throws {
        lock.withLock {
            loggedCalls.append(.index(entries.map(\.uniqueIdentifier)))
            for entry in entries { storedEntries[entry.uniqueIdentifier] = entry }
        }
    }

    func deleteEntries(withDomainIdentifiers domainIdentifiers: [String]) async throws {
        lock.withLock {
            loggedCalls.append(.deleteDomains(domainIdentifiers))
            storedEntries = storedEntries.filter { !domainIdentifiers.contains($0.value.domainIdentifier) }
        }
    }

    func deleteEntries(withIdentifiers identifiers: [String]) async throws {
        lock.withLock {
            loggedCalls.append(.deleteIdentifiers(identifiers))
            for identifier in identifiers { storedEntries[identifier] = nil }
        }
    }
}

/// A settable clock, so the 24-hour rule can be crossed without waiting.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_700_000_000)

    var now: Date { lock.withLock { current } }
    func advance(by interval: TimeInterval) { lock.withLock { current += interval } }
}

private struct LoadFailure: Error {}

/// A throwaway `UserDefaults` suite so tests don't touch the real domain.
private func makeDefaults() -> UserDefaults {
    let suite = "shlinkly.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private func makeLink(
    _ shortCode: String,
    title: String? = nil,
    tags: [String] = [],
    domain: String? = nil
) -> ShortURL {
    ShortURL(
        shortCode: shortCode,
        shortUrl: "https://\(domain ?? "doma.in")/\(shortCode)",
        longUrl: "https://example.com/\(shortCode)",
        dateCreated: Date(timeIntervalSince1970: 0),
        title: title,
        tags: tags,
        domain: domain
    )
}

private func makeIndexer(
    index: FakeIndex = FakeIndex(),
    defaults: UserDefaults = makeDefaults(),
    clock: Clock = Clock()
) -> (SpotlightIndexer, FakeIndex, Clock) {
    (SpotlightIndexer(index: index, defaults: SendableDefaults(defaults), now: { clock.now }), index, clock)
}

struct SpotlightEntryTests {
    private let serverID = UUID()
    private let expiration = Date(timeIntervalSince1970: 42)

    @Test("A titled link uses its title and describes itself as short · long")
    func titledLink() {
        let link = makeLink("abc", title: "  Launch post ", tags: ["news", "2026"], domain: "go.example")
        let entry = SpotlightEntry(link: link, serverID: serverID, expirationDate: expiration)

        #expect(entry.uniqueIdentifier == "\(serverID.uuidString)/go.example/abc")
        #expect(entry.domainIdentifier == serverID.uuidString)
        #expect(entry.title == "Launch post")
        #expect(entry.contentDescription == "go.example/abc · https://example.com/abc")
        #expect(entry.keywords == ["news", "2026", "abc", "go.example"])
        #expect(entry.expirationDate == expiration)
    }

    @Test("An untitled link falls back to the scheme-less short URL and the long URL")
    func untitledLink() {
        for title in [nil, "", "   "] as [String?] {
            let entry = SpotlightEntry(link: makeLink("abc", title: title), serverID: serverID, expirationDate: expiration)
            #expect(entry.title == "doma.in/abc")
            #expect(entry.contentDescription == "https://example.com/abc")
        }
    }

    @Test("The default domain contributes no keyword and a DEFAULT id segment")
    func defaultDomain() {
        let entry = SpotlightEntry(link: makeLink("abc", tags: ["t"]), serverID: serverID, expirationDate: expiration)
        #expect(entry.keywords == ["t", "abc"])
        #expect(entry.uniqueIdentifier == "\(serverID.uuidString)/DEFAULT/abc")
    }
}

struct SpotlightIndexerTests {
    @Test("A full reindex loads first, then deletes the server's entries, then writes")
    func fullReindexOrder() async throws {
        let (indexer, index, clock) = makeIndexer()
        let serverID = UUID()
        let stale = makeLink("stale")
        await indexer.upsert(stale, serverID: serverID)

        try await indexer.fullReindex(serverID: serverID) {
            // Nothing has been deleted while the links are still loading.
            #expect(index.entries.count == 1)
            return [makeLink("a"), makeLink("b")]
        }

        let ids = ["a", "b"].map { "\(serverID.uuidString)/DEFAULT/\($0)" }
        #expect(index.calls.suffix(2) == [.deleteDomains([serverID.uuidString]), .index(ids)])
        #expect(Set(index.entries.keys) == Set(ids))
        #expect(index.entries.values.allSatisfy { $0.expirationDate == clock.now.addingTimeInterval(30 * 24 * 60 * 60) })
        #expect(await indexer.needsReindex(serverID: serverID) == false)
    }

    @Test("A failed load leaves the existing entries and the reindex time alone")
    func fullReindexFailureKeepsEntries() async {
        let (indexer, index, _) = makeIndexer()
        let serverID = UUID()
        await indexer.upsert(makeLink("kept"), serverID: serverID)

        await #expect(throws: LoadFailure.self) {
            try await indexer.fullReindex(serverID: serverID) { throw LoadFailure() }
        }

        #expect(index.entries.count == 1)
        #expect(await indexer.needsReindex(serverID: serverID))
    }

    @Test("A full reindex is due when never done, after 24 hours, or once invalidated")
    func reindexRule() async throws {
        let (indexer, _, clock) = makeIndexer()
        let serverID = UUID()
        #expect(await indexer.needsReindex(serverID: serverID))

        try await indexer.fullReindex(serverID: serverID) { [] }
        clock.advance(by: 23 * 60 * 60)
        #expect(await indexer.needsReindex(serverID: serverID) == false)
        clock.advance(by: 2 * 60 * 60)
        #expect(await indexer.needsReindex(serverID: serverID))

        try await indexer.fullReindex(serverID: serverID) { [] }
        #expect(await indexer.needsReindex(serverID: serverID) == false)
        await indexer.invalidate(serverID: serverID)
        #expect(await indexer.needsReindex(serverID: serverID))
    }

    @Test("Upsert writes one entry and remove deletes it by server + link id")
    func upsertAndRemove() async {
        let (indexer, index, _) = makeIndexer()
        let serverID = UUID()
        let link = makeLink("abc", domain: "go.example")

        await indexer.upsert(link, serverID: serverID)
        #expect(Array(index.entries.keys) == ["\(serverID.uuidString)/go.example/abc"])

        await indexer.remove(linkID: link.id, serverID: serverID)
        #expect(index.entries.isEmpty)
    }

    @Test("Removing a server drops its entries, its reindex time and its known-server record")
    func removeServer() async throws {
        let defaults = makeDefaults()
        let (indexer, index, _) = makeIndexer(defaults: defaults)
        let gone = UUID()
        let kept = UUID()
        try await indexer.fullReindex(serverID: gone) { [makeLink("a")] }
        try await indexer.fullReindex(serverID: kept) { [makeLink("b")] }

        await indexer.removeServer(gone)

        #expect(Array(index.entries.keys) == ["\(kept.uuidString)/DEFAULT/b"])
        #expect(await indexer.needsReindex(serverID: gone))
        #expect(await indexer.needsReindex(serverID: kept) == false)
        #expect(defaults.stringArray(forKey: "shlinkly.spotlight.knownServers") == [kept.uuidString])
    }

    @Test("Reconcile deletes the entries of servers that are no longer configured")
    func reconcile() async throws {
        let defaults = makeDefaults()
        let index = FakeIndex()
        let (indexer, _, _) = makeIndexer(index: index, defaults: defaults)
        let gone = UUID()
        let kept = UUID()
        await indexer.upsert(makeLink("a"), serverID: gone)
        try await indexer.fullReindex(serverID: kept) { [makeLink("b")] }

        // A fresh indexer over the same defaults: the known-server list persists.
        let (relaunched, _, _) = makeIndexer(index: index, defaults: defaults)
        await relaunched.reconcile(currentServerIDs: [kept])

        #expect(Array(index.entries.keys) == ["\(kept.uuidString)/DEFAULT/b"])
        #expect(defaults.stringArray(forKey: "shlinkly.spotlight.knownServers") == [kept.uuidString])
    }

    @Test("Sync fully reindexes a server that's due and only tops up one that isn't")
    func syncChoosesFullOrRecent() async throws {
        let (indexer, index, _) = makeIndexer()
        let fresh = UUID()
        let due = UUID()
        try await indexer.fullReindex(serverID: fresh) { [makeLink("old")] }

        let source: @Sendable (UUID) -> SpotlightIndexer.ServerSource = { id in
            .init(id: id, loadAll: { [makeLink("all")] }, loadRecent: { [makeLink("new")] })
        }
        await indexer.sync(sources: [source(fresh), source(due)], currentServerIDs: [fresh, due])

        // The fresh server keeps its old entry and gains the recent one…
        #expect(Set(index.entries.keys.filter { $0.hasPrefix(fresh.uuidString) })
            == ["\(fresh.uuidString)/DEFAULT/old", "\(fresh.uuidString)/DEFAULT/new"])
        // …the due server is rebuilt from the full load, with no top-up on top.
        #expect(index.entries.keys.filter { $0.hasPrefix(due.uuidString) } == ["\(due.uuidString)/DEFAULT/all"])
        #expect(await indexer.needsReindex(serverID: due) == false)
    }

    @Test("Sync carries on to the next server when one fails")
    func syncSurvivesFailure() async {
        let (indexer, index, _) = makeIndexer()
        let broken = UUID()
        let healthy = UUID()

        await indexer.sync(
            sources: [
                .init(id: broken, loadAll: { throw LoadFailure() }, loadRecent: { [] }),
                .init(id: healthy, loadAll: { [makeLink("ok")] }, loadRecent: { [] }),
            ],
            currentServerIDs: [broken, healthy]
        )

        #expect(Array(index.entries.keys) == ["\(healthy.uuidString)/DEFAULT/ok"])
        #expect(await indexer.needsReindex(serverID: broken))
    }

    @Test("The top-up is skipped for a server whose full reindex is in flight")
    func recentSkippedDuringFullReindex() async throws {
        let (indexer, index, _) = makeIndexer()
        let busy = UUID()
        let idle = UUID()

        try await indexer.fullReindex(serverID: busy) {
            // Mid-reindex (the actor is free while the load is awaited): the
            // busy server's top-up is refused, another server's goes through.
            let skipped = try await indexer.indexRecent(serverID: busy) { [makeLink("recent")] }
            let other = try await indexer.indexRecent(serverID: idle) { [makeLink("recent")] }
            #expect(skipped == false)
            #expect(other == true)
            return [makeLink("full")]
        }

        #expect(Set(index.entries.keys) == ["\(busy.uuidString)/DEFAULT/full", "\(idle.uuidString)/DEFAULT/recent"])

        // Once the reindex is over, the top-up runs again.
        #expect(try await indexer.indexRecent(serverID: busy) { [makeLink("recent")] })
        #expect(index.entries["\(busy.uuidString)/DEFAULT/recent"] != nil)
    }
}
