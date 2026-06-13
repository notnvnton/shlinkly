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
/// server's key is isolated.
///
/// The two platforms use different keychains, chosen so an unsigned/ad-hoc dev
/// build works without provisioning:
/// - **iOS** uses the data-protection keychain: items are
///   `kSecAttrAccessibleAfterFirstUnlock`, and an iCloud-stored key additionally
///   sets `kSecAttrSynchronizable` so it syncs through the user's iCloud
///   Keychain. Since synchronizability is fixed at creation,
///   ``save(_:account:synchronizable:)`` deletes any prior item first; reads and
///   deletes use `kSecAttrSynchronizableAny` to match either form.
/// - **macOS** is sandboxed, so the default (file-based) keychain is redirected
///   to the app's container — usable without a keychain-access-group entitlement
///   (which would force a development certificate). The key is therefore stored
///   locally regardless of the chosen storage; true iCloud-Keychain sync on the
///   Mac needs the data-protection keychain, which a signed release build can opt
///   into later.
public struct KeychainStore: KeychainStoring {
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "de.ahodge.Shlinkly") {
        self.service = service
    }

    /// Attributes common to every query: the generic-password class and the
    /// service. iOS additionally pins the data-protection keychain.
    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(iOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    public func save(_ value: String, account: String, synchronizable: Bool) throws {
        // Synchronizability can't be flipped on an existing item, so clear any
        // prior copy (local or synced) before adding the new one.
        try delete(account: account)

        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        #if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue!
        }
        #endif

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        #if os(iOS)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        #endif

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) throws {
        var query = baseQuery(account: account)
        #if os(iOS)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        #endif

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}
