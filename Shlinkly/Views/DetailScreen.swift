//
//  DetailScreen.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore
#if os(iOS)
import UIKit
#endif

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
    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?
    @Environment(\.openURL) private var openURL

    /// Applies a tag as the shared list filter and returns to the list. Wired
    /// upstream so it can both set the filter and drive navigation (iOS pops,
    /// macOS clears the detail selection).
    private let onSelectTag: (String) -> Void

    init(shortURL: ShortURL, client: ShlinkClient, onSelectTag: @escaping (String) -> Void) {
        _store = State(initialValue: ShortURLDetailStore(shortURL: shortURL, client: client))
        self.onSelectTag = onSelectTag
    }

    private var shortURL: ShortURL { store.shortURL }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let destinationURL {
                    LinkPreviewView(url: destinationURL)
                }
                if !shortURL.tags.isEmpty {
                    TagChipsView(tags: shortURL.tags, onSelectTag: onSelectTag)
                }
                periodPicker
                metricCards
                Toggle("Exclude bots", isOn: excludeBotsBinding)
                    .font(.subheadline)
                chartSection
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
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            store.load()
        }
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
                Button {
                    copyShortURL()
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.subheadline)
                        .foregroundStyle(didCopy ? Color.green : Color.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                        // Fixed box so the doc → checkmark swap can't nudge layout.
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Copy short URL")
                .accessibilityLabel(didCopy ? "Copied" : "Copy short URL")
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
            #if os(macOS)
            HStack(alignment: .top, spacing: 24) {
                countryBreakdown
                    .frame(maxWidth: .infinity, alignment: .leading)
                sourceBreakdown
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            #else
            countryBreakdown
            sourceBreakdown
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

    // MARK: - Actions

    /// Copies the short URL and shows brief confirmation: the icon swaps to a
    /// checkmark for ~1.2s, plus a light haptic on iOS. The copy itself is
    /// unchanged.
    private func copyShortURL() {
        Clipboard.copy(shortURL.shortUrl)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(.easeInOut(duration: 0.15)) { didCopy = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { didCopy = false }
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
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
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

/// A simple left-to-right wrapping layout for chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
