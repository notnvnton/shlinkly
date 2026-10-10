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
        /// ISO 3166-1 alpha-2 country code for the bucket, when known. Carried
        /// for the country breakdown's flag; `nil` for sources and the
        /// "Unknown" bucket.
        public let code: String?
        public var id: String { label }

        public init(label: String, count: Int, isDimmed: Bool, code: String? = nil) {
            self.label = label
            self.count = count
            self.isDimmed = isDimmed
            self.code = code
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
    /// is available immediately; only the visits are fetched. Updated in place
    /// after an edit via ``apply(_:)`` so the header, tags and preview refresh
    /// without rebuilding the screen.
    public private(set) var shortURL: ShortURL
    /// Current coarse state, drives which view the screen renders.
    public private(set) var state: ViewState = .loading
    /// The active period. Change via ``setPeriod(_:)`` so the visits reload.
    public private(set) var period: Period = .last7Days
    /// Whether the breakdowns hide bot visits. Drives all three derived views —
    /// the daily chart, the country breakdown and the source breakdown — from a
    /// single switch. A purely local filter: it never triggers a request and
    /// never affects the metric cards.
    public var excludeBots: Bool = false
    /// A chart step picked by hand, or `nil` to follow the automatic one. Never
    /// persisted: a fresh store and every period change start from automatic.
    private var manualGrouping: VisitGrouping?
    /// The chart page picked with the arrows, or `nil` for the latest one. Like
    /// the step it is never persisted, and a period or step change drops it.
    private var manualChartPage: Int?

    /// Every visit loaded for the current period, bots included. The chart
    /// filters this locally for the bot toggle; the metric cards always use the
    /// full set.
    private var visits: [Visit] = []

    // MARK: Dependencies

    private let client: ShlinkClient
    private let calendar: Calendar

    /// Minimum number of trailing days the chart window spans, whatever the
    /// period. Keeps a brand-new link's chart from degenerating to one or two
    /// cells — it always draws at least a full week of daily bars.
    private static let minimumWindowDays = 7

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
        manualGrouping = nil
        manualChartPage = nil
        load()
    }

    /// Picks the chart step by hand. Only steps in ``availableGroupings`` take
    /// effect; anything else falls back to the automatic step.
    public func setGrouping(_ grouping: VisitGrouping) {
        manualGrouping = grouping
        manualChartPage = nil
    }

    /// Pages the chart back by ``VisitPaging/monthsPerPage`` months. No-op on
    /// the earliest page or when the chart isn't paged.
    public func showPreviousChartPage() {
        guard canShowPreviousChartPage else { return }
        manualChartPage = chartPage - 1
    }

    /// Pages the chart forward by ``VisitPaging/monthsPerPage`` months. No-op
    /// on the latest page or when the chart isn't paged.
    public func showNextChartPage() {
        guard canShowNextChartPage else { return }
        manualChartPage = chartPage + 1
    }

    /// Widens the window to all time. Backs the smart empty state's call to
    /// action when a period has no visits but the link has lifetime visits.
    public func showAllTime() {
        setPeriod(.allTime)
    }

    /// Replaces the displayed short URL after an edit. The short code and
    /// creation date are immutable, so the loaded visits and the window math stay
    /// valid; only the metadata (title, tags, destination, validity, cap) changes.
    public func apply(_ updated: ShortURL) {
        shortURL = updated
    }

    // MARK: - Seeding (tests & previews)

    /// Puts the store straight into the loaded state with `visits`, skipping
    /// the network. For unit tests and SwiftUI previews only.
    func seed(visits: [Visit], period: Period, grouping: VisitGrouping? = nil) {
        loadTask?.cancel()
        self.visits = visits
        self.period = period
        manualGrouping = grouping
        manualChartPage = nil
        state = visits.isEmpty ? .empty : .loaded
    }

    #if DEBUG
    /// A store that is already loaded with made-up `visits`, for SwiftUI
    /// previews: it never talks to a server (its client points nowhere).
    public static func preview(
        shortURL: ShortURL,
        visits: [Visit],
        period: Period = .allTime,
        grouping: VisitGrouping? = nil,
        calendar: Calendar = .current
    ) -> ShortURLDetailStore {
        let client = ShlinkClient(baseURL: URL(string: "https://preview.invalid/rest/v3/")!, apiKey: "preview")
        let store = ShortURLDetailStore(shortURL: shortURL, client: client, calendar: calendar)
        store.seed(visits: visits, period: period, grouping: grouping)
        return store
    }
    #endif

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
    /// the request is bounded to. `end` is always today.
    ///
    /// `start` is the later of two days:
    /// - the period's own start — `dayCount - 1` days before today for 7/30 days
    ///   (so "7 days" covers today plus the six preceding days), unbounded for
    ///   all time;
    /// - the link's creation day, but never later than six days ago, so the
    ///   window is at least ``minimumWindowDays`` long and a brand-new link
    ///   still draws a full week of bars instead of one or two cells.
    ///
    /// In short: `max(periodStart, min(created, today - 6))`. A window never
    /// reaches back before the link existed — a link made yesterday shows 7
    /// days under "30 days", one made 12 days ago shows 12 — while an old link
    /// gets the full fixed 7 or 30 days.
    ///
    /// The request start is only a lower bound — nothing predates the link — so
    /// the period totals still order All ≥ 30 days ≥ 7 days.
    func window(for period: Period, now: Date) -> (start: Date, end: Date) {
        let end = calendar.startOfDay(for: now)
        // The creation day, floored to a minimum span ending today.
        let created = calendar.startOfDay(for: shortURL.dateCreated)
        let floor = calendar.date(byAdding: .day, value: -(Self.minimumWindowDays - 1), to: end) ?? end
        var start = min(created, floor)
        if let days = period.dayCount {
            let periodStart = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
            start = max(periodStart, start)
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
        "Visits by \(chartGrouping.noun) · \(excludeBots ? "no bots" : "total")"
    }

    /// The chart steps the user can choose between. "All time" offers the
    /// automatic step and the coarser ones that still draw enough columns
    /// (``VisitGrouping/minimumCoarserColumns``);
    /// the fixed 7- and 30-day periods are always per day.
    public var availableGroupings: [VisitGrouping] {
        guard period == .allTime else { return [.day] }
        let (start, end) = window(for: period, now: Date())
        return VisitGrouping.available(from: start, through: end, calendar: calendar)
    }

    /// The step the chart is drawn in: the hand-picked one while it is still on
    /// offer, otherwise the automatic one (the finest step that fits the window
    /// in ``VisitGrouping/maximumColumns`` columns).
    public var chartGrouping: VisitGrouping {
        guard period == .allTime else { return .day }
        let (start, end) = window(for: period, now: Date())
        if let manualGrouping,
           VisitGrouping.available(from: start, through: end, calendar: calendar).contains(manualGrouping) {
            return manualGrouping
        }
        return VisitGrouping.automatic(from: start, through: end, calendar: calendar)
    }

    /// The calendar the chart's columns are aligned to, so the view bins its
    /// bars on the very same day / week / month boundaries.
    public var chartCalendar: Calendar { calendar }

    /// The chart's visible columns: ``dailyCounts`` summed into
    /// ``chartGrouping`` steps, cut down to the current page when the chart is
    /// paged. Honours the bot toggle. Unpaged, the columns' total equals the
    /// daily total.
    public var chartBuckets: [VisitBucket] {
        visiblePage(of: chartGrouping.buckets(from: dailyCounts, calendar: calendar))
    }

    // MARK: Chart paging (months, a year at a time)

    /// How many columns the whole window holds at the current step.
    private var chartColumnCount: Int {
        let (start, end) = window(for: period, now: Date())
        return chartGrouping.columnCount(from: start, through: end, calendar: calendar)
    }

    /// Whether the chart shows one page of the window at a time: only the month
    /// step, and only when the window holds more than
    /// ``VisitPaging/monthsPerPage`` months. Every other step draws whole.
    public var isChartPaged: Bool {
        chartGrouping == .month && VisitPaging.isPaged(columns: chartColumnCount)
    }

    /// The number of chart pages; `1` when the chart isn't paged.
    public var chartPageCount: Int {
        isChartPaged ? VisitPaging.pageCount(columns: chartColumnCount) : 1
    }

    /// The page on screen, from `0` (earliest, possibly short) to
    /// `chartPageCount - 1` (latest, ending with the current month — the
    /// default).
    public var chartPage: Int {
        let last = chartPageCount - 1
        return min(max(manualChartPage ?? last, 0), last)
    }

    /// Whether an earlier page exists.
    public var canShowPreviousChartPage: Bool { isChartPaged && chartPage > 0 }

    /// Whether a later page exists.
    public var canShowNextChartPage: Bool { isChartPaged && chartPage < chartPageCount - 1 }

    /// Cuts the window's columns down to the current page; the identity when
    /// the chart isn't paged.
    private func visiblePage<Column>(of columns: [Column]) -> [Column] {
        guard isChartPaged else { return columns }
        return Array(columns[VisitPaging.columnRange(page: chartPage, columns: columns.count)])
    }

    /// The date span under the chart's title. Paged, it is the visible months
    /// with their years ("Oct 2025 – Sep 2026"); otherwise the whole window, as
    /// ``windowDateRange``.
    public var chartDateRange: String {
        guard isChartPaged, let first = chartBuckets.first, let last = chartBuckets.last else {
            return windowDateRange
        }
        let style = Date.FormatStyle.dateTime.month(.abbreviated).year()
        if first.start == last.start { return first.start.formatted(style) }
        return "\(first.start.formatted(style)) – \(last.start.formatted(style))"
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

    /// The people / bots split of every chart column, for the selected bar's
    /// callout. Same columns as ``chartBuckets``, but independent of the bot
    /// toggle — it always knows both halves. Derived from the loaded visits.
    public var chartBreakdowns: [VisitBucketBreakdown] {
        visiblePage(of: chartGrouping.breakdowns(all: dailyCounts(excludingBots: false),
                                                 people: dailyCounts(excludingBots: true),
                                                 calendar: calendar))
    }

    /// The chart's continuous X-axis domain: from the start of the column
    /// holding the window's first day through the end of the column holding
    /// today, so the (possibly partial) edge columns are drawn whole. Per day
    /// that is the window's first day through the day *after* today. Pinning the
    /// whole period stops a single day's data from collapsing the axis to an
    /// hour scale. `window(for:now:)` already guarantees `start <= end`, so this
    /// range is never inverted.
    public var chartXDomain: ClosedRange<Date> {
        // Paged: exactly the visible months, first column's start to last's end.
        if isChartPaged, let first = chartBuckets.first, let last = chartBuckets.last {
            return first.start...max(first.start, last.end)
        }
        let (start, end) = window(for: period, now: Date())
        let grouping = chartGrouping
        let lower = grouping.interval(containing: start, calendar: calendar).start
        let upper = grouping.interval(containing: end, calendar: calendar).end
        return lower...max(lower, upper)
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
    /// (bot-inclusive) columns for the current period and step.
    ///
    /// Deliberately independent of the bot toggle so excluding bots only
    /// shortens the bars — the axis stays put. It *is* recomputed per period
    /// and per step, since each has its own peak. It is **not** recomputed per
    /// page: a paged chart takes the peak of every column in the window, so the
    /// bars of different years can be compared by height.
    public var chartYDomainMax: Int {
        let columns = chartGrouping.buckets(from: dailyCounts(excludingBots: false), calendar: calendar)
        let peak = columns.map(\.count).max() ?? 0
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
        // Tally per country name, keeping the first non-empty code we see so the
        // UI can render a flag. The "Unknown" bucket stays code-less.
        var counts: [String: (count: Int, code: String?)] = [:]
        for visit in filtered {
            let name = visit.visitLocation?.countryName
            let label = (name?.isEmpty == false) ? name! : Self.unknownCountryLabel
            var bucket = counts[label] ?? (0, nil)
            bucket.count += 1
            if bucket.code == nil, let code = visit.visitLocation?.countryCode, !code.isEmpty {
                bucket.code = code
            }
            counts[label] = bucket
        }
        return counts
            .map { RankedEntry(label: $0.key, count: $0.value.count,
                               isDimmed: $0.key == Self.unknownCountryLabel,
                               code: $0.value.code) }
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

    /// Rounds `value` up to the nearest "nice" axis maximum that is not below
    /// it: 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8 or 10 × 10ⁿ (21 → 25, 9 → 10,
    /// 130 → 150). The steps are dense on purpose — a coarse 1-2-5 ladder left
    /// the tallest bar at half height (21 → 50). Below ten only whole numbers
    /// are used, and the result is never below 1 so the domain is always
    /// non-degenerate.
    nonisolated static func niceCeiling(_ value: Int) -> Int {
        guard value > 1 else { return 1 }
        // The power of ten at or below `value`.
        var magnitude = 1
        while magnitude <= value / 10 { magnitude *= 10 }
        // Tenths of the magnitude, so 1.5 and 2.5 stay in integer math.
        let steps = magnitude >= 10
            ? [10, 15, 20, 25, 30, 40, 50, 60, 80, 100].map { $0 * (magnitude / 10) }
            : [1, 2, 3, 4, 5, 6, 8, 10]
        return steps.first { $0 >= value } ?? magnitude * 10
    }
}
