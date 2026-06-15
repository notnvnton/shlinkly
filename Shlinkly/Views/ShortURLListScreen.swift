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
    /// Shared tag cache, used for the iPhone search suggestions and the form's
    /// tag editor.
    private let tagsStore: TagsStore
    /// The active server's client, needed to build the create/edit form.
    private let client: ShlinkClient
    /// Drives the Settings sheet, owned by ``RootView`` so it survives a server
    /// switch; the gear button toggles it.
    @Binding private var showSettings: Bool
    /// Read for the delete-confirmation preferences.
    @Environment(AppModel.self) private var appModel
    /// Drives refresh-on-foreground: when the app/window becomes active again the
    /// current list is re-queried. Tracked on both platforms.
    @Environment(\.scenePhase) private var scenePhase
    @State private var didInitialLoad = false
    /// The create/edit sheet, or `nil` when none is shown.
    @State private var formRoute: FormRoute?
    /// The link awaiting single-delete confirmation.
    @State private var pendingDelete: ShortURL?
    /// A delete failure message to surface in an alert.
    @State private var deleteError: String?
    /// Drives the transient "Copied" toast shown after a copy action (both
    /// platforms). Flipped on with animation, then off ~1.5s later.
    @State private var showCopiedToast = false
    /// Cancels a pending toast-hide so back-to-back copies restart the timer
    /// instead of the first one's timer hiding the second toast early.
    @State private var copiedResetTask: Task<Void, Never>?

    #if os(iOS)
    /// Bumped on each copy to fire a light haptic via `.sensoryFeedback`.
    @State private var copyFeedbackTrigger = 0
    /// The link awaiting the system share sheet, presented from the swipe action
    /// (where `ShareLink` is ignored). `nil` when no share sheet is shown.
    @State private var shareItem: ShareItem?
    /// Shown when the + is tapped and the clipboard looks like it holds a URL.
    @State private var showPasteChoice = false
    /// Multi-select state (iPhone). `isSelecting` swaps the toolbar into a
    /// batch-delete mode; `selectedIDs` tracks the chosen rows.
    @State private var isSelecting = false
    @State private var selectedIDs = Set<ShortURL.ID>()
    @State private var showGroupDeleteConfirm = false
    #endif

    #if os(macOS)
    /// Whether the clipboard currently looks like it holds a URL, refreshed on
    /// appear and on activation. Drives whether the "+" is a pull-down menu
    /// (offering Paste) or a plain button — cached because a menu's items are
    /// built when the toolbar renders, not at click time, and reading the
    /// pasteboard on macOS is synchronous and ungated, so refreshing is cheap.
    @State private var clipboardHasURL = false
    /// Drives the detail column of the split view. macOS selects on tap; iOS
    /// pushes via `NavigationLink` instead and has no selection binding.
    @Binding private var selection: Route?

    init(store: ShortURLListStore, tagsStore: TagsStore, client: ShlinkClient, selection: Binding<Route?>, showSettings: Binding<Bool>) {
        self.store = store
        self.tagsStore = tagsStore
        self.client = client
        _selection = selection
        _showSettings = showSettings
    }
    #else
    init(store: ShortURLListStore, tagsStore: TagsStore, client: ShlinkClient, showSettings: Binding<Bool>) {
        self.store = store
        self.tagsStore = tagsStore
        self.client = client
        _showSettings = showSettings
    }
    #endif

    /// Identifies which form to present so `.sheet(item:)` can rebuild content
    /// per presentation. Create carries an optional clipboard prefill; edit
    /// carries the target link.
    private enum FormRoute: Identifiable {
        case create(prefillURL: String?)
        case edit(ShortURL)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let url): return "edit-\(url.id)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let tag = store.activeTag {
                FilterPill(tag: tag) { store.setActiveTag(nil) }
            }
            content
        }
        .navigationTitle("Links")
        .toolbar { toolbarContent }
        .searchable(text: searchBinding, prompt: Text("Search links"))
        .tagSearchSuggestions(tagSuggestions) { store.applyTagFromSearch($0) }
        #if os(iOS)
        // iPhone: an action sheet rather than a popover, which mis-anchored its
        // arrow to a list row instead of the "+". macOS uses the "+" pull-down.
        .confirmationDialog(
            "You have a link on your clipboard",
            isPresented: $showPasteChoice,
            titleVisibility: .visible
        ) {
            Button("Paste from clipboard") {
                formRoute = .create(prefillURL: Clipboard.peekURLString())
            }
            Button("New link") {
                formRoute = .create(prefillURL: nil)
            }
        }
        #endif
        .sheet(item: $formRoute) { route in
            switch route {
            case .create(let prefill):
                ShortURLFormView(mode: .create, client: client, tagsStore: tagsStore, initialLongURL: prefill) { result in
                    store.insertCreated(result)
                }
            case .edit(let url):
                ShortURLFormView(mode: .edit(url), client: client, tagsStore: tagsStore) { result in
                    store.applyUpdated(result)
                }
            }
        }
        .shortURLDeleteConfirmation(item: $pendingDelete) { url in
            Task { await runDelete(url) }
        }
        .alert("Couldn't delete link", isPresented: deleteErrorBinding, presenting: deleteError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Returning to the foreground (app re-activated on iOS / window became
            // active on macOS): re-query the current list so changes made elsewhere
            // — another device, the web UI, the menu-bar "Generate" action — show
            // up. Skip the first activation; the initial `.task` load covers it, so
            // this never double-loads on launch. `refresh()` keeps the current rows
            // on screen and re-fetches the active page/search/sort.
            if didInitialLoad {
                Task { await store.refresh() }
            }
            #if os(macOS)
            // Also re-check the clipboard so the "+" menu reflects a URL copied
            // while the app was in the background.
            Task { clipboardHasURL = await Clipboard.containsProbableURL() }
            #endif
        }
        .task {
            #if os(macOS)
            clipboardHasURL = await Clipboard.containsProbableURL()
            #endif
            tagsStore.loadIfNeeded()
            guard !didInitialLoad else { return }
            didInitialLoad = true
            store.loadFirstPage()
        }
        .copiedToast(isPresented: showCopiedToast)
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .light), trigger: copyFeedbackTrigger)
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
        #endif
    }

    /// Runs the delete and surfaces a message on the non-success outcomes; the
    /// store removes the row itself on success.
    private func runDelete(_ url: ShortURL) async {
        switch await store.delete(shortCode: url.shortCode, domain: url.domain) {
        case .deleted:
            break
        case .forbidden(let threshold):
            deleteError = ShlinkError.userFacingMessage(for: ShlinkError.deletionForbidden(threshold: threshold))
        case .failed(let message):
            deleteError = message
        }
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    /// Starts a single delete: shows the confirmation when the "a link"
    /// preference is on, otherwise deletes straight away.
    private func requestSingleDelete(_ item: ShortURL) {
        if appModel.preferences.confirmBeforeDeletingOne {
            pendingDelete = item
        } else {
            Task { await runDelete(item) }
        }
    }

    /// Opens the create form, offering to start from a clipboard URL when one is
    /// present (detected without reading; the value is only read if the user taps
    /// "Paste from clipboard").
    private func startCreate() {
        #if os(iOS)
        Task {
            if await Clipboard.containsProbableURL() {
                showPasteChoice = true
            } else {
                formRoute = .create(prefillURL: nil)
            }
        }
        #else
        // macOS opens New Link directly from the empty-state button; the "+"
        // toolbar's pull-down menu is where the Paste-from-clipboard choice lives.
        formRoute = .create(prefillURL: nil)
        #endif
    }

    // MARK: - Row actions

    private func editButton(_ item: ShortURL) -> some View {
        Button {
            formRoute = .edit(item)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
    }

    private func deleteButton(_ item: ShortURL) -> some View {
        Button(role: .destructive) {
            requestSingleDelete(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// The swipe-action delete: red-tinted but *not* `.destructive` role. A
    /// destructive swipe button makes the List animate the row out on tap,
    /// expecting the data source to shrink immediately — but we defer the actual
    /// delete to a confirmation dialog, so the row must stay until confirmed.
    /// Using a tint instead of the role avoids the count-mismatch crash.
    private func swipeDeleteButton(_ item: ShortURL) -> some View {
        Button {
            requestSingleDelete(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(.red)
    }

    /// Copies a link's short URL, fires a light haptic (iOS) and shows the
    /// "Copied" toast. The single entry point for copy across the leading swipe,
    /// the context menu and the macOS hover button. It delegates the actual copy
    /// to ``LinkActions`` so a future widget App Intent can reuse the same logic.
    private func copyShortURL(_ item: ShortURL) {
        LinkActions.copyShortURL(item)
        #if os(iOS)
        copyFeedbackTrigger += 1
        #endif
        presentCopiedToast()
    }

    /// Fades the "Copied" toast in and schedules its fade-out ~1.5s later,
    /// restarting the timer if another copy happens first.
    private func presentCopiedToast() {
        copiedResetTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { showCopiedToast = true }
        copiedResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showCopiedToast = false }
        }
    }

    /// The Copy action, reused by the leading swipe and the context menus.
    private func copyButton(_ item: ShortURL) -> some View {
        Button {
            copyShortURL(item)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }

    /// A native share entry for the context menus (and macOS hover). `ShareLink`
    /// opens the system share sheet itself, so it works everywhere *except*
    /// inside a swipe action — that path uses ``shareShortURL(_:)`` instead.
    @ViewBuilder
    private func shareLink(_ item: ShortURL) -> some View {
        if let url = URL(string: item.shortUrl) {
            ShareLink(item: url)
        }
    }

    #if os(iOS)
    /// Presents the system share sheet for a link via state — used by the swipe
    /// action, where `ShareLink` is ignored and the button must be a `Button`.
    private func shareShortURL(_ item: ShortURL) {
        guard let url = URL(string: item.shortUrl) else { return }
        shareItem = ShareItem(url: url)
    }

    /// The trailing-swipe Share button. A plain `Button` (not `ShareLink`) that
    /// routes through the centralized state-driven share sheet.
    private func swipeShareButton(_ item: ShortURL) -> some View {
        Button {
            shareShortURL(item)
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .tint(.indigo)
    }
    #endif

    /// Tags matching the current search text, surfaced as suggestions while the
    /// user types (iPhone). Empty while not searching, so the URL/code results
    /// show normally.
    private var tagSuggestions: [String] {
        tagsStore.suggestions(for: store.searchTerm)
    }

    #if os(iOS)
    // MARK: - Multi-select (iPhone)

    /// Bridges the selection flag to the list's `editMode`.
    private var editModeBinding: Binding<EditMode> {
        Binding(
            get: { isSelecting ? .active : .inactive },
            set: { isSelecting = ($0 == .active) }
        )
    }

    /// Enters selection mode with `item` pre-selected (the long-pressed row).
    private func enterSelection(_ item: ShortURL) {
        selectedIDs = [item.id]
        isSelecting = true
    }

    private func exitSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    /// Starts a batch delete: confirms when the "several links" preference is on,
    /// otherwise deletes straight away.
    private func requestGroupDelete() {
        guard !selectedIDs.isEmpty else { return }
        if appModel.preferences.confirmBeforeDeletingSeveral {
            showGroupDeleteConfirm = true
        } else {
            Task { await runGroupDelete() }
        }
    }

    /// Deletes every selected link, then leaves selection mode. Reports a single
    /// message if any couldn't be removed.
    private func runGroupDelete() async {
        let targets = store.items.filter { selectedIDs.contains($0.id) }
        var failures = 0
        for target in targets {
            if case .deleted = await store.delete(shortCode: target.shortCode, domain: target.domain) {
                continue
            }
            failures += 1
        }
        exitSelection()
        if failures > 0 {
            deleteError = failures == targets.count
                ? "Couldn't delete the selected links."
                : "Some of the selected links couldn't be deleted."
        }
    }
    #endif

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
                HoverableLinkRow(
                    shortURL: item,
                    onCopy: { copyShortURL(item) },
                    onEdit: { formRoute = .edit(item) },
                    onDelete: { requestSingleDelete(item) },
                    onSelectTag: { store.setActiveTag($0) }
                )
                .tag(Route.shortURLDetail(item))
                .onAppear { store.loadNextPageIfNeeded(currentItem: item) }
                .contextMenu {
                    copyButton(item)
                    shareLink(item)
                    Divider()
                    editButton(item)
                    Divider()
                    deleteButton(item)
                }
            }

            if store.state == .loadingMore {
                loadMoreFooter
            }
        }
        .listStyle(.inset)
        .refreshable { await store.refresh() }
        #else
        List(selection: $selectedIDs) {
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
                .tag(item.id)
                .onAppear { store.loadNextPageIfNeeded(currentItem: item) }
                // Leading: full-swipe copies. Kept as its own block so a Pin
                // button can later sit alongside Copy without restructuring.
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    copyButton(item).tint(.accentColor)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    swipeDeleteButton(item)
                    editButton(item).tint(.blue)
                    swipeShareButton(item)
                }
                .contextMenu {
                    copyButton(item)
                    shareLink(item)
                    Divider()
                    editButton(item)
                    Button {
                        enterSelection(item)
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    Divider()
                    deleteButton(item)
                }
            }

            if store.state == .loadingMore {
                loadMoreFooter
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.editMode, editModeBinding)
        .refreshable { await store.refresh() }
        .shortURLGroupDeleteConfirmation(count: selectedIDs.count, isPresented: $showGroupDeleteConfirm) {
            Task { await runGroupDelete() }
        }
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
                    startCreate()
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

    /// The toolbar swaps to a batch-delete mode while selecting (iPhone);
    /// otherwise it's the gear + sort + add set.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { exitSelection() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    requestGroupDelete()
                } label: {
                    Text(selectedIDs.isEmpty ? "Delete" : "Delete (\(selectedIDs.count))")
                }
                .disabled(selectedIDs.isEmpty)
            }
        } else {
            settingsToolbar
            sortToolbar
            addToolbar
        }
        #else
        settingsToolbar
        refreshToolbar
        sortToolbar
        addToolbar
        #endif
    }

    #if os(macOS)
    /// macOS manual refresh. The Mac has no pull-to-refresh gesture, so the
    /// toolbar button is how the user reloads on demand; it re-queries the active
    /// page/search/sort via ``ShortURLListStore/refresh()``, keeping the current
    /// rows visible. (iOS uses `.refreshable` pull-to-refresh instead.)
    @ToolbarContentBuilder
    private var refreshToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }
    #endif

    /// The gear that opens Settings, pinned to the top-leading corner.
    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        #else
        ToolbarItem(placement: .navigation) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        #endif
    }

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

    /// The "+" that opens the create form, sitting alongside the sort control. On
    /// iOS a plain button (the clipboard choice is an action sheet); on macOS a
    /// pull-down menu offering Paste when the clipboard holds a URL.
    @ToolbarContentBuilder
    private var addToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            #if os(iOS)
            Button {
                startCreate()
            } label: {
                Label("New Link", systemImage: "plus")
            }
            #else
            addMenu
            #endif
        }
    }

    #if os(macOS)
    /// macOS "+": a pull-down menu with Paste/New when the clipboard looks like a
    /// URL, or a plain button that opens New Link when it doesn't — so an empty
    /// clipboard takes a single click and never shows an empty menu.
    @ViewBuilder
    private var addMenu: some View {
        if clipboardHasURL {
            Menu {
                Button("Paste from clipboard") {
                    formRoute = .create(prefillURL: Clipboard.peekURLString())
                }
                Button("New link") {
                    formRoute = .create(prefillURL: nil)
                }
            } label: {
                Label("New Link", systemImage: "plus")
            }
        } else {
            Button {
                formRoute = .create(prefillURL: nil)
            } label: {
                Label("New Link", systemImage: "plus")
            }
        }
    }
    #endif

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

// MARK: - Tag search suggestions (iPhone)

private extension View {
    /// Attaches native tag search suggestions on iOS; a no-op on macOS, where the
    /// sidebar already lists every tag. Tapping a suggestion runs `onSelect`.
    @ViewBuilder
    func tagSearchSuggestions(
        _ tags: [String],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        #if os(iOS)
        self.searchSuggestions {
            ForEach(tags, id: \.self) { tag in
                TagSuggestionRow(tag: tag, onSelect: onSelect)
            }
        }
        #else
        self
        #endif
    }
}

#if os(iOS)
/// One tappable tag suggestion. Lives inside the searchable scope so it can read
/// `dismissSearch` to close the search UI once a tag is chosen.
private struct TagSuggestionRow: View {
    let tag: String
    let onSelect: (String) -> Void
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        Button {
            onSelect(tag)
            dismissSearch()
        } label: {
            Label(tag, systemImage: "tag")
        }
    }
}
#endif

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

// MARK: - Hover-reveal row actions (macOS)

#if os(macOS)
/// A macOS list row whose trailing accessory swaps on hover. At rest it shows
/// the visit count; when the cursor is over the row the count fades out and
/// **Edit**/**Delete** buttons fade in *in the same place* — so the buttons
/// replace the count rather than overlapping it. Unlike a swipe (undiscoverable,
/// non-native on the Mac), the buttons advertise themselves on hover. Delete
/// routes through the same central confirmation alert as the context menu — it
/// never deletes silently. Row selection (a plain tap) and the context menu are
/// unaffected: the buttons capture their own clicks, and while hidden they ignore
/// hit-testing so a click in that area still selects the row.
private struct HoverableLinkRow: View {
    let shortURL: ShortURL
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSelectTag: (String) -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ShortURLRowPrimary(shortURL: shortURL)
                Spacer(minLength: 8)
                trailingAccessory
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())

            if !shortURL.tags.isEmpty {
                RowTags(tags: shortURL.tags, onSelectTag: onSelectTag)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    /// The visit count and the action buttons stacked in one place, cross-fading
    /// by hover. The ZStack sizes to the wider (buttons) child, so the trailing
    /// edge doesn't shift between states.
    private var trailingAccessory: some View {
        ZStack(alignment: .trailing) {
            VisitsCountLabel(total: shortURL.visitsSummary.total)
                .opacity(isHovering ? 0 : 1)

            hoverActions
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 2) {
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 20, height: 20)
            }
            .help("Copy short URL")

            if let url = URL(string: shortURL.shortUrl) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 20, height: 20)
                }
                .help("Share")
            }

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .frame(width: 20, height: 20)
            }
            .help("Edit")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 20, height: 20)
            }
            .help("Delete")
        }
        .buttonStyle(.borderless)
    }
}
#endif

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
