//
//  DetailScreen.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore
#if os(iOS)
import UIKit
#endif

/// The short-URL detail screen, as layout v3 draws it (`MacMain` detail column,
/// `PhoneDetail`): the header (title, short URL, destination, tags, created
/// date), the link preview, Visits (metrics and the bot switch), Over time (the
/// chart), Countries and Sources. Copy / Share / Open are the Mac header's
/// buttons; on the iPhone Share and Copy link sit in the bottom bar.
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
    /// Drives the Copy / Copy link button's brief "Copied".
    @State private var didCopy = false
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
    init(
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
            #if os(macOS)
            macColumn
            #else
            phoneColumn
            #endif
        }
        .canvasBackground()
        .navigationTitle(headerTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { phoneBottomBar }
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

    /// Mac (`MacMain`): the period control centered in the title bar, ⋯ on the
    /// right. It belongs to this screen's toolbar, so with no link selected (the
    /// placeholder) it isn't shown. iPhone (`PhoneDetail`): "Edit" and ⋯ on the
    /// right, no title (the back button reads "‹ Links").
    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .principal) {
            MacSegmented("Period", selection: periodBinding, options: periodOptions)
        }
        .withoutSharedBackground()
        ToolbarItem(placement: .primaryAction) {
            Menu {
                editButton
                deleteButton
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.macSquare)
            .help("More")
            .accessibilityLabel("More")
        }
        .withoutSharedBackground()
        #else
        ToolbarItem(placement: .principal) {
            Color.clear.frame(width: 1, height: 1)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Edit") { isEditing = true }
                .buttonStyle(.navLink())
                .padding(.horizontal, 6)
        }
        .withoutSharedBackground()
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                deleteButton
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.brand)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
        }
        .withoutSharedBackground()
        #endif
    }

    private var editButton: some View {
        Button {
            isEditing = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            pendingDelete = store.shortURL
        } label: {
            Label("Delete", systemImage: "trash")
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

    /// Copy (Mac) / Copy link (iPhone): copies the short URL (the same thing
    /// every other copy path copies) and reads "Copied" for ~1.2s. The button
    /// keeps its size, so nothing around it moves.
    private func copyShortURL() {
        LinkActions.copyShortURL(shortURL)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }

    #if os(macOS)
    // MARK: - Mac column (MacMain)

    /// The detail column: header, link preview, Visits beside Over time,
    /// Countries beside Sources. 14 pt apart, 24 pt in, 4 pt under the title bar.
    private var macColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            macHeaderCard
            if let destinationURL {
                MacCard {
                    LinkPreviewView(url: destinationURL)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                macVisitsCard
                    .frame(width: 240)
                    .frame(maxHeight: .infinity)
                VisitsChartCard(store: store)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            if store.state == .loaded {
                HStack(alignment: .top, spacing: 14) {
                    breakdownCard(title: "Countries", entries: store.countryCounts, showsFlags: true)
                    breakdownCard(title: "Sources", entries: store.sourceCounts, showsFlags: false)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Title (20 pt semibold), short URL (14 pt medium, `--brand-text`),
    /// destination (12 pt `--text2`), the tags with the creation date, then
    /// Copy / Share / Open (`.mbtn`). 16 pt / 18 pt in, 6 pt apart.
    private var macHeaderCard: some View {
        MacCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(headerTitle)
                    .layoutFont(20, .semibold)
                    .foregroundStyle(Palette.text)
                    .lineLimit(3)
                Text(shortURL.shortUrl)
                    .layoutFont(14, .medium)
                    .foregroundStyle(Palette.brand)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                destinationLine(size: 12)
                HStack(alignment: .center, spacing: 6) {
                    ForEach(shortURL.tags, id: \.self) { tag in
                        TagView(text: tag, action: { onSelectTag(tag) })
                    }
                    Spacer(minLength: 6)
                    createdLabel(size: 12)
                }
                .padding(.top, 6)
                HStack(spacing: 8) {
                    Button(didCopy ? "Copied" : "Copy", action: copyShortURL)
                        .help("Copy short URL")
                    if let shortLink = URL(string: shortURL.shortUrl) {
                        ShareLink(item: shortLink) {
                            Text("Share")
                        }
                        .help("Share the short URL")
                    }
                    if let destinationURL {
                        Button("Open") { openURL(destinationURL) }
                            .help("Open the destination in the browser")
                    }
                }
                .buttonStyle(.mac)
                .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    /// Visits (240 pt wide): the three metrics as rows (key left, 18 pt value
    /// right), then Exclude bots at the bottom.
    private var macVisitsCard: some View {
        MacCard {
            VStack(alignment: .leading, spacing: 0) {
                MacLabel("Visits")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                VStack(spacing: 6) {
                    metricTiles(horizontal: true)
                }
                .padding(.horizontal, 14)
                Spacer(minLength: 12)
                HStack {
                    Text("Exclude bots")
                        .layoutFont(13)
                        .foregroundStyle(Palette.text)
                    Spacer(minLength: 8)
                    Toggle("Exclude bots", isOn: excludeBotsBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Palette.switchOn)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .overlay(alignment: .top) { RowSeparator() }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// Countries / Sources: the label and the date range, then `.rank` rows.
    private func breakdownCard(title: String, entries: [ShortURLDetailStore.RankedEntry],
                               showsFlags: Bool) -> some View {
        MacCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    MacLabel(title)
                    Spacer(minLength: 8)
                    Text(store.windowDateRange)
                        .layoutFont(11)
                        .foregroundStyle(Palette.text2)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                BreakdownList(entries: entries, showsFlags: showsFlags)
            }
        }
    }
    #endif

    #if os(iOS)
    // MARK: - iPhone column (PhoneDetail)

    /// The plain header, the preview card, then the Visits, Over time,
    /// Countries and Sources groups, 22 pt apart.
    private var phoneColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            phoneHeader
                .padding(.top, 8)
            if let destinationURL {
                LayoutCard {
                    LinkPreviewView(url: destinationURL)
                }
                .padding(.top, 18)
            }
            phoneVisits
                .padding(.top, 22)
            VisitsChartCard(store: store)
                .padding(.top, 22)
            if store.state == .loaded {
                phoneBreakdown(title: "Countries", entries: store.countryCounts, showsFlags: true)
                    .padding(.top, 22)
                phoneBreakdown(title: "Sources", entries: store.sourceCounts, showsFlags: false)
                    .padding(.top, 22)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    /// No card: title (22 pt semibold), short URL (16 pt medium,
    /// `--brand-text`), destination (13 pt `--text2`), up to three tags with a
    /// "+N" and the creation date. 6 pt apart.
    private var phoneHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerTitle)
                .layoutFont(22, .semibold, tracking: -0.2)
                .foregroundStyle(Palette.text)
                .lineLimit(3)
            Text(shortURL.shortUrl)
                .layoutFont(16, .medium)
                .foregroundStyle(Palette.brand)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            destinationLine(size: 13)
            HStack(alignment: .center, spacing: 6) {
                ForEach(shortURL.tags.prefix(3), id: \.self) { tag in
                    TagView(text: tag, action: { onSelectTag(tag) })
                }
                if shortURL.tags.count > 3 {
                    TagView(text: "+\(shortURL.tags.count - 3)")
                }
                Spacer(minLength: 6)
                createdLabel(size: 13)
            }
            .padding(.top, 6)
        }
    }

    /// "Visits": a card with the period control, the three metric tiles and
    /// the Exclude bots row.
    private var phoneVisits: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Visits")
            LayoutCard {
                VStack(alignment: .leading, spacing: 0) {
                    periodPicker
                    HStack(spacing: 8) {
                        metricTiles(horizontal: false)
                    }
                    .padding(.top, 12)
                    Toggle(isOn: excludeBotsBinding) {
                        Text("Exclude bots")
                    }
                    .toggleStyle(.switch)
                    .tint(Palette.switchOn)
                    .layoutRow()
                    .overlay(alignment: .top) { RowSeparator() }
                    .padding(.horizontal, -12)
                    .padding(.top, 12)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
        }
    }

    /// The native segmented period control, full width.
    private var periodPicker: some View {
        Picker("Period", selection: periodBinding) {
            ForEach(periodOptions, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func phoneBreakdown(title: String, entries: [ShortURLDetailStore.RankedEntry],
                                showsFlags: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
            LayoutCard {
                BreakdownList(entries: entries, showsFlags: showsFlags)
            }
        }
    }

    /// Share (secondary) and Copy link (primary). Opening the destination is
    /// the destination line and the preview row.
    private var phoneBottomBar: some View {
        BottomBar {
            if let shortLink = URL(string: shortURL.shortUrl) {
                ShareLink(item: shortLink) {
                    Text("Share")
                }
                .buttonStyle(.layoutSecondary)
            }
            Button(didCopy ? "Copied" : "Copy link", action: copyShortURL)
                .buttonStyle(.layoutPrimary)
        }
    }
    #endif

    // MARK: - Shared pieces

    /// "↗ destination" in `--text2`, one line. Opens the *destination* in the
    /// browser — never the short URL, so previewing doesn't record a visit.
    @ViewBuilder
    private func destinationLine(size: CGFloat) -> some View {
        let line = Text("↗ \(shortURL.longUrl)")
            .layoutFont(size)
            .foregroundStyle(Palette.text2)
            .lineLimit(1)
            .truncationMode(.tail)
        if let destinationURL {
            Button {
                openURL(destinationURL)
            } label: {
                line
            }
            .buttonStyle(.plain)
            .help("Open in browser")
            .accessibilityLabel("Open destination")
            .accessibilityValue(shortURL.longUrl)
        } else {
            line
        }
    }

    private func createdLabel(size: CGFloat) -> some View {
        Text("Created \(createdDate)")
            .layoutFont(size)
            .foregroundStyle(Palette.text2)
            .lineLimit(1)
            .fixedSize()
    }

    /// Total, People and Bots: title and lifetime value, no second line.
    @ViewBuilder
    private func metricTiles(horizontal: Bool) -> some View {
        let all = store.allTimeMetrics
        MetricTile(title: "Total", value: all.total, kind: .total, horizontal: horizontal)
        MetricTile(title: "People", value: all.nonBots, kind: .people, horizontal: horizontal)
        MetricTile(title: "Bots", value: all.bots, kind: .bots, horizontal: horizontal)
    }

    private var periodOptions: [PeriodOptionValue] {
        [
            .init(value: .last7Days, label: "7 days"),
            .init(value: .last30Days, label: "30 days"),
            .init(value: .allTime, label: "All"),
        ]
    }

    // MARK: - Derived values

    private var destinationURL: URL? { URL(string: shortURL.longUrl) }

    private var headerTitle: String {
        if let title = shortURL.title, !title.isEmpty { return title }
        return shortURL.shortCode
    }

    /// "7 Jun" or "Jun 7" by locale, with the year when it isn't this year.
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

#if os(macOS)
private typealias PeriodOptionValue = MacSegmented<ShortURLDetailStore.Period>.Option
#else
/// A period choice of the segmented control.
private struct PeriodOptionValue {
    let value: ShortURLDetailStore.Period
    let label: String
}
#endif

// MARK: - Preview

#if DEBUG
/// Made-up data for the canvas: a tagged link created five months ago with
/// mixed people and bot traffic from a few countries and sources. The store is
/// seeded, so the screen never talks to a server.
enum DetailScreenPreviewData {
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

#if os(macOS)
#Preview("MacMain detail light") {
    NavigationStack {
        DetailScreenPreviewData.screen(period: .allTime)
    }
    .frame(width: 860, height: 820)
    .background { WindowBackdrop() }
    .brandTint()
    .preferredColorScheme(.light)
}

#Preview("MacMain detail dark") {
    NavigationStack {
        DetailScreenPreviewData.screen(period: .allTime)
    }
    .frame(width: 860, height: 820)
    .background { WindowBackdrop() }
    .brandTint()
    .preferredColorScheme(.dark)
}
#else
#Preview("PhoneDetail light") {
    NavigationStack {
        DetailScreenPreviewData.screen(period: .allTime)
    }
    .brandTint()
    .preferredColorScheme(.light)
}

#Preview("PhoneDetail dark") {
    NavigationStack {
        DetailScreenPreviewData.screen(period: .allTime)
    }
    .brandTint()
    .preferredColorScheme(.dark)
}
#endif

#Preview("Detail, 7 days") {
    NavigationStack {
        DetailScreenPreviewData.screen(period: .last7Days)
    }
    .brandTint()
}
#endif
