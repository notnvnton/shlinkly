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

            Spacer(minLength: 8)

            Label("\(shortURL.visitsSummary.total)", systemImage: "eye")
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
                .accessibilityLabel("\(shortURL.visitsSummary.total) visits")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
