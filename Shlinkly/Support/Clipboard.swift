//
//  Clipboard.swift
//  Shlinkly
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Thin cross-platform wrapper over the system pasteboard.
enum Clipboard {
    /// Copies `string` to the general pasteboard, replacing its contents.
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #endif
    }
}
