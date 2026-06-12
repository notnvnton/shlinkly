import Foundation
import Testing
@testable import ShlinklyCore

/// Live connectivity validation against the dev Shlink instance.
///
/// These are *integration* tests: they hit `go.ahodge.de` over the network and
/// require a valid `SHLINK_API_KEY` in the environment. They confirm two
/// things end-to-end before Phase 1 builds on the client:
///   1. `/health` decodes (server is reachable), and
///   2. an authenticated `/short-urls` call decodes (the API key is valid).
struct ConnectionValidationTests {
    /// Dev Shlink REST root for this session.
    static let baseURL = URL(string: "https://go.ahodge.de/rest/v3/")!

    /// Reads the API key from the environment, failing with an actionable
    /// message when it is missing rather than producing a confusing 401.
    private func requireAPIKey() throws -> String {
        let key = ProcessInfo.processInfo.environment["SHLINK_API_KEY"] ?? ""
        try #require(
            !key.isEmpty,
            "SHLINK_API_KEY is not set. Export it before running the tests, e.g.:\n  SHLINK_API_KEY=<your key> swift test"
        )
        return key
    }

    @Test("health() reaches the server and decodes HealthStatus")
    func healthCheck() async throws {
        let key = try requireAPIKey()
        let client = ShlinkClient(baseURL: Self.baseURL, apiKey: key)

        let health = try await client.health()
        print("✅ /health — status=\(health.status), version=\(health.version)")

        // The endpoint is unauthenticated, so a decode alone proves liveness.
        #expect(!health.status.isEmpty)
        #expect(!health.version.isEmpty)
    }

    @Test("shortURLs() confirms the API key is valid and decodes a page")
    func authenticatedShortURLsProbe() async throws {
        let key = try requireAPIKey()
        let client = ShlinkClient(baseURL: Self.baseURL, apiKey: key)

        let page = try await client.shortURLs(page: 1, itemsPerPage: 1)
        let meta = page.pagination
        print("✅ /short-urls — page \(meta.currentPage)/\(meta.pagesCount), "
            + "\(meta.itemsInCurrentPage) of \(meta.totalItems) total item(s)")
        for url in page.data {
            print("   • \(url.shortCode) → \(url.longUrl)  (visits: \(url.visitsSummary.total))")
        }

        // Reaching here without ShlinkError.unauthorized means the key is valid.
        #expect(meta.currentPage == 1)
        #expect(page.data.count <= 1)
    }
}
