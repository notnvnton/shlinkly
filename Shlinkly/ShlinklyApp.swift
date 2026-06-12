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

    init() {
        let model = AppModel()
        // Phase 1: the active server + key come from the local dev config.
        // A later layer swaps this single call for Keychain-backed instances;
        // AppModel's consumers don't change.
        model.activate(DevConfig.serverInstance, apiKey: DevConfig.apiKey)
        _appModel = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
    }
}
