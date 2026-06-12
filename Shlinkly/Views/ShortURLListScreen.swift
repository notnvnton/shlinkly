//
//  ShortURLListScreen.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The read-only short-URL list: paginated rows with server-side search, sort
/// and infinite scroll. Owns a ``ShortURLListStore`` bound to the active
/// server's client. Intended to sit inside a `NavigationStack` (iOS) or the
/// content column of a `NavigationSplitView` (macOS).
struct ShortURLListScreen: View {
    /// The list store is owned upstream (in `RootView`) so the detail screen can
    /// share its filter state. This screen only reads and drives it.
    private let store: ShortURLListStore
    @State private var didInitialLoad = false

    #if os(macOS)
    /// Drives the detail column of the split view. macOS selects on tap; iOS
    /// pushes via `NavigationLink` instead and has no selection binding.
    @Binding private var selection: Route?

    init(store: ShortURLListStore, selection: Binding<Route?>) {
        self.store = store
        _selection = selection
    }
    #else
    init(store: ShortURLListStore) {
        self.store = store
    }
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if let tag = store.activeTag {
                FilterPill(tag: tag) { store.setActiveTag(nil) }
            }
            content
        }
        .navigationTitle("Links")
        .toolbar { sortToolbar }
        .searchable(text: searchBinding, prompt: Text("Search links"))
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            store.loadFirstPage()
        }
    }

    // MARK: - State routing

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            loadingView
        case .empty:
            emptyView
        case .error(let message):
            errorView(message)
        case .loaded, .loadingMore:
            listView
        }
    }

    // MARK: - Loaded list

    private var listView: some View {
        #if os(macOS)
        List(selection: $selection) {
            ForEach(store.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    ShortURLRow(shortURL: item)
                    if !item.tags.isEmpty {
                        RowTags(tags: item.tags) { store.setActiveTag($0) }
                    }
                }
                .tag(Route.shortURLDetail(item))
                .onAppear { store.loadNextPageIfNeeded(currentItem: item) }
            }

            if store.state == .loadingMore {
                loadMoreFooter
            }
        }
        .listStyle(.inset)
        .refreshable { await store.refresh() }
        #else
        List {
            ForEach(store.items) { item in
                // The chips live *outside* the NavigationLink as siblings so a
                // chip tap fires its own button (filter) without triggering the
                // row's push to the detail screen.
                VStack(alignment: .leading, spacing: 6) {
                    NavigationLink(value: Route.shortURLDetail(item)) {
                        ShortURLRow(shortURL: item)
                    }
                    if !item.tags.isEmpty {
                        RowTags(tags: item.tags) { store.setActiveTag($0) }
                    }
                }
                .onAppear { store.loadNextPageIfNeeded(currentItem: item) }
            }

            if store.state == .loadingMore {
                loadMoreFooter
            }
        }
        .listStyle(.plain)
        .refreshable { await store.refresh() }
        #endif
    }

    private var loadMoreFooter: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .listRowSeparator(.hidden)
        .padding(.vertical, 8)
    }

    // MARK: - Loading skeleton

    private var loadingView: some View {
        List(0..<8, id: \.self) { _ in
            SkeletonRow()
        }
        .listStyle(.plain)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading links")
    }

    // MARK: - Empty

    private var emptyView: some View {
        ContentUnavailableView {
            Label(
                filterActive ? "No matches" : "No links yet",
                systemImage: filterActive ? "magnifyingglass" : "link"
            )
        } description: {
            Text(emptyDescription)
        } actions: {
            if !filterActive {
                Button {
                    // TODO: present the create screen (later layer).
                } label: {
                    Label("Create First Link", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load links", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button {
                store.loadFirstPage()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Toolbar & bindings

    @ToolbarContentBuilder
    private var sortToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort by", selection: orderBinding) {
                    Label("Newest", systemImage: "clock").tag(ShortURLsOrder.newest)
                    Label("Most visited", systemImage: "eye").tag(ShortURLsOrder.mostVisited)
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    /// Search routes through the store so the debounce and server query run.
    private var searchBinding: Binding<String> {
        Binding(get: { store.searchTerm }, set: { store.updateSearch($0) })
    }

    /// Changing the order reloads from the first page.
    private var orderBinding: Binding<ShortURLsOrder> {
        Binding(get: { store.order }, set: { store.setOrder($0) })
    }

    private var searchActive: Bool { !store.searchTerm.isEmpty }

    /// True when a search term or a tag filter is narrowing the list — drives the
    /// "no matches" vs "no links yet" empty state.
    private var filterActive: Bool { searchActive || store.activeTag != nil }

    /// Empty-state copy that names whichever filters are active.
    private var emptyDescription: String {
        switch (store.activeTag, searchActive) {
        case let (tag?, true):
            return "No links tagged \u{201C}\(tag)\u{201D} match \u{201C}\(store.searchTerm)\u{201D}."
        case let (tag?, false):
            return "No links are tagged \u{201C}\(tag)\u{201D}."
        case (nil, true):
            return "No short URLs match \u{201C}\(store.searchTerm)\u{201D}."
        case (nil, false):
            return "Create your first short URL to get started."
        }
    }
}

// MARK: - Row tags

/// The compact tag strip shown under each list row: up to three tappable chips
/// plus a non-interactive "+N" overflow indicator, kept to a single line so it
/// doesn't inflate row height. Tapping a chip applies that tag as the list
/// filter via ``onSelectTag``.
private struct RowTags: View {
    let tags: [String]
    let onSelectTag: (String) -> Void

    private let maxVisible = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(visibleTags, id: \.self) { tag in
                TagChip(text: tag) { onSelectTag(tag) }
            }
            if overflow > 0 {
                TagChip(text: "+\(overflow)")
            }
        }
        .lineLimit(1)
    }

    private var visibleTags: [String] { Array(tags.prefix(maxVisible)) }
    private var overflow: Int { max(0, tags.count - maxVisible) }
}

// MARK: - Filter pill

/// A removable pill shown above the list while a tag filter is active. The ✕
/// clears the filter.
private struct FilterPill: View {
    let tag: String
    let onClear: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill")
                    .font(.caption2)
                Text(tag)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear tag filter")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// A redacted stand-in row shown while the first page loads.
private struct SkeletonRow: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Placeholder short URL title")
                    .font(.body.weight(.semibold))
                Text("abc123 · 2 days ago")
                    .font(.caption)
            }
            Spacer(minLength: 8)
            Label("00", systemImage: "eye")
                .font(.caption)
                .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 4)
    }
}
