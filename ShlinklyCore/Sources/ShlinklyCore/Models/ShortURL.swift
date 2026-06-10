import Foundation

/// A shortened URL as returned by the Shlink REST API v3 `/short-urls` endpoints.
///
/// Mirrors the `ShortUrl` schema from the canonical OpenAPI spec
/// (https://api-spec.shlink.io/). Fields that Shlink may return as `null`
/// — or omit entirely — are modelled as optionals so decoding never fails on
/// a sparsely-populated record.
public struct ShortURL: Codable, Sendable, Equatable {
    /// The unique short code (the part after the domain, e.g. `12C18`).
    public let shortCode: String
    /// The fully-qualified short URL, e.g. `https://doma.in/12C18`.
    public let shortUrl: String
    /// The destination the short URL redirects to.
    public let longUrl: String
    /// When the short URL was created (ISO 8601 with timezone).
    public let dateCreated: Date
    /// Total recorded visits. Deprecated by Shlink in favour of `visitsSummary`,
    /// but still emitted on the v3 API, so we keep it for now.
    public let visitsCount: Int
    /// Human-readable title, resolved from the destination page. Nullable.
    public let title: String?
    /// Tags associated with the short URL. Always present, possibly empty.
    public let tags: [String]
    /// The domain the short URL belongs to. `null` for the default domain.
    public let domain: String?
    /// Whether crawlers are allowed to follow this short URL.
    public let crawlable: Bool
    /// Whether the query string is forwarded to the destination on redirect.
    public let forwardQuery: Bool
    /// Optional validity/visit constraints attached to the short URL.
    public let meta: Meta

    /// Validity window and visit cap metadata for a short URL.
    ///
    /// Every field is nullable in the API: a short URL with no constraints
    /// returns `{ "validSince": null, "validUntil": null, "maxVisits": null }`.
    public struct Meta: Codable, Sendable, Equatable {
        /// The short URL is invalid before this instant. Nullable.
        public let validSince: Date?
        /// The short URL is invalid after this instant. Nullable.
        public let validUntil: Date?
        /// Maximum number of visits before the short URL stops resolving. Nullable.
        public let maxVisits: Int?

        public init(validSince: Date? = nil, validUntil: Date? = nil, maxVisits: Int? = nil) {
            self.validSince = validSince
            self.validUntil = validUntil
            self.maxVisits = maxVisits
        }
    }

    public init(
        shortCode: String,
        shortUrl: String,
        longUrl: String,
        dateCreated: Date,
        visitsCount: Int = 0,
        title: String? = nil,
        tags: [String] = [],
        domain: String? = nil,
        crawlable: Bool = false,
        forwardQuery: Bool = true,
        meta: Meta = Meta()
    ) {
        self.shortCode = shortCode
        self.shortUrl = shortUrl
        self.longUrl = longUrl
        self.dateCreated = dateCreated
        self.visitsCount = visitsCount
        self.title = title
        self.tags = tags
        self.domain = domain
        self.crawlable = crawlable
        self.forwardQuery = forwardQuery
        self.meta = meta
    }
}
