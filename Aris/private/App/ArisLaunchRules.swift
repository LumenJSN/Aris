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

    /// How long the toggle shortcut's notch stays open on its own.
    static let toggleAutoClose: Duration = .seconds(3)
    /// How long the standard music peek shows from its shortcut.
    static let peekShortcutDuration: TimeInterval = 3
}
