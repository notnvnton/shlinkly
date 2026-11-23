//
//  SegmentedPicker.swift
//  Shlinkly
//

import SwiftUI

/// The app's segmented control, identical on iOS and macOS: a ``Palette/track``
/// with a ``Palette/surface`` thumb that slides to the selected segment. Labels
/// are always ``Palette/textPrimary`` (the selected one semibold) — never
/// accent-filled, never system blue.
///
/// Reads as a picker to assistive technologies (each segment is a button with
/// the selected trait). On macOS it joins the keyboard loop when keyboard
/// navigation is on, and ←/→ move the selection; on iOS a selection tick plays.
struct SegmentedPicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: String
    }

    private let title: String
    @Binding private var selection: Value
    private let options: [Option]
    /// `true` to stretch the segments across the available width (the period
    /// control); `false` to hug the labels (the chart's step control).
    private let fillsWidth: Bool

    @Namespace private var thumbSpace

    init(_ title: String, selection: Binding<Value>, options: [Option], fillsWidth: Bool = true) {
        self.title = title
        _selection = selection
        self.options = options
        self.fillsWidth = fillsWidth
    }

    /// 32 pt on iOS, 26 pt on macOS.
    private static var height: CGFloat {
        #if os(macOS)
        26
        #else
        32
        #endif
    }

    private static var padding: CGFloat { 2 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                segment(option)
            }
        }
        .padding(Self.padding)
        .frame(height: Self.height)
        .background(Palette.track, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        #if os(macOS)
        // `.activate`: reachable with keyboard navigation, like a button, but a
        // click doesn't leave a focus ring behind.
        .focusable(interactions: .activate)
        .onKeyPress(.leftArrow) { step(by: -1) }
        .onKeyPress(.rightArrow) { step(by: 1) }
        #else
        .sensoryFeedback(.selection, trigger: selection)
        #endif
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Text(option.label)
            .font(.footnote.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(maxWidth: fillsWidth ? .infinity : nil, maxHeight: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.control - Self.padding, style: .continuous)
                        .fill(Palette.surface)
                        .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
                        .matchedGeometryEffect(id: "thumb", in: thumbSpace)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { select(option.value) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(option.label)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select(option.value) }
    }

    private func select(_ value: Value) {
        guard value != selection else { return }
        withAnimation(.spring(duration: 0.25, bounce: 0.15)) { selection = value }
    }

    #if os(macOS)
    private func step(by offset: Int) -> KeyPress.Result {
        guard let index = options.firstIndex(where: { $0.value == selection }) else { return .ignored }
        let target = index + offset
        guard options.indices.contains(target) else { return .handled }
        select(options[target].value)
        return .handled
    }
    #endif
}

#if DEBUG
private struct SegmentedPickerPreview: View {
    @State private var period = "30 days"
    @State private var step = "Week"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SegmentedPicker("Period", selection: $period, options: ["7 days", "30 days", "All"].map {
                .init(value: $0, label: $0)
            })
            SegmentedPicker("Group by", selection: $step, options: ["Day", "Week", "Month", "Year"].map {
                .init(value: $0, label: $0)
            }, fillsWidth: false)
        }
        .padding(24)
        .frame(width: 360)
    }
}

#Preview("Segmented picker, light") {
    SegmentedPickerPreview()
        .canvasBackground()
        .preferredColorScheme(.light)
}

#Preview("Segmented picker, dark") {
    SegmentedPickerPreview()
        .canvasBackground()
        .preferredColorScheme(.dark)
}
#endif
