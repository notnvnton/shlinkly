import Foundation

/// Aggregated visit counts, introduced in Shlink 5.x to replace the deprecated
/// scalar `visitsCount`.
///
/// Shlink attaches this same summary to several entities — short URLs, tag
/// stats and domain stats — so it lives as a standalone, reusable type rather
/// than being nested under any one of them.
public struct VisitsSummary: Codable, Sendable, Equatable {
    /// Total visits, including those classified as bots.
    public let total: Int
    /// Visits Shlink classified as genuine (non-bot).
    public let nonBots: Int
    /// Visits Shlink classified as bots.
    public let bots: Int

    public init(total: Int = 0, nonBots: Int = 0, bots: Int = 0) {
        self.total = total
        self.nonBots = nonBots
        self.bots = bots
    }
}
