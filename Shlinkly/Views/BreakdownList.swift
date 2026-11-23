//
//  BreakdownList.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The rows of a ranked breakdown card (Countries or Sources): one
/// ``RankedRow`` per entry, or a quiet "No data" line when the period has
/// none. The enclosing ``Card`` carries the title and the date range.
///
/// Bars scale to the list's own peak rather than a fixed axis, so the top row
/// always fills the width and the rest read relative to it.
struct BreakdownList: View {
    let entries: [ShortURLDetailStore.RankedEntry]
    /// Countries lead each row with a flag; Sources don't.
    let showsFlags: Bool

    /// Peak count in the list. The store ranks entries by count, so this is
    /// the first row — guarded to at least 1 so all zeroes can't divide by zero.
    private var maxCount: Int {
        max(entries.map(\.count).max() ?? 0, 1)
    }

    var body: some View {
        if entries.isEmpty {
            Text("No data for this period")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, Space.cardInset)
                .padding(.top, Space.tight)
                .padding(.bottom, Space.cardInset)
        } else {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    RankedRow(entry: entry, maxCount: maxCount, showsFlag: showsFlags)
                }
            }
            .padding(.bottom, Space.tight)
        }
    }
}
