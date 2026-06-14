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

/// The Welcome screen: identity, the privacy promise, three reassurances, and the
/// call to connect. The app logo sits atop, clipped to an app-icon-style tile.
private struct WelcomeScreen: View {
    let onConnect: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 16) {
                    AppLogoMark()

                    VStack(spacing: 6) {
                        Text("Shlinkly")
                            .font(.largeTitle.weight(.bold))
                        Text("A native iOS & Mac client for your self-hosted Shlink.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("We store nothing.")
                    Text("It's all yours.")
                }
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)

                Text("Private by design and fully open source — no Shlinkly cloud, no middleman.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 18) {
                    Promise(
                        icon: "lock.shield",
                        text: "Your links and keys stay on your server and devices."
                    )
                    Promise(
                        icon: "icloud.slash",
                        text: "There's no Shlinkly backend — nothing passes through us."
                    )
                    Promise(
                        icon: "chevron.left.forwardslash.chevron.right",
                        text: "Open source — inspect every line on GitHub."
                    )
                }
                .padding(.horizontal)

                VStack(spacing: 14) {
                    Button(action: onConnect) {
                        Text("Connect your server")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Link("What is Shlink?", destination: URL(string: "https://shlink.io")!)
                        .font(.subheadline)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)
        }
    }
}

/// The app logo atop the Welcome screen: the 1024 master scaled down and clipped
/// to a continuous rounded rectangle so it reads like an app-icon tile.
private struct AppLogoMark: View {
    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One reassurance row: an icon and a line of copy.
private struct Promise: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Text(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
