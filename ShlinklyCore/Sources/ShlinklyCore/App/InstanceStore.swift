import Foundation
import Observation

/// Owns the user's configured servers: the list, which one is active, and the
/// API keys. The **Keychain is the single source of truth** for the servers —
/// each server is one Keychain item carrying both the key and the non-secret
/// metadata (id, name, URL, storage). iCloud-stored servers therefore sync in
/// full across the user's devices, not just their keys. It performs no network
/// work — ``AppModel`` turns the active instance into a live client.
///
/// The *active selection* is a per-device choice, so it stays in `UserDefaults`
/// rather than syncing. The list itself is never cached locally; it's rebuilt
/// from the Keychain on init and via ``reload()`` (e.g. at scene activation), so
/// a server added on another device appears on the next activation.
///
/// Persistence is eager: every mutation writes through immediately, so a crash
/// can't lose a just-added server.
@MainActor
@Observable
public final class InstanceStore {
    /// All configured servers, in insertion order.
    public private(set) var instances: [ServerInstance]
    /// The id of the active server, or `nil` when none is configured.
    public private(set) var activeInstanceID: UUID?

    private let defaults: UserDefaults
    private let keychain: KeychainStoring
    /// Insertion timestamps per instance, carried in each Keychain record's
    /// metadata so the list keeps a stable order across reloads and devices. Kept
    /// out of ``ServerInstance`` so the model the rest of the app sees stays lean.
    private var addedAt: [UUID: Date] = [:]

    private static let activeIDKey = "shlinkly.activeInstanceID"

    /// - Parameters:
    ///   - defaults: Where the per-device active selection lives. Injected for tests.
    ///   - keychain: Where servers (key + metadata) live. Injected for tests (a
    ///     real ``KeychainStore`` by default).
    public init(defaults: UserDefaults = .standard, keychain: KeychainStoring = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        self.instances = []
        self.activeInstanceID = nil
        reload()
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
        keychain.readSecret(account: id.uuidString)
    }

    // MARK: - Source of truth

    /// Rebuilds the in-memory list from the Keychain (authoritative). Run at init
    /// and on scene activation so a server added — with iCloud sync — on another
    /// device shows up here. iCloud Keychain has no live change notification, so
    /// "appears on the next activation" is the intended, accepted behaviour.
    ///
    /// The active selection is re-resolved against the rebuilt list: a stored
    /// per-device choice is honoured when its server still exists, otherwise the
    /// first server is used (or none when the list is empty).
    public func reload() {
        let decoder = JSONDecoder()
        var decoded: [(instance: ServerInstance, addedAt: Date)] = []
        for record in keychain.allRecords() {
            guard let meta = try? decoder.decode(StoredMetadata.self, from: record.metadata) else { continue }
            decoded.append((meta.instance, meta.addedAt))
        }
        decoded.sort { lhs, rhs in
            lhs.addedAt != rhs.addedAt
                ? lhs.addedAt < rhs.addedAt
                : lhs.instance.id.uuidString < rhs.instance.id.uuidString
        }

        instances = decoded.map(\.instance)
        addedAt = Dictionary(decoded.map { ($0.instance.id, $0.addedAt) }, uniquingKeysWith: { first, _ in first })

        if let raw = defaults.string(forKey: Self.activeIDKey),
           let id = UUID(uuidString: raw),
           instances.contains(where: { $0.id == id }) {
            activeInstanceID = id
        } else {
            activeInstanceID = instances.first?.id
        }
    }

    // MARK: - Mutations

    /// Adds a new server and stores it. Becomes active if it's the first one.
    /// Throws (and persists nothing) if the Keychain write fails, so the caller
    /// can surface the failure instead of leaving a keyless server behind.
    public func add(_ instance: ServerInstance, apiKey: String) throws {
        let now = Date()
        try writeRecord(instance, apiKey: apiKey, addedAt: now)
        addedAt[instance.id] = now
        instances.append(instance)
        if activeInstanceID == nil { activeInstanceID = instance.id }
        persistActiveID()
    }

    /// Updates an existing server's details and rewrites its record (the rewrite
    /// also applies any `keyStorage` change, which can't be done in place — it
    /// flips the item's `synchronizable` attribute). Preserves the server's place
    /// in the list. Throws (and persists nothing) if the write failed.
    public func update(_ instance: ServerInstance, apiKey: String) throws {
        let when = addedAt[instance.id] ?? Date()
        try writeRecord(instance, apiKey: apiKey, addedAt: when)
        addedAt[instance.id] = when
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        } else {
            instances.append(instance)
        }
    }

    /// Removes a server and its Keychain record. If the active server is removed,
    /// the first remaining one becomes active (or none if the list empties).
    public func remove(_ id: UUID) {
        try? keychain.delete(account: id.uuidString)
        addedAt[id] = nil
        instances.removeAll { $0.id == id }
        if activeInstanceID == id {
            activeInstanceID = instances.first?.id
        }
        persistActiveID()
    }

    /// Switches the active server. No-op for an unknown id.
    public func setActive(_ id: UUID) {
        guard instances.contains(where: { $0.id == id }) else { return }
        activeInstanceID = id
        persistActiveID()
    }

    // MARK: - Persistence

    private func writeRecord(_ instance: ServerInstance, apiKey: String, addedAt: Date) throws {
        let metadata = try JSONEncoder().encode(StoredMetadata(instance: instance, addedAt: addedAt))
        try keychain.save(KeychainRecord(
            account: instance.id.uuidString,
            secret: apiKey,
            metadata: metadata,
            synchronizable: instance.keyStorage == .iCloud
        ))
    }

    private func persistActiveID() {
        if let activeInstanceID {
            defaults.set(activeInstanceID.uuidString, forKey: Self.activeIDKey)
        } else {
            defaults.removeObject(forKey: Self.activeIDKey)
        }
    }
}

/// The non-secret server details persisted alongside the key in each Keychain
/// item. Decoupled from ``ServerInstance`` so the stored shape can carry extra
/// bookkeeping (the insertion timestamp that orders the list) without widening
/// the model the rest of the app sees.
private struct StoredMetadata: Codable {
    var id: UUID
    var name: String?
    var baseURL: URL
    var keyStorage: KeyStorage
    var addedAt: Date

    init(instance: ServerInstance, addedAt: Date) {
        self.id = instance.id
        self.name = instance.name
        self.baseURL = instance.baseURL
        self.keyStorage = instance.keyStorage
        self.addedAt = addedAt
    }

    var instance: ServerInstance {
        ServerInstance(id: id, name: name, baseURL: baseURL, keyStorage: keyStorage)
    }
}
