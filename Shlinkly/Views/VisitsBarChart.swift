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
    /// The full period window for the X axis. Pinning it here locks the axis to
    /// the whole period (in dates), so a link whose visits land on a single day
    /// still shows the full daily window — never an hour axis with one wide bar.
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
        .chartXScale(domain: xDomain)
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
            // Just the dates along the bottom: no vertical gridlines or ticks, so
            // the chart no longer reads like a spreadsheet grid.
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel()
            }
        }
        // Purely a display chart — no selection or tap. Opt out of hit testing
        // so it can never capture the enclosing ScrollView's pan gesture.
        .allowsHitTesting(false)
        .accessibilityLabel("Visits by day")
    }
}
