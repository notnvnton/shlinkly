//
//  RankedBarList.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// A titled, ranked breakdown rendered as horizontal bars — one row per entry,
/// with the label on the left, a proportional bar, and the count on the right.
///
/// Reused for both the country and the source breakdowns. Unlike the time
/// chart, the bars scale to the list's own peak rather than a fixed axis, so the
/// top row always fills the width and the rest read relative to it. Rows flagged
/// ``ShortURLDetailStore/RankedEntry/isDimmed`` (the "Unknown" country bucket)
/// are de-emphasised.
struct RankedBarList: View {
    let title: String
    /// The window the entries cover, shown under the title like the chart's.
    let dateRange: String
    let entries: [ShortURLDetailStore.RankedEntry]

    /// Peak count in the list; bars scale against it. The store ranks entries by
    /// count, so this is the first row — guarded to at least 1 so a list of all
    /// zeroes can't divide by zero.
    private var maxCount: Int {
        max(entries.map(\.count).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(dateRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entries.isEmpty {
                Text("No data for this period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach(entries) { entry in
                        RankedBarRow(entry: entry, maxCount: maxCount)
                    }
                }
            }
        }
    }
}

/// One bar in a ``RankedBarList``: a full-width track with a proportional fill,
/// the label overlaid at the leading edge and the count trailing.
private struct RankedBarRow: View {
    let entry: ShortURLDetailStore.RankedEntry
    let maxCount: Int

    private var fraction: Double {
        Double(entry.count) / Double(maxCount)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Track behind every bar so short rows still read as a full slot.
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))

            // Proportional fill. A small floor keeps a non-zero count visible
            // even when it's a tiny fraction of the peak.
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 6)
                    .fill(fillColor)
                    .frame(width: max(geo.size.width * fraction, entry.count > 0 ? 6 : 0))
            }

            HStack(spacing: 8) {
                Text(entry.label)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(entry.isDimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                Spacer(minLength: 8)
                Text(entry.count, format: .number)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 30)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.label): \(entry.count) visits")
    }

    /// Muted accent for normal rows; a neutral grey for dimmed ("Unknown") ones
    /// so they recede without disappearing.
    private var fillColor: Color {
        entry.isDimmed ? Color.primary.opacity(0.10) : Color.accentColor.opacity(0.28)
    }
}
