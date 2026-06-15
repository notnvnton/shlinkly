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
/// ``ShortURLDetailStore/dailyCounts``) so every day of the period is one
/// discrete, equal-width cell — empty days included.
///
/// The X axis is a **categorical band scale over integer day indices**, not a
/// `Date` array domain: plotting a `BarMark` against a `Date` array domain traps
/// in Swift Charts at render time. Indices sidestep that while giving the same
/// equal-width cells; each label maps its index back to that day's date.
struct VisitsBarChart: View {
    let data: [ShortURLDetailStore.DailyCount]
    /// Fixed upper bound for the Y axis. Held constant across the bot toggle so
    /// excluding bots only shortens bars instead of rescaling the axis.
    let yMax: Int

    var body: some View {
        Group {
            if data.isEmpty {
                // Defensive: the detail screen only shows this chart in `.loaded`,
                // where the window is always ≥1 day, but never hand Charts an empty
                // (band) domain — that can trap.
                Color.clear
            } else {
                chart
            }
        }
        // Purely a display chart — no selection or tap. Opt out of hit testing so
        // it can never capture the enclosing ScrollView's pan gesture.
        .allowsHitTesting(false)
        .accessibilityLabel("Visits by day")
    }

    private var chart: some View {
        Chart {
            // Enumerate so each bar sits in its own integer band cell, ordered
            // oldest → today (left → right). `item.offset` is the band position;
            // `item.element` carries the day and its count.
            ForEach(Array(data.enumerated()), id: \.offset) { item in
                BarMark(
                    x: .value("Day", item.offset),
                    y: .value("Visits", item.element.count)
                )
                .foregroundStyle(Color.accentColor)
                // Round the top of each bar for a softer, less "spreadsheet" look.
                .cornerRadius(5)
            }
        }
        // Integer band scale: one equal-width cell per loaded day. The bars use
        // the same offsets, so positions always line up. Non-empty here (the
        // `data.isEmpty` guard above).
        .chartXScale(domain: Array(data.indices))
        // `max(_, 1)` keeps the range non-degenerate even if the peak were 0.
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
            // A few evenly-spaced day labels (always including today), in full
            // "Jun 15" form so nothing truncates to "J…". No vertical gridlines.
            AxisMarks(values: labelIndices) { value in
                AxisValueLabel {
                    if let index = value.as(Int.self), data.indices.contains(index) {
                        Text(data[index].day, format: .dateTime.month(.abbreviated).day())
                    }
                }
            }
        }
        // Keep today's bar/label off the right edge in case the band scale's own
        // outer inset is tight.
        .padding(.trailing, 6)
    }

    /// The band indices to label on the X axis: ~4 across a 7-day window, ~5
    /// across 30, always anchored to include today (the last index) so the
    /// right-most label is present and whole. Striding back from today keeps the
    /// spacing even; every value is a valid index of `data`.
    private var labelIndices: [Int] {
        let count = data.count
        guard count > 1 else { return Array(data.indices) }
        let target = count <= 10 ? 4 : 5
        guard count > target else { return Array(data.indices) }
        let step = max(1, Int((Double(count - 1) / Double(target - 1)).rounded()))
        var picked: [Int] = []
        var index = count - 1
        while index >= 0 {
            picked.append(index)
            index -= step
        }
        return picked.reversed()
    }
}
