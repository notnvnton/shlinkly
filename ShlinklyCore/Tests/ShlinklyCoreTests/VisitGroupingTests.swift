import Foundation
import Testing
@testable import ShlinklyCore

/// The chart's day / week / month / year grouping: step selection at the
/// 31-column limit, the steps on offer, and the calendar-aligned sums.
@Suite("Visit grouping")
struct VisitGroupingTests {
    typealias DailyCount = ShortURLDetailStore.DailyCount

    /// Gregorian, UTC, weeks starting on Monday — fixed so the tests don't
    /// depend on the machine's locale or time zone.
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

    private func adding(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    /// One entry per day across the inclusive window, counted by `count(index)`.
    private func daily(from start: Date, through end: Date, count: (Int) -> Int = { _ in 1 }) -> [DailyCount] {
        var result: [DailyCount] = []
        var cursor = start
        while cursor <= end {
            result.append(DailyCount(day: cursor, count: count(result.count)))
            cursor = adding(1, to: cursor)
        }
        return result
    }

    // MARK: - Automatic step

    @Test("31 days stay per day; 32 days switch to weeks")
    func automaticDayBoundary() {
        let start = day(2024, 1, 1)
        #expect(VisitGrouping.day.columnCount(from: start, through: adding(30, to: start), calendar: calendar) == 31)
        #expect(VisitGrouping.automatic(from: start, through: adding(30, to: start), calendar: calendar) == .day)
        #expect(VisitGrouping.day.columnCount(from: start, through: adding(31, to: start), calendar: calendar) == 32)
        #expect(VisitGrouping.automatic(from: start, through: adding(31, to: start), calendar: calendar) == .week)
    }

    @Test("31 weeks stay per week; 32 weeks switch to months")
    func automaticWeekBoundary() {
        // 1 Jan 2024 is a Monday, so the window starts on a week boundary.
        let start = day(2024, 1, 1)
        let end31 = adding(31 * 7 - 1, to: start)
        #expect(VisitGrouping.week.columnCount(from: start, through: end31, calendar: calendar) == 31)
        #expect(VisitGrouping.automatic(from: start, through: end31, calendar: calendar) == .week)
        let end32 = adding(1, to: end31)
        #expect(VisitGrouping.week.columnCount(from: start, through: end32, calendar: calendar) == 32)
        #expect(VisitGrouping.automatic(from: start, through: end32, calendar: calendar) == .month)
    }

    @Test("31 months stay per month; 32 months switch to years")
    func automaticMonthBoundary() {
        let start = day(2020, 1, 1)
        #expect(VisitGrouping.month.columnCount(from: start, through: day(2022, 7, 31), calendar: calendar) == 31)
        #expect(VisitGrouping.automatic(from: start, through: day(2022, 7, 31), calendar: calendar) == .month)
        #expect(VisitGrouping.month.columnCount(from: start, through: day(2022, 8, 1), calendar: calendar) == 32)
        #expect(VisitGrouping.automatic(from: start, through: day(2022, 8, 1), calendar: calendar) == .year)
    }

    @Test("Years are the last resort: 31 fit, 32 still stay per year")
    func automaticYearBoundary() {
        let start = day(1990, 1, 1)
        #expect(VisitGrouping.year.columnCount(from: start, through: day(2020, 12, 31), calendar: calendar) == 31)
        #expect(VisitGrouping.automatic(from: start, through: day(2020, 12, 31), calendar: calendar) == .year)
        #expect(VisitGrouping.year.columnCount(from: start, through: day(2021, 1, 1), calendar: calendar) == 32)
        #expect(VisitGrouping.automatic(from: start, through: day(2021, 1, 1), calendar: calendar) == .year)
    }

    // MARK: - Available steps

    @Test("Offers the automatic step and coarser ones with four or more columns")
    func availableSteps() {
        // About four months, 15 Jun – 17 Oct 2026: 125 days, 19 weeks, 5 months, 1 year.
        #expect(VisitGrouping.available(from: day(2026, 6, 15), through: day(2026, 10, 17), calendar: calendar)
                == [.week, .month])
        // Two calendar years are too few columns to offer the year step.
        #expect(VisitGrouping.available(from: day(2025, 11, 3), through: day(2026, 10, 17), calendar: calendar)
                == [.month])
        // 26 months across four calendar years: the year step earns its place.
        #expect(VisitGrouping.available(from: day(2023, 12, 1), through: day(2026, 1, 15), calendar: calendar)
                == [.month, .year])
        // Four weeks to the day: exactly four weekly columns, one month.
        #expect(VisitGrouping.available(from: day(2026, 6, 1), through: day(2026, 6, 28), calendar: calendar)
                == [.day, .week])
        // Three weeks to the day: three weekly columns are one short.
        #expect(VisitGrouping.available(from: day(2026, 6, 1), through: day(2026, 6, 21), calendar: calendar)
                == [.day])
    }

    @Test("A 7-day window is per day only, wherever it falls")
    func sevenDayWindowOffersNoChoice() {
        // Inside one calendar week and month.
        #expect(VisitGrouping.available(from: day(2026, 6, 15), through: day(2026, 6, 21), calendar: calendar)
                == [.day])
        // Straddling a week and a month boundary: two weekly columns, still not offered.
        #expect(VisitGrouping.week.columnCount(from: day(2026, 6, 27), through: day(2026, 7, 3), calendar: calendar) == 2)
        #expect(VisitGrouping.available(from: day(2026, 6, 27), through: day(2026, 7, 3), calendar: calendar)
                == [.day])
        // Straddling a year boundary too.
        #expect(VisitGrouping.available(from: day(2025, 12, 29), through: day(2026, 1, 4), calendar: calendar)
                == [.day])
    }

    @Test("Month stays on offer when the automatic step is year; nothing finer does")
    func monthOfferedBesideAutomaticYear() {
        // Almost seven years: 82 months, far past the 31-column limit.
        let start = day(2020, 1, 1)
        let end = day(2026, 10, 17)
        #expect(VisitGrouping.automatic(from: start, through: end, calendar: calendar) == .year)
        #expect(VisitGrouping.available(from: start, through: end, calendar: calendar) == [.month, .year])
        // Right at the boundary: 32 months tip the automatic step to year.
        #expect(VisitGrouping.automatic(from: day(2020, 1, 1), through: day(2022, 8, 1), calendar: calendar) == .year)
        #expect(VisitGrouping.available(from: day(2020, 1, 1), through: day(2022, 8, 1), calendar: calendar)
                == [.month, .year])
        // While the automatic step is still month, nothing finer is offered.
        #expect(VisitGrouping.available(from: day(2020, 1, 1), through: day(2022, 7, 31), calendar: calendar)
                == [.month])
    }

    @Test("A window shorter than two days is one daily column with no choice")
    func windowShorterThanTwoDays() {
        let only = day(2026, 6, 15)
        #expect(VisitGrouping.automatic(from: only, through: only, calendar: calendar) == .day)
        #expect(VisitGrouping.available(from: only, through: only, calendar: calendar) == [.day])
        for step in VisitGrouping.allCases {
            #expect(step.columnCount(from: only, through: only, calendar: calendar) == 1)
            let buckets = step.buckets(from: [DailyCount(day: only, count: 4)], calendar: calendar)
            #expect(buckets.map(\.count) == [4])
        }
        #expect(VisitGrouping.week.buckets(from: [], calendar: calendar).isEmpty)
        #expect(VisitGrouping.day.columnCount(from: adding(1, to: only), through: only, calendar: calendar) == 0)
    }

    // MARK: - Buckets

    @Test("Every step keeps the daily total")
    func bucketsKeepTheTotal() {
        let days = daily(from: day(2024, 11, 20), through: day(2026, 10, 17)) { ($0 * 7) % 13 }
        let total = days.reduce(0) { $0 + $1.count }
        #expect(total > 0)
        for step in VisitGrouping.allCases {
            let buckets = step.buckets(from: days, calendar: calendar)
            #expect(buckets.reduce(0) { $0 + $1.count } == total)
            #expect(buckets.count == step.columnCount(from: days.first!.day, through: days.last!.day, calendar: calendar))
        }
    }

    // MARK: - People / bots

    @Test("People and bots add up to each column's total, for every step")
    func breakdownsAddUpToTheTotal() {
        let all = daily(from: day(2024, 11, 20), through: day(2026, 10, 17)) { ($0 * 7) % 13 }
        // Each day keeps a varying share of its visits as people.
        let people = all.enumerated().map { index, point in
            DailyCount(day: point.day, count: point.count * (index % 4) / 4)
        }
        let grandTotal = all.reduce(0) { $0 + $1.count }
        let peopleTotal = people.reduce(0) { $0 + $1.count }
        #expect(peopleTotal > 0 && peopleTotal < grandTotal)

        for step in VisitGrouping.allCases {
            let totals = step.buckets(from: all, calendar: calendar)
            let breakdowns = step.breakdowns(all: all, people: people, calendar: calendar)
            #expect(breakdowns.map(\.start) == totals.map(\.start))
            #expect(breakdowns.map(\.end) == totals.map(\.end))
            for (breakdown, total) in zip(breakdowns, totals) {
                #expect(breakdown.people + breakdown.bots == total.count)
                #expect(breakdown.total == total.count)
                #expect(breakdown.people >= 0 && breakdown.bots >= 0)
            }
            #expect(breakdowns.reduce(0) { $0 + $1.people } == peopleTotal)
            #expect(breakdowns.reduce(0) { $0 + $1.bots } == grandTotal - peopleTotal)
        }
    }

    @Test("A week's breakdown sums that week's days")
    func weekBreakdown() {
        // Mon 15 Jun – Sun 28 Jun 2026: 3 visits a day; one of them a bot in week one only.
        let all = daily(from: day(2026, 6, 15), through: day(2026, 6, 28)) { _ in 3 }
        let people = daily(from: day(2026, 6, 15), through: day(2026, 6, 28)) { $0 < 7 ? 2 : 3 }
        let breakdowns = VisitGrouping.week.breakdowns(all: all, people: people, calendar: calendar)
        #expect(breakdowns.map(\.people) == [14, 21])
        #expect(breakdowns.map(\.bots) == [7, 0])
        #expect(breakdowns.map(\.total) == [21, 21])
        #expect(VisitGrouping.week.breakdowns(all: [], people: [], calendar: calendar).isEmpty)
    }

    @Test("Day buckets mirror the daily counts")
    func dayBuckets() {
        let days = daily(from: day(2026, 6, 15), through: day(2026, 6, 18)) { $0 }
        let buckets = VisitGrouping.day.buckets(from: days, calendar: calendar)
        #expect(buckets.map(\.start) == days.map(\.day))
        #expect(buckets.map(\.count) == [0, 1, 2, 3])
        #expect(buckets.last?.end == day(2026, 6, 19))
    }

    @Test("Weeks start on Monday when firstWeekday is Monday")
    func weekBoundariesFromMonday() {
        // Wed 17 Jun – Tue 30 Jun 2026: a partial week, a full one, a partial one.
        let days = daily(from: day(2026, 6, 17), through: day(2026, 6, 30))
        let buckets = VisitGrouping.week.buckets(from: days, calendar: calendar)
        #expect(buckets.map(\.start) == [day(2026, 6, 15), day(2026, 6, 22), day(2026, 6, 29)])
        #expect(buckets.map(\.end) == [day(2026, 6, 22), day(2026, 6, 29), day(2026, 7, 6)])
        #expect(buckets.map(\.count) == [5, 7, 2])
        // A Sunday belongs to the week that began the Monday before.
        #expect(buckets[0].contains(day(2026, 6, 21)))
        #expect(!buckets[0].contains(day(2026, 6, 22)))
    }

    @Test("Weeks follow the calendar's own firstWeekday")
    func weekBoundariesFromSunday() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let days = daily(from: day(2026, 6, 17), through: day(2026, 6, 30))
        let buckets = VisitGrouping.week.buckets(from: days, calendar: sundayFirst)
        #expect(buckets.map(\.start) == [day(2026, 6, 14), day(2026, 6, 21), day(2026, 6, 28)])
        #expect(buckets.map(\.count) == [4, 7, 3])
    }

    @Test("Months run from the 1st to the next 1st")
    func monthBoundaries() {
        let days = daily(from: day(2026, 1, 30), through: day(2026, 3, 2))
        let buckets = VisitGrouping.month.buckets(from: days, calendar: calendar)
        #expect(buckets.map(\.start) == [day(2026, 1, 1), day(2026, 2, 1), day(2026, 3, 1)])
        #expect(buckets.map(\.end) == [day(2026, 2, 1), day(2026, 3, 1), day(2026, 4, 1)])
        #expect(buckets.map(\.count) == [2, 28, 2])
    }

    @Test("Years run from 1 January to the next 1 January")
    func yearBoundaries() {
        let days = daily(from: day(2024, 12, 30), through: day(2026, 1, 2))
        let buckets = VisitGrouping.year.buckets(from: days, calendar: calendar)
        #expect(buckets.map(\.start) == [day(2024, 1, 1), day(2025, 1, 1), day(2026, 1, 1)])
        #expect(buckets.map(\.end) == [day(2025, 1, 1), day(2026, 1, 1), day(2027, 1, 1)])
        #expect(buckets.map(\.count) == [2, 365, 2])
    }
}
