//
//  SecretField.swift
//  Shlinkly
//

import SwiftUI

/// A masked text field with a show/hide toggle, for the API key. Masked by
/// default (dots via `SecureField`); the trailing eye reveals the value as a
/// plain `TextField`. Autocapitalisation and autocorrection are off so keys
/// aren't mangled.
struct SecretField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isRevealed ? "Hide API key" : "Show API key")
        }
    }
}
