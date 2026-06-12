import Foundation
import Observation

/// Drives the short-URL detail screen: it loads the visits for the selected
/// period, derives the per-day chart data and the period metrics, and exposes
/// the lifetime metrics carried by the short URL itself.
///
/// Mirrors ``ShortURLListStore``'s conventions: all state lives on the main
/// actor, network work hops to the ``ShlinkClient`` actor and back, and a
/// superseded load is cancelled so a slow response can't overwrite fresher
/// state.
@MainActor
@Observable
public final class ShortURLDetailStore {

    /// The visit window the screen is currently showing.
    public enum Period: Hashable, CaseIterable, Sendable {
        case last7Days
        case last30Days
        case allTime

        /// The number of trailing days the window spans, or `nil` for all time.
        /// This both bounds the request (a volume limiter) and sizes the chart's
        /// continuous axis.
        var dayCount: Int? {
            switch self {
            case .last7Days: return 7
            case .last30Days: return 30
            case .allTime: return nil
            }
        }

        /// Short label shown under each metric card and in the empty state.
        public var label: String {
            switch self {
            case .last7Days: return "7 days"
            case .last30Days: return "30 days"
            case .allTime: return "All time"
            }
        }
    }

    /// The coarse screen state, matching the list screen's vocabulary.
    public enum ViewState: Equatable {
        /// A load is in flight with nothing to show yet.
        case loading
        /// Visits for the period are available.
        case loaded
        /// The load succeeded but the period has no visits.
        case empty
        /// The load failed; carries a user-facing message.
        case error(String)
    }

    /// One day's worth of visits, used to drive the bar chart.
    public struct DailyCount: Identifiable, Equatable, Sendable {
        /// Start-of-day for the bucket, in the store's calendar.
        public let day: Date
        public let count: Int
        public var id: Date { day }
    }

    /// A total / people / bots breakdown.
    public struct Metrics: Equatable, Sendable {
        public let total: Int
        public let nonBots: Int
        public let bots: Int
    }

    // MARK: Observable state

    /// The short URL whose detail is shown. Its metadata (title, tags, summary)
    /// is available immediately; only the visits are fetched.
    public let shortURL: ShortURL
    /// Current coarse state, drives which view the screen renders.
    public private(set) var state: ViewState = .loading
    /// The active period. Change via ``setPeriod(_:)`` so the visits reload.
    public private(set) var period: Period = .last7Days
    /// Whether the chart hides bot visits. A purely local filter — it never
    /// triggers a request and never affects the metric cards.
    public var excludeBots: Bool = false

    /// Every visit loaded for the current period, bots included. The chart
    /// filters this locally for the bot toggle; the metric cards always use the
    /// full set.
    private var visits: [Visit] = []

    // MARK: Dependencies

    private let client: ShlinkClient
    private let calendar: Calendar

    // MARK: In-flight work

    /// Supersedable load. Cancelled when a newer one starts (period change,
    /// retry) so a slow response can't overwrite fresher state.
    private var loadTask: Task<Void, Never>?

    /// - Parameters:
    ///   - shortURL: The short URL to detail. Passed whole so metadata renders
    ///     instantly while visits load.
    ///   - client: The configured client for the active server.
    ///   - calendar: Calendar used for day bucketing and window math. Injected
    ///     for testability; defaults to the user's current calendar.
    public init(shortURL: ShortURL, client: ShlinkClient, calendar: Calendar = .current) {
        self.shortURL = shortURL
        self.client = client
        self.calendar = calendar
    }

    // MARK: - Intents

    /// Loads (or reloads) visits for the current period, showing the spinner.
    /// Used for the initial appearance and for retry.
    public func load() {
        loadTask?.cancel()
        state = .loading
        let period = period
        loadTask = Task { [weak self] in
            await self?.run(period)
        }
    }

    /// Switches the period and reloads. No-op if the period is unchanged.
    public func setPeriod(_ newPeriod: Period) {
        guard newPeriod != period else { return }
        period = newPeriod
        load()
    }

    /// Widens the window to all time. Backs the smart empty state's call to
    /// action when a period has no visits but the link has lifetime visits.
    public func showAllTime() {
        setPeriod(.allTime)
    }

    // MARK: - Worker

    private func run(_ period: Period) async {
        let startDate = startDate(for: period, now: Date())
        do {
            // Always load the full set (bots included); the toggle filters locally.
            let loaded = try await client.allShortURLVisits(
                shortCode: shortURL.shortCode,
                domain: shortURL.domain,
                startDate: startDate,
                endDate: nil,
                excludeBots: false
            )
            guard !Task.isCancelled else { return }
            visits = loaded
            state = loaded.isEmpty ? .empty : .loaded
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            state = .error(ShlinkError.userFacingMessage(for: error))
        }
    }

    /// Start-of-day `dayCount - 1` days back, so e.g. "7 days" covers today plus
    /// the six preceding days. `nil` for all time (no lower bound).
    private func startDate(for period: Period, now: Date) -> Date? {
        guard let days = period.dayCount else { return nil }
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday)
    }

    // MARK: - Derived data

    /// Lifetime totals, taken verbatim from the short URL's summary — never
    /// recomputed from loaded visits.
    public var allTimeMetrics: Metrics {
        Metrics(
            total: shortURL.visitsSummary.total,
            nonBots: shortURL.visitsSummary.nonBots,
            bots: shortURL.visitsSummary.bots
        )
    }

    /// Totals for the loaded period, derived from the full (bot-inclusive) set.
    /// Unaffected by the bot toggle.
    public var periodMetrics: Metrics {
        let bots = visits.reduce(into: 0) { $0 += ($1.potentialBot ? 1 : 0) }
        return Metrics(total: visits.count, nonBots: visits.count - bots, bots: bots)
    }

    /// Whether the empty state should offer to widen the window: the period is
    /// empty, but the link has visits at some point in its lifetime.
    public var canSuggestAllTime: Bool {
        state == .empty && period != .allTime && shortURL.visitsSummary.total > 0
    }

    /// Subtitle for the chart, reflecting the bot toggle.
    public var chartSubtitle: String {
        excludeBots ? "Visits by day · no bots" : "Visits by day · total"
    }

    /// Per-day visit counts across the window, with empty days zero-filled so the
    /// chart's axis stays continuous. Honours the bot toggle.
    ///
    /// For fixed windows the span is the requested `[startDate, today]`; for all
    /// time it runs from the earliest loaded visit to today.
    public var dailyCounts: [DailyCount] {
        let now = Date()
        let end = calendar.startOfDay(for: now)
        let filtered = excludeBots ? visits.filter { !$0.potentialBot } : visits

        let start: Date
        if let from = startDate(for: period, now: now) {
            start = calendar.startOfDay(for: from)
        } else if let earliest = visits.map(\.date).min() {
            start = calendar.startOfDay(for: earliest)
        } else {
            start = end
        }

        // Tally the (possibly filtered) visits into day buckets.
        var counts: [Date: Int] = [:]
        for visit in filtered {
            counts[calendar.startOfDay(for: visit.date), default: 0] += 1
        }

        // Walk the window day by day so gaps render as zero-height bars.
        var result: [DailyCount] = []
        var cursor = start
        while cursor <= end {
            result.append(DailyCount(day: cursor, count: counts[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}
