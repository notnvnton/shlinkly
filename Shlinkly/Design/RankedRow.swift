//
//  RankedRow.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// `.rank`: one row of the Countries and Sources cards. The flag (countries
/// only) and name, the count trailing in `--text2`, and under them a 4 pt
/// `--track` with a `--bar` fill at the entry's share of the top entry.
///
/// The dimmed "Unknown" country reads entirely in `--text2` with a `--bar-bots`
/// fill. 15 pt on the iPhone, 13 pt on the Mac.
struct RankedRow: View {
    let entry: ShortURLDetailStore.RankedEntry
    /// The top entry's count; the bar scales against it. At least 1.
    let maxCount: Int
    /// Countries show a flag; Sources don't.
    let showsFlag: Bool

    private var fraction: CGFloat {
        CGFloat(entry.count) / CGFloat(max(maxCount, 1))
    }

    private static var fontSize: CGFloat {
        #if os(macOS)
        13
        #else
        15
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(showsFlag ? "\(Self.flagEmoji(for: entry.code)) \(entry.label)" : entry.label)
                    .foregroundStyle(entry.isDimmed ? Palette.text2 : Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(entry.count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text2)
            }
            .layoutFont(Self.fontSize)
            bar
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.label): \(entry.count) visits")
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Palette.track)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(entry.isDimmed ? AnyShapeStyle(Palette.barBots) : AnyShapeStyle(Palette.bar))
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
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
