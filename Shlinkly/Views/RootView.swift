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

    #if os(macOS)
    @State private var selection: Route?
    #endif

    var body: some View {
        if let client = appModel.client {
            #if os(macOS)
            NavigationSplitView {
                SidebarPlaceholder()
            } content: {
                ShortURLListScreen(client: client, selection: $selection)
            } detail: {
                if let selection {
                    destination(selection, client: client)
                } else {
                    DetailPlaceholder()
                }
            }
            #else
            NavigationStack {
                ShortURLListScreen(client: client)
                    .navigationDestination(for: Route.self) { route in
                        destination(route, client: client)
                    }
            }
            #endif
        } else {
            ContentUnavailableView(
                "No server configured",
                systemImage: "server.rack",
                description: Text("Add a Shlink server to get started.")
            )
        }
    }

    /// Resolves a route to its screen. Keyed by short-URL identity so selecting
    /// a different link rebuilds the screen (and its store) rather than reusing
    /// stale state.
    @ViewBuilder
    private func destination(_ route: Route, client: ShlinkClient) -> some View {
        switch route {
        case .shortURLDetail(let shortURL):
            DetailScreen(shortURL: shortURL, client: client)
                .id(shortURL.id)
        }
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
