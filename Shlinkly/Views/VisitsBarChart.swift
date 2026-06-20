//
//  VisitsBarChart.swift
//  Shlinkly
//

import SwiftUI
import Charts
import ShlinklyCore

/// A per-day bar chart of visits over the selected period.
///
/// Drawn on a **continuous** day axis (`BarMark` with `unit: .day` over a date
/// `Range` domain) — *not* a categorical/band scale, which traps Swift Charts at
/// render (on both Date and Int-index domains). The data is zero-filled across
/// the window (see ``ShortURLDetailStore/dailyCounts``) so empty days still
/// occupy the axis and the timeline reads continuously.
struct VisitsBarChart: View {
    let data: [ShortURLDetailStore.DailyCount]
    /// Fixed upper bound for the Y axis. Held constant across the bot toggle so
    /// excluding bots only shortens bars instead of rescaling the axis.
    let yMax: Int
    /// The full period window for the X axis (start … end-plus-a-day). Pinning the
    /// continuous domain to the whole period keeps a single day's data from
    /// collapsing the axis to an hour scale, and the trailing day of padding keeps
    /// "today" off the right edge.
    let xDomain: ClosedRange<Date>

    var body: some View {
        Chart(data) { point in
            BarMark(
                x: .value("Day", point.day, unit: .day),
                y: .value("Visits", point.count)
            )
            .foregroundStyle(Color.accentColor)
            // Round the top of each bar for a softer, less "spreadsheet" look.
            .cornerRadius(5)
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
            // Explicit, thinned day ticks (≈4 for a week, ≈5 for a month) so Swift
            // Charts can't fall back to an hour axis. These are tick values on the
            // continuous scale, not a scale domain, so they don't create a band scale.
            //
            // The label MUST use the closure form + `.fixedSize()`: with `unit: .day`
            // bars, Charts otherwise clamps each label to one day-cell's width
            // (~11pt on a 30-day domain) and truncates "Jun 15" to "Ju…". `.fixedSize()`
            // lets the text keep its natural width. Do not revert to `AxisValueLabel(format:)`.
            AxisMarks(values: labelDays) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisTick()
                    .foregroundStyle(Color.primary.opacity(0.15))
                AxisValueLabel {
                    if let day = value.as(Date.self) {
                        Text(day, format: .dateTime.month(.abbreviated).day())
                            .fixedSize()
                    }
                }
            }
        }
        // Purely a display chart — no selection or tap. Opt out of hit testing
        // so it can never capture the enclosing ScrollView's pan gesture.
        .allowsHitTesting(false)
        .accessibilityLabel("Visits by day")
    }

    /// The thinned set of days to label: ~4 across a 7-day window, ~5 across 30,
    /// always anchored to include today (the last day) so the right-most label is
    /// present and whole. Striding back from today keeps the spacing even; every
    /// value is an existing `data` day (start-of-day), matching the bar positions.
    private var labelDays: [Date] {
        let days = data.map(\.day)
        guard days.count > 1 else { return days }
        let target = days.count <= 10 ? 4 : 5
        guard days.count > target else { return days }
        let step = max(1, Int((Double(days.count - 1) / Double(target - 1)).rounded()))
        var picked: [Date] = []
        var index = days.count - 1
        while index >= 0 {
            picked.append(days[index])
            index -= step
        }
        return picked.reversed()
    }
}
