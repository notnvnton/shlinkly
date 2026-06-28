//
//  Updater.swift
//  Shlinkly
//
//  Sparkle integration for the macOS *direct-distribution* build ONLY.
//
//  Everything Sparkle-touching is gated behind `os(macOS) && SPARKLE`. The `SPARKLE`
//  compilation condition is set only in the `Release-Direct` configuration, and the
//  `Sparkle.framework` is linked/embedded only there too. In every other build — all
//  of iOS, and the Mac App Store (`Release`) macOS build — `SPARKLE` is undefined, so
//  this file compiles to an inert no-op: no Sparkle symbols, no framework dependency,
//  no "Check for Updates…" menu item. The `AppUpdater` typealias keeps call sites
//  identical across both worlds (real `SparkleUpdater` vs `NoopSparkleUpdater`).
//

import Combine
import SwiftUI

#if os(macOS) && SPARKLE
import Sparkle

/// Owns Sparkle's updater in the direct-distribution build. A thin wrapper over
/// `SPUStandardUpdaterController`, which starts the updater on init and drives
/// Sparkle's standard update UI. The feed URL and public EdDSA key are read from the
/// app's `Info.plist` (`SUFeedURL` / `SUPublicEDKey`).
@MainActor
final class SparkleUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Republished from the updater so the menu item can enable/disable itself —
    /// false while an update is already in progress or the updater can't run.
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true → begin scheduled background checks immediately.
        // nil delegates → default behaviour (config comes entirely from Info.plist).
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Mirrors `SPUStandardUpdaterController.checkForUpdates(_:)`: shows the update
    /// panel and checks the appcast now.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// In the direct build, the app's updater is the real Sparkle one.
typealias AppUpdater = SparkleUpdater

#else

/// No-op stand-in compiled into every non-direct build (all iOS, the Mac App Store
/// macOS build). Same shape as ``SparkleUpdater`` so call sites are identical, but it
/// links nothing and can never check for updates (`canCheckForUpdates` stays false).
@MainActor
final class NoopSparkleUpdater: ObservableObject {
    @Published var canCheckForUpdates = false
    func checkForUpdates() {}
}

/// Outside the direct build, the app's updater is the inert no-op.
typealias AppUpdater = NoopSparkleUpdater

#endif
