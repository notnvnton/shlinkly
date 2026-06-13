import Foundation
import Observation

/// Owns the user's configured servers: the list, which one is active, and the
/// split between non-secret details (`UserDefaults`) and the API keys
/// (Keychain). It performs no network work — ``AppModel`` turns the active
/// instance into a live client.
///
/// Persistence is eager: every mutation writes through immediately, so a crash
/// can't lose a just-added server.
@MainActor
@Observable
public final class InstanceStore {
    /// All configured servers, in the order they were added.
    public private(set) var instances: [ServerInstance]
    /// The id of the active server, or `nil` when none is configured.
    public private(set) var activeInstanceID: UUID?

    private let defaults: UserDefaults
    private let keychain: KeychainStoring

    private static let instancesKey = "shlinkly.instances"
    private static let activeIDKey = "shlinkly.activeInstanceID"

    /// - Parameters:
    ///   - defaults: Where non-secret instance details live. Injected for tests.
    ///   - keychain: Where API keys live. Injected for tests (a real
    ///     ``KeychainStore`` by default).
    public init(defaults: UserDefaults = .standard, keychain: KeychainStoring = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain

        if let data = defaults.data(forKey: Self.instancesKey),
           let decoded = try? JSONDecoder().decode([ServerInstance].self, from: data) {
            self.instances = decoded
        } else {
            self.instances = []
        }

        if let raw = defaults.string(forKey: Self.activeIDKey),
           let id = UUID(uuidString: raw),
           instances.contains(where: { $0.id == id }) {
            self.activeInstanceID = id
        } else {
            self.activeInstanceID = instances.first?.id
        }
    }

    // MARK: - Derived

    /// The active server, or `nil` when none is configured.
    public var activeInstance: ServerInstance? {
        instances.first { $0.id == activeInstanceID }
    }

    /// Whether there are no configured servers (drives onboarding).
    public var isEmpty: Bool { instances.isEmpty }

    /// Reads an instance's API key from the Keychain.
    public func apiKey(for id: UUID) -> String? {
        keychain.read(account: id.uuidString)
    }

    // MARK: - Mutations

    /// Adds a new server and stores its key. Becomes active if it's the first
    /// one. Throws (and persists nothing) if the key couldn't be saved, so the
    /// caller can surface the failure instead of leaving a keyless server behind.
    public func add(_ instance: ServerInstance, apiKey: String) throws {
        try saveKey(apiKey, for: instance)
        instances.append(instance)
        if activeInstanceID == nil { activeInstanceID = instance.id }
        persist()
    }

    /// Updates an existing server's details and rewrites its key (the rewrite
    /// also applies any `keyStorage` change, which can't be done in place).
    /// Throws (and persists nothing) if the key write failed.
    public func update(_ instance: ServerInstance, apiKey: String) throws {
        try saveKey(apiKey, for: instance)
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        } else {
            instances.append(instance)
        }
        persist()
    }

    /// Removes a server and its key. If the active server is removed, the first
    /// remaining one becomes active (or none if the list empties).
    public func remove(_ id: UUID) {
        try? keychain.delete(account: id.uuidString)
        instances.removeAll { $0.id == id }
        if activeInstanceID == id {
            activeInstanceID = instances.first?.id
        }
        persist()
    }

    /// Switches the active server. No-op for an unknown id.
    public func setActive(_ id: UUID) {
        guard instances.contains(where: { $0.id == id }) else { return }
        activeInstanceID = id
        persist()
    }

    // MARK: - Persistence

    private func saveKey(_ apiKey: String, for instance: ServerInstance) throws {
        try keychain.save(
            apiKey,
            account: instance.id.uuidString,
            synchronizable: instance.keyStorage == .iCloud
        )
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(instances) {
            defaults.set(data, forKey: Self.instancesKey)
        }
        if let activeInstanceID {
            defaults.set(activeInstanceID.uuidString, forKey: Self.activeIDKey)
        } else {
            defaults.removeObject(forKey: Self.activeIDKey)
        }
    }
}
