//
//  TagChip.swift
//  Shlinkly
//

import SwiftUI

/// A single compact tag chip: small, tight, muted. The shared style for tags
/// across the app — used on the detail screen now, and slated for the list
/// rows when tappable tag filtering lands (layer 2b.2).
struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.14), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
