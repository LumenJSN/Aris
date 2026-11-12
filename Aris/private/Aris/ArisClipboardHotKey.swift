//
//  ArisClipboardHotKey.swift
//  Aris
//
//  ⌃⌥V opens the notch on the 클립보드 tab, ready to search (change it in Settings → Shortcuts; Maccy's own ⇧⌘C is
//  left alone). While the 클립보드 tab is turned off Aris lets go of the key, so it reaches the app in front.
//

import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openClipboard = Self("openClipboard", default: .init(.v, modifiers: [.control, .option]))
}

extension Notification.Name {
    static let clipboardHotKey = Notification.Name("com.lumenjsn.aris.clipboardHotKey")
}

enum ArisClipboardHotKey {
    @MainActor static func register() {
        KeyboardShortcuts.onKeyDown(for: .openClipboard) {
            NotificationCenter.default.post(name: .clipboardHotKey, object: nil)
        }
    }

    /// Off: the shortcut stays as the user set it but Aris stops taking the key from other apps; on: it takes it again.
    @MainActor static func setEnabled(_ on: Bool) {
        if on { KeyboardShortcuts.enable(.openClipboard) } else { KeyboardShortcuts.disable(.openClipboard) }
    }
}
