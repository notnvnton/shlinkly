//
//  VisitsChartCard.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The contents of the detail screen's chart card: the title, the date span
/// (with the paging arrows when the month chart is paged), the step picker, and
/// below them the chart itself — or its loading / empty / error stand-in.
///
/// Everything it shows comes from the ``ShortURLDetailStore``; it holds no state
/// of its own. Kept apart from ``DetailScreen`` so it can be previewed with a
/// seeded store, without a server.
struct VisitsChartCard: View {
    let store: ShortURLDetailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.chartSubtitle)
                        .font(.headline)
                    dateRange
                }
                Spacer(minLength: 0)
                groupingPicker
            }
            chartContent
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Date span & paging

    /// The span under the title. When the month chart is paged it is flanked by
    /// the "‹" / "›" arrows that turn the page a year at a time.
    @ViewBuilder
    private var dateRange: some View {
        let label = Text(store.chartDateRange)
            .font(.caption)
            .foregroundStyle(.secondary)
        if store.state == .loaded, store.isChartPaged {
            HStack(spacing: 0) {
                pageButton(systemImage: "chevron.left",
                           label: "Previous 12 months",
                           isEnabled: store.canShowPreviousChartPage) {
                    store.showPreviousChartPage()
                }
                label
                pageButton(systemImage: "chevron.right",
                           label: "Next 12 months",
                           isEnabled: store.canShowNextChartPage) {
                    store.showNextChartPage()
                }
            }
            // Pull the row left so the chevron's glyph, not its roomy tap
            // target, lines up with the title above.
            .padding(.leading, -Self.pageButtonInset)
        } else {
            label
        }
    }

    /// The side of a paging arrow's tap target: the 44pt touch minimum on iOS,
    /// a compact pointer target on the Mac.
    private static var pageButtonSide: CGFloat {
        #if os(iOS)
        44
        #else
        22
        #endif
    }

    /// How far the chevron glyph sits inside its tap target.
    private static var pageButtonInset: CGFloat { (pageButtonSide - 8) / 2 }

    private func pageButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: Self.pageButtonSide, height: Self.pageButtonSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    // MARK: - Step picker

    /// The chart's step control (Day / Week / Month / Year). Only "All time"
    /// offers a choice, and only when the window is long enough for a coarser
    /// step to be worth drawing; otherwise there is nothing to pick and it stays
    /// out of the header.
    @ViewBuilder
    private var groupingPicker: some View {
        let groupings = store.availableGroupings
        if store.state == .loaded, groupings.count > 1 {
            Picker("Group by", selection: groupingBinding) {
                ForEach(groupings, id: \.self) { grouping in
                    Text(grouping.label).tag(grouping)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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

    private var emptyTitle: String {
        switch store.period {
        case .last7Days: return "No visits in the last 7 days"
        case .last30Days: return "No visits in the last 30 days"
        case .allTime: return "No visits yet"
        }
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
        .padding(16)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .padding()
        .frame(maxWidth: 680)
}
#endif
