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
    /// Hosted here, above the per-client ``ConfiguredRoot``, so switching or
    /// editing the active server (which rebuilds that subtree) doesn't dismiss
    /// an open Settings sheet.
    @State private var showSettings = false

    var body: some View {
        Group {
            if appModel.needsOnboarding {
                // No servers configured yet — walk the user through connecting one.
                OnboardingView()
            } else if let client = appModel.client {
                // Identity-keyed so a re-activated server (new client) rebuilds
                // the shared list store rather than reusing the old one.
                ConfiguredRoot(client: client, showSettings: $showSettings)
                    .id(ObjectIdentifier(client))
            } else {
                // A server exists but its key couldn't be read from the Keychain.
                ContentUnavailableView(
                    "Couldn't load credentials",
                    systemImage: "key.slash",
                    description: Text("The saved API key for this server is unavailable. Re-add the server to continue.")
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .brandTint()
        }
        #if os(macOS)
        // The translucent matte window: the desktop blurred behind it, under a
        // soft lavender wash. Every column sits on it; nothing on the Mac paints
        // an opaque canvas.
        .background { WindowBackdrop() }
        #endif
        // Hosted here, above the per-client ``ConfiguredRoot``, so the pill
        // survives the subtree rebuild a server switch causes.
        .spotlightNoticeToast()
        // Removing the last server drops back to onboarding; close Settings so it
        // isn't left hanging over the Welcome screen.
        .onChange(of: appModel.needsOnboarding) { _, onboarding in
            if onboarding { showSettings = false }
        }
    }
}

/// The navigation shell for an active server. Owns the shared
/// ``ShortURLListStore`` so the list and the detail screen filter the *same*
/// state — tapping a tag on detail genuinely narrows the list behind it.
private struct ConfiguredRoot: View {
    let client: ShlinkClient
    @Binding var showSettings: Bool
    /// Read to consume a ``DeepLink`` parked by the scene's `onOpenURL`.
    @Environment(AppModel.self) private var appModel
    @State private var listStore: ShortURLListStore
    /// Shared, in-memory tag cache: feeds the macOS sidebar and the iPhone
    /// search suggestions from one load.
    @State private var tagsStore: TagsStore

    #if os(macOS)
    @State private var selection: Route?
    /// Guards the one-time first-launch auto-selection so clearing the detail
    /// (after a delete or a tag filter) doesn't snap back to the first row.
    @State private var didAutoSelectFirst = false
    /// Bumped each time the detail is closed on purpose (delete, tag filter,
    /// create request), so the list can tell that apart from the `List` dropping
    /// a selection whose row a refresh took away.
    @State private var detailDismissCount = 0
    #else
    @State private var path: [Route] = []
    #endif

    init(client: ShlinkClient, showSettings: Binding<Bool>) {
        self.client = client
        _showSettings = showSettings
        _listStore = State(initialValue: ShortURLListStore(client: client))
        _tagsStore = State(initialValue: TagsStore(client: client))
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            TagSidebar(listStore: listStore, tagsStore: tagsStore)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            ShortURLListScreen(store: listStore, tagsStore: tagsStore, client: client, selection: $selection, detailDismissCount: detailDismissCount, showSettings: $showSettings)
                .navigationSplitViewColumnWidth(min: 320, ideal: 360)
        } detail: {
            if let selection {
                destination(selection)
            } else {
                DetailPlaceholder()
            }
        }
        .onChange(of: listStore.items.first?.id) { _, _ in
            autoSelectFirstIfNeeded()
        }
        .onChange(of: appModel.pendingDeepLink, initial: true) { _, deepLink in
            handleDeepLink(deepLink)
        }
        #else
        NavigationStack(path: $path) {
            ShortURLListScreen(store: listStore, tagsStore: tagsStore, client: client, showSettings: $showSettings)
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        .onChange(of: appModel.pendingDeepLink, initial: true) { _, deepLink in
            handleDeepLink(deepLink)
        }
        #endif
    }

    // MARK: - Deep linking

    /// Resolves and navigates to a pending deep link, then clears it. Fast path:
    /// the link is already in the loaded list → navigate with no network. Slow
    /// path: fetch the single link, then navigate. A failed fetch (unknown code
    /// or offline) is swallowed — the user simply lands on the list, no error UI.
    private func handleDeepLink(_ deepLink: DeepLink?) {
        guard let deepLink else { return }
        // A Spotlight link can arrive together with a server switch. This shell
        // belongs to one client; if it's no longer the live one, it is about to
        // be torn down — leave the link parked for the shell replacing it.
        if case .spotlightLink = deepLink, appModel.client !== client { return }
        appModel.pendingDeepLink = nil
        switch deepLink {
        case .linkDetail(let shortCode):
            if let existing = listStore.items.first(where: { $0.shortCode == shortCode }) {
                navigate(to: existing)
            } else {
                Task {
                    if let fetched = try? await client.shortURL(shortCode: shortCode) {
                        navigate(to: fetched)
                    }
                }
            }
        case .spotlightLink(let shortURL):
            // Already fetched from its server by ``AppModel``; just show it.
            navigate(to: shortURL)
        case .createLink(let fromClipboard):
            // The list screen owns the create sheet, so hand it the request
            // rather than navigating. Any open detail is dismissed first so the
            // form opens over the list, matching the "+" button's context.
            navigateToRoot()
            appModel.pendingCreate = .init(fromClipboard: fromClipboard)
        }
    }

    /// Returns to the list from any prior navigation state, so a create request
    /// arriving while a detail is open lands in the same place the "+" would.
    private func navigateToRoot() {
        #if os(macOS)
        detailDismissCount += 1
        selection = nil
        #else
        path.removeAll()
        #endif
    }

    /// Lands on a link's detail from any prior navigation state: iOS resets the
    /// stack to root and pushes the detail; macOS sets the split-view selection.
    private func navigate(to shortURL: ShortURL) {
        #if os(macOS)
        selection = .shortURLDetail(shortURL)
        #else
        path = [.shortURLDetail(shortURL)]
        #endif
    }

    /// Resolves a route to its screen. Keyed by short-URL identity so selecting
    /// a different link rebuilds the screen (and its store) rather than reusing
    /// stale state.
    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .shortURLDetail(let shortURL):
            DetailScreen(
                shortURL: shortURL,
                client: client,
                listStore: listStore,
                tagsStore: tagsStore,
                onSelectTag: applyTagFilter,
                onDeleted: dismissDetail
            )
            .id(shortURL.id)
        }
    }

    /// Applies a tag filter from the detail screen and returns to the list:
    /// iOS pops the stack to root, macOS clears the detail selection so the
    /// refreshed (filtered) list is what the user lands on.
    private func applyTagFilter(_ tag: String) {
        listStore.setActiveTag(tag)
        #if os(macOS)
        detailDismissCount += 1
        selection = nil
        #else
        path.removeAll()
        #endif
    }

    /// Returns from the detail screen after its link is deleted: iOS pops the
    /// stack, macOS clears the detail selection so the placeholder shows.
    private func dismissDetail() {
        #if os(macOS)
        detailDismissCount += 1
        selection = nil
        #else
        if !path.isEmpty { path.removeLast() }
        #endif
    }

    #if os(macOS)
    /// On the first macOS launch, selects the first link once the list loads so
    /// the detail column isn't left empty. Fires only once (`didAutoSelectFirst`)
    /// and never overrides an existing selection.
    private func autoSelectFirstIfNeeded() {
        guard !didAutoSelectFirst,
              selection == nil,
              let first = listStore.items.first else { return }
        didAutoSelectFirst = true
        selection = .shortURLDetail(first)
    }
    #endif
}

#if os(macOS)
/// The macOS sidebar: "All Links" (clears the filter) above the full tag list.
/// Selecting a row drives the *same* ``ShortURLListStore/activeTag`` the middle
/// list and the detail chips use, so the whole window stays in sync — selecting
/// a tag here filters the content column, and "All Links" resets it. The
/// highlight is read straight from `activeTag`, so a filter set elsewhere (a
/// row chip, a detail tap) reflects back as the selected sidebar row.
///
/// Not a `List`, for the same reason as the link list: the system highlight is
/// gray or the system accent. Rows draw the soft lavender ``SelectionPill``;
/// ↑/↓ move the selection while the sidebar has focus.
private struct TagSidebar: View {
    let listStore: ShortURLListStore
    let tagsStore: TagsStore
    @Environment(AppModel.self) private var appModel
    @FocusState private var isFocused: Bool

    /// A concrete value per row: "All Links" has its own case rather than a
    /// `nil` tag, so every row compares the same way.
    private enum Item: Hashable {
        case allLinks
        case tag(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                SidebarRow(title: "All Links", systemImage: "link", isSelected: current == .allLinks) {
                    select(.allLinks)
                }

                if !tagsStore.tags.isEmpty {
                    Text("Tags")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.top, Space.footBand)
                        .padding(.bottom, Space.hairline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(tagsStore.tags, id: \.self) { tag in
                        SidebarRow(title: tag, systemImage: "tag", isSelected: current == .tag(tag)) {
                            select(.tag(tag))
                        }
                    }
                }
            }
            .padding(.vertical, Space.tight)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
        .sidebarBackground()
        .navigationTitle(appModel.activeInstance?.displayName ?? "Shlinkly")
        .task { tagsStore.loadIfNeeded() }
    }

    /// Every row in order, for keyboard movement.
    private var items: [Item] {
        [.allLinks] + tagsStore.tags.map(Item.tag)
    }

    /// A `nil` filter shows "All Links" selected.
    private var current: Item {
        listStore.activeTag.map(Item.tag) ?? .allLinks
    }

    /// Picking a tag applies it, picking "All Links" clears it.
    private func select(_ item: Item) {
        switch item {
        case .tag(let tag): listStore.setActiveTag(tag)
        case .allLinks: listStore.setActiveTag(nil)
        }
        isFocused = true
    }

    private func move(by offset: Int) -> KeyPress.Result {
        let rows = items
        guard let index = rows.firstIndex(of: current) else { return .ignored }
        let target = index + offset
        guard rows.indices.contains(target) else { return .handled }
        select(rows[target])
        return .handled
    }
}

private extension View {
    /// The sidebar column's background. From macOS 26: none at all, so the
    /// system's floating, frosted Liquid Glass sidebar shows (the window's wash
    /// sits under it). Below 26: the sidebar material with a lavender wash.
    @ViewBuilder
    func sidebarBackground() -> some View {
        if #available(macOS 26, *) {
            scrollContentBackground(.hidden)
        } else {
            background { SidebarBackdrop() }
        }
    }
}

/// One sidebar row: a brand-tinted symbol and the title on the selection pill.
private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Space.tight) {
            Image(systemName: systemImage)
                .foregroundStyle(Palette.accent)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(isSelected ? Palette.accentText : Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.body)
        .padding(.horizontal, 20)
        .frame(minHeight: 28)
        .background { SelectionPill(isSelected: isSelected, isHovering: isHovering) }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
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
