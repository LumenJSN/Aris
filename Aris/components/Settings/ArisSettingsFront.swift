//
//  ArisSettingsFront.swift
//  Aris
//
//  When the settings window, coming forward, has to hand the Mac's menu bar to Aris by stepping back first. Aris is a
//  menu-bar app that becomes a regular one while its settings are open. macOS draws an app's menus when the app is
//  activated; an app that was already the active one when it turned regular (a fix button in the notch opened
//  Settings while the notch had the keyboard) is not activated anew, so the menu bar kept the previous app's name
//  over Aris's window (third VM run). In that one case, once the change has settled, the Dock (which shows nothing)
//  is made active for a moment and Aris comes forward again, as an activation macOS then draws. In every other case
//  the window comes forward exactly as before, and nothing is taken from any app. Foundation only (tested).
//

import Foundation

struct ArisSettingsFront: Equatable {
    /// Aris was already a regular app (its settings or the setup were open).
    let wasRegular: Bool
    /// Aris was the active app when the window was asked for.
    let wasActive: Bool

    /// How long the change to a regular app is given to settle before Aris steps back, and how long the Dock is
    /// active before Aris comes forward again.
    static let settle: TimeInterval = 0.15
    static let away: TimeInterval = 0.2
    /// The program that is made active in between: it has no window that comes forward and no menu bar of its own.
    static let between = "com.apple.dock"

    /// Whether Aris steps back and comes forward again: only when it turned regular while it was already active.
    var reactivates: Bool { !wasRegular && wasActive }

    /// Whether the second half still runs when its time comes: the window is still up and nobody else took the
    /// keyboard meanwhile (`frontmost`: the active app's bundle id; Aris's own or the in-between program's).
    static func comesBack(windowVisible: Bool, frontmost: String?, own: String?) -> Bool {
        windowVisible && (frontmost == between || (frontmost != nil && frontmost == own))
    }
}
