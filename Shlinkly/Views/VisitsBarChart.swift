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

    var body: some View {
        Chart(data) { point in
            BarMark(
                x: .value("Day", point.day, unit: .day),
                y: .value("Visits", point.count)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
        }
        .accessibilityLabel("Visits by day")
    }
}
