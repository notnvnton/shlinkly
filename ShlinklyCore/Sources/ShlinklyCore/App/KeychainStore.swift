import Foundation
import Security

/// Reads and writes a single secret (a Shlink API key) keyed by an account
/// string. Abstracted behind a protocol so stores can be unit-tested with an
/// in-memory fake rather than touching the real Keychain.
public protocol KeychainStoring: Sendable {
    /// Stores `value` for `account`, replacing any existing item. `synchronizable`
    /// chooses iCloud Keychain sync; it can't be changed in place, so callers
    /// delete-then-add (this method does exactly that).
    func save(_ value: String, account: String, synchronizable: Bool) throws
    /// Returns the stored value for `account`, or `nil` if there is none.
    func read(account: String) -> String?
    /// Removes the item for `account`. A missing item is not an error.
    func delete(account: String) throws
}

/// Errors surfaced by ``KeychainStore``.
public enum KeychainError: Error, Equatable {
    /// A `Security` call returned an unexpected `OSStatus`.
    case unhandled(OSStatus)
}

/// A `kSecClassGenericPassword`-backed ``KeychainStoring``.
///
/// `service` is the bundle id and `account` is the instance's UUID, so each
/// server's key is isolated. Items are stored with
/// `kSecAttrAccessibleAfterFirstUnlock`; an iCloud-synced key additionally sets
/// `kSecAttrSynchronizable`. Since synchronizability is fixed at creation,
/// ``save(_:account:synchronizable:)`` deletes any prior item first and re-adds
/// with the requested flag. Reads and deletes use `kSecAttrSynchronizableAny`
/// so they find the item regardless of how it was stored.
public struct KeychainStore: KeychainStoring {
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "de.ahodge.Shlinkly") {
        self.service = service
    }

    /// Attributes common to every query: the generic-password class, the service,
    /// and — on macOS — the modern data-protection keychain, which is what
    /// supports `synchronizable` + `accessible` the way iOS does.
    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    public func save(_ value: String, account: String, synchronizable: Bool) throws {
        // Synchronizability can't be flipped on an existing item, so clear any
        // prior copy (local or synced) before adding the new one.
        try delete(account: account)

        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue!
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) throws {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}
