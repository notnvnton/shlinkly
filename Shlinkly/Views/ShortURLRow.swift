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

/// The leading block of a short-URL row: the bold title (or the destination URL
/// when untitled) above the short code and a relative creation date. Shared by
/// the plain ``ShortURLRow`` and the macOS hover row so both read identically.
struct ShortURLRowPrimary: View {
    let shortURL: ShortURL

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(primaryText)
                .font(.body.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 5) {
                Text(shortURL.shortCode)
                Text("·")
                Text(shortURL.dateCreated, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    /// The bold first line: the resolved title, or the destination URL when
    /// the short URL has no title.
    private var primaryText: String {
        if let title = shortURL.title, !title.isEmpty {
            return title
        }
        return shortURL.longUrl
    }
}

/// The trailing visit-count badge (eye + total) of a short-URL row. Pulled out
/// so the macOS hover row can stack it with the Edit/Delete buttons and swap
/// between them in place.
struct VisitsCountLabel: View {
    let total: Int

    var body: some View {
        Label("\(total)", systemImage: "eye")
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .monospacedDigit()
            .accessibilityLabel("\(total) visits")
    }
}
