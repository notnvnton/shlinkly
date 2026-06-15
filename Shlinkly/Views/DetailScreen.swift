//
//  DetailScreen.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The short-URL detail screen: header, native link preview, tags, a period
/// control, lifetime/period metric cards, a bot toggle and a per-day visits
/// chart.
///
/// Owns a ``ShortURLDetailStore`` bound to the passed short URL and the active
/// server's client. The layout is a single vertical scroll on every platform;
/// on macOS it fills the detail column of the split view.
struct DetailScreen: View {
    @State private var store: ShortURLDetailStore
    @State private var didInitialLoad = false
    @State private var isEditing = false
    @State private var pendingDelete: ShortURL?
    @State private var deleteError: String?
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
        _store = State(initialValue: ShortURLDetailStore(shortURL: shortURL, client: client))
        self.client = client
        self.listStore = listStore
        self.tagsStore = tagsStore
        self.onSelectTag = onSelectTag
        self.onDeleted = onDeleted
    }

    private var shortURL: ShortURL { store.shortURL }

    var body: some View {
        ScrollView {
            // Each block is its own card so the dense page reads as distinct
            // sections rather than one wall of content. The same structure (and
            // the same surface convention) is used on both platforms; only the
            // breakdown columns differ (see `breakdownSections`).
            VStack(alignment: .leading, spacing: 20) {
                DetailCard { header }
                if let destinationURL {
                    DetailCard {
                        LinkPreviewView(url: destinationURL)
                    }
                }
                DetailCard { summarySection }
                DetailCard { chartSection }
                breakdownSections
            }
            .padding()
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headerTitle)
                .font(.title2.weight(.semibold))
                .lineLimit(3)

            HStack(spacing: 8) {
                Text(shortURL.shortUrl)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                CopyButton(value: shortURL.shortUrl, label: "Copy short URL")
            }

            if let destinationURL {
                // Opens the *destination* in the system browser — never the short
                // URL, so we don't record a visit just by previewing the link.
                Button {
                    openURL(destinationURL)
                } label: {
                    Label("Open in browser", systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Tags belong to the link's identity, so they live in the header card
            // rather than as a floating row between sections.
            if !shortURL.tags.isEmpty {
                TagChipsView(tags: shortURL.tags, onSelectTag: onSelectTag)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Summary (period + metric tiles + bot toggle)

    /// Period control, the three metric tiles and the bot toggle share one card:
    /// they all govern the same period/visits data, so grouping them reads as a
    /// single control surface. The tiles are their own rounded sub-cards within.
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            periodPicker
            metricCards
            Toggle("Exclude bots", isOn: excludeBotsBinding)
                .font(.subheadline)
        }
    }

    // MARK: - Period control

    private var periodPicker: some View {
        Picker("Period", selection: periodBinding) {
            Text("7 days").tag(ShortURLDetailStore.Period.last7Days)
            Text("30 days").tag(ShortURLDetailStore.Period.last30Days)
            Text("All").tag(ShortURLDetailStore.Period.allTime)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Metric cards

    private var metricCards: some View {
        let all = store.allTimeMetrics
        let period = store.periodMetrics
        let label = store.period.label
        let loading = store.state == .loading
        return HStack(spacing: 12) {
            MetricCard(title: "Total", allTime: all.total, period: period.total,
                       periodLabel: label, tint: .primary, isLoadingPeriod: loading)
            MetricCard(title: "People", allTime: all.nonBots, period: period.nonBots,
                       periodLabel: label, tint: .green, isLoadingPeriod: loading)
            MetricCard(title: "Bots", allTime: all.bots, period: period.bots,
                       periodLabel: label, tint: .secondary, isLoadingPeriod: loading)
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.chartSubtitle)
                    .font(.headline)
                Text(store.windowDateRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            chartContent
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Breakdowns (countries + sources)

    /// The country and source breakdowns under the time chart. Shown only once
    /// visits have loaded — while loading / empty / error the chart section
    /// already carries the state, so we don't repeat it here. Both track the
    /// period and the bot toggle through the store. macOS lays them out as two
    /// side-by-side columns (the wider window has room); iPhone keeps the stack.
    @ViewBuilder
    private var breakdownSections: some View {
        if store.state == .loaded {
            // Each breakdown gets its own card. On the wider macOS column they sit
            // side by side (the cards stretch to fill each half); on the narrow
            // iPhone they stack, picking up the same 20pt gap as the other cards.
            #if os(macOS)
            HStack(alignment: .top, spacing: 20) {
                DetailCard { countryBreakdown }
                DetailCard { sourceBreakdown }
            }
            #else
            DetailCard { countryBreakdown }
            DetailCard { sourceBreakdown }
            #endif
        }
    }

    private var countryBreakdown: some View {
        CountryBreakdownList(title: "Countries",
                             dateRange: store.windowDateRange,
                             entries: store.countryCounts)
    }

    private var sourceBreakdown: some View {
        RankedBarList(title: "Sources",
                      dateRange: store.windowDateRange,
                      entries: store.sourceCounts)
    }

    @ViewBuilder
    private var chartContent: some View {
        switch store.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 220)
        case .error(let message):
            chartMessage(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't load visits",
                detail: message
            ) {
                Button("Try Again") { store.load() }
                    .buttonStyle(.bordered)
            }
        case .empty:
            chartMessage(
                systemImage: "chart.bar",
                title: emptyTitle,
                detail: nil
            ) {
                if store.canSuggestAllTime {
                    Button("See all time") { store.showAllTime() }
                        .buttonStyle(.bordered)
                }
            }
        case .loaded:
            VisitsBarChart(data: store.dailyCounts, yMax: store.chartYDomainMax)
                .frame(height: 220)
        }
    }

    @ViewBuilder
    private func chartMessage<Action: View>(
        systemImage: String,
        title: String,
        detail: String?,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            action()
        }
        .frame(maxWidth: .infinity, minHeight: 220)
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

    private var emptyTitle: String {
        switch store.period {
        case .last7Days: return "No visits in the last 7 days"
        case .last30Days: return "No visits in the last 30 days"
        case .allTime: return "No visits yet"
        }
    }

    // MARK: - Bindings

    private var periodBinding: Binding<ShortURLDetailStore.Period> {
        Binding(get: { store.period }, set: { store.setPeriod($0) })
    }

    private var excludeBotsBinding: Binding<Bool> {
        Binding(get: { store.excludeBots }, set: { store.excludeBots = $0 })
    }
}

// MARK: - Section card

/// A card surface for one detail section: the project's standard translucent
/// fill — `Color.primary.opacity(0.06)`, the same convention the metric tiles
/// already use and which compiles on both iOS and macOS (no `secondarySystem…`
/// platform-only colors) — rounded to 12pt with 16pt of internal padding, and
/// stretched to the column width. Every section on the screen is wrapped in one,
/// so the page reads as evenly-spaced cards identically on both platforms.
private struct DetailCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Metric card

/// One metric: a big lifetime figure over a smaller per-period figure.
///
/// The lifetime number comes from the short URL's summary and never changes;
/// the period number and its label track the selected period. The bot toggle
/// does not affect these — cards always show the full breakdown.
private struct MetricCard: View {
    let title: String
    let allTime: Int
    let period: Int
    let periodLabel: String
    let tint: Color
    let isLoadingPeriod: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(allTime, format: .number)
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Divider()

            HStack(spacing: 4) {
                Text(period, format: .number)
                    .monospacedDigit()
                Text(periodLabel)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .redacted(reason: isLoadingPeriod ? .placeholder : [])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        // A touch more opaque than the enclosing summary card (0.06) so the tiles
        // read as raised sub-cards rather than blending into it. Same convention
        // (translucent `primary`), so it compiles on iOS and macOS alike.
        .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
                TagChip(text: tag) { onSelectTag(tag) }
            }
        }
    }
}
