//
//  SecretField.swift
//  Shlinkly
//

import SwiftUI

/// A masked text field with a show/hide toggle, for the API key. Masked by
/// default (dots via `SecureField`); the trailing eye reveals the value as a
/// plain `TextField`. Autocapitalisation and autocorrection are off so keys
/// aren't mangled.
///
/// Takes the host form's focus binding so the key field participates in the
/// shared `@FocusState` — that lets the iOS keyboard's "Done" button dismiss the
/// keyboard while the key is being edited, same as the other fields. Harmless on
/// macOS (focus exists there too; the keyboard toolbar is iOS-only).
struct SecretField<FocusValue: Hashable>: View {
    let placeholder: String
    @Binding var text: String
    /// The host's focus state, projected in (e.g. `$focusedField`).
    let focus: FocusState<FocusValue?>.Binding
    /// The focus case identifying this field within the host form.
    let focusValue: FocusValue
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
            .focused(focus, equals: focusValue)
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
