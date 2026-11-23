//
//  ShortURLRow.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// A single row in the short-URL list: title (or the long URL when untitled),
/// then the short code and a relative creation date, with a visit count on the
/// trailing edge.
struct ShortURLRow: View {
    let shortURL: ShortURL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ShortURLRowPrimary(shortURL: shortURL)
            Spacer(minLength: 8)
            VisitsCountLabel(total: shortURL.visitsSummary.total)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// The leading block of a short-URL row: the title (or the destination URL
/// when untitled) above the short code and a relative creation date. Shared by
/// the plain ``ShortURLRow`` and the macOS list row so both read identically.
struct ShortURLRowPrimary: View {
    let shortURL: ShortURL
    /// The selected macOS row tints its title ``Palette/accentText``.
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(primaryText)
                .font(.body.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(isSelected ? Palette.accentText : Palette.textPrimary)

            HStack(spacing: 5) {
                Text(shortURL.shortCode)
                Text("·")
                Text(shortURL.dateCreated, format: .relative(presentation: .named))
            }
            .font(.footnote)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
        }
    }

    /// The first line: the resolved title, or the destination URL when the
    /// short URL has no title.
    private var primaryText: String {
        if let title = shortURL.title, !title.isEmpty {
            return title
        }
        return shortURL.longUrl
    }
}

/// The trailing visit count of a short-URL row: the number alone, monospaced.
/// Pulled out so the macOS row can swap it with its hover actions in place.
struct VisitsCountLabel: View {
    let total: Int

    var body: some View {
        Text(total, format: .number)
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Palette.textSecondary)
            .accessibilityLabel("\(total) visits")
    }
}
