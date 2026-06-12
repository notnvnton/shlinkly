import Foundation

/// A configured Shlink server the app can talk to.
///
/// Holds only the non-secret connection details (identity, display name and
/// REST root). The API key is kept separately from this value type: in Phase 1
/// it comes from the local dev config, and in a later layer it moves to the
/// Keychain, keyed by ``id``. Keeping the secret out of this struct means
/// instances can be freely logged, encoded and passed around.
public struct ServerInstance: Identifiable, Sendable, Equatable, Codable {
    /// Stable identifier, used to associate the instance with its stored key.
    public let id: UUID
    /// Human-readable name shown in the UI (e.g. the host).
    public var name: String
    /// The versioned REST root, e.g. `https://example.com/rest/v3/`.
    /// A trailing slash is recommended so relative paths resolve correctly.
    public var baseURL: URL

    public init(id: UUID = UUID(), name: String, baseURL: URL) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }
}
