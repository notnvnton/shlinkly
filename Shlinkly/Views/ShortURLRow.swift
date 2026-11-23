//
//  ShortURLRow.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// A `PhoneList` row: the 16 pt medium title (or the long URL when untitled),
/// the 13 pt meta line (short code · relative date), and the 15 pt visit count
/// trailing. At least 62 pt tall, 16 pt in, 12 pt between text and count.
struct PhoneLinkRow: View {
    let shortURL: ShortURL

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LinkRowText(shortURL: shortURL, titleSize: 16, metaSize: 13)
            Spacer(minLength: 0)
            VisitsCountLabel(total: shortURL.visitsSummary.total, size: 15, weight: .regular)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The text block of a link row: the title (or the destination URL when the
/// short URL has no title) on one line, above the short code and a relative
/// creation date in `--text2`, 2 pt (iPhone) / 3 pt (Mac) apart. Shared by the
/// iPhone and Mac rows so both read the same.
struct LinkRowText: View {
    let shortURL: ShortURL
    let titleSize: CGFloat
    let metaSize: CGFloat
    /// The selected Mac row's title is `--sel-text`.
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: titleSize > 14 ? 2 : 3) {
            Text(primaryText)
                .layoutFont(titleSize, .medium)
                .foregroundStyle(isSelected ? Palette.selText : Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)

            Text("\(shortURL.shortCode) · \(shortURL.dateCreated.formatted(.relative(presentation: .named)))")
                .layoutFont(metaSize)
                .foregroundStyle(Palette.text2)
                .lineLimit(1)
        }
    }

    private var primaryText: String {
        if let title = shortURL.title, !title.isEmpty {
            return title
        }
        return shortURL.longUrl
    }
}

/// A row's visit count: the number alone, tabular, in `--text2`.
struct VisitsCountLabel: View {
    let total: Int
    var size: CGFloat = 12
    var weight: Font.Weight = .medium

    var body: some View {
        Text(total, format: .number)
            .layoutFont(size, weight)
            .monospacedDigit()
            .foregroundStyle(Palette.text2)
            .accessibilityLabel("\(total) visits")
    }
}
