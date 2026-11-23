//
//  Segmented.swift
//  Shlinkly
//

import SwiftUI

#if os(macOS)
/// `.mseg` (Mac), neutral like Holds. Every segment has the same width (CSS
/// `grid-auto-columns: 1fr`): the widest label plus its padding, text centered.
///
/// - Regular: a `--seg-track` track 28 pt high (radius 8, 2 pt inside), 13 pt
///   medium labels with 14 pt on each side, the thumb radius 6.
/// - Small (`.mseg.sm`): 24 pt high (radius 7), 12 pt labels with 10 pt on
///   each side, the thumb radius 5.
///
/// The selected segment sits on a `--seg-thumb` thumb (`0 1 2` at 10%) and reads
/// semibold `--text`; the others `--seg-text`. Background and color change over
/// 160 ms. No brand fill.
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

    enum Size {
        case regular
        case small

        var height: CGFloat { self == .regular ? 28 : 24 }
        var trackRadius: CGFloat { self == .regular ? 8 : 7 }
        var thumbRadius: CGFloat { self == .regular ? 6 : 5 }
        var fontSize: CGFloat { self == .regular ? 13 : 12 }
        var padding: CGFloat { self == .regular ? 14 : 10 }
    }

    private let title: String
    @Binding private var selection: Value
    private let options: [Option]
    private let size: Size

    init(_ title: String, selection: Binding<Value>, options: [Option], size: Size = .regular) {
        self.title = title
        _selection = selection
        self.options = options
        self.size = size
    }

    var body: some View {
        EqualWidthRow {
            ForEach(options, id: \.value) { option in
                segment(option)
            }
        }
        .padding(2)
        .frame(height: size.height)
        .background(Palette.segTrack, in: RoundedRectangle(cornerRadius: size.trackRadius, style: .continuous))
        .fixedSize()
        .animation(.easeInOut(duration: 0.16), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .focusable(interactions: .activate)
        .onKeyPress(.leftArrow) { step(by: -1) }
        .onKeyPress(.rightArrow) { step(by: 1) }
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Text(option.label)
            .layoutFont(size.fontSize, isSelected ? .semibold : .medium)
            .foregroundStyle(isSelected ? Palette.text : Palette.segText)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, size.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: size.thumbRadius, style: .continuous)
                    .fill(Palette.segThumb)
                    .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
                    .opacity(isSelected ? 1 : 0)
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

/// Lays its subviews out side by side, each as wide as the widest one's ideal
/// width (CSS `grid-auto-columns: 1fr` in a shrink-wrapped grid), at the
/// proposed height.
private struct EqualWidthRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = widest(subviews)
        let height = proposal.height ?? subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: width * CGFloat(subviews.count), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = widest(subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * width, y: bounds.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }

    private func widest(_ subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }
}
#endif
