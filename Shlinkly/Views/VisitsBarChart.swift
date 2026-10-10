//
//  VisitsBarChart.swift
//  Shlinkly
//

import SwiftUI
import Charts
import ShlinklyCore

/// A bar chart of visits over the selected period, one bar per day, week, month
/// or year (``VisitGrouping``).
///
/// Drawn on a **continuous** date axis (`BarMark` with a calendar `unit` over a
/// date `Range` domain) — *not* a categorical/band scale, which traps Swift Charts
/// at render (on both Date and Int-index domains). The data is zero-filled across
/// the window (see ``ShortURLDetailStore/chartBuckets``) so empty columns still
/// occupy the axis and the timeline reads continuously.
///
/// Hovering (macOS) or touching (iOS) a bar highlights it and floats a callout
/// with its exact period and count above it.
struct VisitsBarChart: View {
    let data: [VisitBucket]
    /// The people / bots split of the same columns, for the callout. Always
    /// carries both halves, whatever the bot toggle says.
    let breakdowns: [VisitBucketBreakdown]
    /// The step each bar spans; picks the bar width, the axis label format and
    /// the callout's wording.
    let grouping: VisitGrouping
    /// The calendar `data` was bucketed with, so the bars are binned on the very
    /// same day / week / month boundaries.
    let calendar: Calendar
    /// Fixed upper bound for the Y axis. Held constant across the bot toggle so
    /// excluding bots only shortens bars instead of rescaling the axis.
    let yMax: Int
    /// The full period window for the X axis, widened to whole columns. Pinning
    /// the continuous domain to the whole period keeps a single day's data from
    /// collapsing the axis to an hour scale.
    let xDomain: ClosedRange<Date>
    /// The period and bot filter the data was built for. Not drawn — a change to
    /// either (or to `grouping`) drops the current selection.
    let period: ShortURLDetailStore.Period
    let excludeBots: Bool
    /// The page of a paged (month) chart on screen. Not drawn either — turning
    /// the page drops the selection too.
    let page: Int

    /// A date inside the selected column. macOS: the date under the pointer,
    /// straight from `chartXSelection`. iOS: the start of the tapped column,
    /// which stays selected until it is tapped again or the tap lands elsewhere.
    @State private var selectedDate: Date?
    /// The plot area's current width, measured through the chart's proxy so the
    /// bars can be sized in points. Zero until the first layout pass.
    @State private var plotWidth: CGFloat = 0

    /// The widest a bar may get, in points. With only a handful of columns
    /// (7 days, a few weeks) a bar would otherwise swell to fill its whole slot.
    private static let maximumBarWidth: CGFloat = 24
    /// The share of its slot a bar fills when the slot is the limiting factor.
    private static let barWidthRatio: CGFloat = 0.75
    /// The least empty space left between two neighbouring bars, in points, so
    /// dense charts (30 daily bars on an iPhone) don't fuse into one block.
    private static let minimumBarGap: CGFloat = 2

    var body: some View {
        Chart {
            ForEach(data) { bucket in
                BarMark(
                    x: .value("Date", bucket.start, unit: unit, calendar: calendar),
                    y: .value("Visits", bucket.count),
                    width: barWidth.map { .fixed($0) } ?? .automatic
                )
                .foregroundStyle(Color.accentColor)
                // With a bar selected, the others recede.
                .opacity(selectedBucket == nil || selectedBucket?.id == bucket.id ? 1 : 0.35)
                // Round the top of each bar for a softer, less "spreadsheet" look.
                .cornerRadius(min(5, (barWidth ?? 10) / 2))
            }
            if let selectedBucket {
                // A faint guide behind the bars. The callout is *not* an annotation
                // on this mark: an annotation is drawn at its mark's depth, so tall
                // bars showed through it. It lives in the chart overlay instead.
                RuleMark(x: .value("Selected", selectedBucket.start, unit: unit, calendar: calendar))
                    .foregroundStyle(Color.primary.opacity(0.12))
                    .zIndex(-1)
            }
        }
        // Continuous date domain — a Range, never an array. (Array/band and
        // Int-index scales both crash Swift Charts at render, so this stays
        // continuous.) The store guarantees start <= end.
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...max(yMax, 1))
        .chartYAxis {
            // Sparse Y ticks, each with a single thin, solid, very light guide
            // line — no dashes, no heavy gridlines.
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel()
            }
        }
        .chartXAxis {
            // Explicit, thinned column ticks (≈4 for a week, ≈5 beyond) so Swift
            // Charts can't fall back to an hour axis. These are tick values on the
            // continuous scale, not a scale domain, so they don't create a band scale.
            //
            // The label MUST use the closure form + `.fixedSize()`: with unit-binned
            // bars, Charts otherwise clamps each label to one cell's width
            // (~11pt on a 30-day domain) and truncates "Jun 15" to "Ju…". `.fixedSize()`
            // lets the text keep its natural width. Do not revert to `AxisValueLabel(format:)`.
            AxisMarks(values: labelDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisTick()
                    .foregroundStyle(Color.primary.opacity(0.15))
                // An explicit, standard anchor: the label hangs below its tick and
                // starts at it — where Charts puts it by default — without leaving
                // Charts to derive a custom `UnitPoint` (which it warns about).
                AxisValueLabel(anchor: .topLeading) {
                    if let date = value.as(Date.self) {
                        Text(date, format: axisLabelFormat)
                            .fixedSize()
                    }
                }
            }
        }
        // Track the plot area's real width (it changes with the window on the
        // Mac and with rotation on iOS) so `barWidth` follows it.
        .chartBackground { proxy in
            Color.clear
                .onChange(of: proxy.plotSize.width, initial: true) { _, width in
                    plotWidth = width
                }
        }
        // The overlay sits above every mark, so the (opaque) callout placed in it
        // is always drawn over the bars, dimmed or not.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    #if os(iOS)
                    // iOS selects by *tap*, not by `chartXSelection`: that one only
                    // shows the callout while a finger drags across the plot (a plain
                    // tap shows nothing) and its drag competes with the page's scroll.
                    // A tap gesture leaves vertical scrolling and the edge-swipe
                    // "back" entirely alone.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            handleTap(at: location, proxy: proxy, geometry: geometry)
                        }
                    #endif
                    if let selectedBucket,
                       let placement = calloutPlacement(for: selectedBucket, proxy: proxy, geometry: geometry) {
                        placement {
                            callout(for: selectedBucket)
                        }
                        // Never in the way of a tap or the pointer.
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        #if os(iOS)
        .sensoryFeedback(trigger: selectedDate) { _, new in
            // A light tick when a column is picked; silence when it is cleared.
            new == nil ? nil : .selection
        }
        #else
        .chartXSelection(value: $selectedDate)
        #endif
        .onChange(of: period) { _, _ in selectedDate = nil }
        .onChange(of: grouping) { _, _ in selectedDate = nil }
        .onChange(of: excludeBots) { _, _ in selectedDate = nil }
        .onChange(of: page) { _, _ in selectedDate = nil }
        .accessibilityLabel("Visits by \(grouping.noun)")
    }

    /// The calendar unit one bar spans on the continuous axis.
    private var unit: Calendar.Component { grouping.calendarComponent }

    /// The bar width in points: ``barWidthRatio`` of one column's slot, leaving
    /// at least ``minimumBarGap`` between neighbours and capped at
    /// ``maximumBarWidth``. The bar stays centred in its period — the `unit`
    /// binning positions it, this only narrows it. `nil` (Charts' own sizing)
    /// until the plot has been measured.
    private var barWidth: CGFloat? {
        guard plotWidth > 0, !data.isEmpty else { return nil }
        let slot = plotWidth / CGFloat(data.count)
        let width = min(slot * Self.barWidthRatio, slot - Self.minimumBarGap, Self.maximumBarWidth)
        return max(1, width)
    }

    #if os(iOS)
    /// Resolves a tap to the column whose period it falls in. Tapping a column
    /// selects it, tapping the selected one clears it, tapping another moves the
    /// selection, and a tap outside the plot (axis labels, margins) clears it.
    private func handleTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotAnchor = proxy.plotFrame else { return }
        let plot = geometry[plotAnchor]
        guard plot.contains(location),
              let date = proxy.value(atX: location.x - plot.minX, as: Date.self),
              let tapped = data.first(where: { $0.contains(date) }),
              tapped.id != selectedBucket?.id else {
            selectedDate = nil
            return
        }
        selectedDate = tapped.start
    }
    #endif

    /// The column under the pointer / finger, if any.
    private var selectedBucket: VisitBucket? {
        guard let selectedDate else { return nil }
        return data.first { $0.contains(selectedDate) }
    }

    // MARK: - Callout

    /// Where the callout goes for `bucket`: inside the plot, pinned to its top
    /// edge (above the plot it covered the card's title and step picker), and
    /// beside the bar rather than on it, so the bar it describes stays visible.
    /// `nil` until the chart has laid out.
    private func calloutPlacement(
        for bucket: VisitBucket,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> CalloutPlacement? {
        guard let plotAnchor = proxy.plotFrame,
              let startX = proxy.position(forX: bucket.start),
              let endX = proxy.position(forX: bucket.end) else { return nil }
        let plot = geometry[plotAnchor]
        return CalloutPlacement(
            barCenterX: plot.minX + (startX + endX) / 2,
            top: plot.minY,
            gap: (barWidth ?? 0) / 2 + 6,
            onTrailingSide: calloutOnTrailingSide(of: bucket)
        )
    }

    /// Whether the callout goes to the right of `bucket`'s bar: yes for the bars
    /// in the left half of the chart, where there is room on that side.
    private func calloutOnTrailingSide(of bucket: VisitBucket) -> Bool {
        guard let index = data.firstIndex(where: { $0.id == bucket.id }) else { return true }
        return index * 2 < data.count
    }

    /// An opaque system surface that follows light / dark on its own. Not a
    /// material: inside a chart annotation a material has nothing to blur and
    /// came out near-black in light mode on iPhone, hiding the text.
    private var calloutBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// The floating card beside the selected bar: its period and its exact
    /// count. Borrows the toast pill's hairline border and soft shadow on a
    /// rounded rectangle, since it stacks several lines.
    private func callout(for bucket: VisitBucket) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 1) {
            Text(periodTitle(for: bucket))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(countTitle(for: bucket.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if let detail = breakdownTitle(for: bucket) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(calloutBackground, in: shape)
        .overlay(shape.strokeBorder(.separator))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    /// The selected column's headline count. With bots excluded the bars count
    /// people, so the headline says so; otherwise it counts visits.
    private func countTitle(for count: Int) -> String {
        if count == 0 { return "No visits" }
        return excludeBots ? peopleTitle(count) : (count == 1 ? "1 visit" : "\(count.formatted()) visits")
    }

    /// The people / bots line under the headline: "12 people · 9 bots", or just
    /// the half that isn't zero. `nil` — no third line — when bots are excluded
    /// (the headline already is the people count) or the column is empty.
    private func breakdownTitle(for bucket: VisitBucket) -> String? {
        guard !excludeBots,
              let breakdown = breakdowns.first(where: { $0.start == bucket.start }),
              breakdown.total > 0 else { return nil }
        if breakdown.bots == 0 { return peopleTitle(breakdown.people) }
        let bots = breakdown.bots == 1 ? "1 bot" : "\(breakdown.bots.formatted()) bots"
        if breakdown.people == 0 { return bots }
        return "\(peopleTitle(breakdown.people)) · \(bots)"
    }

    private func peopleTitle(_ count: Int) -> String {
        count == 1 ? "1 person" : "\(count.formatted()) people"
    }

    /// The selected column's period in words: "15 Jun", "Week of 15 Jun",
    /// "June 2026" or "2026" (field order follows the locale).
    private func periodTitle(for bucket: VisitBucket) -> String {
        let dayAndMonth = Date.FormatStyle.dateTime.day().month(.abbreviated)
        switch grouping {
        case .day:
            return bucket.start.formatted(dayAndMonth)
        case .week:
            return "Week of \(bucket.start.formatted(dayAndMonth))"
        case .month:
            return bucket.start.formatted(.dateTime.month(.wide).year())
        case .year:
            return bucket.start.formatted(.dateTime.year())
        }
    }

    // MARK: - Axis labels

    /// Axis label per step: "Jun 15" for a day or a week (the week by its first
    /// day), "Jun" for a month, "2026" for a year — localized.
    private var axisLabelFormat: Date.FormatStyle {
        switch grouping {
        case .day, .week: return .dateTime.month(.abbreviated).day()
        case .month: return .dateTime.month(.abbreviated)
        case .year: return .dateTime.year()
        }
    }

    /// The thinned set of columns to label: ~4 across up to 10 columns, ~5 beyond,
    /// always anchored to include the last column (today's) so the right-most
    /// label is present and whole. Striding back from it keeps the spacing even;
    /// every value is an existing column start, matching the bar positions.
    private var labelDates: [Date] {
        let starts = data.map(\.start)
        guard starts.count > 1 else { return starts }
        let target = starts.count <= 10 ? 4 : 5
        guard starts.count > target else { return starts }
        let step = max(1, Int((Double(starts.count - 1) / Double(target - 1)).rounded()))
        var picked: [Date] = []
        var index = starts.count - 1
        while index >= 0 {
            picked.append(starts[index])
            index -= step
        }
        return picked.reversed()
    }
}

/// Places the callout in the chart overlay: its top at the plot's top edge, and
/// horizontally beside the selected bar — `gap` to the right of the bar's centre
/// or `gap` to its left — then slid back inside the chart if it would poke past
/// either edge. A layout rather than an offset because the clamp needs the
/// callout's own measured width.
private struct CalloutPlacement: Layout {
    /// The selected bar's centre, in the overlay's coordinates.
    let barCenterX: CGFloat
    /// The plot area's top edge, in the overlay's coordinates.
    let top: CGFloat
    /// Distance from the bar's centre to the callout's near edge.
    let gap: CGFloat
    /// `true` to sit to the right of the bar, `false` to its left.
    let onTrailingSide: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let callout = subviews.first else { return }
        let size = callout.sizeThatFits(.unspecified)
        let preferred = onTrailingSide ? barCenterX + gap : barCenterX - gap - size.width
        let x = min(max(preferred, 0), max(0, bounds.width - size.width))
        callout.place(
            at: CGPoint(x: bounds.minX + x, y: bounds.minY + top),
            anchor: .topLeading,
            proposal: ProposedViewSize(size)
        )
    }
}
