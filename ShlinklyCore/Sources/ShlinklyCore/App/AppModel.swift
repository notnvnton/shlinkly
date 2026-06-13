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

    /// The persisted servers + active selection. Exposed so Settings can list and
    /// edit them; mutate it through this model's methods so ``client`` stays in
    /// sync.
    public let instanceStore: InstanceStore

    /// App-wide preferences (the delete-confirmation switches).
    public let preferences: AppPreferences

    /// Session used for every client this model vends. Injected for testability.
    private let urlSession: URLSession

    public init(
        instanceStore: InstanceStore = InstanceStore(),
        preferences: AppPreferences = AppPreferences(),
        urlSession: URLSession = .shared
    ) {
        self.instanceStore = instanceStore
        self.preferences = preferences
        self.urlSession = urlSession
    }

    /// True when there are no configured servers — the app should onboard.
    public var needsOnboarding: Bool { instanceStore.isEmpty }

    /// Loads the active server from the store and brings its client online.
    /// Call once at launch. When no server is configured (or its key can't be
    /// read) the app stays deactivated and onboarding takes over.
    public func bootstrap() {
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
        client = ShlinkClient(baseURL: instance.restRoot, apiKey: apiKey, urlSession: urlSession)
    }

    /// Clears the active server and tears down the client.
    public func deactivate() {
        activeInstance = nil
        client = nil
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
        guard wasActive else { return }
        if let instance = instanceStore.activeInstance,
           let key = instanceStore.apiKey(for: instance.id) {
            activate(instance, apiKey: key)
        } else {
            deactivate()
        }
    }
}
