//
//  GenerationSignal.swift
//  ShlinklyCore
//

import Foundation

/// Cross-process signal names for "a short link is being created", broadcast as
/// Darwin notifications (`CFNotificationCenterGetDarwinNotifyCenter`).
///
/// Darwin notifications cross the process **and** sandbox boundary between the
/// macOS Share Extension's separate process and the main app — unlike
/// `DistributedNotificationCenter`, which the extension's sandbox blocks. The
/// signal carries no payload: the menu-bar icon only needs to know start / success
/// / failure, and reacts with the animation it already has.
///
/// Public so both the app (receiver) and the macOS Share Extension (poster) can
/// share the exact names. Defined here without a platform gate — these are just
/// strings and a `CFNotification` post, available on every Apple platform; only the
/// *macOS* Share Extension actually posts (see `ShareCreateView`, `#if os(macOS)`).
public enum GenerationSignal {
    public static let started   = "de.ahodge.shlinkly.generation.started"
    public static let succeeded = "de.ahodge.shlinkly.generation.succeeded"
    public static let failed    = "de.ahodge.shlinkly.generation.failed"
}

/// Posts a Darwin notification by name — no payload, delivered immediately.
public func postGenerationSignal(_ name: String) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(name as CFString),
        nil,
        nil,
        true
    )
}
