//
//  ShlinklyApp.swift
//  Shlinkly
//
//  Created by Anton Hodge on 10.06.26.
//

import SwiftUI
import ShlinklyCore

@main
struct ShlinklyApp: App {
    @State private var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel()
        // Credentials come from Keychain-backed instances: bootstrap brings the
        // active server online, or leaves the app in onboarding when none exist.
        model.bootstrap()
        _appModel = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                // The servers live in the (iCloud-synced) Keychain, which has no
                // live change notification — so re-read it whenever the app comes
                // to the foreground. A server added with iCloud sync on another
                // device appears here on this activation.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        appModel.refreshFromStore()
                    }
                }
        }
    }
}
