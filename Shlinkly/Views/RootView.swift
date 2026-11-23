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
        #if os(iOS)
        // The Mac has its own Settings window (the `Settings` scene).
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .brandTint()
        }
        #else
        // `.win`: one continuous surface. The desktop blurred behind the
        // window under the `--win` wash; every column sits on it.
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
    /// The sidebar's visibility, driven by our own toggle (``SidebarToggleButton``)
    /// rather than the system's, so it sits where `MacMain` draws it.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 216 pt panel plus its 8 pt inset (`MacMain`). Our sidebar toggle
            // sits at the right end of the panel's top row.
            TagSidebar(listStore: listStore, tagsStore: tagsStore, onToggleSidebar: { toggleSidebar() })
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 280)
        } content: {
            // With the sidebar hidden, the same toggle sits at the start of the
            // list header, after the traffic lights: always exactly one.
            ShortURLListScreen(store: listStore, tagsStore: tagsStore, client: client, selection: $selection, detailDismissCount: detailDismissCount, showSettings: $showSettings)
                .showingSidebarToggle(sidebarRevealAction)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 300, ideal: 330)
        } detail: {
            if let selection {
                destination(selection)
            } else {
                DetailPlaceholder()
            }
        }
        // The title bar as drawn: the columns draw their own header rows
        // (``MacTitleRow``), so the window has no system title (the scene's
        // `.hiddenTitleBar`), no toolbar and no system sidebar toggle in any
        // state. ⌃⌘S and View › Toggle Sidebar belong to the split view, not
        // the toolbar, and keep working.
        .toolbar(removing: .sidebarToggle)
        .hidingWindowToolbar()
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
    /// The list header's "show sidebar" action, only while the sidebar is hidden.
    private var sidebarRevealAction: (() -> Void)? {
        guard columnVisibility != .all else { return nil }
        return { toggleSidebar() }
    }

    /// Hides or shows the sidebar column.
    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .all ? .doubleColumn : .all
        }
    }

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
/// The macOS sidebar (`.msidebar`): "All Links" (clears the filter) above the
/// "Tags" label and the full tag list, as `.mrow` rows. Selecting a row drives
/// the *same* ``ShortURLListStore/activeTag`` the middle list and the detail
/// chips use, so the whole window stays in sync. The highlight is read straight
/// from `activeTag`, so a filter set elsewhere reflects back here.
///
/// Not a `List`: the system highlight is gray or the system accent; the layout
/// draws a `--sel` pill. ↑/↓ move the selection while the sidebar has focus.
private struct TagSidebar: View {
    let listStore: ShortURLListStore
    let tagsStore: TagsStore
    /// Hides the sidebar (the toggle at the right end of the panel's top row).
    let onToggleSidebar: () -> Void
    @Environment(AppModel.self) private var appModel
    @FocusState private var isFocused: Bool

    /// A concrete value per row: "All Links" has its own case rather than a
    /// `nil` tag, so every row compares the same way.
    private enum Item: Hashable {
        case allLinks
        case tag(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The panel's 44 pt top row: the traffic lights (system) on the
            // left, the toggle 10 pt from the panel's right edge.
            MacTitleRow(height: 44) { _ in
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SidebarToggleButton(isSidebarVisible: true, action: onToggleSidebar)
                }
                .padding(.trailing, 10)
            }
            tagList
        }
        .ignoresSafeArea(.container, edges: .top)
        .sidebarBackground()
        .navigationTitle(appModel.activeInstance?.displayName ?? "Shlinkly")
        .task { tagsStore.loadIfNeeded() }
    }

    private var tagList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    SidebarRow(title: "All Links", systemImage: "link", isSelected: current == .allLinks) {
                        select(.allLinks)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                if !tagsStore.tags.isEmpty {
                    MacLabel("Tags")
                        .padding(.top, 14)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(tagsStore.tags, id: \.self) { tag in
                            SidebarRow(title: tag, systemImage: "tag", isSelected: current == .tag(tag)) {
                                select(.tag(tag))
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .padding(.bottom, 8)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
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
    /// Hides the window toolbar: the header rows are drawn by the columns.
    /// `toolbarVisibility(_:for:)` from macOS 15, its predecessor
    /// `toolbar(_:for:)` (macOS 13) below.
    @ViewBuilder
    func hidingWindowToolbar() -> some View {
        if #available(macOS 15, *) {
            toolbarVisibility(.hidden, for: .windowToolbar)
        } else {
            toolbar(.hidden, for: .windowToolbar)
        }
    }

    /// The sidebar column's background. From macOS 26: none, so the system's
    /// floating glass sidebar is the drawn panel. Below 26: the window surface
    /// with the `.msidebar` panel on it.
    @ViewBuilder
    func sidebarBackground() -> some View {
        if #available(macOS 26, *) {
            scrollContentBackground(.hidden)
        } else {
            background {
                ZStack {
                    WindowBackdrop()
                    SidebarPanel()
                        .ignoresSafeArea()
                }
            }
        }
    }
}

/// One `.mrow` sidebar row: a 15 pt glyph in `--brand-text` (`--sel-text` when
/// selected) and the 13 pt title (medium when selected), 6 pt / 10 pt in.
private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Palette.selText : Palette.brand)
                .frame(width: 15, height: 15)
                .accessibilityHidden(true)
            Text(title)
                .layoutFont(13, isSelected ? .medium : .regular)
                .foregroundStyle(isSelected ? Palette.selText : Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background { MacRowBackground(isSelected: isSelected, isHovering: isHovering) }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
    }
}

/// Detail stub shown until a link is selected (not drawn; kept, in the
/// layout's text colors).
private struct DetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 0) {
            // The detail header row without controls, so the window still
            // drags from here.
            MacTitleRow(height: 52) { _ in Color.clear }
            ContentUnavailableView {
                Label("Select a link", systemImage: "link")
                    .foregroundStyle(Palette.text)
            } description: {
                Text("Choose a short URL to see its details.")
                    .foregroundStyle(Palette.text2)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}
#endif

// MARK: - Preview

#if DEBUG && os(macOS)
/// The whole Mac window as `MacMain` draws it: sidebar, list column and detail
/// column, from seeded stores (nothing talks to a server).
private struct MacMainPreview: View {
    var sidebarVisible = true
    @State private var listStore = ShortURLListStore.preview(items: ShortURLListScreenPreview.items)
    @State private var tagsStore = TagsStore.preview(tags: ["books", "library", "test", "website"])
    @State private var appModel = AppModel(spotlight: nil)
    @State private var selection: Route? = .shortURLDetail(ShortURLListScreenPreview.items[1])

    var body: some View {
        let client = ShlinkClient(baseURL: URL(string: "https://preview.invalid/rest/v3/")!, apiKey: "preview")
        NavigationSplitView(columnVisibility: .constant(sidebarVisible ? .all : .doubleColumn)) {
            TagSidebar(listStore: listStore, tagsStore: tagsStore, onToggleSidebar: {})
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 280)
        } content: {
            ShortURLListScreen(store: listStore, tagsStore: tagsStore, client: client, selection: $selection,
                               detailDismissCount: 0, showSettings: .constant(false))
                .skippingInitialLoad()
                .showingSidebarToggle(sidebarVisible ? nil : {})
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 300, ideal: 330)
        } detail: {
            DetailScreenPreviewData.screen(period: .allTime)
        }
        .toolbar(removing: .sidebarToggle)
        .hidingWindowToolbar()
        .background { WindowBackdrop() }
        .environment(appModel)
        .brandTint()
        .frame(width: 1280, height: 780)
    }
}

#Preview("MacMain light") {
    MacMainPreview()
        .preferredColorScheme(.light)
}

#Preview("MacMain dark") {
    MacMainPreview()
        .preferredColorScheme(.dark)
}

#Preview("MacMain, sidebar hidden") {
    MacMainPreview(sidebarVisible: false)
        .preferredColorScheme(.light)
}
#endif
