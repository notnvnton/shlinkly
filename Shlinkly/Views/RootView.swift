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

    #if os(macOS)
    @State private var selection: Route?
    #else
    @State private var path: [Route] = []
    #endif

    init(client: ShlinkClient) {
        self.client = client
        _listStore = State(initialValue: ShortURLListStore(client: client))
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            SidebarPlaceholder()
        } content: {
            ShortURLListScreen(store: listStore, selection: $selection)
        } detail: {
            if let selection {
                destination(selection)
            } else {
                DetailPlaceholder()
            }
        }
        #else
        NavigationStack(path: $path) {
            ShortURLListScreen(store: listStore)
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
/// Sidebar stub — real server/section navigation arrives in a later layer.
private struct SidebarPlaceholder: View {
    var body: some View {
        List {
            Label("All Links", systemImage: "link")
        }
        .navigationTitle("Shlinkly")
        .frame(minWidth: 200)
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
