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

    /// One row of a ranked breakdown (countries, referrer sources): a label,
    /// its visit count for the period, and whether it's a low-signal bucket the
    /// UI should de-emphasise.
    public struct RankedEntry: Identifiable, Equatable, Sendable {
        /// Display label — a country name, a referrer host, or a sentinel
        /// ("Unknown" / "Direct"). The breakdowns aggregate by label, so it's
        /// unique within a list and doubles as the identity.
        public let label: String
        /// Number of visits in this bucket for the current period.
        public let count: Int
        /// Whether to visually dim the row. Set for the "Unknown" country
        /// bucket; "Direct" is a real category, so it stays full strength.
        public let isDimmed: Bool
        public var id: String { label }

        public init(label: String, count: Int, isDimmed: Bool) {
            self.label = label
            self.count = count
            self.isDimmed = isDimmed
        }
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
    /// Whether the breakdowns hide bot visits. Drives all three derived views —
    /// the daily chart, the country breakdown and the source breakdown — from a
    /// single switch. A purely local filter: it never triggers a request and
    /// never affects the metric cards.
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
        // Clamp the request window to the creation date — no visits predate it.
        let startDate = window(for: period, now: Date()).start
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

    /// The inclusive start-of-day window `[start, end]` that the chart spans and
    /// the request is bounded to, clamped so it never reaches before the link
    /// was created.
    ///
    /// - 7/30 days: `start` is `dayCount - 1` days before today (so "7 days"
    ///   covers today plus the six preceding days), but no earlier than the
    ///   creation day — which drops the empty left tail for young links.
    /// - All time: `start` is the creation day.
    ///
    /// Because the windows clamp to the same floor they nest, so the period
    /// totals order All ≥ 30 days ≥ 7 days; for a link younger than the period
    /// all three windows coincide.
    func window(for period: Period, now: Date) -> (start: Date, end: Date) {
        let end = calendar.startOfDay(for: now)
        let created = calendar.startOfDay(for: shortURL.dateCreated)
        let start: Date
        if let days = period.dayCount {
            let naive = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
            start = max(naive, created)
        } else {
            start = created
        }
        // A creation date in the future (clock skew) must not invert the window.
        return (min(start, end), end)
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

    /// The window's date span formatted like the chart axis (e.g.
    /// "Jun 7 – Jun 12"); collapses to a single date for a one-day window.
    public var windowDateRange: String {
        let (start, end) = window(for: period, now: Date())
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(style)
        }
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }

    /// Per-day visit counts across ``window(for:now:)``, with empty days
    /// zero-filled so the chart's axis stays continuous. Honours the bot toggle.
    public var dailyCounts: [DailyCount] {
        dailyCounts(excludingBots: excludeBots)
    }

    /// Visits grouped by visitor country, ranked high to low. Built from the
    /// same loaded period as the chart and honouring the same bot toggle.
    /// Visits Shlink couldn't geolocate fall into a dimmed "Unknown" bucket
    /// that ranks by its own count like any other row.
    public var countryCounts: [RankedEntry] {
        countryCounts(excludingBots: excludeBots)
    }

    /// Visits grouped by referrer host, ranked high to low. Built from the same
    /// loaded period as the chart and honouring the same bot toggle. Visits with
    /// no usable referer collapse into a "Direct" bucket — a real category, so
    /// it isn't dimmed.
    public var sourceCounts: [RankedEntry] {
        sourceCounts(excludingBots: excludeBots)
    }

    /// Upper bound for the chart's Y axis: the "nice" rounded peak of the full
    /// (bot-inclusive) daily counts for the current period.
    ///
    /// Deliberately independent of the bot toggle so excluding bots only
    /// shortens the bars — the axis stays put. It *is* recomputed per period,
    /// since each period has its own peak.
    public var chartYDomainMax: Int {
        let peak = dailyCounts(excludingBots: false).map(\.count).max() ?? 0
        return Self.niceCeiling(peak)
    }

    /// Per-day counts over the current window, optionally dropping bots.
    private func dailyCounts(excludingBots: Bool) -> [DailyCount] {
        let (start, end) = window(for: period, now: Date())
        let filtered = excludingBots ? visits.filter { !$0.potentialBot } : visits

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

    /// Sentinel labels for the buckets that aren't a real country / referrer.
    static let unknownCountryLabel = "Unknown"
    static let directSourceLabel = "Direct"

    /// Visits in the loaded set bucketed by country name and ranked by count,
    /// optionally dropping bots. Ungeolocated visits (no country name) fall into
    /// a dimmed "Unknown" bucket which ranks on its own count — it isn't pinned.
    private func countryCounts(excludingBots: Bool) -> [RankedEntry] {
        let filtered = excludingBots ? visits.filter { !$0.potentialBot } : visits
        var counts: [String: Int] = [:]
        for visit in filtered {
            let name = visit.visitLocation?.countryName
            let label = (name?.isEmpty == false) ? name! : Self.unknownCountryLabel
            counts[label, default: 0] += 1
        }
        return counts
            .map { RankedEntry(label: $0.key, count: $0.value,
                               isDimmed: $0.key == Self.unknownCountryLabel) }
            .sorted(by: Self.rankOrder)
    }

    /// Visits in the loaded set bucketed by referrer host and ranked by count,
    /// optionally dropping bots. Hosts are normalised by stripping a leading
    /// "www."; an empty, missing or unparseable referer collapses into "Direct".
    private func sourceCounts(excludingBots: Bool) -> [RankedEntry] {
        let filtered = excludingBots ? visits.filter { !$0.potentialBot } : visits
        var counts: [String: Int] = [:]
        for visit in filtered {
            counts[Self.sourceLabel(for: visit.referer), default: 0] += 1
        }
        return counts
            .map { RankedEntry(label: $0.key, count: $0.value, isDimmed: false) }
            .sorted(by: Self.rankOrder)
    }

    /// The referrer host to show for a visit, normalised: the URL host with any
    /// leading "www." removed. An empty / nil / unparseable referer (no host)
    /// becomes "Direct", matching how Shlink records direct visits.
    static func sourceLabel(for referer: String?) -> String {
        guard let referer,
              !referer.trimmingCharacters(in: .whitespaces).isEmpty,
              let host = URLComponents(string: referer)?.host,
              !host.isEmpty
        else { return directSourceLabel }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Ranking order shared by both breakdowns: count descending, then label
    /// ascending so equal counts get a stable, deterministic order across the
    /// dictionary's unordered iteration.
    private static func rankOrder(_ a: RankedEntry, _ b: RankedEntry) -> Bool {
        a.count != b.count ? a.count > b.count : a.label < b.label
    }

    /// Rounds `value` up to a "nice" axis maximum (1, 2 or 5 × 10ⁿ); never
    /// below 1 so the domain is always non-degenerate.
    static func niceCeiling(_ value: Int) -> Int {
        guard value > 1 else { return 1 }
        let v = Double(value)
        let magnitude = pow(10, floor(log10(v)))
        let normalized = v / magnitude
        let nice: Double
        if normalized <= 1 { nice = 1 }
        else if normalized <= 2 { nice = 2 }
        else if normalized <= 5 { nice = 5 }
        else { nice = 10 }
        return Int((nice * magnitude).rounded())
    }
}
