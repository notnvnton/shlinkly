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
    /// Aggregated visit counts for the short URL. Shlink 5.x removed the former
    /// scalar `visitsCount` in favour of this nested summary.
    public let visitsSummary: VisitsSummary
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
        visitsSummary: VisitsSummary = VisitsSummary(),
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
        self.visitsSummary = visitsSummary
        self.title = title
        self.tags = tags
        self.domain = domain
        self.crawlable = crawlable
        self.forwardQuery = forwardQuery
        self.meta = meta
    }
}

extension ShortURL: Identifiable {
    /// A stable identity for list diffing. `shortCode` is unique only within a
    /// domain, so the domain is folded in to stay correct when a result set
    /// spans the default domain plus custom ones.
    public var id: String { "\(domain ?? "DEFAULT")/\(shortCode)" }
}
