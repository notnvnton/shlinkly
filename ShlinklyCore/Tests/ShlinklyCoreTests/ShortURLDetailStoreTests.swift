import Foundation
import Testing
@testable import ShlinklyCore

@Suite("Short URL detail store")
struct ShortURLDetailStoreTests {
    @Test("The Y ceiling is the nearest nice number at or above the peak", arguments: [
        (0, 1), (1, 1), (2, 2), (3, 3), (4, 4), (5, 5), (6, 6), (7, 8), (8, 8), (9, 10), (10, 10),
        (11, 15), (15, 15), (16, 20), (21, 25), (26, 30), (31, 40), (41, 50), (51, 60), (61, 80), (81, 100),
        (100, 100), (101, 150), (130, 150), (151, 200), (201, 250), (999, 1000), (1000, 1000), (1001, 1500),
        (12_345, 15_000),
    ])
    func niceCeiling(peak: Int, ceiling: Int) {
        #expect(ShortURLDetailStore.niceCeiling(peak) == ceiling)
    }

    @Test("The Y ceiling never cuts the peak off and never overshoots by more than half")
    func niceCeilingStaysTight() {
        for peak in 1...5_000 {
            let ceiling = ShortURLDetailStore.niceCeiling(peak)
            #expect(ceiling >= peak)
            // The widest gap in the ladder is 1 → 1.5, so the peak always
            // reaches at least two thirds of the axis.
            #expect(ceiling * 2 <= peak * 3 || peak < 10)
        }
    }

    // MARK: - Window

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private static func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// "Now" for the window tests: mid-afternoon on 10 Oct 2026.
    private static let now = day(2026, 10, 10, hour: 15)
    private static let today = day(2026, 10, 10)

    /// The window's length in days, both ends included.
    private static func length(_ window: (start: Date, end: Date)) -> Int {
        (calendar.dateComponents([.day], from: window.start, to: window.end).day ?? 0) + 1
    }

    @MainActor
    private static func store(created: Date) -> ShortURLDetailStore {
        let shortURL = ShortURL(shortCode: "abc", shortUrl: "https://s.test/abc",
                                longUrl: "https://example.com", dateCreated: created)
        let client = ShlinkClient(baseURL: URL(string: "https://s.test/rest/v3/")!, apiKey: "k")
        return ShortURLDetailStore(shortURL: shortURL, client: client, calendar: calendar)
    }

    @Test("An old link gets the full fixed 7- and 30-day windows")
    @MainActor
    func windowForOldLink() {
        let store = Self.store(created: Self.day(2026, 6, 15, hour: 9))
        let week = store.window(for: .last7Days, now: Self.now)
        #expect(week.start == Self.day(2026, 10, 4))
        #expect(week.end == Self.today)
        #expect(Self.length(week) == 7)

        let month = store.window(for: .last30Days, now: Self.now)
        #expect(month.start == Self.day(2026, 9, 11))
        #expect(month.end == Self.today)
        #expect(Self.length(month) == 30)

        let all = store.window(for: .allTime, now: Self.now)
        #expect(all.start == Self.day(2026, 6, 15))
        #expect(all.end == Self.today)
    }

    @Test("A two-day-old link shows seven days in every period")
    @MainActor
    func windowForTwoDayOldLink() {
        // Created yesterday: today is its second day.
        let store = Self.store(created: Self.day(2026, 10, 9, hour: 18))
        for period in ShortURLDetailStore.Period.allCases {
            let window = store.window(for: period, now: Self.now)
            #expect(window.start == Self.day(2026, 10, 4))
            #expect(window.end == Self.today)
            #expect(Self.length(window) == 7)
        }
    }

    @Test("A twelve-day-old link shows twelve days under 30 days, seven under 7 days")
    @MainActor
    func windowForTwelveDayOldLink() {
        // 29 Sep – 10 Oct inclusive is twelve days.
        let store = Self.store(created: Self.day(2026, 9, 29, hour: 7))
        let month = store.window(for: .last30Days, now: Self.now)
        #expect(month.start == Self.day(2026, 9, 29))
        #expect(Self.length(month) == 12)

        let week = store.window(for: .last7Days, now: Self.now)
        #expect(week.start == Self.day(2026, 10, 4))
        #expect(Self.length(week) == 7)

        let all = store.window(for: .allTime, now: Self.now)
        #expect(all.start == Self.day(2026, 9, 29))
        #expect(Self.length(all) == 12)
    }

    @Test("Window edges: created exactly 7 or 30 days ago, today, or in the future")
    @MainActor
    func windowEdges() {
        // Seven days inclusive: the creation day is the 7-day window's first day.
        let sevenDays = Self.store(created: Self.day(2026, 10, 4))
        #expect(Self.length(sevenDays.window(for: .last7Days, now: Self.now)) == 7)
        #expect(Self.length(sevenDays.window(for: .last30Days, now: Self.now)) == 7)

        // Thirty days inclusive, and one more: 30 days never grows past 30.
        let thirtyDays = Self.store(created: Self.day(2026, 9, 11))
        #expect(Self.length(thirtyDays.window(for: .last30Days, now: Self.now)) == 30)
        let thirtyOne = Self.store(created: Self.day(2026, 9, 10))
        #expect(Self.length(thirtyOne.window(for: .last30Days, now: Self.now)) == 30)
        #expect(Self.length(thirtyOne.window(for: .allTime, now: Self.now)) == 31)

        // Created today, or (clock skew) tomorrow: still a full week ending today.
        for created in [Self.day(2026, 10, 10, hour: 8), Self.day(2026, 10, 11, hour: 8)] {
            let store = Self.store(created: created)
            for period in ShortURLDetailStore.Period.allCases {
                let window = store.window(for: period, now: Self.now)
                #expect(window.end == Self.today)
                #expect(Self.length(window) == 7)
            }
        }
    }
}
