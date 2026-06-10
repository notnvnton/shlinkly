import Foundation

/// Generic wrapper for Shlink's paginated list responses.
///
/// Shlink returns list endpoints as `{ "data": [...], "pagination": {...} }`,
/// usually nested under a named key (e.g. `shortUrls`, `visits`). This type
/// models the inner `data` + `pagination` object; the networking layer is
/// responsible for unwrapping any outer key before decoding into this.
public struct Pagination<T>: Codable, Sendable, Equatable where T: Codable & Sendable & Equatable {
    /// The items on the current page.
    public let data: [T]
    /// Paging metadata describing the full result set.
    public let pagination: PaginationMeta

    public init(data: [T], pagination: PaginationMeta) {
        self.data = data
        self.pagination = pagination
    }
}

/// Paging metadata returned alongside every paginated Shlink response.
public struct PaginationMeta: Codable, Sendable, Equatable {
    /// The page number that was requested/returned (1-based).
    public let currentPage: Int
    /// Total number of pages available for the current query.
    public let pagesCount: Int
    /// The page size that was applied.
    public let itemsPerPage: Int
    /// How many items are actually present on this page.
    public let itemsInCurrentPage: Int
    /// Total number of items across all pages.
    public let totalItems: Int

    public init(
        currentPage: Int,
        pagesCount: Int,
        itemsPerPage: Int,
        itemsInCurrentPage: Int,
        totalItems: Int
    ) {
        self.currentPage = currentPage
        self.pagesCount = pagesCount
        self.itemsPerPage = itemsPerPage
        self.itemsInCurrentPage = itemsInCurrentPage
        self.totalItems = totalItems
    }
}
