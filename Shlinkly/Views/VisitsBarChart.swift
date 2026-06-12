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
                x: .value("Day", point.day, unit: .day),
                y: .value("Visits", point.count)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
        }
        // Purely a display chart — no selection or tap. Opt out of hit testing
        // so it can never capture the enclosing ScrollView's pan gesture.
        .allowsHitTesting(false)
        .accessibilityLabel("Visits by day")
    }
}
