//
//  InfoPopoverButton.swift
//  Shlinkly
//

import SwiftUI

/// A small `questionmark.circle` button that reveals a titled explanation in a
/// popover when tapped. On macOS it also carries the same text as a `.help`
/// tooltip, so the explanation surfaces on hover too.
///
/// Reusable wherever a field needs a "what does this do?" affordance; its first
/// use is beside the query-forwarding toggle in the short-URL form.
struct InfoPopoverButton: View {
    let title: String
    let message: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("More information: \(title)")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: 300, alignment: .leading)
            // Keep it a popover on iPhone rather than auto-adapting to a sheet.
            .presentationCompactAdaptation(.popover)
        }
        #if os(macOS)
        .help(message)
        #endif
    }
}
