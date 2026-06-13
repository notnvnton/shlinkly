import Foundation
import Testing
@testable import ShlinklyCore

/// In-memory ``KeychainStoring`` for tests: no real Keychain, but it keeps the
/// full record (secret + metadata + `synchronizable`) each server was saved with,
/// so storage-change behaviour and reload-from-Keychain can be asserted.
private final class FakeKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: KeychainRecord] = [:]

    func save(_ record: KeychainRecord) throws {
        lock.lock(); defer { lock.unlock() }
        store[record.account] = record
    }
    func readSecret(account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return store[account]?.secret
    }
    func delete(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        store[account] = nil
    }
    func allRecords() -> [KeychainRecord] {
        lock.lock(); defer { lock.unlock() }
        return Array(store.values)
    }
    func record(account: String) -> KeychainRecord? {
        lock.lock(); defer { lock.unlock() }
        return store[account]
    }
}

/// A ``KeychainStoring`` whose `save` always fails — used to prove the store
/// propagates the error (and persists nothing) instead of dropping the server.
private struct FailingKeychain: KeychainStoring {
    func save(_ record: KeychainRecord) throws {
        throw KeychainError.unhandled(-34018) // errSecMissingEntitlement
    }
    func readSecret(account: String) -> String? { nil }
    func delete(account: String) throws {}
    func allRecords() -> [KeychainRecord] { [] }
}

/// A throwaway `UserDefaults` suite so tests don't touch the real domain.
private func makeDefaults() -> UserDefaults {
    let suite = "shlinkly.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private func makeInstance(name: String? = nil, host: String = "example.com", storage: KeyStorage = .local) -> ServerInstance {
    ServerInstance(name: name, baseURL: URL(string: "https://\(host)")!, keyStorage: storage)
}

@MainActor
struct InstanceStoreTests {
    @Test("First added instance becomes active and its key lands in the keychain")
    func addFirstInstanceActivates() async throws {
        let keychain = FakeKeychain()
        let store = InstanceStore(defaults: makeDefaults(), keychain: keychain)
        let instance = makeInstance()

        #expect(store.isEmpty)
        try store.add(instance, apiKey: "key-1")

        #expect(store.activeInstanceID == instance.id)
        #expect(store.activeInstance == instance)
        #expect(store.apiKey(for: instance.id) == "key-1")
        #expect(keychain.record(account: instance.id.uuidString)?.synchronizable == false)
    }

    @Test("iCloud storage saves the key as synchronizable")
    func iCloudStorageSetsSynchronizable() async throws {
        let keychain = FakeKeychain()
        let store = InstanceStore(defaults: makeDefaults(), keychain: keychain)
        let instance = makeInstance(storage: .iCloud)

        try store.add(instance, apiKey: "key-icloud")
        #expect(keychain.record(account: instance.id.uuidString)?.synchronizable == true)
    }

    @Test("Changing storage on update rewrites the key with the new sync flag")
    func updateFlipsSynchronizable() async throws {
        let keychain = FakeKeychain()
        let store = InstanceStore(defaults: makeDefaults(), keychain: keychain)
        var instance = makeInstance(storage: .local)
        try store.add(instance, apiKey: "k")
        #expect(keychain.record(account: instance.id.uuidString)?.synchronizable == false)

        instance.keyStorage = .iCloud
        try store.update(instance, apiKey: "k")
        #expect(keychain.record(account: instance.id.uuidString)?.synchronizable == true)
    }

    @Test("Removing the active instance promotes the next and deletes the key")
    func removeActivePromotesNext() async throws {
        let keychain = FakeKeychain()
        let store = InstanceStore(defaults: makeDefaults(), keychain: keychain)
        let first = makeInstance(host: "one.example.com")
        let second = makeInstance(host: "two.example.com")
        try store.add(first, apiKey: "k1")
        try store.add(second, apiKey: "k2")
        #expect(store.activeInstanceID == first.id)

        store.remove(first.id)
        #expect(store.activeInstanceID == second.id)
        #expect(store.apiKey(for: first.id) == nil)
        #expect(store.instances.count == 1)
    }

    @Test("A failed key save propagates and persists nothing")
    func failedSavePropagates() async throws {
        let store = InstanceStore(defaults: makeDefaults(), keychain: FailingKeychain())
        let instance = makeInstance()

        #expect(throws: KeychainError.self) {
            try store.add(instance, apiKey: "k")
        }
        #expect(store.isEmpty)
        #expect(store.activeInstanceID == nil)
    }

    @Test("Removing the last instance clears the active selection")
    func removeLastDeactivates() async throws {
        let store = InstanceStore(defaults: makeDefaults(), keychain: FakeKeychain())
        let only = makeInstance()
        try store.add(only, apiKey: "k")
        store.remove(only.id)
        #expect(store.isEmpty)
        #expect(store.activeInstanceID == nil)
    }

    @Test("Instances and active id persist across store reloads")
    func persistsAcrossReloads() async throws {
        let defaults = makeDefaults()
        let keychain = FakeKeychain()
        let first = makeInstance(host: "one.example.com")
        let second = makeInstance(host: "two.example.com")
        do {
            let store = InstanceStore(defaults: defaults, keychain: keychain)
            try store.add(first, apiKey: "k1")
            try store.add(second, apiKey: "k2")
            store.setActive(second.id)
        }
        // A fresh store reading the same defaults sees the same state.
        let reloaded = InstanceStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.instances.map(\.id) == [first.id, second.id])
        #expect(reloaded.activeInstanceID == second.id)
    }

    @Test("A synced server's name, URL and storage rebuild from the Keychain alone")
    func metadataRebuildsFromKeychainOnAnotherDevice() async throws {
        // The Keychain is the source of truth, so a server added on one device
        // is reconstructed on another that shares only the iCloud Keychain — a
        // *different* UserDefaults, standing in for a separate device.
        let keychain = FakeKeychain()
        let saved = makeInstance(name: "My Shlink", host: "go.example.com", storage: .iCloud)
        do {
            let store = InstanceStore(defaults: makeDefaults(), keychain: keychain)
            try store.add(saved, apiKey: "the-key")
        }

        let otherDevice = InstanceStore(defaults: makeDefaults(), keychain: keychain)
        let reloaded = try #require(otherDevice.instances.first)
        #expect(otherDevice.instances.count == 1)
        #expect(reloaded.id == saved.id)
        #expect(reloaded.name == "My Shlink")
        #expect(reloaded.baseURL == saved.baseURL)
        #expect(reloaded.keyStorage == .iCloud)
        #expect(otherDevice.apiKey(for: saved.id) == "the-key")
        #expect(otherDevice.activeInstanceID == saved.id)
    }
}

@MainActor
struct AppPreferencesTests {
    @Test("Both delete-confirmation switches default to on when never set")
    func defaultsAreOn() {
        let prefs = AppPreferences(defaults: makeDefaults())
        #expect(prefs.confirmBeforeDeletingOne)
        #expect(prefs.confirmBeforeDeletingSeveral)
    }

    @Test("Switching a preference off persists across reloads")
    func persistsAcrossReloads() {
        let defaults = makeDefaults()
        do {
            let prefs = AppPreferences(defaults: defaults)
            prefs.confirmBeforeDeletingOne = false
        }
        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.confirmBeforeDeletingOne == false)
        #expect(reloaded.confirmBeforeDeletingSeveral) // untouched → still on
    }
}

struct ServerURLNormalizerTests {
    @Test("Adds https when no scheme is present")
    func addsScheme() {
        #expect(ServerURLNormalizer.normalize("go.ahodge.de")?.absoluteString == "https://go.ahodge.de")
    }

    @Test("Strips a trailing slash and keeps an explicit scheme")
    func stripsTrailingSlashKeepsScheme() {
        #expect(ServerURLNormalizer.normalize("http://localhost:8080/")?.absoluteString == "http://localhost:8080")
    }

    @Test("Trims surrounding whitespace")
    func trimsWhitespace() {
        #expect(ServerURLNormalizer.normalize("  https://go.ahodge.de  ")?.absoluteString == "https://go.ahodge.de")
    }

    @Test("Rejects empty or host-less input")
    func rejectsInvalid() {
        #expect(ServerURLNormalizer.normalize("") == nil)
        #expect(ServerURLNormalizer.normalize("   ") == nil)
    }

    @Test("restRoot appends the versioned REST path to the server root")
    func restRootAppendsPath() {
        let instance = ServerInstance(baseURL: URL(string: "https://go.ahodge.de")!)
        #expect(instance.restRoot.absoluteString == "https://go.ahodge.de/rest/v3/")
    }

    @Test("displayName falls back to the host when no name is set")
    func displayNameFallsBackToHost() {
        let unnamed = ServerInstance(baseURL: URL(string: "https://go.ahodge.de")!)
        #expect(unnamed.displayName == "go.ahodge.de")
        let named = ServerInstance(name: "My Shlink", baseURL: URL(string: "https://go.ahodge.de")!)
        #expect(named.displayName == "My Shlink")
    }
}
