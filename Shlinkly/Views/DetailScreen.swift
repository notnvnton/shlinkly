//
//  DetailScreen.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore
#if os(iOS)
import UIKit
#endif

/// The short-URL detail screen: a header card (title, short URL, destination,
/// tags and the Copy / Share / Open tiles), the native link preview, the visits
/// card (period control, lifetime/period metric tiles, bot toggle), the visits
/// chart, and the country and source breakdowns.
///
/// Owns a ``ShortURLDetailStore`` bound to the passed short URL and the active
/// server's client. The layout is a single vertical scroll on every platform;
/// on macOS it fills the detail column of the split view.
struct DetailScreen: View {
    @State private var store: ShortURLDetailStore
    @State private var didInitialLoad: Bool
    @State private var isEditing = false
    @State private var pendingDelete: ShortURL?
    @State private var deleteError: String?
    /// Drives the Copy tile's brief checkmark.
    @State private var didCopyFromTile = false
    @State private var copyResetTask: Task<Void, Never>?
    @Environment(\.openURL) private var openURL

    /// The active server's client and the shared tag cache, threaded so the edit
    /// form can submit and offer tag suggestions.
    private let client: ShlinkClient
    private let listStore: ShortURLListStore
    private let tagsStore: TagsStore
    /// Applies a tag as the shared list filter and returns to the list. Wired
    /// upstream so it can both set the filter and drive navigation (iOS pops,
    /// macOS clears the detail selection).
    private let onSelectTag: (String) -> Void
    /// Called after the link is deleted so the navigation returns to the list.
    private let onDeleted: () -> Void

    init(
        shortURL: ShortURL,
        client: ShlinkClient,
        listStore: ShortURLListStore,
        tagsStore: TagsStore,
        onSelectTag: @escaping (String) -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.init(store: ShortURLDetailStore(shortURL: shortURL, client: client),
                  client: client,
                  listStore: listStore,
                  tagsStore: tagsStore,
                  loadsOnAppear: true,
                  onSelectTag: onSelectTag,
                  onDeleted: onDeleted)
    }

    /// The designated initializer. Previews pass an already-seeded store and
    /// `loadsOnAppear: false`, so the screen never talks to a server.
    fileprivate init(
        store: ShortURLDetailStore,
        client: ShlinkClient,
        listStore: ShortURLListStore,
        tagsStore: TagsStore,
        loadsOnAppear: Bool,
        onSelectTag: @escaping (String) -> Void,
        onDeleted: @escaping () -> Void
    ) {
        _store = State(initialValue: store)
        _didInitialLoad = State(initialValue: !loadsOnAppear)
        self.client = client
        self.listStore = listStore
        self.tagsStore = tagsStore
        self.onSelectTag = onSelectTag
        self.onDeleted = onDeleted
    }

    private var shortURL: ShortURL { store.shortURL }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.blockGap) {
                headerCard
                if let destinationURL {
                    linkPreviewCard(destinationURL)
                }
                visitsCard
                VisitsChartCard(store: store)
                breakdownSections
            }
            .padding(.horizontal, Space.screenEdge)
            .padding(.vertical, Space.blockGap)
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .canvasBackground()
        .navigationTitle(navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { detailToolbar }
        .sheet(isPresented: $isEditing) {
            ShortURLFormView(mode: .edit(store.shortURL), client: client, tagsStore: tagsStore) { updated in
                // Refresh both the detail in place and the row behind it.
                store.apply(updated)
                listStore.applyUpdated(updated)
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
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            store.load()
        }
    }

    // MARK: - Toolbar & actions

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    pendingDelete = store.shortURL
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }
    }

    /// Deletes the link via the shared list store (which removes the row), then
    /// navigates back on success or surfaces a message otherwise.
    private func runDelete(_ url: ShortURL) async {
        switch await listStore.delete(shortCode: url.shortCode, domain: url.domain) {
        case .deleted:
            onDeleted()
        case .forbidden(let threshold):
            deleteError = ShlinkError.userFacingMessage(for: ShlinkError.deletionForbidden(threshold: threshold))
        case .failed(let message):
            deleteError = message
        }
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    /// The Copy tile: copies the short URL (the same thing every other copy
    /// path copies) and swaps its icon to a checkmark for ~1.2s, like
    /// ``CopyButton``.
    private func copyFromTile() {
        LinkActions.copyShortURL(shortURL)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(.easeInOut(duration: 0.15)) { didCopyFromTile = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { didCopyFromTile = false }
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text(headerTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(3)
                    .padding(.horizontal, Space.cardInset)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                shortURLRow
                CardHairline()
                destinationRow
                CardHairline()
                tagsBand
                actionRow
            }
        }
    }

    /// The short URL with its copy button. The button's 44 pt target is pulled
    /// in so its glyph, not its tap area, lines up with the card's text edge.
    private var shortURLRow: some View {
        HStack(spacing: Space.tight) {
            Text(shortURL.shortUrl)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.accentText)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            CopyButton(value: shortURL.shortUrl, label: "Copy short URL", targetSide: 44)
        }
        .frame(minHeight: Space.row)
        .padding(.leading, Space.cardInset)
        .padding(.trailing, Space.cardInset - 11)
    }

    /// The destination. Tapping opens the *destination* in the system browser —
    /// never the short URL, so we don't record a visit just by previewing the
    /// link.
    @ViewBuilder
    private var destinationRow: some View {
        let row = HStack(spacing: Space.tight) {
            Image(systemName: "arrow.up.right")
                .font(.subheadline)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(shortURL.longUrl)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Space.cardInset)
        .contentShape(Rectangle())

        if let destinationURL {
            Button {
                openURL(destinationURL)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .help("Open in browser")
            .accessibilityLabel("Open destination")
            .accessibilityValue(shortURL.longUrl)
        } else {
            row
        }
    }

    /// Tags and the creation date. Tags belong to the link's identity, so they
    /// live in the header card. With no tags, only the date.
    private var tagsBand: some View {
        HStack(alignment: .top, spacing: Space.tight) {
            if !shortURL.tags.isEmpty {
                TagChipsView(tags: shortURL.tags, onSelectTag: onSelectTag)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Created \(createdDate)")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .fixedSize()
                // Centre the date on the first row of 26 pt chips.
                .frame(minHeight: 26)
        }
        .padding(.horizontal, Space.cardInset)
        .padding(.vertical, Space.labelBand)
    }

    /// Copy, Share, Open. A fourth tile (QR code) is one more line here.
    private var actionRow: some View {
        HStack(spacing: Space.tight) {
            ActionTile(didCopyFromTile ? "Copied" : "Copy",
                       systemImage: didCopyFromTile ? "checkmark" : "doc.on.doc",
                       action: copyFromTile)
            if let shortLink = URL(string: shortURL.shortUrl) {
                // `ShareLink` works in an ordinary view on both platforms (it
                // is only ignored inside `.swipeActions`). Shares the short URL,
                // like the list's share actions.
                ShareLink(item: shortLink) {
                    ActionTileLabel(title: "Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ActionTileButtonStyle())
                .help("Share")
            }
            if let destinationURL {
                ActionTile("Open", systemImage: "safari") {
                    openURL(destinationURL)
                }
            }
        }
        .padding(.horizontal, Space.cardInset)
        .padding(.bottom, Space.cardInset)
    }

    // MARK: - Link preview

    /// The matte link preview: site icon, page title and host. Tapping it
    /// opens the destination.
    private func linkPreviewCard(_ url: URL) -> some View {
        Card {
            LinkPreviewView(url: url)
        }
    }

    // MARK: - Visits card (period + metric tiles + bot toggle)

    /// Period control, the three metric tiles and the bot toggle share one card:
    /// they all govern the same period/visits data.
    private var visitsCard: some View {
        Card("Visits") {
            VStack(alignment: .leading, spacing: 0) {
                periodPicker
                    .padding(.horizontal, Space.cardInset)
                metricTiles
                    .padding(.horizontal, Space.cardInset)
                    .padding(.top, Space.labelBand)
                    .padding(.bottom, Space.cardInset)
                CardHairline()
                Toggle("Exclude bots", isOn: excludeBotsBinding)
                    .toggleStyle(.switch)
                    .font(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .tint(Palette.accent)
                    .frame(minHeight: Space.row)
                    .padding(.horizontal, Space.cardInset)
            }
        }
    }

    private var periodPicker: some View {
        SegmentedPicker("Period", selection: periodBinding, options: [
            .init(value: .last7Days, label: "7 days"),
            .init(value: .last30Days, label: "30 days"),
            .init(value: .allTime, label: "All"),
        ])
    }

    /// Lifetime figures from the link's summary over the selected period's.
    /// The bot toggle doesn't affect these — the tiles always show the full
    /// breakdown.
    private var metricTiles: some View {
        let all = store.allTimeMetrics
        let period = store.periodMetrics
        let suffix = periodSuffix
        let loading = store.state == .loading
        return HStack(spacing: Space.tight) {
            MetricTile(title: "Total", allTime: all.total, valueColor: Palette.textPrimary,
                       period: period.total, periodSuffix: suffix, isLoadingPeriod: loading)
            MetricTile(title: "People", allTime: all.nonBots, valueColor: Palette.accentText,
                       period: period.nonBots, periodSuffix: suffix, isLoadingPeriod: loading)
            MetricTile(title: "Bots", allTime: all.bots, valueColor: Palette.textSecondary,
                       period: period.bots, periodSuffix: suffix, isLoadingPeriod: loading)
        }
    }

    /// What follows the period figure on a metric tile: "449 in 30 days".
    /// `nil` for "All", where the line would only repeat the all-time figure.
    private var periodSuffix: String? {
        switch store.period {
        case .last7Days: return "in 7 days"
        case .last30Days: return "in 30 days"
        case .allTime: return nil
        }
    }

    // MARK: - Breakdowns (countries + sources)

    /// The country and source breakdowns under the time chart. Shown only once
    /// visits have loaded — while loading / empty / error the chart card
    /// already carries the state. Both track the period and the bot toggle
    /// through the store. macOS lays them out side by side; iPhone stacks them.
    @ViewBuilder
    private var breakdownSections: some View {
        if store.state == .loaded {
            #if os(macOS)
            HStack(alignment: .top, spacing: Space.blockGap) {
                countryBreakdown
                sourceBreakdown
            }
            #else
            countryBreakdown
            sourceBreakdown
            #endif
        }
    }

    private var countryBreakdown: some View {
        Card("Countries") {
            BreakdownList(entries: store.countryCounts, showsFlags: true)
        } accessory: {
            breakdownDateRange
        }
    }

    private var sourceBreakdown: some View {
        Card("Sources") {
            BreakdownList(entries: store.sourceCounts, showsFlags: false)
        } accessory: {
            breakdownDateRange
        }
    }

    private var breakdownDateRange: some View {
        Text(store.windowDateRange)
            .font(.footnote)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
    }

    // MARK: - Derived values

    private var destinationURL: URL? { URL(string: shortURL.longUrl) }

    /// Reading width for the scroll content. macOS gets a wider column so the
    /// side-by-side Countries/Sources breakdown has room; iPhone stays narrow.
    private var contentMaxWidth: CGFloat {
        #if os(macOS)
        860
        #else
        680
        #endif
    }

    private var headerTitle: String {
        if let title = shortURL.title, !title.isEmpty { return title }
        return shortURL.shortCode
    }

    private var navigationTitle: String {
        if let title = shortURL.title, !title.isEmpty { return title }
        return shortURL.shortCode
    }

    /// "Nov 3", or "Nov 3, 2024" when the link wasn't created this year.
    private var createdDate: String {
        let created = shortURL.dateCreated
        let thisYear = Calendar.current.isDate(created, equalTo: Date(), toGranularity: .year)
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return created.formatted(thisYear ? style : style.year())
    }

    // MARK: - Bindings

    private var periodBinding: Binding<ShortURLDetailStore.Period> {
        Binding(get: { store.period }, set: { store.setPeriod($0) })
    }

    private var excludeBotsBinding: Binding<Bool> {
        Binding(get: { store.excludeBots }, set: { store.excludeBots = $0 })
    }
}

// MARK: - Tag chips

/// Wrapping, tappable tag chips built from the shared ``TagChip`` style. Detail
/// shows every tag (no "+N" overflow); tapping one filters the list and returns
/// to it via ``onSelectTag``.
private struct TagChipsView: View {
    let tags: [String]
    let onSelectTag: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                TagChip(text: tag, size: .regular) { onSelectTag(tag) }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
/// Made-up data for the canvas: a tagged link created five months ago with
/// mixed people and bot traffic from a few countries and sources. The store is
/// seeded, so the screen never talks to a server.
private enum DetailScreenPreviewData {
    @MainActor
    static func screen(period: ShortURLDetailStore.Period = .last30Days) -> DetailScreen {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let created = calendar.date(byAdding: .day, value: -150, to: today) ?? today
        let countries: [(code: String?, name: String?)] = [
            ("DE", "Germany"), ("US", "United States"), ("DE", "Germany"),
            ("FR", "France"), (nil, nil), ("NL", "Netherlands"), ("DE", "Germany"),
        ]
        let referers: [String?] = [nil, "https://news.ycombinator.com/item", nil,
                                   "https://mastodon.social/@someone", "https://www.google.com/"]

        var visits: [Visit] = []
        for offset in 0...150 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: created) else { continue }
            let count = max(0, 2 + (offset * 7) % 6 - (offset % 9 == 0 ? 2 : 0) + (offset > 120 ? 3 : 0))
            for index in 0..<count {
                let country = countries[(offset + index) % countries.count]
                let location = country.code == nil
                    ? nil
                    : Visit.VisitLocation(countryCode: country.code, countryName: country.name)
                visits.append(Visit(referer: referers[(offset * 3 + index) % referers.count],
                                    date: date,
                                    potentialBot: index % 4 == 3,
                                    visitLocation: location))
            }
        }
        let bots = visits.filter(\.potentialBot).count
        let shortURL = ShortURL(
            shortCode: "launch",
            shortUrl: "https://s.example/launch",
            longUrl: "https://example.com/blog/2026/introducing-the-new-shlinkly",
            dateCreated: created,
            visitsSummary: VisitsSummary(total: visits.count, nonBots: visits.count - bots, bots: bots),
            title: "Introducing the new Shlinkly",
            tags: ["launch", "blog", "newsletter"]
        )
        let client = ShlinkClient(baseURL: URL(string: "https://preview.invalid/rest/v3/")!, apiKey: "preview")
        return DetailScreen(
            store: .preview(shortURL: shortURL, visits: visits, period: period, calendar: calendar),
            client: client,
            listStore: ShortURLListStore(client: client),
            tagsStore: TagsStore(client: client),
            loadsOnAppear: false,
            onSelectTag: { _ in },
            onDeleted: {}
        )
    }
}

#Preview("Detail, 30 days, light") {
    NavigationStack {
        DetailScreenPreviewData.screen()
    }
    .brandTint()
    .preferredColorScheme(.light)
}

#Preview("Detail, 30 days, dark") {
    NavigationStack {
        DetailScreenPreviewData.screen()
    }
    .brandTint()
    .preferredColorScheme(.dark)
}

#Preview("Detail, All") {
    NavigationStack {
        DetailScreenPreviewData.screen(period: .allTime)
    }
    .brandTint()
}

#Preview("Detail, 7 days") {
    NavigationStack {
        DetailScreenPreviewData.screen(period: .last7Days)
    }
    .brandTint()
}
#endif
