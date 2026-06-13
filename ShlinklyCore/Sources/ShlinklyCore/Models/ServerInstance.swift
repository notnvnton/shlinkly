import Foundation

/// A configured Shlink server the app can talk to.
///
/// Holds only the non-secret connection details (identity, optional display
/// name, server root and where the key is kept). The API key itself never lives
/// here — it's in the Keychain, keyed by ``id`` — so instances can be freely
/// logged, encoded into `UserDefaults` and passed around.
public struct ServerInstance: Identifiable, Sendable, Equatable, Codable {
    /// Stable identifier, used as the Keychain account for the instance's key.
    public let id: UUID
    /// Optional human-readable name shown in the UI. When absent the host of
    /// ``baseURL`` stands in (see ``displayName``).
    public var name: String?
    /// The Shlink server root the user entered, e.g. `https://go.ahodge.de`
    /// (no trailing slash, scheme guaranteed). The REST path is appended by
    /// ``restRoot`` — the user never types `/rest/v3/`.
    public var baseURL: URL
    /// Where this instance's API key is stored (this device vs iCloud Keychain).
    public var keyStorage: KeyStorage

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        baseURL: URL,
        keyStorage: KeyStorage = .local
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.keyStorage = keyStorage
    }

    /// The versioned REST root the client talks to, e.g.
    /// `https://go.ahodge.de/rest/v3/`. Derived from ``baseURL`` so the stored
    /// value stays the clean server root the user sees in the form.
    public var restRoot: URL {
        baseURL.appending(path: "rest/v3/")
    }

    /// The label to show for this server: the user-given name when set and
    /// non-blank, otherwise the host of ``baseURL`` (e.g. `go.ahodge.de`), with a
    /// last-resort fallback to the full URL string.
    public var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return baseURL.host ?? baseURL.absoluteString
    }
}
