import Foundation
import Testing
@testable import ShlinklyCore

/// The month chart's paging: twelve columns a page, counted from the end.
@Suite("Visit paging")
struct VisitPagingTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private var calendar: Calendar { Self.calendar }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Monthly columns for the inclusive day window, one visit a day.
    private func months(from start: Date, through end: Date) -> [VisitBucket] {
        var daily: [ShortURLDetailStore.DailyCount] = []
        var cursor = start
        while cursor <= end {
            daily.append(.init(day: cursor, count: 1))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        return VisitGrouping.month.buckets(from: daily, calendar: calendar)
    }

    @Test("Twelve months fit one page; thirteen need two")
    func twelveAndThirteen() {
        #expect(!VisitPaging.isPaged(columns: 12))
        #expect(VisitPaging.pageCount(columns: 12) == 1)
        #expect(VisitPaging.columnRange(page: 0, columns: 12) == 0..<12)

        #expect(VisitPaging.isPaged(columns: 13))
        #expect(VisitPaging.pageCount(columns: 13) == 2)
        #expect(VisitPaging.lastPage(columns: 13) == 1)
        // The latest page is full; the earliest holds the single leftover month.
        #expect(VisitPaging.columnRange(page: 1, columns: 13) == 1..<13)
        #expect(VisitPaging.columnRange(page: 0, columns: 13) == 0..<1)
    }

    @Test("Exactly 24 months make two full pages")
    func twentyFour() {
        #expect(VisitPaging.pageCount(columns: 24) == 2)
        #expect(VisitPaging.columnRange(page: 0, columns: 24) == 0..<12)
        #expect(VisitPaging.columnRange(page: 1, columns: 24) == 12..<24)
    }

    @Test("30 months: the last page is full, the first is the short one")
    func thirty() {
        #expect(VisitPaging.pageCount(columns: 30) == 3)
        #expect(VisitPaging.lastPage(columns: 30) == 2)
        #expect(VisitPaging.columnRange(page: 2, columns: 30) == 18..<30)
        #expect(VisitPaging.columnRange(page: 1, columns: 30) == 6..<18)
        #expect(VisitPaging.columnRange(page: 0, columns: 30) == 0..<6)
    }

    @Test("Pages cover every column exactly once, whatever the count")
    func pagesPartitionTheColumns() {
        for columns in 1...100 {
            let count = VisitPaging.pageCount(columns: columns)
            let ranges = (0..<count).map { VisitPaging.columnRange(page: $0, columns: columns) }
            #expect(ranges.flatMap { Array($0) } == Array(0..<columns))
            #expect(ranges.dropFirst().allSatisfy { $0.count == VisitPaging.monthsPerPage })
            #expect((ranges.first?.count ?? 0) >= 1)
        }
    }

    @Test("Out-of-range pages clamp; no columns means one empty page")
    func edges() {
        #expect(VisitPaging.columnRange(page: -3, columns: 30) == 0..<6)
        #expect(VisitPaging.columnRange(page: 99, columns: 30) == 18..<30)
        #expect(VisitPaging.pageCount(columns: 0) == 1)
        #expect(VisitPaging.columnRange(page: 0, columns: 0).isEmpty)
        #expect(!VisitPaging.isPaged(columns: 0))
    }

    @Test("Pages run back from the current month, across year boundaries")
    func pagesCrossYearBoundaries() {
        // 20 Apr 2024 – 17 Oct 2026: 31 monthly columns, Apr 2024 … Oct 2026.
        let columns = months(from: day(2024, 4, 20), through: day(2026, 10, 17))
        #expect(columns.count == 31)
        #expect(VisitPaging.pageCount(columns: columns.count) == 3)

        let latest = columns[VisitPaging.columnRange(page: 2, columns: columns.count)]
        #expect(latest.first?.start == day(2025, 11, 1))
        #expect(latest.last?.start == day(2026, 10, 1))

        let middle = columns[VisitPaging.columnRange(page: 1, columns: columns.count)]
        #expect(middle.first?.start == day(2024, 11, 1))
        #expect(middle.last?.start == day(2025, 10, 1))

        let earliest = columns[VisitPaging.columnRange(page: 0, columns: columns.count)]
        #expect(earliest.map(\.start) == (4...10).map { day(2024, $0, 1) })
    }
}

/// Paging as the detail store applies it to its month chart.
@Suite("Short URL detail store — chart paging")
@MainActor
struct ShortURLDetailStorePagingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    /// A store for a link created `monthsAgo` months ago, with `perMonth(index)`
    /// visits on the 1st of each month since (index 0 = the creation month).
    private func makeStore(monthsAgo: Int, grouping: VisitGrouping?, perMonth: (Int) -> Int) -> ShortURLDetailStore {
        let thisMonth = calendar.dateInterval(of: .month, for: Date())!.start
        let created = calendar.date(byAdding: .month, value: -monthsAgo, to: thisMonth)!
        var visits: [Visit] = []
        for index in 0...monthsAgo {
            let date = calendar.date(byAdding: .month, value: index, to: created)!
            for visit in 0..<perMonth(index) {
                visits.append(Visit(date: date, potentialBot: visit % 3 == 0))
            }
        }
        let shortURL = ShortURL(shortCode: "abc", shortUrl: "https://s.test/abc",
                                longUrl: "https://example.com", dateCreated: created)
        let client = ShlinkClient(baseURL: URL(string: "https://s.test/rest/v3/")!, apiKey: "k")
        let store = ShortURLDetailStore(shortURL: shortURL, client: client, calendar: calendar)
        store.seed(visits: visits, period: .allTime, grouping: grouping)
        return store
    }

    @Test("The Y ceiling is shared by every page of a paged month chart")
    func sharedYCeiling() {
        // 30 columns; the peak (40 visits) sits in the oldest months, the
        // latest year never exceeds 3.
        let store = makeStore(monthsAgo: 29, grouping: .month) { $0 == 2 ? 40 : 3 }
        #expect(store.chartGrouping == .month)
        #expect(store.isChartPaged)
        #expect(store.chartPageCount == 3)
        #expect(store.chartPage == 2)

        var ceilings: [Int] = []
        var peaks: [Int] = []
        var sizes: [Int] = []
        store.excludeBots = false
        for page in stride(from: 2, through: 0, by: -1) {
            #expect(store.chartPage == page)
            ceilings.append(store.chartYDomainMax)
            peaks.append(store.chartBuckets.map(\.count).max() ?? 0)
            sizes.append(store.chartBuckets.count)
            #expect(store.chartBreakdowns.map(\.start) == store.chartBuckets.map(\.start))
            store.showPreviousChartPage()
        }
        #expect(ceilings == [40, 40, 40])
        #expect(peaks == [3, 3, 40])
        #expect(sizes == [12, 12, 6])
    }

    @Test("Arrows stop at the ends, and the page resets with the step and the period")
    func navigation() {
        let store = makeStore(monthsAgo: 29, grouping: .month) { _ in 2 }
        #expect(!store.canShowNextChartPage)
        #expect(store.canShowPreviousChartPage)
        store.showNextChartPage()
        #expect(store.chartPage == 2)

        store.showPreviousChartPage()
        store.showPreviousChartPage()
        #expect(store.chartPage == 0)
        #expect(!store.canShowPreviousChartPage)
        #expect(store.canShowNextChartPage)
        store.showPreviousChartPage()
        #expect(store.chartPage == 0)

        // The visible domain is exactly the page's months.
        #expect(store.chartXDomain.lowerBound == store.chartBuckets.first?.start)
        #expect(store.chartXDomain.upperBound == store.chartBuckets.last?.end)

        store.setGrouping(.month)
        #expect(store.chartPage == 2)
    }

    @Test("Only the month step pages, and only past twelve months")
    func whatPages() {
        // 12 months: one page, no arrows.
        let year = makeStore(monthsAgo: 11, grouping: .month) { _ in 1 }
        #expect(year.chartGrouping == .month)
        #expect(!year.isChartPaged)
        #expect(year.chartBuckets.count == 12)
        #expect(!year.canShowPreviousChartPage && !year.canShowNextChartPage)

        // 13 months: two pages, the latest one full.
        let thirteen = makeStore(monthsAgo: 12, grouping: .month) { _ in 1 }
        #expect(thirteen.isChartPaged)
        #expect(thirteen.chartPageCount == 2)
        #expect(thirteen.chartBuckets.count == 12)

        // Long-lived link: automatic is year (unpaged), month is on offer and pages.
        let old = makeStore(monthsAgo: 59, grouping: nil) { _ in 1 }
        #expect(old.chartGrouping == .year)
        #expect(!old.isChartPaged)
        #expect(old.availableGroupings == [.month, .year])
        old.setGrouping(.month)
        #expect(old.isChartPaged)
        #expect(old.chartPageCount == 5)
        #expect(old.chartBuckets.count == 12)
    }
}
