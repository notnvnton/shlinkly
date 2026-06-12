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
    @State private var store: ShortURLListStore
    @State private var didInitialLoad = false

    init(client: ShlinkClient) {
        _store = State(initialValue: ShortURLListStore(client: client))
    }

    var body: some View {
        content
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
        List {
            ForEach(store.items) { item in
                Button {
                    // TODO: push the detail screen (layer 2).
                } label: {
                    ShortURLRow(shortURL: item)
                }
                .buttonStyle(.plain)
                .onAppear { store.loadNextPageIfNeeded(currentItem: item) }
            }

            if store.state == .loadingMore {
                loadMoreFooter
            }
        }
        .listStyle(.plain)
        .refreshable { await store.refresh() }
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
                searchActive ? "No matches" : "No links yet",
                systemImage: searchActive ? "magnifyingglass" : "link"
            )
        } description: {
            Text(searchActive
                ? "No short URLs match \u{201C}\(store.searchTerm)\u{201D}."
                : "Create your first short URL to get started.")
        } actions: {
            if !searchActive {
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
