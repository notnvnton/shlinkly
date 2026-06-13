import Foundation
import Observation

/// Drives the short-URL list screen: it owns the items, the paging cursor, the
/// search term and the sort order, and turns user intent (scroll, search, sort,
/// pull-to-refresh) into ``ShlinkClient`` calls.
///
/// All state lives on the main actor so SwiftUI can read it directly. Network
/// work hops to the client actor and back; mutations only ever happen here.
@MainActor
@Observable
public final class ShortURLListStore {
    /// The coarse screen state. The list is shown for both ``loaded`` and
    /// ``loadingMore``; the other cases are full-screen.
    public enum ViewState: Equatable {
        /// Initial / reset load in flight, no items to show yet.
        case loading
        /// At least one item is available.
        case loaded
        /// The query succeeded but returned nothing.
        case empty
        /// A page beyond the first is being appended.
        case loadingMore
        /// The load failed; carries a user-facing message.
        case error(String)
    }

    // MARK: Observable state

    /// Items loaded so far, in server order.
    public private(set) var items: [ShortURL] = []
    /// Current coarse state, drives which view the screen renders.
    public private(set) var state: ViewState = .loading
    /// The active search term. Update via ``updateSearch(_:)`` so the debounce runs.
    public private(set) var searchTerm: String = ""
    /// The active sort order. Update via ``setOrder(_:)`` so the list reloads.
    public private(set) var order: ShortURLsOrder = .newest
    /// The tag the list is filtered to, or `nil` for no tag filter. Set via
    /// ``setActiveTag(_:)``; combines with ``searchTerm``. A single tag for now —
    /// the network layer already accepts several.
    public private(set) var activeTag: String?

    /// Whether another page exists beyond what's loaded.
    public var hasMore: Bool { currentPage < totalPages }

    // MARK: Dependencies & config

    private let client: ShlinkClient
    private let pageSize: Int
    private let debounce: Duration

    // MARK: Paging cursor

    private var currentPage = 0
    private var totalPages = 1

    // MARK: In-flight work

    /// Supersedable load (first page / refresh / search / sort). Cancelled when
    /// a newer one starts so a slow response can't overwrite fresher state.
    private var loadTask: Task<Void, Never>?
    /// Separate handle for appends so paging doesn't fight the primary load.
    private var loadMoreTask: Task<Void, Never>?
    /// Pending debounced search.
    private var debounceTask: Task<Void, Never>?

    /// - Parameters:
    ///   - client: The configured client for the active server.
    ///   - pageSize: Items requested per page.
    ///   - debounce: Quiet period after the last keystroke before searching.
    public init(
        client: ShlinkClient,
        pageSize: Int = 30,
        debounce: Duration = .milliseconds(400)
    ) {
        self.client = client
        self.pageSize = pageSize
        self.debounce = debounce
    }

    // MARK: - Intents

    /// Loads (or reloads) the first page, showing the full-screen spinner.
    /// Used for the initial appearance, sort changes, search, and retry.
    public func loadFirstPage() {
        debounceTask?.cancel()
        loadMoreTask?.cancel()
        loadTask?.cancel()
        state = .loading
        loadTask = Task { [weak self] in
            await self?.runFirstPage()
        }
    }

    /// Reloads the first page for pull-to-refresh. Unlike ``loadFirstPage()``
    /// it keeps the current list on screen (the system shows its own spinner)
    /// and only surfaces an error if there was nothing to fall back to.
    public func refresh() async {
        debounceTask?.cancel()
        loadMoreTask?.cancel()
        loadTask?.cancel()
        do {
            let result = try await fetchPage(1)
            apply(firstPage: result)
        } catch {
            guard !(error is CancellationError) else { return }
            if items.isEmpty { state = .error(ShlinkError.userFacingMessage(for: error)) }
            // Otherwise keep the existing list rather than discarding it.
        }
    }

    /// Appends the next page if one exists and no append is already running.
    public func loadNextPage() {
        guard state == .loaded, hasMore else { return }
        state = .loadingMore
        let next = currentPage + 1
        loadMoreTask = Task { [weak self] in
            await self?.runNextPage(next)
        }
    }

    /// Triggers ``loadNextPage()`` once `item` nears the end of the list. The
    /// view calls this from each row's `onAppear` for infinite scrolling.
    public func loadNextPageIfNeeded(currentItem item: ShortURL) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let threshold = items.count - 5
        if index >= threshold { loadNextPage() }
    }

    /// Updates the search term and schedules a debounced server-side reload.
    public func updateSearch(_ term: String) {
        guard term != searchTerm else { return }
        searchTerm = term
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }
            self.loadFirstPage()
        }
    }

    /// Changes the sort order and reloads from the first page immediately.
    public func setOrder(_ newOrder: ShortURLsOrder) {
        guard newOrder != order else { return }
        order = newOrder
        loadFirstPage()
    }

    /// Filters the list to a single tag (or clears the filter with `nil`) and
    /// reloads from the first page. An empty string is treated as no filter.
    /// The filter combines with the active ``searchTerm``.
    public func setActiveTag(_ tag: String?) {
        let normalized = (tag?.isEmpty ?? true) ? nil : tag
        guard normalized != activeTag else { return }
        activeTag = normalized
        loadFirstPage()
    }

    /// Applies a tag chosen from a search suggestion: clears the search term and
    /// sets the tag in a single reload, so the user lands on the tag-filtered
    /// list rather than the text-search results they were typing.
    public func applyTagFromSearch(_ tag: String) {
        searchTerm = ""
        activeTag = tag.isEmpty ? nil : tag
        loadFirstPage()
    }

    // MARK: - Point mutations (after create / edit / delete)
    //
    // These update the in-memory list surgically so a write doesn't force a full
    // refetch — a refetch would reset the paging cursor and could reshuffle items
    // under the user. Pull-to-refresh remains the way to fully reconcile.

    /// The outcome of a ``delete(shortCode:domain:)`` call, so the UI can show the
    /// right message (or nothing, on success).
    public enum DeleteResult: Equatable {
        /// Deleted (or already gone): the item has been removed from the list.
        case deleted
        /// The server refused to delete a high-traffic link; carries the visit
        /// ``threshold`` it protects.
        case forbidden(threshold: Int)
        /// The delete failed for another reason; carries a user-facing message.
        case failed(String)
    }

    /// Inserts a freshly created short URL at the top of the list. A create from
    /// an empty list flips the state back to ``ViewState/loaded``.
    public func insertCreated(_ url: ShortURL) {
        items.insert(url, at: 0)
        if state == .empty { state = .loaded }
    }

    /// Replaces an edited short URL in place, matched by identity (domain +
    /// short code, both immutable across an edit). No-op if it isn't loaded.
    public func applyUpdated(_ url: ShortURL) {
        guard let index = items.firstIndex(where: { $0.id == url.id }) else { return }
        items[index] = url
    }

    /// Removes a short URL from the list, matched by short code and domain.
    /// If it empties the list, the state flips to ``ViewState/empty``.
    public func removeDeleted(shortCode: String, domain: String?) {
        items.removeAll { $0.shortCode == shortCode && $0.domain == domain }
        if items.isEmpty, state == .loaded { state = .empty }
    }

    /// Deletes a short URL on the server and removes it from the list on success
    /// (or when it's already gone). The result tells the caller whether to show
    /// an error — the deletion-threshold guard and other failures don't mutate
    /// the list.
    public func delete(shortCode: String, domain: String?) async -> DeleteResult {
        do {
            try await client.deleteShortURL(shortCode: shortCode, domain: domain)
            removeDeleted(shortCode: shortCode, domain: domain)
            return .deleted
        } catch ShlinkError.deletionForbidden(let threshold) {
            return .forbidden(threshold: threshold)
        } catch {
            return .failed(ShlinkError.userFacingMessage(for: error))
        }
    }

    // MARK: - Workers

    private func runFirstPage() async {
        do {
            let result = try await fetchPage(1)
            guard !Task.isCancelled else { return }
            apply(firstPage: result)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            state = .error(ShlinkError.userFacingMessage(for: error))
        }
    }

    private func runNextPage(_ page: Int) async {
        do {
            let result = try await fetchPage(page)
            guard !Task.isCancelled else { return }
            items.append(contentsOf: result.data)
            currentPage = result.pagination.currentPage
            totalPages = result.pagination.pagesCount
            state = .loaded
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            // A paging failure shouldn't wipe what's already shown; drop back to
            // loaded so the user can scroll to retry.
            state = .loaded
        }
    }

    private func apply(firstPage result: Pagination<ShortURL>) {
        items = result.data
        currentPage = result.pagination.currentPage
        totalPages = result.pagination.pagesCount
        state = result.data.isEmpty ? .empty : .loaded
    }

    private func fetchPage(_ page: Int) async throws -> Pagination<ShortURL> {
        try await client.shortURLs(
            page: page,
            itemsPerPage: pageSize,
            searchTerm: searchTerm.isEmpty ? nil : searchTerm,
            tags: activeTag.map { [$0] } ?? [],
            orderBy: order
        )
    }

}
