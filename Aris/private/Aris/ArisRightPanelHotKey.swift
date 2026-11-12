//
//  ArisRightPanelHotKey.swift
//  Aris
//
//  A key that opens the right side notch (할 일, 캘린더) without the pointer, as ⌃⌥V opens the left one. It has no
//  key until the user picks one in settings (노치 · 사이드 노치), so nothing is taken from other apps by default. It opens
//  the tab the panel was last on (or the one that is left when the other is turned off) on the display the pointer
//  is on, with the keyboard as the left one's key does. Pressed again it puts the panel away, so the pointer is
//  needed for neither (the left one closes from its search field). While every right tab is off Aris lets go of the
//  key.
//

import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openRightPanel = Self("openRightPanel")
}

enum ArisRightPanelHotKey {
    @MainActor static func register() {
        KeyboardShortcuts.onKeyDown(for: .openRightPanel) {
            MainActor.assumeIsolated {
                let panels = ArisSidePanels.shared
                if panels.open.contains(.right) { panels.collapse(.right) } else { panels.show(.right, keyboard: true) }
            }
        }
    }

    /// Off: the shortcut stays as the user set it but Aris stops taking the key from other apps; on: it takes it again.
    @MainActor static func setEnabled(_ on: Bool) {
        if on { KeyboardShortcuts.enable(.openRightPanel) } else { KeyboardShortcuts.disable(.openRightPanel) }
    }
}
