import Foundation

/// A single recorded visit (click) on a short URL.
///
/// Mirrors the `Visit` schema from the Shlink REST API v3 OpenAPI spec.
/// `referer`, `userAgent` and `visitLocation` are all nullable — a visit that
/// has not yet been geolocated returns `"visitLocation": null`.
public struct Visit: Codable, Sendable, Equatable {
    /// The referring URL, if any.
    public let referer: String?
    /// When the visit occurred (ISO 8601 with timezone).
    public let date: Date
    /// The visitor's user agent string, if captured.
    public let userAgent: String?
    /// Whether Shlink classified this visit as coming from a bot.
    public let potentialBot: Bool
    /// Geolocation data for the visit. `null` until Shlink resolves it.
    public let visitLocation: VisitLocation?

    /// Geolocation details attached to a visit.
    ///
    /// Individual fields may be empty strings or absent depending on how much
    /// the GeoLite database could resolve, so they are all optional.
    public struct VisitLocation: Codable, Sendable, Equatable {
        public let cityName: String?
        public let countryCode: String?
        public let countryName: String?
        public let latitude: Double?
        public let longitude: Double?
        public let regionName: String?
        public let timezone: String?

        public init(
            cityName: String? = nil,
            countryCode: String? = nil,
            countryName: String? = nil,
            latitude: Double? = nil,
            longitude: Double? = nil,
            regionName: String? = nil,
            timezone: String? = nil
        ) {
            self.cityName = cityName
            self.countryCode = countryCode
            self.countryName = countryName
            self.latitude = latitude
            self.longitude = longitude
            self.regionName = regionName
            self.timezone = timezone
        }
    }

    public init(
        referer: String? = nil,
        date: Date,
        userAgent: String? = nil,
        potentialBot: Bool = false,
        visitLocation: VisitLocation? = nil
    ) {
        self.referer = referer
        self.date = date
        self.userAgent = userAgent
        self.potentialBot = potentialBot
        self.visitLocation = visitLocation
    }
}
