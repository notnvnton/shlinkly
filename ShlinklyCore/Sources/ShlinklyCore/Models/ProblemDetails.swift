import Foundation

/// An RFC 7807 "problem detail" error payload.
///
/// Shlink returns failures as `application/problem+json` bodies following
/// RFC 7807. The standard members are modelled alongside the Shlink-specific
/// extensions the write endpoints surface (`invalidElements`, `customSlug`,
/// `threshold`). All members are optional because the spec only guarantees the
/// standard ones best-effort, and the extensions appear only on their
/// respective error types.
public struct ProblemDetails: Codable, Sendable, Equatable {
    /// A URI reference identifying the problem type.
    public let type: String?
    /// A short, human-readable summary of the problem type.
    public let title: String?
    /// The HTTP status code generated for this occurrence.
    public let status: Int?
    /// A human-readable explanation specific to this occurrence.
    public let detail: String?
    /// Names of the request fields that failed validation. Present on Shlink's
    /// generic invalid-data error (HTTP 400).
    public let invalidElements: [String]?
    /// The slug that was rejected as already in use. Present on the
    /// `non-unique-slug` error (HTTP 400).
    public let customSlug: String?
    /// The visit count above which the server refuses to delete a short URL.
    /// Present on the `invalid-short-url-deletion` error (HTTP 422).
    public let threshold: Int?

    public init(
        type: String? = nil,
        title: String? = nil,
        status: Int? = nil,
        detail: String? = nil,
        invalidElements: [String]? = nil,
        customSlug: String? = nil,
        threshold: Int? = nil
    ) {
        self.type = type
        self.title = title
        self.status = status
        self.detail = detail
        self.invalidElements = invalidElements
        self.customSlug = customSlug
        self.threshold = threshold
    }
}
