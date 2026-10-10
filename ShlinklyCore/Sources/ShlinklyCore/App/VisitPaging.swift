import Foundation

/// Splits a long run of chart columns into fixed-size pages, counted **from the
/// end**: the last page always ends with the newest column and is full, the one
/// before it holds the columns just before that, and only the earliest page may
/// be short. Pages are numbered from the earliest (`0`) to the latest
/// (`pageCount - 1`), so "next" is always "newer".
///
/// The visits chart uses it for the month step: more than a year of months is
/// shown ``monthsPerPage`` at a time. Pure index math — no dates, no calendar.
public enum VisitPaging {
    /// How many monthly columns one page of the chart shows.
    public static let monthsPerPage = 12

    /// Whether `columns` columns need paging at all: only once they overflow a
    /// single page.
    public static func isPaged(columns: Int, pageSize: Int = monthsPerPage) -> Bool {
        pageSize > 0 && columns > pageSize
    }

    /// The number of pages `columns` columns fill; at least one, so an empty
    /// chart still has a (blank) page to stand on.
    public static func pageCount(columns: Int, pageSize: Int = monthsPerPage) -> Int {
        guard pageSize > 0, columns > 0 else { return 1 }
        return (columns + pageSize - 1) / pageSize
    }

    /// The page shown by default: the latest one.
    public static func lastPage(columns: Int, pageSize: Int = monthsPerPage) -> Int {
        pageCount(columns: columns, pageSize: pageSize) - 1
    }

    /// The column indices `page` covers. An out-of-range page is clamped to the
    /// nearest real one.
    public static func columnRange(page: Int, columns: Int, pageSize: Int = monthsPerPage) -> Range<Int> {
        guard pageSize > 0, columns > 0 else { return 0..<0 }
        let last = lastPage(columns: columns, pageSize: pageSize)
        let clamped = min(max(page, 0), last)
        // Whole pages between this one and the end.
        let upper = columns - (last - clamped) * pageSize
        return max(0, upper - pageSize)..<upper
    }
}
