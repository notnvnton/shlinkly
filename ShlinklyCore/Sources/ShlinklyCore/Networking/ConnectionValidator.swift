import Foundation

/// Normalises the server URL a user types in the connect form.
public enum ServerURLNormalizer {
    /// Turns raw input into a clean server root: trims whitespace, prepends
    /// `https://` when no scheme is present, and strips trailing slashes. Returns
    /// `nil` when the result isn't a usable absolute URL (no host). This is the
    /// Shlink *root* — the client appends `/rest/v3/` itself.
    public static func normalize(_ raw: String) -> URL? {
        var string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }
        if !string.contains("://") {
            string = "https://" + string
        }
        while string.hasSuffix("/") {
            string.removeLast()
        }
        guard let url = URL(string: string), let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }
}

/// Checks that a server root + API key actually reach a working Shlink before the
/// app saves the instance. Used by both the onboarding form and the Settings
/// add/edit form so the two validate identically.
public enum ConnectionValidator {
    /// The outcome of validating a candidate server, mapped to the exact UI
    /// copy the form shows.
    public enum Result: Equatable {
        /// Reachable, real Shlink, key accepted. Carries the total link count for
        /// the "Connected — N links found" confirmation.
        case connected(linkCount: Int)
        /// `/health` couldn't be reached (offline, bad host, TLS).
        case unreachable
        /// Something answered, but it isn't a Shlink server.
        case notShlink
        /// Reached Shlink, but the key was rejected (HTTP 401).
        case invalidKey
        /// Any other failure; carries a user-facing message.
        case failed(String)
    }

    /// Runs the two-step probe the spec requires:
    ///   1. unauthenticated `/health` → proves the URL is a live Shlink, and
    ///   2. an authenticated `/short-urls?itemsPerPage=1` → proves the key works
    ///      and yields the total link count.
    ///
    /// - Parameters:
    ///   - serverRoot: The normalised server root (e.g. `https://go.ahodge.de`).
    ///   - apiKey: The key to send as `X-Api-Key`.
    ///   - urlSession: Injected for testing; defaults to `.shared`.
    public static func validate(
        serverRoot: URL,
        apiKey: String,
        urlSession: URLSession = .shared
    ) async -> Result {
        let restRoot = serverRoot.appending(path: "rest/v3/")
        let client = ShlinkClient(baseURL: restRoot, apiKey: apiKey, urlSession: urlSession)

        // Step 1 — liveness. A transport failure means we never reached it; any
        // other failure (bad status, undecodable body) means it answered but
        // isn't Shlink.
        do {
            _ = try await client.health()
        } catch ShlinkError.networkError {
            return .unreachable
        } catch {
            return .notShlink
        }

        // Step 2 — the key. 401 is the rejected-key case; the total comes from
        // pagination even when the first page is empty.
        do {
            let page = try await client.shortURLs(page: 1, itemsPerPage: 1)
            return .connected(linkCount: page.pagination.totalItems)
        } catch ShlinkError.unauthorized {
            return .invalidKey
        } catch ShlinkError.networkError {
            return .unreachable
        } catch {
            return .failed(ShlinkError.userFacingMessage(for: error))
        }
    }
}
