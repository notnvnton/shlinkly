import Foundation

/// Where a server's API key is stored.
///
/// The choice maps onto the Keychain's `kSecAttrSynchronizable` attribute:
/// ``local`` items stay on one device, ``iCloud`` items sync through the user's
/// iCloud Keychain (end-to-end encrypted by Apple). The non-secret instance
/// details (name, URL, this flag) live in `UserDefaults`; only the key itself is
/// in the Keychain.
public enum KeyStorage: String, Codable, Sendable, CaseIterable, Equatable {
    /// Stored only on this device (`synchronizable` not set).
    case local
    /// Synced across the user's devices via iCloud Keychain (`synchronizable`).
    case iCloud
}
