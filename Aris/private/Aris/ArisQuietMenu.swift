//
//  ArisQuietMenu.swift
//  Aris
//
//  The ✦ menu's mute item: "음소거", ticked while Aris is muted; choosing it flips the same switch as the notch's.
//

import AppKit

@MainActor
final class ArisQuietMenu: NSObject {
    private static let target = ArisQuietMenu()

    /// Built each time the menu opens, so the tick is the state right now.
    static func item() -> NSMenuItem {
        let item = NSMenuItem(title: ArisQuietCopy.menuItem(english: ArisUIWords.english), action: #selector(ArisQuietMenu.toggle), keyEquivalent: "")
        item.target = target
        item.state = ArisQuietGate.muted ? .on : .off
        return item
    }

    @objc private func toggle() { ArisQuietLive.shared.toggle() }
}
