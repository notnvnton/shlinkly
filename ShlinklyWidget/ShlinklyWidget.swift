//
//  ShlinklyWidget.swift
//  ShlinklyWidget
//

import SwiftUI
import WidgetKit

/// A pure launcher widget: every control opens the main app on a `shlinkly://`
/// deep link and nothing else. It holds no data, reads no pasteboard and makes
/// no network calls, so its timeline is a single entry that never refreshes —
/// there is nothing that could go stale.
struct ShlinklyWidget: Widget {
    private let kind = "ShlinklyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in
            LauncherView()
                // iOS 17+ requires the widget's background to be declared via
                // `containerBackground` so the system knows what to strip in
                // StandBy / Lock Screen contexts. Without it the content doesn't
                // render at all on-device. `Widgets.html`: `#FFFFFF` / `#1F1E25`.
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Quick Create")
        .description("Create a new short link, or one from your clipboard.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The one and only entry. `.never` because the view is entirely static — no
/// reload budget is spent on a widget that just holds two links.
struct LauncherEntry: TimelineEntry {
    let date: Date
}

struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        LauncherEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: .now)], policy: .never))
    }
}

/// Deep links this widget can open. Kept as static, known-good literals so the
/// non-optional `URL` initialiser is safe here — no user input reaches them.
private enum WidgetDestination {
    static let create = URL(string: "shlinkly://create")!
    static let createFromClipboard = URL(string: "shlinkly://create?source=clipboard")!
}

struct LauncherView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            // One tap target for the whole tile — `widgetURL` is the family's
            // native affordance, and there is only one destination to offer.
            SmallTile()
                .widgetURL(WidgetDestination.create)
        default:
            // Medium needs two independent destinations, which `widgetURL`
            // (single-URL only) can't express — hence `Link` per button.
            MediumTile()
        }
    }
}

/// `Widgets.html`, small: the mark at the top, "New link" (16 pt semibold) at
/// the bottom. The artboard's "or from clipboard" line is left out: tapping the
/// small widget opens a blank form, so the line would promise something it
/// doesn't do.
private struct SmallTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetBrandMark()
            Spacer(minLength: 0)
            Text("New link")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WidgetTheme.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// `Widgets.html`, medium: "Shlinkly" (13 pt semibold, `--brand-text`) over two
/// tiles, 10 pt apart: "New link" on `--brand-fill` and "From clipboard" on
/// `--pastel`, each with its 15 pt semibold label at the bottom-left. The
/// artboard's "· host" isn't shown: the widget holds no data, so it can't know
/// the active server.
private struct MediumTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shlinkly")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTheme.brand)
            HStack(spacing: 10) {
                Link(destination: WidgetDestination.create) {
                    LaunchTile(title: "New link", fill: AnyShapeStyle(WidgetTheme.brandFill),
                               textColor: WidgetTheme.onBrand)
                }
                Link(destination: WidgetDestination.createFromClipboard) {
                    LaunchTile(title: "From clipboard", fill: AnyShapeStyle(WidgetTheme.pastel),
                               textColor: WidgetTheme.pastelText)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One of the medium widget's two tiles: radius 14, 12 pt in, the label at the
/// bottom-left. `contentShape` so the whole tile is tappable.
private struct LaunchTile: View {
    let title: String
    let fill: AnyShapeStyle
    let textColor: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background(fill, in: shape)
            .contentShape(shape)
    }
}

#Preview("Widgets small", as: .systemSmall) {
    ShlinklyWidget()
} timeline: {
    LauncherEntry(date: .now)
}

#Preview("Widgets medium", as: .systemMedium) {
    ShlinklyWidget()
} timeline: {
    LauncherEntry(date: .now)
}

@main
struct ShlinklyWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShlinklyWidget()
    }
}
