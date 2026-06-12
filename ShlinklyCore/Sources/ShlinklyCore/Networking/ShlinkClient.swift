import Foundation

/// A thread-safe client for the Shlink REST API v3.
///
/// Implemented as an `actor` so it can be shared freely across tasks without
/// data races. This is the Phase 0 skeleton: it covers the unauthenticated
/// health probe and a single authenticated list call used to validate
/// connectivity and API-key validity. It will grow in Phase 1.
///
/// All requests automatically carry the `X-Api-Key` and `Accept` headers via
/// ``makeRequest(path:method:queryItems:)``.
public actor ShlinkClient {
    private let baseURL: URL
    private let apiKey: String
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    /// - Parameters:
    ///   - baseURL: The versioned REST root, e.g. `https://example.com/rest/v3/`.
    ///     A trailing slash is recommended so relative paths resolve correctly.
    ///   - apiKey: The Shlink API key, sent as the `X-Api-Key` header.
    ///   - urlSession: The session used for requests. Defaults to `.shared`.
    public init(baseURL: URL, apiKey: String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.urlSession = urlSession
        self.decoder = ShlinkClient.makeDecoder()
    }

    // MARK: - Endpoints

    /// Performs the unauthenticated `/health` check.
    ///
    /// Auth is not required here, so a success only proves the server is
    /// reachable — not that the API key is valid. Use ``shortURLs(page:itemsPerPage:)``
    /// to confirm the key.
    public func health() async throws -> HealthStatus {
        let request = try makeRequest(path: "health")
        return try await send(request)
    }

    /// Fetches a page of short URLs. This is an authenticated call, so a
    /// successful response confirms the API key is valid.
    ///
    /// Parameter names mirror the `GET /short-urls` query parameters in the
    /// Shlink REST API OpenAPI spec (https://api-spec.shlink.io/), verified
    /// against the spec rather than assumed.
    ///
    /// - Parameters:
    ///   - page: 1-based page number.
    ///   - itemsPerPage: Page size.
    ///   - searchTerm: Optional substring filter applied by the server across
    ///     `longUrl` and `shortCode`. Empty/`nil` means no filter.
    ///   - tags: Optional tag filter. Each tag is sent as a `tags[]` item; the
    ///     server returns short URLs carrying *any* of the given tags.
    ///   - orderBy: Optional server-side ordering. `nil` uses the server default.
    public func shortURLs(
        page: Int = 1,
        itemsPerPage: Int = 20,
        searchTerm: String? = nil,
        tags: [String] = [],
        orderBy: ShortURLsOrder? = nil
    ) async throws -> Pagination<ShortURL> {
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "itemsPerPage", value: String(itemsPerPage)),
        ]
        if let searchTerm, !searchTerm.isEmpty {
            queryItems.append(URLQueryItem(name: "searchTerm", value: searchTerm))
        }
        if let orderBy {
            queryItems.append(URLQueryItem(name: "orderBy", value: orderBy.rawValue))
        }
        // Shlink expects repeated `tags[]` items (PHP-style array encoding).
        for tag in tags where !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "tags[]", value: tag))
        }

        let request = try makeRequest(path: "short-urls", queryItems: queryItems)
        // Shlink nests the paginated payload under a `shortUrls` key.
        let wrapper: ShortURLsResponse = try await send(request)
        return wrapper.shortUrls
    }

    /// Decodes the outer envelope that Shlink wraps short-URL lists in.
    private struct ShortURLsResponse: Decodable {
        let shortUrls: Pagination<ShortURL>
    }

    // MARK: - Request building & transport

    /// Builds a request against `baseURL` with the standard Shlink headers.
    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        let url = baseURL.appending(path: path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ShlinkError.invalidResponse
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let resolvedURL = components.url else {
            throw ShlinkError.invalidResponse
        }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Executes a request and maps the HTTP status code onto either a decoded
    /// value or the appropriate ``ShlinkError``.
    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw ShlinkError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ShlinkError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw ShlinkError.decodingError(error)
            }
        case 401:
            throw ShlinkError.unauthorized
        case 404:
            throw ShlinkError.notFound
        case 400...499:
            // Other client errors should carry an RFC 7807 problem+json body.
            if let problem = try? decoder.decode(ProblemDetails.self, from: data) {
                throw ShlinkError.apiError(problem)
            }
            throw ShlinkError.invalidResponse
        default:
            throw ShlinkError.invalidResponse
        }
    }

    // MARK: - Decoding

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Shlink emits ISO 8601 timestamps with a timezone offset, occasionally
        // with fractional seconds. `.iso8601` only handles the former, so we
        // parse both forms explicitly.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601DateParser.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO 8601 date but got \"\(raw)\""
                )
            }
            return date
        }
        return decoder
    }
}

/// Parses ISO 8601 timestamps with or without fractional seconds.
///
/// `ISO8601DateFormatter` is not `Sendable`, so we construct short-lived
/// instances per parse rather than sharing mutable global state — correct
/// under Swift 6 strict concurrency, and cheap enough at the volumes this
/// skeleton handles.
enum ISO8601DateParser {
    static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
