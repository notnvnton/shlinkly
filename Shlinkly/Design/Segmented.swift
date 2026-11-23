//
//  Segmented.swift
//  Shlinkly
//

import SwiftUI

#if os(macOS)
/// `.mseg` (Mac), neutral like Holds: a `--seg-track` track (radius 8, 2 pt
/// inside, 28 pt tall) with a `--seg-thumb` thumb (radius 6, `0 1 2` at 10%)
/// under the selected segment. Labels 13 pt medium `--seg-text`; the selected
/// one semibold `--text`. No brand fill.
///
/// A SwiftUI control because the native `NSSegmentedControl` can't take this
/// height or these colors. It reads as a picker to assistive technologies, and
/// joins the keyboard loop when keyboard navigation is on (←/→ move the
/// selection).
struct MacSegmented<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: String
    }

    private let title: String
    @Binding private var selection: Value
    private let options: [Option]

    init(_ title: String, selection: Binding<Value>, options: [Option]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                segment(option)
            }
        }
        .padding(2)
        .frame(height: 28)
        .background(Palette.segTrack, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .focusable(interactions: .activate)
        .onKeyPress(.leftArrow) { step(by: -1) }
        .onKeyPress(.rightArrow) { step(by: 1) }
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Text(option.label)
            .layoutFont(13, isSelected ? .semibold : .medium)
            .foregroundStyle(isSelected ? Palette.text : Palette.segText)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.segThumb)
                        .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selection = option.value }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(option.label)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { selection = option.value }
    }

    private func step(by offset: Int) -> KeyPress.Result {
        guard let index = options.firstIndex(where: { $0.value == selection }) else { return .ignored }
        let target = index + offset
        guard options.indices.contains(target) else { return .handled }
        selection = options[target].value
        return .handled
    }
}
#endif
