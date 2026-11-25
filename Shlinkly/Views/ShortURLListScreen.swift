//
//  ShortURLListScreen.swift
//  Shlinkly
//

import SwiftUI
import os
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
    /// Whether the clipboard currently looks like it holds a URL, refreshed on
    /// `.task` and on scenePhase → `.active`. Drives whether the "+" toolbar item
    /// is a `Menu` (offering Paste) or a plain button — cached because a `Menu`'s
    /// items are built when the toolbar renders, not at tap time. Probed via
    /// `Clipboard.containsProbableURL()`, which never reveals the contents (no iOS
    /// "pasted from" banner). Shared by iOS and macOS.
    @State private var clipboardHasURL = false
    /// `false` only in previews, whose store is seeded and must not hit a
    /// server.
    private var loadsOnAppear = true
    #if os(macOS)
    /// Shows the sidebar again: set while the sidebar is hidden, so its toggle
    /// sits at the start of the list header (see ``showingSidebarToggle(_:)``).
    private var showSidebar: (() -> Void)?
    #endif
    #if os(iOS)
    /// Whether the search card's field has focus; choosing a tag suggestion
    /// clears it, closing the keyboard.
    @FocusState private var isSearchFocused: Bool
    #endif

    #if os(iOS)
    /// Bumped on each copy to fire a light haptic via `.sensoryFeedback`.
    @State private var copyFeedbackTrigger = 0
    /// The link awaiting the system share sheet, presented from the swipe action
    /// (where `ShareLink` is ignored). `nil` when no share sheet is shown.
    @State private var shareItem: ShareItem?
    /// Multi-select state (iPhone). `isSelecting` swaps the toolbar into a
    /// batch-delete mode; `selectedIDs` tracks the chosen rows.
    @State private var isSelecting = false
    @State private var selectedIDs = Set<ShortURL.ID>()
    @State private var showGroupDeleteConfirm = false
    #endif

    #if os(macOS)
    /// True while a toolbar-initiated refresh is in flight, so the button shows a
    /// small inline spinner instead of a full-screen overlay — the list stays put.
    @State private var isRefreshing = false
    /// Drives the detail column of the split view. macOS selects on tap; iOS
    /// pushes via `NavigationLink` instead and has no selection binding.
    @Binding private var selection: Route?
    /// How many times the detail has been closed on purpose upstream; see
    /// ``restoreSelectionIfDropped(from:to:)``.
    private let detailDismissCount: Int
    /// True while a coordinated refresh is running, so a second one is queued
    /// instead of racing it (the store itself doesn't serialize refreshes).
    @State private var refreshInFlight = false
    /// A refresh was asked for while one was running: run exactly one more when
    /// it lands, however many requests piled up.
    @State private var refreshQueued = false
    /// The selection as it stood when the current refresh began, kept for a
    /// moment after it lands — the window in which the `List` may drop a
    /// selection whose row the refresh removed.
    @State private var heldSelection: Route?
    @State private var heldDismissCount = 0
    @State private var releaseHeldSelectionTask: Task<Void, Never>?
    /// Whether the link list has keyboard focus, so ↑/↓ move the selection.
    @FocusState private var isListFocused: Bool

    private static let refreshLog = Logger(subsystem: "de.ahodge.shlinkly", category: "ListRefresh")

    init(store: ShortURLListStore, tagsStore: TagsStore, client: ShlinkClient, selection: Binding<Route?>, detailDismissCount: Int, showSettings: Binding<Bool>) {
        self.store = store
        self.tagsStore = tagsStore
        self.client = client
        _selection = selection
        self.detailDismissCount = detailDismissCount
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

    /// The spring that drives row add/delete/reorder. Declared on the List (keyed
    /// to `store.items`, which is `Equatable`) rather than wrapped around the
    /// store's mutations — a `withAnimation` inside the `@Observable` store's
    /// async paths never reaches this view, so the animation was lost. Driving it
    /// from the value here is what actually animates the List's native row diff.
    private static let listAnimation: Animation = .spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        screen
        .navigationTitle("Links")
        .sheet(item: $formRoute) { route in
            Group {
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
            .brandTint()
        }
        .shortURLDeleteConfirmation(item: $pendingDelete) { url in
            Task { await runDelete(url) }
        }
        .alert("Couldn't delete link", isPresented: deleteErrorBinding, presenting: deleteError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        #if os(macOS)
        // Links created without this screen's form (menu bar, Share Extension)
        // and plain app activation, funnelled through ``AppModel``.
        .onChange(of: appModel.externalLinksChange) { old, new in
            // A creation anywhere among the signals since the last one seen
            // forces the refresh; activation alone is only a hint.
            let created = new.lastCreationSerial > old.serial
            requestRefresh(trigger: created ? "a link was created outside the list" : "app became active",
                           force: created)
        }
        .onChange(of: selection) { old, new in
            restoreSelectionIfDropped(from: old, to: new)
        }
        #endif
        .onChange(of: scenePhase) { old, phase in
            #if os(macOS)
            // Diagnostic: shows on-device whether `.active` ever arrives here.
            Self.refreshLog.notice("ListRefresh: scenePhase (list) \(String(describing: old), privacy: .public) → \(String(describing: phase), privacy: .public)")
            #endif
            guard phase == .active else { return }
            // Returning to the foreground (app re-activated on iOS / window became
            // active on macOS): re-query the current list so changes made elsewhere
            // — another device, the web UI, the menu-bar "Generate" action — show
            // up. Skip the first activation; the initial `.task` load covers it, so
            // this never double-loads on launch. `refresh()` keeps the current rows
            // on screen and re-fetches the active page/search/sort.
            if didInitialLoad {
                #if os(macOS)
                requestRefresh(trigger: "scenePhase became active", force: false)
                #else
                Task { await store.refresh() }
                #endif
            }
            // Also re-check the clipboard so the "+" menu reflects a URL copied
            // while the app was backgrounded/inactive.
            Task { clipboardHasURL = await Clipboard.containsProbableURL() }
        }
        .task {
            clipboardHasURL = await Clipboard.containsProbableURL()
            guard loadsOnAppear else { return }
            tagsStore.loadIfNeeded()
            guard !didInitialLoad else { return }
            didInitialLoad = true
            store.loadFirstPage()
        }
        // A create request parked by a deep link (the widget's buttons) opens the
        // very same form the "+" menu does — including the clipboard prefill, read
        // here in the app at open time, never in the widget process.
        .onChange(of: appModel.pendingCreate, initial: true) { _, request in
            guard let request else { return }
            appModel.pendingCreate = nil
            formRoute = .create(prefillURL: request.fromClipboard ? Clipboard.peekURLString() : nil)
        }
        .copiedToast(isPresented: showCopiedToast)
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .light), trigger: copyFeedbackTrigger)
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
        #endif
    }

    #if os(macOS)
    // MARK: - Coordinated refresh (macOS)

    /// Asks for a background refresh. A forced one (a link really was created
    /// elsewhere) always runs; an unforced one (the app merely became active)
    /// is skipped while pages beyond the first are loaded, because a refresh
    /// re-fetches page 1 only and would throw them — and the scroll position —
    /// away on every return to the app.
    private func requestRefresh(trigger: String, force: Bool) {
        guard didInitialLoad else {
            Self.refreshLog.notice("ListRefresh: \(trigger, privacy: .public) — skipped: initial load hasn't run yet")
            return
        }
        if !force, store.hasLoadedBeyondFirstPage {
            Self.refreshLog.notice("ListRefresh: \(trigger, privacy: .public) — skipped: paged")
            return
        }
        Task { await coordinatedRefresh(trigger: trigger, force: force) }
    }

    /// Runs ``ShortURLListStore/refresh()`` one at a time. A request arriving
    /// mid-refresh never starts a second one. A forced request queues a single
    /// follow-up instead — the link it reports may have been created after the
    /// running request left — so a burst of them collapses into one extra fetch.
    /// An unforced one (activation, which usually arrives twice: from AppKit and
    /// from `scenePhase`) carries no news of its own and is simply dropped.
    private func coordinatedRefresh(trigger: String, force: Bool) async {
        if refreshInFlight, !force {
            Self.refreshLog.notice("ListRefresh: \(trigger, privacy: .public) — skipped: refresh already running")
            return
        }
        if refreshInFlight {
            refreshQueued = true
            Self.refreshLog.notice("ListRefresh: \(trigger, privacy: .public) — refresh already running, queued one follow-up")
            return
        }
        refreshInFlight = true
        Self.refreshLog.notice("ListRefresh: \(trigger, privacy: .public) — refresh started")
        repeat {
            if refreshQueued {
                Self.refreshLog.notice("ListRefresh: running the queued follow-up refresh")
            }
            refreshQueued = false
            releaseHeldSelectionTask?.cancel()
            heldSelection = selection
            heldDismissCount = detailDismissCount
            await store.refresh()
            resyncSelectionAfterRefresh()
        } while refreshQueued
        refreshInFlight = false
        Self.refreshLog.notice("ListRefresh: refresh finished — \(store.items.count, privacy: .public) row(s)")
        // The `List` may report a dropped selection a beat after the rows change.
        releaseHeldSelectionTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            heldSelection = nil
        }
    }

    /// The link a route points at, by identity.
    private func linkID(_ route: Route?) -> String? {
        guard case .shortURLDetail(let shortURL)? = route else { return nil }
        return shortURL.id
    }

    /// Rows are tagged with the whole link value, so a refreshed copy of the
    /// selected link (a new visit count, say) no longer matches the selection
    /// and its row would lose the highlight. Re-point the selection at the fresh
    /// copy; the detail is keyed by identity, so it isn't rebuilt.
    private func resyncSelectionAfterRefresh() {
        guard case .shortURLDetail(let current)? = selection else { return }
        if let fresh = store.items.first(where: { $0.id == current.id }) {
            if fresh != current { selection = .shortURLDetail(fresh) }
        } else {
            Self.refreshLog.notice("ListRefresh: the open link is no longer on the first page — keeping its detail open")
        }
    }

    /// Puts the selection back when the `List` cleared it because a refresh
    /// took its row away: the detail the user has open stays open. Left alone
    /// when the detail was closed on purpose (`detailDismissCount` moved), when
    /// the row is still there (the user deselected it), or outside a refresh.
    private func restoreSelectionIfDropped(from old: Route?, to new: Route?) {
        guard new == nil,
              let droppedID = linkID(old),
              droppedID == linkID(heldSelection),
              detailDismissCount == heldDismissCount,
              !store.items.contains(where: { $0.id == droppedID }) else { return }
        Self.refreshLog.notice("ListRefresh: the list dropped the selection after a refresh — restoring it")
        selection = old
    }
    #endif

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

    /// Opens a blank create form. Used by the empty-state "Create First Link"
    /// button; the clipboard Paste choice lives on the "+" toolbar item's `Menu`
    /// (see `addMenu`), not here.
    private func startCreate() {
        formRoute = .create(prefillURL: nil)
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
    /// routes through the centralized state-driven share sheet. No tint: the
    /// system's neutral swipe gray keeps it apart from the accent Edit.
    private func swipeShareButton(_ item: ShortURL) -> some View {
        Button {
            shareShortURL(item)
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
    #endif

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

    // MARK: - Screen

    /// `MacMain` list column: the header row, the gray search field 8 pt
    /// under it, then the rows. `PhoneList`: one scrolling page (large title, search card, tag
    /// chips, the rows card) with "New link" in the bottom bar.
    @ViewBuilder
    private var screen: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            macHeader
            macSearchField
            if let tag = store.activeTag {
                macFilterPill(tag)
            }
            macContent
        }
        .ignoresSafeArea(.container, edges: .top)
        #else
        phoneList
            .canvasBackground()
            .navigationBarTitleDisplayMode(.inline)
            // `PhoneList`'s bar is drawn (``phoneNavBar``): the system bar
            // places its items on its own. Hidden on this screen only; the
            // detail keeps its system bar and back button.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { phoneNavBar }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isSelecting {
                    BottomBar(column: true) { newLinkButton }
                }
            }
        #endif
    }

    #if os(macOS)
    // MARK: - Mac list column

    /// The list column's 52 pt header row (`MacMain`), on the traffic lights'
    /// line: "Links" (15 pt semibold) 18 pt in, Refresh, Sort and "+" at the
    /// trailing edge, the last one 12 pt in, everything 10 pt apart (the
    /// `.titlebar` gap). "Links" truncates before it can reach the buttons.
    /// With the sidebar hidden its toggle comes first, 12 pt after the
    /// traffic lights, and "Links" 12 pt after the toggle.
    private var macHeader: some View {
        MacTitleRow(height: 52) { lightsTrailing in
            HStack(spacing: 0) {
                if let showSidebar {
                    SidebarToggleButton(isSidebarVisible: false, action: showSidebar)
                        .padding(.leading, (lightsTrailing ?? 0) + 12)
                    macHeaderTitle
                        .padding(.leading, 12)
                } else {
                    macHeaderTitle
                        .padding(.leading, 18)
                }
                Spacer(minLength: 10)
                macHeaderButtons
                    .fixedSize()
                    .padding(.trailing, 12)
            }
        }
    }

    /// "Links". Clicks fall through to the row, so it drags the window too.
    private var macHeaderTitle: some View {
        Text("Links")
            .layoutFont(15, .semibold)
            .foregroundStyle(Palette.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isHeader)
    }

    /// The search field under the list column's title bar: 28 pt, radius 7,
    /// `--seg-track`, a 12 pt magnifier, 13 pt text.
    private var macSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.text2)
                .accessibilityHidden(true)
            TextField("Search links", text: searchBinding, prompt: Text("Search links").foregroundStyle(Palette.text2))
                .textFieldStyle(.plain)
                .layoutFont(13)
                .foregroundStyle(Palette.text)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Palette.segTrack, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// The active tag filter: a `.tag` "tag ×" 8 pt under the search field,
    /// lined up with the rows' text (18 pt in). × clears the filter.
    private func macFilterPill(_ tag: String) -> some View {
        HStack(spacing: 0) {
            TagView(text: tag, onRemove: { store.setActiveTag(nil) })
                .accessibilityLabel("Filtered by tag \(tag)")
            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var macContent: some View {
        switch store.state {
        case .loading:
            macLoadingView
        case .empty:
            macStateView(title: filterActive ? "No matches" : "No links yet",
                         message: emptyDescription,
                         actionTitle: filterActive ? nil : "Create First Link") { startCreate() }
        case .error(let message):
            macStateView(title: "Couldn't load links", message: message,
                         actionTitle: "Try Again") { store.loadFirstPage() }
        case .loaded, .loadingMore:
            macListView
        }
    }

    // Not a `List`: the Mac's `List` draws its selection in the system accent
    // color and offers no way to replace it. A lazy stack draws the `--sel`
    // pill itself and keeps the same `selection` binding, so the detail column,
    // the refresh resync and the ListRefresh restore all work unchanged. ↑/↓
    // move the selection while the list has focus (a click on a row gives it
    // focus).
    private var macListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.items) { item in
                        MacLinkRow(
                            shortURL: item,
                            isSelected: item.id == selectedLinkID,
                            onSelect: { select(item) },
                            onCopy: { copyShortURL(item) },
                            onEdit: { formRoute = .edit(item) },
                            onDelete: { requestSingleDelete(item) },
                            onSelectTag: { store.setActiveTag($0) }
                        )
                        .id(item.id)
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
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .animation(Self.listAnimation, value: store.items)
            }
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { moveSelection(by: -1, proxy: proxy) }
            .onKeyPress(.downArrow) { moveSelection(by: 1, proxy: proxy) }
            .accessibilityLabel("Links")
        }
    }

    private var macLoadingView: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(0..<8, id: \.self) { _ in
                    SkeletonRow()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 8)
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading links")
    }

    /// Empty and error states (not drawn): the message in the layout's text
    /// colors and a `.mbtn-primary` action.
    private func macStateView(title: String, message: String, actionTitle: String?,
                              action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .layoutFont(15, .semibold)
                .foregroundStyle(Palette.text)
            Text(message)
                .layoutFont(13)
                .foregroundStyle(Palette.text2)
                .multilineTextAlignment(.center)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.macPrimary)
                    .padding(.top, 6)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mac selection & keyboard

    /// The selected link's identity. Matched by id, not value, so a refreshed
    /// copy of the link (new visit count) stays highlighted.
    private var selectedLinkID: String? { linkID(selection) }

    /// A click on a row selects it and gives the list keyboard focus.
    private func select(_ item: ShortURL) {
        selection = .shortURLDetail(item)
        isListFocused = true
    }

    /// ↑/↓: moves the selection to the neighbouring row (or the first / last
    /// row when nothing is selected) and scrolls just enough to show it.
    private func moveSelection(by offset: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        let items = store.items
        guard !items.isEmpty else { return .ignored }
        let current = items.firstIndex { $0.id == selectedLinkID }
        let target = current.map { $0 + offset } ?? (offset > 0 ? 0 : items.count - 1)
        guard items.indices.contains(target) else { return .handled }
        selection = .shortURLDetail(items[target])
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(items[target].id)
        }
        return .handled
    }
    #endif

    #if os(iOS)
    // MARK: - iPhone list

    /// The whole `PhoneList` page as one `List`, so pull-to-refresh, swipe
    /// actions, the context menu and multi-select keep working: the header rows
    /// (title, search card, tag chips) sit on the screen background, and the
    /// link rows each draw their slice of the rows card.
    private var phoneList: some View {
        List(selection: $selectedIDs) {
            Text("Links")
                .layoutFont(30, .semibold, tracking: -0.3)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
                .pageRow(top: 6)

            phoneSearchField
                .tagSearchSuggestions(tagSuggestions) { tag in
                    store.applyTagFromSearch(tag)
                    isSearchFocused = false
                }
                .pageRow(top: 14)

            if !tagsStore.tags.isEmpty {
                tagChips
                    .pageRow(top: 12, horizontal: 0)
            }

            switch store.state {
            case .loading:
                ForEach(0..<8, id: \.self) { index in
                    SkeletonRow()
                        .padding(.horizontal, 16)
                        .frame(minHeight: 62)
                        .background { RowsCardSegment(isFirst: index == 0, isLast: index == 7) }
                        .redacted(reason: .placeholder)
                        .pageRow(top: index == 0 ? 16 : 0)
                }
                .accessibilityLabel("Loading links")
            case .empty:
                phoneStateView(title: filterActive ? "No matches" : "No links yet",
                               message: emptyDescription, actionTitle: nil) {}
            case .error(let message):
                phoneStateView(title: "Couldn't load links", message: message,
                               actionTitle: "Try Again") { store.loadFirstPage() }
            case .loaded, .loadingMore:
                phoneLinkRows
                if store.state == .loadingMore {
                    loadMoreFooter
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padContentColumnMargins()
        .environment(\.defaultMinListRowHeight, 0)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.editMode, editModeBinding)
        .refreshable { await store.refresh() }
        .animation(Self.listAnimation, value: store.items)
        .shortURLGroupDeleteConfirmation(count: selectedIDs.count, isPresented: $showGroupDeleteConfirm) {
            Task { await runGroupDelete() }
        }
    }

    /// The rows card: 62 pt rows, 1 pt `--sep` lines between them.
    private var phoneLinkRows: some View {
        ForEach(store.items) { item in
            let isFirst = item.id == store.items.first?.id
            let isLast = item.id == store.items.last?.id
            PhoneLinkRow(shortURL: item)
                // The hidden link makes the whole row navigate, without the
                // disclosure chevron the layout doesn't draw.
                .background {
                    NavigationLink(value: Route.shortURLDetail(item)) { EmptyView() }
                        .opacity(0)
                }
                .background { RowsCardSegment(isFirst: isFirst, isLast: isLast) }
                .pageRow(top: isFirst ? 16 : 0)
                .tag(item.id)
                .onAppear { store.loadNextPageIfNeeded(currentItem: item) }
                // Leading: full-swipe copies. Kept as its own block so a Pin
                // button can later sit alongside Copy without restructuring.
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    copyButton(item).tint(Palette.brand)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    swipeDeleteButton(item)
                    editButton(item).tint(Palette.brand)
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
    }

    /// The search card: 44 pt, a 15 pt magnifier, 16 pt text.
    private var phoneSearchField: some View {
        LayoutCard {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.text2)
                    .accessibilityHidden(true)
                TextField("Search links", text: searchBinding, prompt: Text("Search links").foregroundStyle(Palette.text2))
                    .layoutFont(16)
                    .foregroundStyle(Palette.text)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
        }
    }

    /// The tag filter chips: "All" plus every tag. They drive the same
    /// ``ShortURLListStore/activeTag`` the Mac sidebar uses.
    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isOn: store.activeTag == nil) {
                    store.setActiveTag(nil)
                }
                ForEach(tagsStore.tags, id: \.self) { tag in
                    FilterChip(title: tag, isOn: store.activeTag == tag) {
                        store.setActiveTag(tag)
                    }
                }
            }
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    /// Empty and error states (not drawn): the message in the layout's text
    /// colors and a `.btn-text` action.
    private func phoneStateView(title: String, message: String, actionTitle: String?,
                                action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .layoutFont(17, .semibold)
                .foregroundStyle(Palette.text)
            Text(message)
                .layoutFont(15)
                .foregroundStyle(Palette.text2)
                .multilineTextAlignment(.center)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.layoutText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .pageRow(top: 16)
    }

    /// "New link", the screen's main action. With a URL on the clipboard it is a
    /// `Menu` (Paste / New), otherwise a plain button. See the invariant on
    /// ``addMenu``: the choice is owned by this button, never a screen-root
    /// dialog.
    @ViewBuilder
    private var newLinkButton: some View {
        if clipboardHasURL {
            Menu {
                Button("Paste from clipboard") {
                    formRoute = .create(prefillURL: Clipboard.peekURLString())
                }
                Button("New link") {
                    formRoute = .create(prefillURL: nil)
                }
            } label: {
                PrimaryButtonFace(title: "New link")
            }
        } else {
            Button("New link") {
                formRoute = .create(prefillURL: nil)
            }
            .buttonStyle(.layoutPrimary)
        }
    }

    /// The server pill: the active server's host. It opens a menu of the
    /// configured servers and switches between them.
    private var serverPill: some View {
        Menu {
            ForEach(appModel.instanceStore.instances) { instance in
                Button {
                    appModel.selectInstance(instance.id)
                } label: {
                    if instance.id == appModel.activeInstance?.id {
                        Label(instance.displayName, systemImage: "checkmark")
                    } else {
                        Text(instance.displayName)
                    }
                }
            }
        } label: {
            ServerPillLabel(title: serverTitle)
        }
        .accessibilityLabel("Server, \(serverTitle)")
    }

    private var serverTitle: String {
        guard let active = appModel.activeInstance else { return "Server" }
        return active.baseURL.host ?? active.displayName
    }

    /// Sort (`PhoneList`, left of the server pill): a 44 pt `.iconbtn` with the
    /// 19 pt sort glyph in `--brand-text`. The same "Sort by" menu as before
    /// layout v3: Newest or Most visited, bound to the store's order.
    private var phoneSortMenu: some View {
        Menu {
            Picker("Sort by", selection: orderBinding) {
                Label("Newest", systemImage: "clock").tag(ShortURLsOrder.newest)
                Label("Most visited", systemImage: "eye").tag(ShortURLsOrder.mostVisited)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Palette.brand)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Sort")
    }

    /// Tags matching the current search text, offered under the search card
    /// while the user types. Empty while not searching, so the URL/code results
    /// show normally.
    private var tagSuggestions: [String] {
        tagsStore.suggestions(for: store.searchTerm)
    }
    #endif

    private var loadMoreFooter: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 8)
        #if os(iOS)
        .pageRow(top: 0)
        #endif
    }

    // MARK: - Toolbar & bindings

    #if os(iOS)
    /// `PhoneList`'s `.navbar`, drawn and pinned: 44 pt, 8 pt in on the
    /// leading side, 16 pt on the trailing side. The gear (a 44 pt `.iconbtn`)
    /// at the leading edge; Sort (44 pt) and the server pill, 2 pt apart, at
    /// the trailing edge. No inline title: the page draws its large "Links".
    /// While selecting (not drawn) it holds Cancel and Delete, their text
    /// 16 pt from the edges. Its background is `--bg`'s top color, so rows
    /// scroll under it.
    private var phoneNavBar: some View {
        HStack(spacing: 0) {
            if isSelecting {
                Button("Cancel") { exitSelection() }
                    .buttonStyle(.navLink())
                    .padding(.leading, 8)
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    requestGroupDelete()
                } label: {
                    Text(selectedIDs.isEmpty ? "Delete" : "Delete (\(selectedIDs.count))")
                }
                .buttonStyle(TextButtonStyle(role: .danger, size: 17))
                .disabled(selectedIDs.isEmpty)
            } else {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Palette.brand)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    phoneSortMenu
                    serverPill
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(height: 44)
        .background {
            Color(light: hex(0xF5F5F8), dark: hex(0x25232E))
                .ignoresSafeArea(edges: .top)
        }
    }
    #endif

    #if os(macOS)
    /// Refresh, Sort and "+", 10 pt apart (the `.titlebar` gap).
    private var macHeaderButtons: some View {
        HStack(spacing: 10) {
            refreshButton
            sortMenu
            addMenu
        }
    }

    /// Manual refresh (`.mbtn-sq`). The Mac has no pull-to-refresh, so this is
    /// how the user reloads on demand; it re-queries the active
    /// page/search/sort, keeping the current rows visible. A small spinner
    /// replaces the glyph while it runs.
    private var refreshButton: some View {
        Button {
            Task {
                isRefreshing = true
                await coordinatedRefresh(trigger: "toolbar button", force: true)
                isRefreshing = false
            }
        } label: {
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .buttonStyle(.macSquare)
        .disabled(isRefreshing)
        .help("Refresh")
        .accessibilityLabel("Refresh")
    }

    /// Sort (`.mbtn-sq`): Newest or Most visited.
    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: orderBinding) {
                Label("Newest", systemImage: "clock").tag(ShortURLsOrder.newest)
                Label("Most visited", systemImage: "eye").tag(ShortURLsOrder.mostVisited)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.macSquare)
        .help("Sort")
        .accessibilityLabel("Sort")
    }
    #endif

    /// The Mac's "+" (`.mbtn-sq.mbtn-primary`).
    ///
    /// REGRESSION GUARD — invariant: the clipboard choice MUST be owned by the
    /// new-link button itself (a `Menu` anchored to the button: this one on the
    /// Mac, ``newLinkButton`` on the iPhone). It MUST NOT be a screen-root
    /// `.confirmationDialog`/`.popover`: those take no source anchor, so on iPad
    /// SwiftUI synthesizes the popover arrow from the screen bounds and it lands
    /// on a list row instead of the button (regressed 3×). A `Menu`'s popover is
    /// anchored by the system to its own label, so it structurally cannot hit a
    /// row. With no URL on the clipboard it is a plain button, so an empty
    /// clipboard takes a single click and never shows an empty menu.
    #if os(macOS)
    @ViewBuilder
    private var addMenu: some View {
        let glyph = Image(systemName: "plus")
            .font(.system(size: 11, weight: .semibold))
        if clipboardHasURL {
            Menu {
                Button("Paste from clipboard") {
                    formRoute = .create(prefillURL: Clipboard.peekURLString())
                }
                Button("New link") {
                    formRoute = .create(prefillURL: nil)
                }
            } label: {
                glyph
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.macSquarePrimary)
            .help("New link")
            .accessibilityLabel("New link")
        } else {
            Button {
                formRoute = .create(prefillURL: nil)
            } label: {
                glyph
            }
            .buttonStyle(.macSquarePrimary)
            .help("New link")
            .accessibilityLabel("New link")
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

#if os(macOS)
extension ShortURLListScreen {
    /// Puts the sidebar toggle at the start of the list header (pass `nil` to
    /// leave it out): used while the sidebar is hidden, so it can be shown
    /// again.
    func showingSidebarToggle(_ action: (() -> Void)?) -> ShortURLListScreen {
        var copy = self
        copy.showSidebar = action
        return copy
    }
}
#endif

// MARK: - Tag search suggestions (iPhone)

#if os(iOS)
private extension View {
    /// The tag suggestions under the search card: while the typed text matches
    /// tags, a card of them appears 8 pt below; choosing one runs `onSelect`
    /// (apply the tag, clear the search, close the keyboard). The layout's
    /// search is a card, not `.searchable`, so this replaces the system
    /// `searchSuggestions` with the same data and the same action.
    func tagSearchSuggestions(
        _ tags: [String],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: 8) {
            self
            if !tags.isEmpty {
                LayoutCard {
                    VStack(spacing: 0) {
                        ForEach(tags, id: \.self) { tag in
                            TagSuggestionRow(tag: tag, onSelect: onSelect)
                            if tag != tags.last {
                                RowSeparator()
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One tappable tag suggestion: a `.row` with the tag glyph and the tag.
private struct TagSuggestionRow: View {
    let tag: String
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(tag)
        } label: {
            Label(tag, systemImage: "tag")
                .labelStyle(.titleAndIcon)
                .layoutRow()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the links with this tag")
    }
}
#endif

// MARK: - Row helpers

#if os(iOS)
private extension View {
    /// A row of the `PhoneList` page: 20 pt in from the screen edges, `top`
    /// above it, no system background or separator.
    func pageRow(top: CGFloat, horizontal: CGFloat = 20) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: 0, trailing: horizontal))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// iPad: insets the page's content (rows, header rows, chips) to the
    /// centered content column, while the `List` itself stays full width, so
    /// it scrolls and pulls to refresh from anywhere on the screen. The width
    /// is read in the same layout pass (`GeometryReader`), so nothing moves
    /// once it appears. iPhone: unchanged.
    @ViewBuilder
    func padContentColumnMargins() -> some View {
        if DeviceIdiom.isPad {
            GeometryReader { proxy in
                let gutter = max(0, (proxy.size.width - LayoutMetrics.contentColumnWidth) / 2)
                self.contentMargins(.horizontal, gutter, for: .scrollContent)
            }
        } else {
            self
        }
    }
}

/// One row's slice of the `.card` the iPhone list draws around its rows:
/// `--card`, a 1 pt `--card-border` ring, radius 14 on the first row's top and
/// the last row's bottom, a 1 pt `--sep` line under every row but the last.
private struct RowsCardSegment: View {
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        let radius: CGFloat = 14
        let shape = UnevenRoundedRectangle(topLeadingRadius: isFirst ? radius : 0,
                                           bottomLeadingRadius: isLast ? radius : 0,
                                           bottomTrailingRadius: isLast ? radius : 0,
                                           topTrailingRadius: isFirst ? radius : 0,
                                           style: .continuous)
        shape
            .fill(Palette.card)
            .overlay {
                // The ring, without the edges shared with the neighbouring rows.
                shape
                    .strokeBorder(Palette.cardBorder, lineWidth: 1)
                    .mask {
                        Rectangle()
                            .padding(.top, isFirst ? 0 : 1)
                            .padding(.bottom, isLast ? 0 : 1)
                    }
            }
            .overlay(alignment: .bottom) {
                if !isLast {
                    RowSeparator()
                        .padding(.horizontal, 1)
                }
            }
    }
}
#endif

#if os(macOS)
// MARK: - Mac list row

/// The tags under a Mac row: up to three `.tag`s (20 pt, 11 pt) and a "+N"
/// overflow, 4 pt apart. Tapping a tag applies it as the list filter.
private struct RowTags: View {
    let tags: [String]
    let onSelectTag: (String) -> Void

    private let maxVisible = 3

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleTags, id: \.self) { tag in
                TagView(text: tag, size: .small, action: { onSelectTag(tag) })
            }
            if overflow > 0 {
                TagView(text: "+\(overflow)", size: .small)
            }
        }
        .lineLimit(1)
    }

    private var visibleTags: [String] { Array(tags.prefix(maxVisible)) }
    private var overflow: Int { max(0, tags.count - maxVisible) }
}

/// A `.mrow` of the Mac link list: the 13 pt medium title (`--sel-text` when
/// selected), the 11 pt meta line, the tags when the link has any, and the
/// 12 pt medium visit count. The selected row sits on the `--sel` pill.
///
/// The trailing count swaps on hover for borderless Copy / Share / Edit /
/// Delete icon buttons in the same place (not drawn; kept). Delete routes
/// through the same central confirmation as the context menu.
private struct MacLinkRow: View {
    let shortURL: ShortURL
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSelectTag: (String) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                LinkRowText(shortURL: shortURL, titleSize: 13, metaSize: 11, isSelected: isSelected)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { onSelect() }
                if !shortURL.tags.isEmpty {
                    RowTags(tags: shortURL.tags, onSelectTag: onSelectTag)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailingAccessory
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background { MacRowBackground(isSelected: isSelected, isHovering: isHovering) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .accessibilityElement(children: .contain)
    }

    /// The visit count and the hover actions in one place, cross-fading.
    private var trailingAccessory: some View {
        ZStack(alignment: .topTrailing) {
            VisitsCountLabel(total: shortURL.visitsSummary.total, size: 12)
                .opacity(isHovering ? 0 : 1)

            hoverActions
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .accessibilityHidden(!isHovering)
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 2) {
            HoverIconButton(systemImage: "doc.on.doc", label: "Copy short URL", action: onCopy)

            if let url = URL(string: shortURL.shortUrl) {
                ShareLink(item: url) {
                    HoverIcon(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("Share")
                .accessibilityLabel("Share")
            }

            HoverIconButton(systemImage: "pencil", label: "Edit", action: onEdit)
            HoverIconButton(systemImage: "trash", label: "Delete", role: .destructive, action: onDelete)
        }
    }
}

/// A borderless icon button for the row's hover actions: `--text2` at rest,
/// `--brand-text` under the pointer.
private struct HoverIconButton: View {
    let systemImage: String
    let label: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HoverIcon(systemImage: systemImage)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The glyph of a hover action, tracking its own hover state.
private struct HoverIcon: View {
    let systemImage: String
    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12))
            .foregroundStyle(isHovering ? Palette.brand : Palette.text2)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }
}
#endif

/// A redacted stand-in row shown while the first page loads.
private struct SkeletonRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Placeholder short URL title")
                Text("abc123 · 2 days ago")
            }
            Spacer(minLength: 8)
            Text("00")
        }
        .layoutFont(13)
    }
}

// MARK: - Preview

#if DEBUG
extension ShortURLListScreen {
    /// Skips the initial load, so a preview's seeded store stays as seeded.
    func skippingInitialLoad() -> ShortURLListScreen {
        var copy = self
        copy.loadsOnAppear = false
        return copy
    }
}

/// A seeded list for the canvas: titled and untitled links, with and without
/// tags. On the Mac the second row is selected, so the selection pill shows.
struct ShortURLListScreenPreview: View {
    static let items: [ShortURL] = {
        let now = Date()
        func link(_ code: String, _ title: String?, days: Double, visits: Int, tags: [String] = []) -> ShortURL {
            ShortURL(shortCode: code,
                     shortUrl: "https://s.example/\(code)",
                     longUrl: "https://example.com/articles/\(code)/a-fairly-long-destination-path",
                     dateCreated: now.addingTimeInterval(-days * 86_400),
                     visitsSummary: VisitsSummary(total: visits, nonBots: visits * 3 / 4, bots: visits / 4),
                     title: title,
                     tags: tags)
        }
        return [
            link("launch", "Introducing the new Shlinkly", days: 1, visits: 1_284, tags: ["launch", "blog"]),
            link("abs", "Audiobookshelf: self-hosted audiobooks and podcasts", days: 3, visits: 312,
                 tags: ["selfhosted", "media", "audio", "reading"]),
            link("q3", nil, days: 9, visits: 21),
            link("talk", "Slides: Swift Charts without the band scale", days: 40, visits: 87, tags: ["talks"]),
            link("cv", "Résumé", days: 200, visits: 5),
        ]
    }()

    @State private var store = ShortURLListStore.preview(items: Self.items)
    @State private var tagsStore = TagsStore.preview(tags: ["blog", "launch", "media", "talks"])
    @State private var appModel = AppModel(spotlight: nil)
    #if os(macOS)
    @State private var selection: Route? = .shortURLDetail(Self.items[1])
    #endif

    var body: some View {
        let client = ShlinkClient(baseURL: URL(string: "https://preview.invalid/rest/v3/")!, apiKey: "preview")
        #if os(macOS)
        NavigationStack {
            ShortURLListScreen(store: store, tagsStore: tagsStore, client: client, selection: $selection,
                               detailDismissCount: 0, showSettings: .constant(false))
                .skippingInitialLoad()
        }
        .frame(width: 380, height: 520)
        .background { WindowBackdrop() }
        .environment(appModel)
        .brandTint()
        #else
        NavigationStack {
            ShortURLListScreen(store: store, tagsStore: tagsStore, client: client, showSettings: .constant(false))
                .skippingInitialLoad()
        }
        .environment(appModel)
        .brandTint()
        #endif
    }
}

#if os(iOS)
#Preview("PhoneList light") {
    ShortURLListScreenPreview()
        .preferredColorScheme(.light)
}

#Preview("PhoneList dark") {
    ShortURLListScreenPreview()
        .preferredColorScheme(.dark)
}
#endif
#endif
