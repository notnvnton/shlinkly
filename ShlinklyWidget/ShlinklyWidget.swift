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
                // render at all on-device. `.fill.tertiary` is the neutral,
                // theme-adaptive system fill; the brand accent stays on the
                // glyphs and button underlays only.
                .containerBackground(.fill.tertiary, for: .widget)
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

private extension ShapeStyle where Self == Color {
    /// The brand purple. Local to the widget: its process shares no asset
    /// catalogue with the app, and a launcher isn't worth an asset dependency.
    static var brand: Color { Color(red: 0.42, green: 0.29, blue: 0.78) }
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

private struct SmallTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .semibold))
            Spacer(minLength: 0)
            Text("New link")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(Color.brand)
    }
}

private struct MediumTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Shlinkly", systemImage: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Link(destination: WidgetDestination.create) {
                    ActionTile(systemImage: "plus", title: "New link")
                }
                Link(destination: WidgetDestination.createFromClipboard) {
                    ActionTile(systemImage: "doc.on.clipboard", title: "From clipboard")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// One of the medium widget's two buttons. `contentShape` so the whole tile is
/// tappable, not just the glyph and text.
private struct ActionTile: View {
    let systemImage: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.brand)
        .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@main
struct ShlinklyWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShlinklyWidget()
    }
}
