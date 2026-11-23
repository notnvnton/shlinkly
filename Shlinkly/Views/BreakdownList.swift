//
//  BreakdownList.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The rows of a ranked breakdown card (Countries or Sources): one `.rank`
/// ``RankedRow`` per entry with a 1 pt `--sep` line between them, or a quiet
/// "No data" line when the period has none.
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
            // Not drawn; kept, in the layout's text style.
            Text("No data for this period")
                .layoutFont(Self.fontSize)
                .foregroundStyle(Palette.text2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        } else {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    RankedRow(entry: entry, maxCount: maxCount, showsFlag: showsFlags)
                        .padding(.horizontal, 16)
                        .padding(.top, Self.verticalInset)
                        .padding(.bottom, entry.id == entries.last?.id ? Self.lastBottomInset : Self.verticalInset)
                        .overlay(alignment: .bottom) {
                            if entry.id != entries.last?.id {
                                RowSeparator()
                            }
                        }
                }
            }
        }
    }

    /// `.rank`: 10 pt / 16 pt in on the iPhone; 8 pt / 16 pt on the Mac, with
    /// 12 pt under the last row.
    private static var verticalInset: CGFloat {
        #if os(macOS)
        8
        #else
        10
        #endif
    }

    private static var lastBottomInset: CGFloat {
        #if os(macOS)
        12
        #else
        10
        #endif
    }

    private static var fontSize: CGFloat {
        #if os(macOS)
        13
        #else
        15
        #endif
    }
}
