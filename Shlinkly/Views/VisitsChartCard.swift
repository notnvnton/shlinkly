//
//  VisitsChartCard.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// "Over time", as layout v3 draws it.
///
/// Mac (`MacMain`): one `.mcard`. Its top row holds the "Over time" label and,
/// when there is a choice, the step control (`.mseg.sm`, "Week | Month") on the
/// right; then the chart (170 pt plot), the axis, and a footer with the date
/// range on the left and the legend on the right.
///
/// iPhone (`PhoneDetail`): the "Over time" label with the small segmented step
/// control on its right, then a `.card` with the chart (180 pt plot) and the
/// same footer.
///
/// The paging arrows of a paged month chart aren't drawn; they keep working,
/// as square `.mbtn`s (Mac, 24 pt to match the step control) or brand chevrons
/// (iPhone) beside the step control.
/// Everything comes from the ``ShortURLDetailStore``; this view holds no state.
struct VisitsChartCard: View {
    let store: ShortURLDetailStore

    var body: some View {
        #if os(macOS)
        MacCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 6) {
                    MacLabel("Over time")
                        .padding(.vertical, 4)
                    Spacer(minLength: 8)
                    if store.state == .loaded {
                        pagingButtons
                        groupingPicker
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 14)
                .padding(.top, 8)

                chartContent(plotHeight: 170)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if store.state == .loaded {
                    footer
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 12)
        }
        #else
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text("Over time")
                    .layoutFont(13, .medium)
                    .foregroundStyle(Palette.text2)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if store.state == .loaded {
                    pagingButtons
                    groupingPicker
                }
            }
            .padding(.bottom, 8)

            LayoutCard {
                VStack(alignment: .leading, spacing: 0) {
                    chartContent(plotHeight: 180)
                    if store.state == .loaded {
                        footer
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
        }
        #endif
    }

    // MARK: - Footer

    /// The date range on the left (11 pt Mac, 12 pt iPhone), the legend on the
    /// right (11 pt): an 8 pt `--bar` square "People" and, while bots are
    /// drawn, an 8 pt `--bar-bots` square "Bots", 12 pt apart.
    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(store.chartDateRange)
                .layoutFont(Self.footerSize)
                .monospacedDigit()
                .foregroundStyle(Palette.text2)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                legendItem("People", fill: AnyShapeStyle(Palette.bar))
                if !store.excludeBots {
                    legendItem("Bots", fill: AnyShapeStyle(Palette.barBots))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private static var footerSize: CGFloat {
        #if os(macOS)
        11
        #else
        12
        #endif
    }

    private func legendItem(_ title: String, fill: AnyShapeStyle) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(fill)
                .frame(width: 8, height: 8)
            Text(title)
                .layoutFont(11)
                .foregroundStyle(Palette.text2)
                .lineLimit(1)
        }
    }

    // MARK: - Step control

    /// Day / Week / Month / Year. Only "All time" offers a choice, and only
    /// when the window is long enough for a coarser step to be worth drawing.
    @ViewBuilder
    private var groupingPicker: some View {
        let groupings = store.availableGroupings
        if groupings.count > 1 {
            #if os(macOS)
            // `.mseg.sm` ("Week | Month"): the available steps only.
            MacSegmented("Group by", selection: groupingBinding,
                         options: groupings.map { .init(value: $0, label: $0.label) },
                         size: .small)
            #else
            Picker("Group by", selection: groupingBinding) {
                ForEach(groupings, id: \.self) { grouping in
                    Text(grouping.label).tag(grouping)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            #endif
        }
    }

    private var groupingBinding: Binding<VisitGrouping> {
        Binding(get: { store.chartGrouping }, set: { store.setGrouping($0) })
    }

    // MARK: - Paging

    /// The "‹" / "›" arrows that turn a paged month chart a year at a time.
    @ViewBuilder
    private var pagingButtons: some View {
        if store.isChartPaged {
            HStack(spacing: 4) {
                pageButton(systemImage: "chevron.left", label: "Previous 12 months",
                           isEnabled: store.canShowPreviousChartPage) {
                    store.showPreviousChartPage()
                }
                pageButton(systemImage: "chevron.right", label: "Next 12 months",
                           isEnabled: store.canShowNextChartPage) {
                    store.showNextChartPage()
                }
            }
        }
    }

    private func pageButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                #if os(iOS)
                .foregroundStyle(Palette.brand)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
                #endif
        }
        #if os(macOS)
        .buttonStyle(MacButtonStyle(square: true, height: 24))
        #else
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        #endif
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .help(label)
    }

    // MARK: - Chart

    /// The chart, or its loading / empty / error stand-in (not drawn; kept, in
    /// the layout's colors and buttons).
    @ViewBuilder
    private func chartContent(plotHeight: CGFloat) -> some View {
        switch store.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: plotHeight)
        case .error(let message):
            chartMessage(title: "Couldn't load visits", detail: message, plotHeight: plotHeight) {
                Button("Try Again") { store.load() }
                    .stateButtonStyle()
            }
        case .empty:
            chartMessage(title: emptyTitle, detail: nil, plotHeight: plotHeight) {
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
                // The plot plus the axis labels under it (6 pt gap, 11 pt).
                .frame(height: plotHeight + 22)
        }
    }

    private func chartMessage<Action: View>(
        title: String,
        detail: String?,
        plotHeight: CGFloat,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .layoutFont(15, .semibold)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .layoutFont(13)
                    .foregroundStyle(Palette.text2)
                    .multilineTextAlignment(.center)
            }
            action()
        }
        .frame(maxWidth: .infinity, minHeight: plotHeight)
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
    /// A state's one action (not drawn): `.mbtn-primary` on the Mac,
    /// `.btn-text` on the iPhone.
    @ViewBuilder
    func stateButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.macPrimary)
        #else
        buttonStyle(.layoutText)
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

#Preview("Over time, months 12 at a time") {
    VisitsChartCard(store: VisitsChartCardPreviewData.store())
        .padding(24)
        .frame(maxWidth: 680)
        .canvasBackground()
}
#endif
