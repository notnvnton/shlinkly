//
//  Surfaces.swift
//  Shlinkly
//

import SwiftUI

// Cards, rows, labels and footnotes of layout v3 (`theme.css`).

/// `.card` (iPhone): `--card`, radius 14, a 1 pt `--card-border` ring.
struct LayoutCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: shape)
            .overlay(shape.strokeBorder(Palette.cardBorder, lineWidth: 1))
            .clipShape(shape)
    }
}

/// `.mcard` (Mac): `--mcard`, radius 12, a 0.5 pt `--mcard-border` ring. The
/// `solid` variant is the one the Mac sheets draw (`--card` with a 1 pt
/// `--card-border` ring).
struct MacCard<Content: View>: View {
    private let solid: Bool
    private let content: Content

    init(solid: Bool = false, @ViewBuilder content: () -> Content) {
        self.solid = solid
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(solid ? Palette.card : Palette.mcard, in: shape)
            .overlay(shape.strokeBorder(solid ? Palette.cardBorder : Palette.mcardBorder,
                                        lineWidth: solid ? 1 : 0.5))
            .clipShape(shape)
    }
}

/// The 1 pt `--sep` line between a card's rows (full width, as drawn).
struct RowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Palette.sep)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// `.label` (iPhone): 13 pt medium `--text2`, 4 pt in, 8 pt above the card.
struct SectionLabel: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .layoutFont(13, .medium)
            .foregroundStyle(Palette.text2)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// `.mlabel` (Mac): 11 pt medium `--text2`. Callers give the padding the
/// artboard shows for that spot.
struct MacLabel: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .layoutFont(11, .medium)
            .foregroundStyle(Palette.text2)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// `.foot`: a footnote under a card. 12 pt on the iPhone, 11 pt on the Mac
/// (as the Mac artboards override it), `--text2` unless a status color is
/// given.
struct Footnote: View {
    private let text: Text
    private let color: Color

    init(_ text: String, color: Color = Palette.text2) {
        self.text = Text(text)
        self.color = color
    }

    init(_ text: Text, color: Color = Palette.text2) {
        self.text = text
        self.color = color
    }

    var body: some View {
        text
            #if os(macOS)
            .layoutFont(11)
            .padding(.top, 6)
            #else
            .layoutFont(12)
            .padding(.top, 8)
            #endif
            .lineSpacing(2)
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum LayoutMetrics {
    /// The width of the centered content column: the detail on iOS, and on
    /// iPad also the list and the list's and detail's bottom bars.
    static let contentColumnWidth: CGFloat = 680
}

extension View {
    /// `.row` / `.field` (iPhone): at least 48 pt, 16 pt in, 16 pt text.
    func layoutRow(minHeight: CGFloat = 48) -> some View {
        layoutFont(16)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
    }

    /// The centered content column (`max-width: 680px; margin: 0 auto` on
    /// the iPad artboards): at most ``LayoutMetrics/contentColumnWidth``
    /// wide, horizontal padding included, centered in the full width. When
    /// `enabled` is false the view is returned as it is.
    @ViewBuilder
    func contentColumn(_ enabled: Bool = true) -> some View {
        if enabled {
            frame(maxWidth: LayoutMetrics.contentColumnWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        } else {
            self
        }
    }

    /// `.mfield` (Mac): 30 pt by default, 14 pt in, 13 pt text.
    func macField(height: CGFloat = 30) -> some View {
        layoutFont(13)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
    }
}

/// A `.mfield` / `.field` label column: 96 pt wide.
struct FieldLabel: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(Palette.text)
            .lineLimit(1)
            .frame(width: 96, alignment: .leading)
    }
}

#if os(macOS)
extension View {
    /// A `.mfield` value's placeholder, drawn where the typed text goes: at
    /// the trailing edge, 13 pt, `--text2` (`.mfield input { text-align:
    /// right }`), while `isEmpty`. Apply it to the field itself, with an empty
    /// `prompt`, so it ends inside the field (before a "Show" button). The
    /// Short code's slug field passes `.leading`: its text starts right after
    /// the host's "/".
    ///
    /// Not the field's `prompt`: a styled prompt reaches AppKit as an
    /// attributed placeholder with no paragraph style, which AppKit draws at
    /// the leading edge whatever the field's alignment. A plain prompt follows
    /// the alignment but takes the system placeholder color, not `--text2`.
    /// Flush with the field's trailing edge, which is where AppKit ends
    /// right-aligned typed text, while editing and at rest.
    func macPlaceholder(_ text: String, isEmpty: Bool, alignment: Alignment = .trailing) -> some View {
        overlay(alignment: alignment) {
            if isEmpty {
                Text(text)
                    .layoutFont(13)
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Sizes itself, and every subview, to its first subview: the Short code's
/// slug field is as wide as an invisible text of its value (or of the
/// placeholder), like CSS `field-sizing: content`. The proposal is passed on,
/// so the text, and with it the field, can shrink when the row runs out of
/// space; the field then scrolls its text.
struct SizedByFirst: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

/// `.sheet` with `.sheetbar` (Mac): a 15 pt semibold title, the content
/// (fields in cards, 14 pt apart), and a bottom bar under a 1 pt `--sep`
/// hairline. The content scrolls when it's taller than the sheet.
struct MacSheet<Content: View, Bar: View>: View {
    private let title: String
    private let content: Content
    private let bar: Bar

    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder bar: () -> Bar) {
        self.title = title
        self.content = content()
        self.bar = bar()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .layoutFont(15, .semibold)
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 8) {
                bar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { RowSeparator() }
        }
        .background(Palette.sheetBg)
    }
}
#endif

#if os(iOS)
/// The iPhone sheets' own header (`.navbar` as `PhoneQR`, `PhoneLinkForm`,
/// `PhoneServerForm` and `PhoneSettings` draw it): 52 pt in all, of which the
/// top 14 pt is padding (`box-sizing: border-box`), so the row's center is
/// 33 pt below the sheet's top edge. The 22 pt semibold title at the 20 pt
/// leading inset, one text action ("Done" / "Cancel", no padding of its own)
/// with its text edge on the 20 pt trailing inset.
///
/// `inSheet: false` is the same form pushed onto a navigation stack (the
/// server form from onboarding, not drawn): a 44 pt row under the system bar.
struct SheetHeader<Trailing: View>: View {
    private let title: String
    private let inSheet: Bool
    private let trailing: Trailing

    init(_ title: String, inSheet: Bool = true, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.inSheet = inSheet
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .layoutFont(22, .semibold, tracking: -0.2)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .frame(height: inSheet ? 38 : 44)
        .padding(.top, inSheet ? 14 : 0)
        .padding(.horizontal, 20)
    }
}

#if DEBUG
extension View {
    /// Shows a sheet's content the way the app presents it (over a blank
    /// screen, in a system sheet), so its header sits against the sheet's top
    /// edge as the artboards draw it.
    func previewAsSheet() -> some View {
        Color.gray.opacity(0.4)
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) { self }
    }
}
#endif

/// The device is an iPad (also an iPad app in Split View or Slide Over).
/// Not the size class: an iPhone Plus / Pro Max in landscape is regular too.
enum DeviceIdiom {
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
}

/// `.bottombar` (iPhone): the screen's main actions, 12 pt apart, 20 pt in,
/// 12 pt above. The artboard's 34 pt below is the home-indicator area, which
/// the bottom safe area already provides. Sits on the screen background.
///
/// iPad: at least the side inset below the buttons (`.bottombar` padding
/// `12px 20px 20px` on the iPad artboards). A centered sheet has no bottom
/// safe area, so the inset itself is added there; full screen, the home
/// indicator's safe area covers it. `column: true` keeps the buttons in the
/// content column (the list and the detail); the background stays full
/// width. On iPhone neither applies, so the bar is laid out as before.
struct BottomBar<Content: View>: View {
    /// The side inset, and on iPad the least room below the buttons.
    private static var inset: CGFloat { 20 }

    private let vertical: Bool
    private let spacing: CGFloat
    private let column: Bool
    private let content: Content
    /// iPad only. `nil` until measured, which counts as "the safe area covers
    /// the inset" (no extra padding), so a full-screen bar never moves.
    @State private var bottomSafeArea: CGFloat?

    init(vertical: Bool = false, spacing: CGFloat = 12, column: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.vertical = vertical
        self.spacing = spacing
        self.column = column
        self.content = content()
    }

    var body: some View {
        let isPad = DeviceIdiom.isPad
        Group {
            if vertical {
                VStack(spacing: spacing) { content }
            } else {
                HStack(spacing: spacing) { content }
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 12)
        .padding(.bottom, isPad ? padBottomPadding : 0)
        .contentColumn(column && isPad)
        .background { Palette.bgSolid.ignoresSafeArea() }
        .modifier(BottomSafeAreaReader(isActive: isPad, value: $bottomSafeArea))
    }

    private var padBottomPadding: CGFloat {
        guard let bottomSafeArea else { return 0 }
        return max(0, Self.inset - bottomSafeArea)
    }
}

/// Reports the bottom safe area of the view it is applied to, only while
/// `isActive`; otherwise it adds nothing.
private struct BottomSafeAreaReader: ViewModifier {
    let isActive: Bool
    @Binding var value: CGFloat?

    func body(content: Content) -> some View {
        if isActive {
            content.onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.bottom
            } action: { newValue in
                value = newValue
            }
        } else {
            content
        }
    }
}
#endif
