import Foundation
import Security

/// One server's persisted Keychain record: the API key (the item's secret) plus
/// an opaque metadata blob (the non-secret instance details, JSON-encoded) kept
/// in the *same* item, and whether it syncs through iCloud Keychain.
///
/// Bundling the metadata with the key means a server travels atomically: an
/// iCloud-synced record carries its name and URL to the user's other devices
/// alongside the key, so the whole server reappears there — not just the key.
public struct KeychainRecord: Sendable, Equatable {
    /// The instance's UUID string — the Keychain account, unique per server.
    public var account: String
    /// The API key, stored as the item's secret data.
    public var secret: String
    /// JSON-encoded instance metadata, stored in the item's `kSecAttrGeneric`
    /// attribute so name/URL/storage live in the same item as the key.
    public var metadata: Data
    /// Synced via iCloud Keychain (`kSecAttrSynchronizable`) iff `true`.
    public var synchronizable: Bool

    public init(account: String, secret: String, metadata: Data, synchronizable: Bool) {
        self.account = account
        self.secret = secret
        self.metadata = metadata
        self.synchronizable = synchronizable
    }
}

/// Persists server records in the Keychain — the single source of truth for the
/// configured servers. iCloud-synced records ride iCloud Keychain to the user's
/// other devices; local ones stay on the device. Abstracted behind a protocol so
/// the store can be unit-tested with an in-memory fake rather than the real
/// Keychain.
public protocol KeychainStoring: Sendable {
    /// Upserts `record`, replacing any prior item for the same account. The
    /// `synchronizable` flag can't be flipped in place, so this delete-then-adds.
    func save(_ record: KeychainRecord) throws
    /// Returns the API key for `account`, or `nil` if there is none.
    func readSecret(account: String) -> String?
    /// Removes the item for `account` (local or synced). A missing item is fine.
    func delete(account: String) throws
    /// Every stored record — local *and* synced — reconstructed from item
    /// attributes. Order is unspecified; the caller sorts.
    func allRecords() -> [KeychainRecord]
}

/// Errors surfaced by ``KeychainStore``.
public enum KeychainError: Error, Equatable {
    /// A `Security` call returned an unexpected `OSStatus`.
    case unhandled(OSStatus)

    /// A user-facing explanation for the connect screen. Carries the raw
    /// `OSStatus` to aid diagnosis — e.g. `-34018` (`errSecMissingEntitlement`)
    /// is what macOS returns until the Keychain Sharing capability is added.
    public var message: String {
        switch self {
        case .unhandled(let status):
            return "Couldn't save the API key to your Keychain (error \(status)). The server wasn't added."
        }
    }
}

/// A `kSecClassGenericPassword`-backed ``KeychainStoring``.
///
/// `service` is the bundle id; `account` is the instance's UUID, so each server's
/// record is isolated. The API key is the item's secret data; the non-secret
/// metadata rides in `kSecAttrGeneric`.
///
/// Both platforms use the **data-protection keychain** so an iCloud-stored record
/// syncs across the user's devices through iCloud Keychain. Items are
/// `kSecAttrAccessibleAfterFirstUnlock`; an iCloud record additionally sets
/// `kSecAttrSynchronizable`. Since synchronizability is fixed at creation,
/// ``save(_:)`` deletes any prior item first, and reads/deletes/listing use
/// `kSecAttrSynchronizableAny` to match either form — *crucially* the listing
/// query too, or synced records wouldn't come back.
///
/// On macOS this needs a keychain access group, which is provided automatically
/// by the app's code signature (the target is signed with a team) — so no
/// explicit `keychain-access-groups` entitlement is added.
public struct KeychainStore: KeychainStoring {
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "de.ahodge.Shlinkly") {
        self.service = service
    }

    /// Attributes common to every account-scoped query: the generic-password
    /// class, the service, the account, and the data-protection keychain (the
    /// only one iOS has, and the one macOS needs for iCloud-Keychain sync).
    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    public func save(_ record: KeychainRecord) throws {
        // Synchronizability can't be flipped on an existing item, so clear any
        // prior copy (local or synced) before adding the new one.
        try delete(account: record.account)

        var query = baseQuery(account: record.account)
        query[kSecValueData as String] = Data(record.secret.utf8)
        query[kSecAttrGeneric as String] = record.metadata
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if record.synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue!
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            // Don't drop the key silently: log the OSStatus (e.g. -34018,
            // errSecMissingEntitlement, on macOS before Keychain Sharing is
            // added) and throw so the caller can show it. Nothing is persisted.
            NSLog("Shlinkly: Keychain save failed — OSStatus=%d, synchronizable=%@", Int(status), record.synchronizable ? "true" : "false")
            throw KeychainError.unhandled(status)
        }
    }

    public func readSecret(account: String) -> String? {
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

    public func allRecords() -> [KeychainRecord] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            // Without SynchronizableAny the query returns only this device's local
            // items — every iCloud-synced server would be invisible. This is the
            // line that makes the synced list whole.
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  let metadata = item[kSecAttrGeneric as String] as? Data else { return nil }
            let secret = (item[kSecValueData as String] as? Data)
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let synchronizable = (item[kSecAttrSynchronizable as String] as? Bool) ?? false
            return KeychainRecord(account: account, secret: secret, metadata: metadata, synchronizable: synchronizable)
        }
    }
}
