//
//  MetricTile.swift
//  Shlinkly
//

import SwiftUI

/// One metric on a ``Palette/sunken`` tile: its title, the all-time figure,
/// and a period line under it ("449 in 30 days"). With the "All" period the
/// line would only repeat the figure, so it is hidden — but its room is kept,
/// so every tile stays the same height.
struct MetricTile: View {
    let title: String
    /// The lifetime figure, from the link's visit summary.
    let allTime: Int
    let valueColor: Color
    /// The figure for the selected period.
    let period: Int
    /// What follows the period figure ("in 7 days"), or `nil` to hide the
    /// line (the "All" period).
    let periodSuffix: String?
    /// Redacts the period line while the period's visits load.
    let isLoadingPeriod: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)

            Text(allTime, format: .number)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("\(Text(period, format: .number).monospacedDigit()) \(periodSuffix ?? "")")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .redacted(reason: isLoadingPeriod ? .placeholder : [])
                // Reserve the line's height even when there is nothing to say.
                .opacity(periodSuffix == nil ? 0 : 1)
                .accessibilityHidden(periodSuffix == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
