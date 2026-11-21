//
//  ArisLaunchRules.swift
//  Aris
//
//  The launch-time decisions of the app entry, as plain functions: the one-time display-mode migration and which
//  notch the toggle shortcut acts on.
//

import Foundation

enum ArisLaunchRules {
    /// The display mode for a first launch after older builds, from their three switches (only when no mode is stored).
    static func migratedDisplayMode(showOnAllDisplays: Bool, followActiveDisplay: Bool, automaticallySwitchDisplay: Bool) -> DisplayMode {
        if showOnAllDisplays { return .allDisplays }
        if followActiveDisplay { return .activeDisplay }
        if automaticallySwitchDisplay { return .fallbackIfPreferredUnavailable }
        return .preferredDisplay
    }

    /// Whether a mode change crosses between "all displays" and a single display (the other window set goes first).
    static func crossesWindowSets(from old: DisplayMode?, to new: DisplayMode) -> Bool {
        guard let old else { return false }
        return (old == .allDisplays) != (new == .allDisplays)
    }

    /// The toggle shortcut's notch has no timer: it stays open until closed, and a click in another app closes it
    /// while it is still open.
    static func toggleClosesOnClickElsewhere(open: Bool) -> Bool { open }
    /// How long the standard music peek shows from its shortcut.
    static let peekShortcutDuration: TimeInterval = 3
}
