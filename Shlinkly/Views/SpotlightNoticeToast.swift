//
//  SpotlightNoticeToast.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The pill shown after a Spotlight result is tapped: either "Switched to
/// <server>" when opening the link meant changing the active server, or why the
/// link couldn't be opened. Same look as ``CopiedToast``; sits at the top so the
/// two never overlap.
struct SpotlightNoticeToast: View {
    let kind: AppModel.SpotlightNotice.Kind

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(message)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .toastPill()
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        switch kind {
        case .switchedServer(let name): "Switched to \(name)"
        case .linkGone: "Link no longer exists"
        case .openFailed: "Couldn't open link"
        }
    }

    private var symbol: String {
        switch kind {
        case .switchedServer: "server.rack"
        case .linkGone: "xmark.circle.fill"
        case .openFailed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .switchedServer: .accentColor
        case .linkGone: .secondary
        case .openFailed: .orange
        }
    }
}

/// Watches ``AppModel/spotlightNotice`` and shows each one for two seconds:
/// fades it in at the top edge, then fades it out and clears the model's value.
/// A newer notice replaces the one on screen and restarts the timer.
private struct SpotlightNoticeToastModifier: ViewModifier {
    @Environment(AppModel.self) private var appModel
    @State private var shown: AppModel.SpotlightNotice?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let shown {
                    SpotlightNoticeToast(kind: shown.kind)
                        .padding(.top, 12)
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .id(shown.id)
                }
            }
            .onChange(of: appModel.spotlightNotice, initial: true) { _, notice in
                guard let notice else { return }
                appModel.spotlightNotice = nil
                present(notice)
            }
    }

    private func present(_ notice: AppModel.SpotlightNotice) {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { shown = notice }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { shown = nil }
        }
    }
}

extension View {
    /// Overlays the transient Spotlight-tap pill (see ``SpotlightNoticeToast``)
    /// near the top edge whenever the model has one to show.
    func spotlightNoticeToast() -> some View {
        modifier(SpotlightNoticeToastModifier())
    }
}
