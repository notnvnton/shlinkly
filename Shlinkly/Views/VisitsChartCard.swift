//
//  VisitsChartCard.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The detail screen's chart card: one label band — "Over time", with the step
/// picker and the paging arrows on the trailing side — then the chart, then a
/// footnote row with the date span and the series legend. While loading, empty
/// or failed, the chart's stand-in takes the plot's place.
///
/// Everything it shows comes from the ``ShortURLDetailStore``; it holds no state
/// of its own. Kept apart from ``DetailScreen`` so it can be previewed with a
/// seeded store, without a server.
struct VisitsChartCard: View {
    let store: ShortURLDetailStore

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                labelBand
                chartContent
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Space.cardInset)
                if store.state == .loaded {
                    footnoteRow
                        .padding(.horizontal, Space.cardInset)
                        .padding(.top, Space.tight)
                        .padding(.bottom, Space.footBand)
                } else {
                    Color.clear.frame(height: Space.cardInset)
                }
            }
        }
    }

    // MARK: - Label band

    /// "Over time" with the controls trailing. When the controls don't fit
    /// beside the label (an iPhone with four steps *and* paging), they drop to
    /// a row of their own under it.
    private var labelBand: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Space.tight) {
                CardLabel("Over time")
                Spacer(minLength: Space.tight)
                controls
            }
            VStack(alignment: .leading, spacing: Space.tight) {
                CardLabel("Over time")
                HStack(spacing: Space.tight) {
                    Spacer(minLength: 0)
                    controls
                }
            }
        }
        .padding(.horizontal, Space.cardInset)
        .padding(.vertical, Space.labelBand)
    }

    @ViewBuilder
    private var controls: some View {
        if store.state == .loaded {
            HStack(spacing: Space.tight) {
                groupingPicker
                pagingButtons
            }
        }
    }

    // MARK: - Footnote row

    /// The date span on the leading side, the legend on the trailing side.
    private var footnoteRow: some View {
        HStack(alignment: .center, spacing: Space.tight) {
            Text(store.chartDateRange)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: Space.tight)
            legend
        }
    }

    /// People always; Bots only while they are drawn (exclude bots off).
    private var legend: some View {
        HStack(spacing: 10) {
            legendItem("People", color: Palette.seriesPeople)
            if !store.excludeBots {
                legendItem("Bots", color: Palette.seriesBots)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Paging

    /// The "‹" / "›" arrows that turn a paged month chart a year at a time.
    @ViewBuilder
    private var pagingButtons: some View {
        if store.isChartPaged {
            HStack(spacing: 4) {
                pageButton(systemImage: "chevron.left",
                           label: "Previous 12 months",
                           isEnabled: store.canShowPreviousChartPage) {
                    store.showPreviousChartPage()
                }
                pageButton(systemImage: "chevron.right",
                           label: "Next 12 months",
                           isEnabled: store.canShowNextChartPage) {
                    store.showNextChartPage()
                }
            }
        }
    }

    @ViewBuilder
    private func pageButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isEnabled ? Palette.accent : Palette.textSecondary)
        }
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        #if os(macOS)
        button.buttonStyle(.matteIcon(side: 26))
        #else
        // The 44 pt touch minimum, borderless like the rest of the iPhone card.
        button
            .frame(width: 36, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
        #endif
    }

    // MARK: - Step picker

    /// The chart's step control (Day / Week / Month / Year). Only "All time"
    /// offers a choice, and only when the window is long enough for a coarser
    /// step to be worth drawing; otherwise there is nothing to pick and it stays
    /// out of the band.
    @ViewBuilder
    private var groupingPicker: some View {
        let groupings = store.availableGroupings
        if store.state == .loaded, groupings.count > 1 {
            SegmentedPicker("Group by",
                            selection: groupingBinding,
                            options: groupings.map { .init(value: $0, label: $0.label) },
                            fillsWidth: false)
                .fixedSize()
        }
    }

    private var groupingBinding: Binding<VisitGrouping> {
        Binding(get: { store.chartGrouping }, set: { store.setGrouping($0) })
    }

    // MARK: - Chart

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
                    .stateButtonStyle()
            }
        case .empty:
            chartMessage(
                systemImage: "chart.bar",
                title: emptyTitle,
                detail: nil
            ) {
                if store.canSuggestAllTime {
                    Button("See all time") { store.showAllTime() }
                        .stateButtonStyle()
                }
            }
        case .loaded:
            VisitsBarChart(data: store.chartBuckets,
                           breakdowns: store.chartBreakdowns,
                           grouping: store.chartGrouping,
                           calendar: store.chartCalendar,
                           yMax: store.chartYDomainMax,
                           xDomain: store.chartXDomain,
                           period: store.period,
                           excludeBots: store.excludeBots,
                           page: store.chartPage)
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
                .foregroundStyle(Palette.textSecondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            action()
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var emptyTitle: String {
        switch store.period {
        case .last7Days: return "No visits in the last 7 days"
        case .last30Days: return "No visits in the last 30 days"
        case .allTime: return "No visits yet"
        }
    }
}

extension View {
    /// The empty- and error-state buttons: matte on macOS, bordered on iOS.
    @ViewBuilder
    func stateButtonStyle(prominent: Bool = false) -> some View {
        #if os(macOS)
        if prominent {
            buttonStyle(.matteProminent)
        } else {
            buttonStyle(.matte)
        }
        #else
        if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
        #endif
    }
}

// MARK: - Preview

#if DEBUG
/// Made-up data for the canvas: a link created 30 months ago whose traffic
/// differs clearly from year to year, so paging and the shared Y axis show.
private enum VisitsChartCardPreviewData {
    @MainActor
    static func store() -> ShortURLDetailStore {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let created = calendar.date(byAdding: .month, value: -29, to: today) ?? today
        let dayCount = calendar.dateComponents([.day], from: created, to: today).day ?? 0

        var visits: [Visit] = []
        for offset in 0...max(dayCount, 0) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: created) else { continue }
            let monthsBack = calendar.dateComponents([.month], from: date, to: today).month ?? 0
            // A quiet first stretch, a busy middle year, a moderate latest one.
            let level = monthsBack >= 24 ? 1 : (monthsBack >= 12 ? 6 : 3)
            // A deterministic wobble so neighbouring months differ.
            let count = max(0, level + (offset * 7) % 5 - 2 + (offset % 31 == 0 ? level * 2 : 0))
            for index in 0..<count {
                visits.append(Visit(date: date, potentialBot: index % 4 == 3))
            }
        }
        let bots = visits.filter(\.potentialBot).count
        let shortURL = ShortURL(
            shortCode: "preview",
            shortUrl: "https://s.example/preview",
            longUrl: "https://example.com/a/long/address",
            dateCreated: created,
            visitsSummary: VisitsSummary(total: visits.count, nonBots: visits.count - bots, bots: bots)
        )
        return .preview(shortURL: shortURL, visits: visits, period: .allTime, grouping: .month, calendar: calendar)
    }
}

#Preview("Months, 12 at a time") {
    VisitsChartCard(store: VisitsChartCardPreviewData.store())
        .padding(Space.screenEdge)
        .frame(maxWidth: 680)
        .canvasBackground()
}
#endif
