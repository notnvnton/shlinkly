import Foundation

/// Response of Shlink's unauthenticated `/health` endpoint.
///
/// The endpoint returns additional members (e.g. `links`) which are ignored
/// here — we only care about liveness (`status`) and the server `version`.
public struct HealthStatus: Codable, Sendable, Equatable {
    /// Health indicator, typically `"pass"` (also `"fail"` / `"warn"`).
    public let status: String
    /// The running Shlink server version, e.g. `"3.7.3"`.
    public let version: String

    public init(status: String, version: String) {
        self.status = status
        self.version = version
    }
}
