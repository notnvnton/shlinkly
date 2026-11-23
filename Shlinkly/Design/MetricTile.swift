//
//  MetricTile.swift
//  Shlinkly
//

import SwiftUI

/// `.metric`: a metric tile, title and value only. Radius 10, 10 pt / 12 pt in.
/// Total and Bots on `--npastel` with `--npastel-text`, People on `--pastel`
/// with `--pastel-text`. The key is 12 pt medium; the value 22 pt semibold with
/// tabular digits (18 pt in the Mac's horizontal rows).
struct MetricTile: View {
    enum Kind {
        case total
        case people
        case bots
    }

    let title: String
    let value: Int
    let kind: Kind
    /// The Mac's Visits card lays each metric out as one row: key left, value
    /// right.
    var horizontal = false

    var body: some View {
        Group {
            if horizontal {
                HStack(alignment: .center, spacing: 8) {
                    key
                    Spacer(minLength: 8)
                    figure(size: 18)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    key
                    figure(size: 22)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(kind == .people ? Palette.pastelText : Palette.npastelText)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            if kind == .people {
                shape.fill(Palette.pastel)
            } else {
                shape.fill(Palette.npastel)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var key: some View {
        Text(title)
            .layoutFont(12, .medium)
            .lineLimit(1)
    }

    private func figure(size: CGFloat) -> some View {
        Text(value, format: .number)
            .layoutFont(size, .semibold)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}
