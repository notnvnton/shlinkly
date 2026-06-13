import Foundation

/// The JSON body for `PATCH /short-urls/{shortCode}`.
///
/// Edit carries **only** the fields the API lets you change after creation. The
/// short code, custom slug, domain and short-code length are immutable, so they
/// are intentionally absent — never sent.
///
/// PATCH semantics: an omitted field keeps its current value, so to *clear* a
/// nullable field this body sends an explicit `null` rather than dropping it.
/// The custom `encode(to:)` enforces that — `title`, `validSince`, `validUntil`
/// and `maxVisits` are always written (a value or `null`), and an empty `tags`
/// array clears all tags. Because the form is a complete snapshot of the
/// editable state, sending every field is exactly right.
///
/// As with ``CreateShortURLRequest``, `validSince`/`validUntil` are written at
/// the top level even though reads nest them under `meta`.
public struct EditShortURLRequest: Encodable, Sendable, Equatable {
    /// The destination URL.
    public var longUrl: String
    /// Title, or `nil` to clear it (sent as explicit `null`).
    public var title: String?
    /// Tags; an empty array clears all tags.
    public var tags: [String]
    /// Lower validity bound, or `nil` to clear it (explicit `null`).
    public var validSince: Date?
    /// Upper validity bound, or `nil` to clear it (explicit `null`).
    public var validUntil: Date?
    /// Visit cap, or `nil` to clear it (explicit `null`).
    public var maxVisits: Int?
    /// Whether crawlers may follow the short URL.
    public var crawlable: Bool
    /// Whether the query string is forwarded to the destination on redirect.
    public var forwardQuery: Bool

    public init(
        longUrl: String,
        title: String? = nil,
        tags: [String] = [],
        validSince: Date? = nil,
        validUntil: Date? = nil,
        maxVisits: Int? = nil,
        crawlable: Bool = false,
        forwardQuery: Bool = true
    ) {
        self.longUrl = longUrl
        self.title = title
        self.tags = tags
        self.validSince = validSince
        self.validUntil = validUntil
        self.maxVisits = maxVisits
        self.crawlable = crawlable
        self.forwardQuery = forwardQuery
    }

    enum CodingKeys: String, CodingKey {
        case longUrl, title, tags, validSince, validUntil, maxVisits, crawlable, forwardQuery
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(longUrl, forKey: .longUrl)

        // Nullable fields are *always* written so a `null` clears them.
        if let title {
            try container.encode(title, forKey: .title)
        } else {
            try container.encodeNil(forKey: .title)
        }

        // An empty array is a meaningful value here: it clears every tag.
        try container.encode(tags, forKey: .tags)

        if let validSince {
            try container.encode(ISO8601DateParser.string(from: validSince), forKey: .validSince)
        } else {
            try container.encodeNil(forKey: .validSince)
        }
        if let validUntil {
            try container.encode(ISO8601DateParser.string(from: validUntil), forKey: .validUntil)
        } else {
            try container.encodeNil(forKey: .validUntil)
        }
        if let maxVisits {
            try container.encode(maxVisits, forKey: .maxVisits)
        } else {
            try container.encodeNil(forKey: .maxVisits)
        }

        try container.encode(crawlable, forKey: .crawlable)
        try container.encode(forwardQuery, forKey: .forwardQuery)
    }
}
