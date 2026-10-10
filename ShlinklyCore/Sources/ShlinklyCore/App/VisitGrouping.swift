import Foundation

/// How wide one column of the visits chart is. Ordered from the finest step to
/// the coarsest, so "coarser than" is plain `>`.
///
/// Only the "All time" period ever leaves ``day``: a link that has lived for
/// months would otherwise draw a hair-thin bar per day. The grouping is pure
/// calendar math over the already-loaded daily counts — it never touches the
/// network.
public enum VisitGrouping: Int, CaseIterable, Comparable, Hashable, Sendable {
    case day
    case week
    case month
    case year

    /// The most columns a chart may draw before the next coarser step is picked.
    public static let maximumColumns = 31

    public static func < (lhs: VisitGrouping, rhs: VisitGrouping) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Segment title in the step picker.
    public var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }

    /// The step as it reads in the chart title ("Visits by week").
    public var noun: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        }
    }

    /// The calendar unit one column spans. Weeks are `weekOfYear`, so they start
    /// on the calendar's own `firstWeekday`.
    public var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    /// The calendar-aligned column containing `date`: its day, its week (from
    /// the calendar's `firstWeekday`), its month or its year. `end` is exclusive.
    public func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        if let interval = calendar.dateInterval(of: calendarComponent, for: date) {
            return interval
        }
        // Unreachable for these units on a real calendar; degrade to the day.
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start)
    }

    /// How many columns of this step the inclusive day window `[start, end]`
    /// touches. The first and last columns may be partial. Zero for an inverted
    /// window.
    public func columnCount(from start: Date, through end: Date, calendar: Calendar) -> Int {
        guard start <= end else { return 0 }
        var count = 0
        var cursor = interval(containing: start, calendar: calendar).start
        while cursor <= end {
            count += 1
            let next = interval(containing: cursor, calendar: calendar).end
            guard next > cursor else { break }
            cursor = next
        }
        return count
    }

    /// The finest step that draws the window `[start, end]` in at most
    /// ``maximumColumns`` columns; ``year`` when even years don't fit.
    public static func automatic(from start: Date, through end: Date, calendar: Calendar) -> VisitGrouping {
        allCases.first { $0.columnCount(from: start, through: end, calendar: calendar) <= maximumColumns } ?? .year
    }

    /// The steps worth offering for the window `[start, end]`: the automatic
    /// one, plus every coarser step that still yields at least two columns.
    /// Finer steps are never offered — they are what the automatic step exists
    /// to avoid.
    public static func available(from start: Date, through end: Date, calendar: Calendar) -> [VisitGrouping] {
        let auto = automatic(from: start, through: end, calendar: calendar)
        return allCases.filter { step in
            step == auto || (step > auto && step.columnCount(from: start, through: end, calendar: calendar) >= 2)
        }
    }

    /// Sums consecutive daily counts into this step's calendar-aligned columns.
    /// `daily` must be in ascending day order (as ``ShortURLDetailStore`` builds
    /// it); every day lands in exactly one column, so the columns' total always
    /// equals the daily total.
    public func buckets(from daily: [ShortURLDetailStore.DailyCount], calendar: Calendar) -> [VisitBucket] {
        var result: [VisitBucket] = []
        for point in daily {
            if let last = result.last, point.day < last.end {
                result[result.count - 1].count += point.count
            } else {
                let interval = interval(containing: point.day, calendar: calendar)
                result.append(VisitBucket(start: interval.start, end: interval.end, count: point.count))
            }
        }
        return result
    }
}

/// One column of the visits chart: a calendar-aligned span and its visits.
public struct VisitBucket: Identifiable, Equatable, Sendable {
    /// Start of the column's day / week / month / year.
    public let start: Date
    /// Exclusive end — the start of the next column.
    public let end: Date
    public internal(set) var count: Int
    public var id: Date { start }

    public init(start: Date, end: Date, count: Int) {
        self.start = start
        self.end = end
        self.count = count
    }

    /// Whether `date` falls inside this column.
    public func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}
