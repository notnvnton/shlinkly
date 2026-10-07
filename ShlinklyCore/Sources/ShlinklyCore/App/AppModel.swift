import Foundation
import Observation

/// Top-level application state: which Shlink server is active, and a client
/// configured to talk to it.
///
/// Consumers depend only on ``activeInstance`` and ``client``. *How* the active
/// server and its API key are sourced is hidden behind ``activate(_:apiKey:)`` —
/// the single seam through which credentials enter the app. Server management
/// (add / edit / select / remove) and persistence live in ``instanceStore``;
/// the management methods here keep that store and the live ``client`` in sync,
/// always routing the actual client (re)build through the same seam.
@MainActor
@Observable
public final class AppModel {
    /// The server currently in use, or `nil` when none is configured.
    public private(set) var activeInstance: ServerInstance?

    /// A client wired to ``activeInstance``, or `nil` when none is configured.
    /// Rebuilt whenever the active server changes.
    public private(set) var client: ShlinkClient?

    /// A deep link awaiting navigation. The scene's `onOpenURL` parses an
    /// incoming `shlinkly://` URL and sets it here; the active navigation shell
    /// observes it, resolves the target (list cache or a fetch), navigates, and
    /// clears it. Lives on this `@MainActor` model — the one object both the URL
    /// handler and the navigation shell share — so neither needs to know the other.
    public var pendingDeepLink: DeepLink?

    /// A create-form request awaiting presentation, parked the same way as
    /// ``pendingDeepLink`` but consumed by the list screen (which owns the form
    /// sheet) rather than the navigation shell. `true` asks for the clipboard
    /// prefill; the pasteboard read itself happens there, on the main app, when
    /// the form is opened.
    public var pendingCreate: PendingCreate?

    /// A parked request to open the create form. A struct rather than a `Bool?`
    /// so repeated identical requests (two taps on the same widget button) are
    /// distinct values and each one re-triggers the sheet.
    public struct PendingCreate: Equatable, Sendable, Identifiable {
        public let id = UUID()
        /// Whether to prefill the form from the pasteboard.
        public let fromClipboard: Bool

        public init(fromClipboard: Bool) {
            self.fromClipboard = fromClipboard
        }
    }

    /// The persisted servers + active selection. Exposed so Settings can list and
    /// edit them; mutate it through this model's methods so ``client`` stays in
    /// sync.
    public let instanceStore: InstanceStore

    /// App-wide preferences (the delete-confirmation switches).
    public let preferences: AppPreferences

    /// Session used for every client this model vends. Injected for testability.
    private let urlSession: URLSession

    /// Keeps the system search index in step with the servers' links, or `nil`
    /// to leave Spotlight alone. Only this model — i.e. the main app — ever
    /// drives it; the Share Extensions and the widget don't build an ``AppModel``.
    private let spotlight: SpotlightIndexer?

    /// The Spotlight sync in flight, if any. At most one runs at a time: a
    /// trigger that arrives while it's set is dropped.
    private var spotlightSyncTask: Task<Void, Never>?

    public init(
        instanceStore: InstanceStore = InstanceStore(),
        preferences: AppPreferences = AppPreferences(),
        urlSession: URLSession = .shared,
        spotlight: SpotlightIndexer? = SpotlightIndexer()
    ) {
        self.instanceStore = instanceStore
        self.preferences = preferences
        self.urlSession = urlSession
        self.spotlight = spotlight
    }

    /// True when there are no configured servers — the app should onboard.
    public var needsOnboarding: Bool { instanceStore.isEmpty }

    /// Loads the active server from the store and brings its client online.
    /// Call once at launch. When no server is configured (or its key can't be
    /// read) the app stays deactivated and onboarding takes over.
    public func bootstrap() {
        // The servers are loaded by now, whichever way activation goes below.
        defer { syncSpotlight() }
        guard let active = instanceStore.activeInstance,
              let key = instanceStore.apiKey(for: active.id) else {
            deactivate()
            return
        }
        activate(active, apiKey: key)
    }

    /// Makes `instance` the active server and (re)builds ``client`` with the
    /// given key. The single seam through which credentials enter the app; the
    /// client talks to the instance's ``ServerInstance/restRoot``.
    public func activate(_ instance: ServerInstance, apiKey: String) {
        activeInstance = instance
        client = ShlinkClient(
            baseURL: instance.restRoot,
            apiKey: apiKey,
            urlSession: urlSession,
            mutationObserver: spotlightObserver(for: instance.id)
        )
    }

    /// Clears the active server and tears down the client.
    public func deactivate() {
        activeInstance = nil
        client = nil
    }

    /// Re-reads the Keychain-backed store (the source of truth) and brings any
    /// newly-appeared server online. Call at scene activation: a server added with
    /// iCloud sync on another device shows up the next time the app becomes
    /// active. The current session is left untouched while its server is still
    /// present, so a refresh never yanks an in-use server out from under the UI;
    /// it only (re)activates when there's nothing live yet, or the active server
    /// vanished (e.g. it was removed on another device).
    public func refreshFromStore() {
        instanceStore.reload()
        let activeStillPresent = activeInstance.map { current in
            instanceStore.instances.contains { $0.id == current.id }
        } ?? false
        if !activeStillPresent {
            bootstrap()
        }
        syncSpotlight()
    }

    // MARK: - Spotlight

    /// Brings the Spotlight index up to date in the background: drops servers
    /// that are gone, then walks every server that has an API key — a full
    /// reindex when its last one is over a day old (or never happened),
    /// otherwise a light top-up of its newest links. Low priority, never blocks
    /// the UI, failures only reach the log. A no-op while a sync is running.
    public func syncSpotlight() {
        guard let spotlight, spotlightSyncTask == nil else { return }
        let currentServerIDs = instanceStore.instances.map(\.id)
        let session = urlSession
        let servers: [(id: UUID, client: ShlinkClient)] = instanceStore.instances.compactMap { instance in
            guard let key = instanceStore.apiKey(for: instance.id), !key.isEmpty else { return nil }
            // A private client with no mutation observer: reads only.
            return (instance.id, ShlinkClient(baseURL: instance.restRoot, apiKey: key, urlSession: session))
        }
        spotlightSyncTask = Task(priority: .utility) { [weak self] in
            await spotlight.sync(servers: servers, currentServerIDs: currentServerIDs)
            self?.spotlightSyncTask = nil
        }
    }

    /// The observer handed to the live client so links created, edited or
    /// deleted through it reach Spotlight straight away. Each callback only
    /// spawns a detached-from-the-result task: indexing can't fail the write.
    private func spotlightObserver(for serverID: UUID) -> ShortURLMutationObserver? {
        guard let spotlight else { return nil }
        return ShortURLMutationObserver(
            didSave: { link in
                Task(priority: .utility) { await spotlight.upsert(link, serverID: serverID) }
            },
            didDelete: { shortCode, domain in
                let linkID = ShortURL.identity(shortCode: shortCode, domain: domain)
                Task(priority: .utility) { await spotlight.remove(linkID: linkID, serverID: serverID) }
            }
        )
    }

    // MARK: - Server management

    /// Adds a server. The first one becomes active and comes online (leaving
    /// onboarding); a server added alongside others is left for the user to
    /// switch to deliberately, so the current session isn't disrupted.
    public func addInstance(_ instance: ServerInstance, apiKey: String) throws {
        let hadActiveServer = activeInstance != nil
        try instanceStore.add(instance, apiKey: apiKey)
        if !hadActiveServer {
            activate(instance, apiKey: apiKey)
        }
    }

    /// Saves edits to a server. If the edited server is the active one, its
    /// client is rebuilt (URL or key may have changed). Throws (changing nothing
    /// live) if the key couldn't be written.
    public func updateInstance(_ instance: ServerInstance, apiKey: String) throws {
        try instanceStore.update(instance, apiKey: apiKey)
        if instance.id == activeInstance?.id {
            activate(instance, apiKey: apiKey)
        }
        // URL or key may have changed: forget the last reindex so the next
        // activation rebuilds this server's entries from scratch.
        if let spotlight {
            Task(priority: .utility) { await spotlight.invalidate(serverID: instance.id) }
        }
    }

    /// Switches the active server and rebuilds the client for it.
    public func selectInstance(_ id: UUID) {
        guard id != activeInstance?.id else { return }
        instanceStore.setActive(id)
        guard let instance = instanceStore.activeInstance,
              let key = instanceStore.apiKey(for: instance.id) else {
            deactivate()
            return
        }
        activate(instance, apiKey: key)
    }

    /// Removes a server. If it was active, falls back to whichever server the
    /// store promotes (or deactivates into onboarding when none remain).
    public func removeInstance(_ id: UUID) {
        let wasActive = id == activeInstance?.id
        instanceStore.remove(id)
        if let spotlight {
            Task(priority: .utility) { await spotlight.removeServer(id) }
        }
        guard wasActive else { return }
        if let instance = instanceStore.activeInstance,
           let key = instanceStore.apiKey(for: instance.id) {
            activate(instance, apiKey: key)
        } else {
            deactivate()
        }
    }
}
