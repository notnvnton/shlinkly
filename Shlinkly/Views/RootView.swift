//
//  RootView.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The app's root. Reads the active server's client from ``AppModel`` and
/// presents the list inside the platform-appropriate navigation container,
/// routing to ``DetailScreen`` through the typed ``Route``.
struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let client = appModel.client {
            // Identity-keyed so a re-activated server (new client) rebuilds the
            // shared list store rather than reusing the old one.
            ConfiguredRoot(client: client)
                .id(ObjectIdentifier(client))
        } else {
            ContentUnavailableView(
                "No server configured",
                systemImage: "server.rack",
                description: Text("Add a Shlink server to get started.")
            )
        }
    }
}

/// The navigation shell for an active server. Owns the shared
/// ``ShortURLListStore`` so the list and the detail screen filter the *same*
/// state — tapping a tag on detail genuinely narrows the list behind it.
private struct ConfiguredRoot: View {
    let client: ShlinkClient
    @State private var listStore: ShortURLListStore
    /// Shared, in-memory tag cache: feeds the macOS sidebar and the iPhone
    /// search suggestions from one load.
    @State private var tagsStore: TagsStore

    #if os(macOS)
    @State private var selection: Route?
    #else
    @State private var path: [Route] = []
    #endif

    init(client: ShlinkClient) {
        self.client = client
        _listStore = State(initialValue: ShortURLListStore(client: client))
        _tagsStore = State(initialValue: TagsStore(client: client))
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            TagSidebar(listStore: listStore, tagsStore: tagsStore)
        } content: {
            ShortURLListScreen(store: listStore, tagsStore: tagsStore, selection: $selection)
        } detail: {
            if let selection {
                destination(selection)
            } else {
                DetailPlaceholder()
            }
        }
        #else
        NavigationStack(path: $path) {
            ShortURLListScreen(store: listStore, tagsStore: tagsStore)
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        #endif
    }

    /// Resolves a route to its screen. Keyed by short-URL identity so selecting
    /// a different link rebuilds the screen (and its store) rather than reusing
    /// stale state.
    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .shortURLDetail(let shortURL):
            DetailScreen(shortURL: shortURL, client: client, onSelectTag: applyTagFilter)
                .id(shortURL.id)
        }
    }

    /// Applies a tag filter from the detail screen and returns to the list:
    /// iOS pops the stack to root, macOS clears the detail selection so the
    /// refreshed (filtered) list is what the user lands on.
    private func applyTagFilter(_ tag: String) {
        listStore.setActiveTag(tag)
        #if os(macOS)
        selection = nil
        #else
        path.removeAll()
        #endif
    }
}

#if os(macOS)
/// The macOS sidebar: "All Links" (clears the filter) above the full tag list.
/// Selecting a row drives the *same* ``ShortURLListStore/activeTag`` the middle
/// list and the detail chips use, so the whole window stays in sync — selecting
/// a tag here filters the content column, and "All Links" resets it. The
/// selection is bound straight to `activeTag` so a filter set elsewhere (a row
/// chip, a detail tap) reflects back as the highlighted sidebar row.
private struct TagSidebar: View {
    let listStore: ShortURLListStore
    let tagsStore: TagsStore

    /// A concrete selection value per row. "All Links" gets its own case rather
    /// than a `nil` tag — `List` treats a `nil` selection as "nothing selected",
    /// so a `nil`-tagged row never fires the binding and can't be picked. The
    /// enum sidesteps that: every row, including All Links, has a non-nil tag.
    private enum Item: Hashable {
        case allLinks
        case tag(String)
    }

    var body: some View {
        List(selection: selectionBinding) {
            Label("All Links", systemImage: "link")
                .tag(Item.allLinks)

            if !tagsStore.tags.isEmpty {
                Section("Tags") {
                    ForEach(tagsStore.tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .tag(Item.tag(tag))
                    }
                }
            }
        }
        .navigationTitle("Shlinkly")
        .frame(minWidth: 200)
        .task { tagsStore.loadIfNeeded() }
    }

    /// Bridges the single-selection binding and ``ShortURLListStore/activeTag``:
    /// a `nil` filter shows "All Links" selected, picking a tag applies it, and
    /// picking "All Links" clears it. Reading from `activeTag` means a filter set
    /// elsewhere (a row chip, a detail tap) reflects back here as the highlight.
    private var selectionBinding: Binding<Item?> {
        Binding(
            get: { listStore.activeTag.map(Item.tag) ?? .allLinks },
            set: { item in
                switch item {
                case .tag(let tag): listStore.setActiveTag(tag)
                case .allLinks, .none: listStore.setActiveTag(nil)
                }
            }
        )
    }
}

/// Detail stub shown until a link is selected.
private struct DetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Select a link",
            systemImage: "link",
            description: Text("Choose a short URL to see its details.")
        )
    }
}
#endif
