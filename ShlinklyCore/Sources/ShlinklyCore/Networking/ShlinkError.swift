import Foundation

/// Errors surfaced by ``ShlinkClient``.
///
/// The associated values intentionally carry the underlying `Error` for
/// transport/decoding failures so callers can log or inspect the root cause,
/// while API-level failures are surfaced as a structured ``ProblemDetails``.
public enum ShlinkError: Error {
    /// The request never produced a usable HTTP response (e.g. offline, DNS,
    /// TLS, timeout). Carries the originating `URLError`/transport error.
    case networkError(Error)
    /// A response arrived but was not something we can interpret (e.g. a
    /// non-HTTP response, or a request URL we couldn't build).
    case invalidResponse
    /// A valid HTTP response arrived with a status we don't specifically handle
    /// (an unexpected 4xx without a problem+json body, or a 5xx). Carries the
    /// status code so the message can name it instead of masking the cause as a
    /// connectivity failure.
    case unexpectedStatus(Int)
    /// The API returned an RFC 7807 error body which decoded successfully.
    case apiError(ProblemDetails)
    /// The response status was 2xx but the body failed to decode into the
    /// expected type. Carries the `DecodingError`.
    case decodingError(Error)
    /// HTTP 401 — the API key is missing or invalid.
    case unauthorized
    /// HTTP 404 — the requested resource does not exist.
    case notFound
    /// HTTP 400 `non-unique-slug` — the requested custom slug is already taken.
    /// Carries the rejected slug (empty when the server didn't echo it back).
    case slugInUse(slug: String)
    /// HTTP 422 `invalid-short-url-deletion` — the server refuses to delete a
    /// short URL whose visit count exceeds the configured `threshold`.
    case deletionForbidden(threshold: Int)
    /// HTTP 400 validation failure — carries the names of the fields the server
    /// rejected (`invalidElements`).
    case invalidData(elements: [String])
}
