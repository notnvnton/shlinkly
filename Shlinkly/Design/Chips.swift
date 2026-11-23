//
//  Chips.swift
//  Shlinkly
//

import SwiftUI

/// `.tag`: a pastel tag. `--pastel` fill, `--pastel-text`, medium weight,
/// capsule. Three sizes appear in the artboards: 24 pt / 12 pt (headers), 20 pt /
/// 11 pt (Mac list rows, Settings), 28 pt / 13 pt (the iPhone link form).
///
/// Pass `action` to make it tappable (it filters by the tag), or `onRemove` for
/// the form's "name ×" chip.
struct TagView: View {
    enum Size {
        case regular
        case small
        case large

        var height: CGFloat {
            switch self {
            case .regular: return 24
            case .small: return 20
            case .large: return 28
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .regular: return 12
            case .small: return 11
            case .large: return 13
            }
        }
    }

    let text: String
    var size: Size = .regular
    var action: (() -> Void)?
    var onRemove: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the links with this tag")
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            Text(text)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Text("×")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove tag \(text)")
            }
        }
        .layoutFont(size.fontSize, .medium)
        .foregroundStyle(Palette.pastelText)
        .padding(.horizontal, 9)
        .frame(height: size.height)
        .background(Palette.pastel, in: Capsule())
        .contentShape(Capsule())
        .fixedSize()
    }
}

/// `.chip` / `.chip.on`: a filter chip. 32 pt, capsule, 14 pt medium. Off:
/// `--card` with a 1 pt `--card-border` ring. On: `--chip-on-bg`,
/// `--chip-on-text`.
struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .layoutFont(14, .medium)
                .foregroundStyle(isOn ? Palette.chipOnText : Palette.text)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background {
                    if isOn {
                        Capsule().fill(Palette.chipOnFill)
                    } else {
                        Capsule()
                            .fill(Palette.card)
                            .overlay { Capsule().strokeBorder(Palette.cardBorder, lineWidth: 1) }
                    }
                }
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// `.dot`: the 7 pt `--ok` status dot.
struct StatusDot: View {
    var body: some View {
        Circle()
            .fill(Palette.ok)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

/// `.pill`: the server pill's face. 30 pt, capsule, `--pastel`, 14 pt medium
/// `--pastel-text`, a status dot, the server, and "⌄".
struct ServerPillLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            StatusDot()
            Text("\(title) ⌄")
                .lineLimit(1)
        }
        .layoutFont(14, .medium)
        .foregroundStyle(Palette.pastelText)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Palette.pastel, in: Capsule())
        .fixedSize()
    }
}
