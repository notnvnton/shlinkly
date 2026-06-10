import Foundation

/// An RFC 7807 "problem detail" error payload.
///
/// Shlink returns failures as `application/problem+json` bodies following
/// RFC 7807. Only the standard members are modelled here; Shlink-specific
/// extensions (e.g. `invalidElements`) are ignored for now and can be added
/// when a feature needs them. All members are optional because the spec only
/// guarantees them best-effort.
public struct ProblemDetails: Codable, Sendable, Equatable {
    /// A URI reference identifying the problem type.
    public let type: String?
    /// A short, human-readable summary of the problem type.
    public let title: String?
    /// The HTTP status code generated for this occurrence.
    public let status: Int?
    /// A human-readable explanation specific to this occurrence.
    public let detail: String?

    public init(
        type: String? = nil,
        title: String? = nil,
        status: Int? = nil,
        detail: String? = nil
    ) {
        self.type = type
        self.title = title
        self.status = status
        self.detail = detail
    }
}
