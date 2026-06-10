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
    /// A response arrived but was not something we can interpret (non-HTTP
    /// response, or an unexpected status code with no problem+json body).
    case invalidResponse
    /// The API returned an RFC 7807 error body which decoded successfully.
    case apiError(ProblemDetails)
    /// The response status was 2xx but the body failed to decode into the
    /// expected type. Carries the `DecodingError`.
    case decodingError(Error)
    /// HTTP 401 — the API key is missing or invalid.
    case unauthorized
    /// HTTP 404 — the requested resource does not exist.
    case notFound
}
