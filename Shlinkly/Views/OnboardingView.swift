//
//  OnboardingView.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// First-run onboarding, shown only while no server is configured. A privacy-led
/// Welcome screen leads to the shared connect form; a successful connection adds
/// the instance, which flips ``AppModel/needsOnboarding`` and lets the root swap
/// straight to the list — no intermediate screens.
struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showConnectForm = false

    var body: some View {
        NavigationStack {
            WelcomeScreen { showConnectForm = true }
                .navigationDestination(isPresented: $showConnectForm) {
                    ServerFormView(mode: .add) { instance, key in
                        try appModel.addInstance(instance, apiKey: key)
                    }
                }
        }
    }
}

/// The Welcome screen, as layout v3 draws it (`PhoneOnboarding`): the mark,
/// the "Shlinkly" eyebrow, the 30 pt title, one line about the app, three
/// checked points with a semibold lead, and "Connect your server" at the
/// bottom. "What is Shlink?" isn't drawn; it stays, as a text button under it.
private struct WelcomeScreen: View {
    let onConnect: () -> Void

    private static let points: [(lead: String, text: String)] = [
        ("It's all yours.", "Private by design and fully open source. No Shlinkly cloud, no middleman."),
        ("We store nothing.", "There's no Shlinkly backend, so nothing passes through us."),
        ("Open source.", "Inspect every line on GitHub."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        BrandMark(side: 56, radius: 14, glyph: 30)
                            .padding(.bottom, 8)
                        Text("Shlinkly")
                            .layoutFont(13, .semibold)
                            .foregroundStyle(Palette.brand)
                        Text("Your links, on your own server.")
                            .layoutFont(30, .semibold, tracking: -0.3)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("A native iOS and Mac client for your self-hosted Shlink.")
                            .layoutFont(15)
                            .foregroundStyle(Palette.text2)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 44)

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Self.points, id: \.lead) { point in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.brand)
                                    .frame(width: 18, height: 18)
                                    .padding(.top, 2)
                                    .accessibilityHidden(true)
                                Text("\(Text(point.lead).fontWeight(.semibold).foregroundStyle(Palette.text)) \(Text(point.text).foregroundStyle(Palette.text2))")
                                    .layoutFont(15)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 28)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 460, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 4) {
                Button("Connect your server", action: onConnect)
                    .buttonStyle(.layoutPrimary)
                Link("What is Shlink?", destination: URL(string: "https://shlink.io")!)
                    .buttonStyle(.layoutText)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .canvasBackground()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

#if DEBUG
#if os(iOS)
#Preview("PhoneOnboarding light") {
    NavigationStack { WelcomeScreen {} }
        .brandTint()
        .preferredColorScheme(.light)
}

#Preview("PhoneOnboarding dark") {
    NavigationStack { WelcomeScreen {} }
        .brandTint()
        .preferredColorScheme(.dark)
}
#endif
#endif
