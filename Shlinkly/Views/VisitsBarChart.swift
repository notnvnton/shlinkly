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

    /// The date under the pointer / finger, straight from `chartXSelection`.
    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(data) { bucket in
                BarMark(
                    x: .value("Date", bucket.start, unit: unit, calendar: calendar),
                    y: .value("Visits", bucket.count)
                )
                .foregroundStyle(Color.accentColor)
                // With a bar selected, the others recede.
                .opacity(selectedBucket == nil || selectedBucket?.id == bucket.id ? 1 : 0.35)
                // Round the top of each bar for a softer, less "spreadsheet" look.
                .cornerRadius(5)
            }
            if let selectedBucket {
                RuleMark(x: .value("Selected", selectedBucket.start, unit: unit, calendar: calendar))
                    .foregroundStyle(Color.primary.opacity(0.12))
                    .zIndex(-1)
                    // `.fit(to: .chart)` slides the callout sideways so it never
                    // pokes past the chart's left/right edge; vertically it is
                    // left alone and floats above the plot.
                    .annotation(
                        position: .top,
                        spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        callout(for: selectedBucket)
                    }
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
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: axisLabelFormat)
                            .fixedSize()
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .onChange(of: period) { _, _ in selectedDate = nil }
        .onChange(of: grouping) { _, _ in selectedDate = nil }
        .onChange(of: excludeBots) { _, _ in selectedDate = nil }
        .accessibilityLabel("Visits by \(grouping.noun)")
    }

    /// The calendar unit one bar spans on the continuous axis.
    private var unit: Calendar.Component { grouping.calendarComponent }

    /// The column under the pointer / finger, if any.
    private var selectedBucket: VisitBucket? {
        guard let selectedDate else { return nil }
        return data.first { $0.contains(selectedDate) }
    }

    // MARK: - Callout

    /// The floating card over the selected bar: its period and its exact count.
    /// Borrows the toast pill's surface (material, hairline border, soft shadow)
    /// on a rounded rectangle, since it stacks two lines.
    private func callout(for bucket: VisitBucket) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 1) {
            Text(periodTitle(for: bucket))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(bucket.count == 1 ? "1 visit" : "\(bucket.count.formatted()) visits")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.separator))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
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
