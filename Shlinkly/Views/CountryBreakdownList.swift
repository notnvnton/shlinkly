//
//  CountryBreakdownList.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The country breakdown: one row per country as an emoji flag, the country
/// name, and the visit count trailing. Unlike the source breakdown there are no
/// bars — a short list of flagged rows reads cleaner. Rows flagged
/// ``ShortURLDetailStore/RankedEntry/isDimmed`` (the "Unknown" bucket) recede.
struct CountryBreakdownList: View {
    let title: String
    /// The window the entries cover, shown under the title like the chart's.
    let dateRange: String
    let entries: [ShortURLDetailStore.RankedEntry]

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
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        CountryRow(entry: entry)
                    }
                }
            }
        }
    }
}

/// One country: flag, name, trailing count. The "Unknown" / unknown-code case
/// renders a neutral white flag and dims the text.
private struct CountryRow: View {
    let entry: ShortURLDetailStore.RankedEntry

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.flagEmoji(for: entry.code))
                .font(.title3)
                .accessibilityHidden(true)
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
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.label): \(entry.count) visits")
    }

    /// Builds an emoji flag from an ISO 3166-1 alpha-2 code by mapping each
    /// letter to its regional indicator symbol (U+1F1E6 is 🇦, offset by the
    /// letter's distance from 'A'). Any empty / non-two-letter / non-A–Z code —
    /// including the code-less "Unknown" bucket — falls back to a neutral white
    /// flag.
    static func flagEmoji(for code: String?) -> String {
        let neutral = "🏳️"
        guard let code, code.count == 2 else { return neutral }
        var scalars = String.UnicodeScalarView()
        for letter in code.uppercased().unicodeScalars {
            guard ("A"..."Z").contains(letter),
                  let indicator = Unicode.Scalar(0x1F1E6 + (letter.value - 65))
            else { return neutral }
            scalars.append(indicator)
        }
        return String(scalars)
    }
}
