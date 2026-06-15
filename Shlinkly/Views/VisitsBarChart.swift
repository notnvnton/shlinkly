//
//  VisitsBarChart.swift
//  Shlinkly
//

import SwiftUI
import Charts
import ShlinklyCore

/// A per-day bar chart of visits over the selected period.
///
/// The data is expected to be zero-filled across the window (see
/// ``ShortURLDetailStore/dailyCounts``) so empty days still occupy the axis and
/// the timeline reads continuously.
struct VisitsBarChart: View {
    let data: [ShortURLDetailStore.DailyCount]
    /// Fixed upper bound for the Y axis. Held constant across the bot toggle so
    /// excluding bots only shortens bars instead of rescaling the axis.
    let yMax: Int

    var body: some View {
        Chart(data) { point in
            BarMark(
                x: .value("Day", point.day),
                y: .value("Visits", point.count)
            )
            .foregroundStyle(Color.accentColor)
            // Round the top of each bar for a softer, less "spreadsheet" look.
            .cornerRadius(5)
        }
        // Discrete day bands: an *array* domain (not a continuous time range)
        // gives a band scale, so every day of the period is one equal-width cell.
        // A single day is then a normal-width bar — never stretched, and the axis
        // never collapses to hours. All three periods share this; only the cell
        // count differs. `point.day` is start-of-day, so it matches the domain.
        .chartXScale(domain: data.map(\.day))
        .chartYScale(domain: 0...yMax)
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
            // A few evenly-spaced day labels (always including today), in full
            // "Jun 15" form so nothing truncates to "J…". No vertical gridlines.
            AxisMarks(values: labelDays) {
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        // Keep today's bar/label off the right edge in case the band scale's own
        // outer inset is tight.
        .padding(.trailing, 6)
        // Purely a display chart — no selection or tap. Opt out of hit testing
        // so it can never capture the enclosing ScrollView's pan gesture.
        .allowsHitTesting(false)
        .accessibilityLabel("Visits by day")
    }

    /// The subset of days to label on the X axis: ~4 across a 7-day window, ~5
    /// across 30, always anchored to include today (the last day) so the
    /// right-most label is present and whole. Striding back from today keeps the
    /// spacing even and guarantees today is never the one that gets dropped.
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
