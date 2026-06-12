//
//  RootView.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The app's root. Reads the active server's client from ``AppModel`` and
/// presents the list inside the platform-appropriate navigation container.
struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let client = appModel.client {
            #if os(macOS)
            NavigationSplitView {
                SidebarPlaceholder()
            } content: {
                ShortURLListScreen(client: client)
            } detail: {
                DetailPlaceholder()
            }
            #else
            NavigationStack {
                ShortURLListScreen(client: client)
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

/// Detail stub — the detail screen is layer 2.
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
