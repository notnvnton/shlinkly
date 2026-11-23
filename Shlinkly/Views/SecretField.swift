//
//  SecretField.swift
//  Shlinkly
//

import SwiftUI

/// A masked text field with a "Show" / "Hide" text button, for the API key
/// (layout v3: `MacServerSheet`, `PhoneServerForm`). Masked by default (dots via
/// `SecureField`); "Show" reveals the value as a plain `TextField`.
/// Autocapitalisation and autocorrection are off so keys aren't mangled.
///
/// Takes the host form's focus binding so the key field participates in the
/// shared `@FocusState` — that lets the iOS keyboard's "Done" button dismiss the
/// keyboard while the key is being edited, same as the other fields.
struct SecretField<FocusValue: Hashable>: View {
    let placeholder: String
    @Binding var text: String
    /// The host's focus state, projected in (e.g. `$focusedField`).
    let focus: FocusState<FocusValue?>.Binding
    /// The focus case identifying this field within the host form.
    let focusValue: FocusValue
    /// The Mac's label-left rows align the value to the trailing edge.
    var alignment: TextAlignment = .leading
    /// "Show" in `--brand-text`: 12 pt on the Mac, 14 pt on the iPhone.
    var toggleSize: CGFloat = 14
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField("API key", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.text2))
                } else {
                    SecureField("API key", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.text2))
                }
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(alignment)
            .foregroundStyle(Palette.text)
            .focused(focus, equals: focusValue)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            // Best-effort: marking the field as a one-time code stops iOS from
            // offering to save the API key into Passwords ("Save Password?").
            .textContentType(.oneTimeCode)
            #endif

            Button(isRevealed ? "Hide" : "Show") {
                isRevealed.toggle()
            }
            .buttonStyle(.plain)
            .layoutFont(toggleSize)
            .foregroundStyle(Palette.brand)
            .accessibilityLabel(isRevealed ? "Hide API key" : "Show API key")
        }
    }
}
