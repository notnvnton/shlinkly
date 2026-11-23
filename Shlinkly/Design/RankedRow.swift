//
//  RankedRow.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// One row of a ranked breakdown (Countries, Sources): an optional leading
/// flag, the name and the trailing count, with a 4 pt bar under the text
/// showing the entry's share of the top entry.
///
/// Rows flagged ``ShortURLDetailStore/RankedEntry/isDimmed`` (the "Unknown"
/// country bucket) recede: secondary text and a ``Palette/seriesBots`` fill.
struct RankedRow: View {
    let entry: ShortURLDetailStore.RankedEntry
    /// The top entry's count; the bar scales against it. At least 1.
    let maxCount: Int
    /// Countries show a flag; Sources don't.
    let showsFlag: Bool

    /// 48 pt on iOS, 38 pt on macOS. A minimum, so large text can grow it.
    private static var height: CGFloat {
        #if os(macOS)
        38
        #else
        48
        #endif
    }

    private var fraction: CGFloat {
        CGFloat(entry.count) / CGFloat(max(maxCount, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if showsFlag {
                    Text(Self.flagEmoji(for: entry.code))
                        .font(.body)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                Text(entry.label)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(entry.isDimmed ? Palette.textSecondary : Palette.textPrimary)
                Spacer(minLength: Space.tight)
                Text(entry.count, format: .number)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            bar
        }
        .frame(minHeight: Self.height)
        .padding(.horizontal, Space.cardInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.label): \(entry.count) visits")
    }

    /// The share bar: a ``Palette/sunken`` track with a proportional fill, both
    /// capsule-rounded. A small floor keeps a non-zero count visible.
    private var bar: some View {
        Capsule()
            .fill(Palette.sunken)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(entry.isDimmed ? Palette.seriesBots : Palette.seriesPeople)
                        .frame(width: max(geometry.size.width * fraction, entry.count > 0 ? 4 : 0))
                }
            }
            .accessibilityHidden(true)
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
