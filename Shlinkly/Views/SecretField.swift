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
                    TextField("API key", text: $text, prompt: Text(placeholder))
                } else {
                    SecureField("API key", text: $text, prompt: Text(placeholder))
                }
            }
            // Hide the label so macOS Form doesn't add a left label column; the
            // prompt is the in-field placeholder.
            .labelsHidden()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            // Best-effort: marking the field as a one-time code stops iOS from
            // offering to save the API key into Passwords ("Save Password?").
            .textContentType(.oneTimeCode)
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
