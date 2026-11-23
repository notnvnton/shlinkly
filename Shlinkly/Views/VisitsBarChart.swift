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
/// Hovering (macOS) or tapping (iOS) a column shows the `.callout` beside it:
/// it fades in and rises 4 pt over 160 ms (ease-out) and fades out over 120 ms
/// (ease-in), while the other columns dim to 0.45 over 160 ms.
struct VisitsBarChart: View {
    let data: [VisitBucket]
    /// The people / bots split of the same columns: drawn as the stacked bars
    /// (bots on top only while `excludeBots` is off) and spelled out in the
    /// callout. Always carries both halves, whatever the bot toggle says.
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
    /// The column the callout shows and the dimming follows: `selectedDate`'s
    /// column, set with the layout's timing (see ``updateShownColumn(for:)``).
    @State private var shownColumnStart: Date?
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
            // One mark per column, so a column is one shape: one silhouette,
            // one rounded top, no seam. Its fill is a gradient with a hard stop
            // at the people level — translucent brand above (the bots, the
            // "empty" part of the tube), the brand gradient below (the people).
            // Charts maps a mark's gradient to the mark's own bounds (checked by
            // rendering), so the stop lands exactly at `bots / total`. With bots
            // excluded, the column is people only.
            ForEach(breakdowns) { column in
                let height = excludeBots ? column.people : column.total
                BarMark(
                    x: .value("Date", column.start, unit: unit, calendar: calendar),
                    yStart: .value("Visits", 0),
                    yEnd: .value("Visits", height),
                    width: barWidth.map { .fixed($0) } ?? .automatic
                )
                .foregroundStyle(columnFill(people: column.people, bots: excludeBots ? 0 : column.bots))
                // With a column selected, the others recede, both parts together.
                .opacity(barOpacity(for: column.start))
                .clipShape(columnShape)
            }
        }
        // `.bar { transition: opacity .16s ease }`: dimming and un-dimming.
        .animation(.easeInOut(duration: 0.16), value: shownColumnStart)
        // Continuous date domain — a Range, never an array. (Array/band and
        // Int-index scales both crash Swift Charts at render, so this stays
        // continuous.) The store guarantees start <= end.
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...max(yMax, 1))
        .chartYAxis {
            // As drawn: three labels (the ceiling, the middle, 0) with a 1 pt
            // `--sep` line at each, horizontal only. The middle one only when
            // the ceiling halves into a whole number.
            AxisMarks(position: .leading, values: yAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Palette.sep)
                AxisValueLabel {
                    if let number = value.as(Int.self) {
                        Text(number, format: .number)
                            .layoutFont(Self.yLabelSize)
                            .monospacedDigit()
                            .foregroundStyle(Palette.text2)
                    }
                }
            }
        }
        .chartXAxis {
            // Labels only: no vertical grid lines, no ticks (the Y axis keeps the
            // horizontal guides). Explicit, thinned column values (at most 5) so
            // Swift Charts can't fall back to an hour axis. These are tick values
            // on the continuous scale, not a scale domain, so they don't create a
            // band scale.
            //
            // The label MUST use the closure form + `.fixedSize()`: with unit-binned
            // bars, Charts otherwise clamps each label to one cell's width
            // (~11pt on a 30-day domain) and truncates "Jun 15" to "Ju…". `.fixedSize()`
            // lets the text keep its natural width. Do not revert to `AxisValueLabel(format:)`.
            AxisMarks(values: labelDates) { value in
                // Explicit, standard anchors — never a custom `UnitPoint` (Charts
                // warns about deriving one): the first label starts at the plot's
                // leading edge, the last one ends at its trailing edge, the rest
                // centre under their column's start. None can poke out of the plot.
                AxisValueLabel(anchor: labelAnchor(index: value.index, count: value.count)) {
                    if let date = value.as(Date.self) {
                        Text(labelDate(for: date), format: axisLabelFormat)
                            .layoutFont(11)
                            .monospacedDigit()
                            .foregroundStyle(Palette.text2)
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
                    if let shownBucket,
                       let placement = calloutPlacement(for: shownBucket, proxy: proxy, geometry: geometry) {
                        placement {
                            callout(for: shownBucket)
                        }
                        // Shown: opacity 1 at its place. Hidden: opacity 0, 4 pt lower.
                        .transition(.opacity.combined(with: .offset(y: 4)))
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
        .onChange(of: selectedDate) { _, newDate in
            updateShownColumn(for: newDate)
        }
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

    /// The column the callout is showing.
    private var shownBucket: VisitBucket? {
        guard let shownColumnStart else { return nil }
        return data.first { $0.start == shownColumnStart }
    }

    /// Follows the selection with the layout's timing: the callout appears over
    /// 160 ms ease-out and disappears over 120 ms ease-in; moving from one
    /// column to the next moves it straight there, as drawn (only its opacity
    /// and offset are animated, never its position).
    private func updateShownColumn(for date: Date?) {
        let start = date.flatMap { selected in data.first { $0.contains(selected) }?.start }
        guard start != shownColumnStart else { return }
        if start == nil {
            withAnimation(.easeIn(duration: 0.12)) { shownColumnStart = nil }
        } else if shownColumnStart == nil {
            withAnimation(.easeOut(duration: 0.16)) { shownColumnStart = start }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { shownColumnStart = start }
        }
    }

    /// Full strength with nothing selected or for the selected column; with a
    /// column selected, the others recede to 0.45.
    private func barOpacity(for columnStart: Date) -> Double {
        guard let shownColumnStart else { return 1 }
        return shownColumnStart == columnStart ? 1 : 0.45
    }

    /// The Y labels: the ceiling, its half when whole, and 0.
    private var yAxisValues: [Int] {
        let ceiling = max(yMax, 1)
        return ceiling % 2 == 0 ? [0, ceiling / 2, ceiling] : [0, ceiling]
    }

    /// Y labels: 10 pt on the Mac, 11 pt on the iPhone.
    private static var yLabelSize: CGFloat {
        #if os(macOS)
        10
        #else
        11
        #endif
    }

    /// A column's clip: rounded top corners only (4 pt, or half the bar on a
    /// very thin bar), square at the baseline. The column is one mark, so this
    /// is its only rounded edge.
    private var columnShape: UnevenRoundedRectangle {
        let radius = min(4, (barWidth ?? 8) / 2)
        return UnevenRoundedRectangle(topLeadingRadius: radius,
                                      topTrailingRadius: radius,
                                      style: .continuous)
    }

    /// A column's fill, top to bottom: `--bar-bots` (the bots, the same hue,
    /// translucent) down to the people level, then a flat, hard change into the
    /// `--bar` gradient (the people). No bots: `--bar` fills the whole column.
    private func columnFill(people: Int, bots: Int) -> LinearGradient {
        let total = people + bots
        let level = total > 0 ? CGFloat(bots) / CGFloat(total) : 0
        var stops: [Gradient.Stop] = []
        if level > 0 {
            stops.append(.init(color: Palette.barBots, location: 0))
            stops.append(.init(color: Palette.barBots, location: level))
        }
        stops.append(.init(color: Palette.barTop, location: level))
        stops.append(.init(color: Palette.barBottom, location: 1))
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
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
            top: plot.minY + Self.calloutTop,
            gap: (barWidth ?? 0) / 2 + 14,
            onTrailingSide: calloutOnTrailingSide(of: bucket)
        )
    }

    /// Whether the callout goes to the right of `bucket`'s bar: yes for the bars
    /// in the first 55% of the chart (as drawn), where there is room.
    private func calloutOnTrailingSide(of bucket: VisitBucket) -> Bool {
        guard let index = data.firstIndex(where: { $0.id == bucket.id }), data.count > 1 else { return true }
        return Double(index) / Double(data.count - 1) < 0.55
    }

    /// The callout's distance from the plot's top: 8 pt (Mac), 6 pt (iPhone).
    private static var calloutTop: CGFloat {
        #if os(macOS)
        8
        #else
        6
        #endif
    }

    /// `.callout`: the card beside the selected column. Its period, its count
    /// (semibold) and the people / bots split; `--card` (`#2B2A33` in dark) with
    /// a 1 pt `--card-border` ring and `0 6 16` at 10%, radius 10, 8 pt / 10 pt
    /// in, at least 118 pt wide. 11 / 14 / 11 pt on the Mac, 12 / 16 / 12 pt on
    /// the iPhone.
    private func callout(for bucket: VisitBucket) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(alignment: .leading, spacing: 1) {
            Text(periodTitle(for: bucket))
                .layoutFont(Self.calloutSmall)
                .foregroundStyle(Palette.text2)
            Text(countTitle(for: bucket.count))
                .layoutFont(Self.calloutLarge, .semibold)
                .monospacedDigit()
                .foregroundStyle(Palette.text)
            if let detail = breakdownTitle(for: bucket) {
                Text(detail)
                    .layoutFont(Self.calloutSmall)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text2)
            }
        }
        .fixedSize()
        .frame(minWidth: 118 - 20, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.calloutBg, in: shape)
        .overlay(shape.strokeBorder(Palette.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 6)
    }

    private static var calloutSmall: CGFloat {
        #if os(macOS)
        11
        #else
        12
        #endif
    }

    private static var calloutLarge: CGFloat {
        #if os(macOS)
        14
        #else
        16
        #endif
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
    /// always anchored to include the last column (today's). Striding back from
    /// it keeps the spacing even. Every value is an existing column start,
    /// except the last: it is moved to the domain's end (the plot's trailing
    /// edge) so its label can end there, and ``labelDate(for:)`` maps it back to
    /// the last column's date.
    private var labelDates: [Date] {
        let starts = data.map(\.start)
        guard starts.count > 1 else { return starts }
        let target = starts.count <= 10 ? 4 : 5
        var picked: [Date]
        if starts.count <= target {
            picked = starts
        } else {
            let step = max(1, Int((Double(starts.count - 1) / Double(target - 1)).rounded()))
            picked = []
            var index = starts.count - 1
            while index >= 0 {
                picked.append(starts[index])
                index -= step
            }
            picked.reverse()
        }
        picked[picked.count - 1] = xDomain.upperBound
        return picked
    }

    /// The date a label names: the domain's end stands for the last column.
    private func labelDate(for value: Date) -> Date {
        guard value == xDomain.upperBound, let last = data.last else { return value }
        return last.start
    }

    /// First label hangs from the plot's leading edge, the last from its
    /// trailing edge, the others are centred under their tick.
    private func labelAnchor(index: Int, count: Int) -> UnitPoint {
        if index == 0 { return .topLeading }
        if index == count - 1, count > 1 { return .topTrailing }
        return .top
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
