//
//  DevConfig.example.swift
//  Shlinkly
//
//  Template for local development configuration.
//
//  Copy this file to `DevConfig.swift` (same folder) and paste your Shlink dev
//  API key. `DevConfig.swift` is git-ignored, so the key never leaves your
//  machine. This template is intentionally excluded from the build target (see
//  the membership exception in project.pbxproj), so it never collides with the
//  real `DevConfig.swift`.
//
//  This is a temporary Phase 1 stand-in for real server management. A later
//  layer replaces it with Keychain-backed instances, at which point the app's
//  entry point stops reading DevConfig and AppModel's consumers stay unchanged.
//

import Foundation
import ShlinklyCore

enum DevConfig {
    /// The Shlink server the app talks to during development.
    static let serverInstance = ServerInstance(
        id: UUID(uuidString: "00000000-0000-4000-A000-000000000001")!,
        name: "go.ahodge.de",
        baseURL: URL(string: "https://go.ahodge.de/rest/v3/")!
    )

    /// Your Shlink API key, sent as the `X-Api-Key` header. Keep it out of git.
    static let apiKey = "PASTE_YOUR_DEV_API_KEY_HERE"
}
