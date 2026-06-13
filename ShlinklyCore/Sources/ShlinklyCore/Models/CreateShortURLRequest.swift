import Foundation

/// The JSON body for `POST /short-urls`.
///
/// Carries the fields this layer's create form exposes. Optional fields are
/// *omitted* when `nil` rather than sent as `null`: on creation an absent field
/// means "use the server default", so there is nothing to clear (contrast with
/// ``EditShortURLRequest``, where an explicit `null` is how a field is cleared).
///
/// `validSince`/`validUntil` are written at the top level here even though the
/// API returns them nested under `meta` on reads — the documented write/read
/// asymmetry, mirrored by ``ShortURL/Meta``.
public struct CreateShortURLRequest: Encodable, Sendable, Equatable {
    /// The destination URL. Required.
    public var longUrl: String
    /// Human-readable title. Omitted when `nil`.
    public var title: String?
    /// Tags to attach. Omitted when `nil` or empty.
    public var tags: [String]?
    /// A custom slug for the short code. Create-only; omitted when `nil`.
    public var customSlug: String?
    /// Lower bound of the validity window. Omitted when `nil`.
    public var validSince: Date?
    /// Upper bound of the validity window. Omitted when `nil`.
    public var validUntil: Date?
    /// Maximum visits before the short URL stops resolving. Omitted when `nil`.
    public var maxVisits: Int?
    /// Whether crawlers may follow the short URL.
    public var crawlable: Bool
    /// Whether the query string is forwarded to the destination on redirect.
    public var forwardQuery: Bool

    public init(
        longUrl: String,
        title: String? = nil,
        tags: [String]? = nil,
        customSlug: String? = nil,
        validSince: Date? = nil,
        validUntil: Date? = nil,
        maxVisits: Int? = nil,
        crawlable: Bool = false,
        forwardQuery: Bool = true
    ) {
        self.longUrl = longUrl
        self.title = title
        self.tags = tags
        self.customSlug = customSlug
        self.validSince = validSince
        self.validUntil = validUntil
        self.maxVisits = maxVisits
        self.crawlable = crawlable
        self.forwardQuery = forwardQuery
    }

    enum CodingKeys: String, CodingKey {
        case longUrl, title, tags, customSlug, validSince, validUntil, maxVisits, crawlable, forwardQuery
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(longUrl, forKey: .longUrl)
        try container.encodeIfPresent(title, forKey: .title)
        if let tags, !tags.isEmpty {
            try container.encode(tags, forKey: .tags)
        }
        try container.encodeIfPresent(customSlug, forKey: .customSlug)
        // Dates go out as ISO-8601 strings; omitted entirely when unset.
        if let validSince {
            try container.encode(ISO8601DateParser.string(from: validSince), forKey: .validSince)
        }
        if let validUntil {
            try container.encode(ISO8601DateParser.string(from: validUntil), forKey: .validUntil)
        }
        try container.encodeIfPresent(maxVisits, forKey: .maxVisits)
        try container.encode(crawlable, forKey: .crawlable)
        try container.encode(forwardQuery, forKey: .forwardQuery)
    }
}
