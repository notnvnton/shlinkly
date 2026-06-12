import Foundation

/// Ordering options for the `/short-urls` list endpoint.
///
/// Raw values map verbatim onto the `orderBy` query parameter's enum as defined
/// in the Shlink REST API OpenAPI spec (https://api-spec.shlink.io/). The spec
/// also accepts `longUrl-*`, `shortCode-*`, `title-*` and `nonBotVisits-*`; only
/// the orderings the list screen needs are surfaced here, and more can be added
/// without touching call sites.
public enum ShortURLsOrder: String, Sendable, CaseIterable, Hashable {
    /// Most recently created first (the list screen default).
    case newest = "dateCreated-DESC"
    /// Oldest created first.
    case oldest = "dateCreated-ASC"
    /// Most visited first (counts include bot visits, matching `visitsSummary.total`).
    case mostVisited = "visits-DESC"
    /// Least visited first.
    case leastVisited = "visits-ASC"
}
