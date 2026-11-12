//
//  ArisNotchRules.swift
//  Aris
//
//  The decisions behind the notch's state, as plain functions so they can be tested without windows or screens:
//  whether a notch opens, which page it shows after closing, the heights of a closed notch and of the hover strip
//  under it, the tab-setting couplings, the preferred display's migration, and which displays count as full screen.
//

import CoreGraphics

enum ArisNotchRules {
    struct Opening: Equatable {
        /// A Claude approval is waiting: show the Claude page (even when the notch is already open).
        let selectClaude: Bool
        let opens: Bool
    }

    /// Opening is refused during the very first launch and when the notch is already open.
    static func opening(isOpen: Bool, firstLaunch: Bool, approvalPending: Bool) -> Opening {
        Opening(selectClaude: approvalPending, opens: !firstLaunch && !isOpen)
    }

    /// The page after a notch closes, or nil to keep it: the Aris page stays (Aris restores the page itself when its
    /// turn ends, and other displays may still show it); otherwise home, unless the last tab is remembered.
    static func pageAfterClose(current: NotchViews, rememberLastTab: Bool) -> NotchViews? {
        if current == .aris || rememberLastTab { return nil }
        return .home
    }

    /// A closed notch hidden for a full-screen app collapses to nothing on a display without a notch (or one that is
    /// gone); a real notch keeps its height.
    static func effectiveClosedHeight(hidden: Bool, connected: Bool, hasNotch: Bool, closedHeight: CGFloat) -> CGFloat {
        hidden && (!connected || !hasNotch) ? 0 : closedHeight
    }

    /// The invisible strip under a closed notch that reaches down to the menu bar's bottom ("hide title bar" on).
    static func chinHeight(hideTitleBar: Bool, connected: Bool, closed: Bool, effectiveHeight: CGFloat, menuBarHeight: CGFloat) -> CGFloat {
        guard hideTitleBar, connected, closed, effectiveHeight > 0 else { return 0 }
        return max(0, menuBarHeight - effectiveHeight)
    }

    struct TabSettings: Equatable {
        var alwaysShowTabs: Bool
        var rememberLastTab: Bool
        /// Go back to the home page.
        var selectHome = false
    }

    /// Turning "always show tabs" off also stops remembering the last tab, and goes home unless the shelf has items
    /// and opens by default.
    static func alwaysShowTabsChanged(to on: Bool, rememberLastTab: Bool, shelfEmpty: Bool, openShelfByDefault: Bool) -> TabSettings {
        guard !on else { return TabSettings(alwaysShowTabs: true, rememberLastTab: rememberLastTab) }
        return TabSettings(alwaysShowTabs: false, rememberLastTab: false, selectHome: shelfEmpty || !openShelfByDefault)
    }

    /// Remembering the last tab needs the tabs shown.
    static func rememberLastTabChanged(to on: Bool, alwaysShowTabs: Bool) -> TabSettings {
        TabSettings(alwaysShowTabs: on ? true : alwaysShowTabs, rememberLastTab: on)
    }

    struct PreferredDisplay: Equatable {
        let uuid: String?
        /// Store `uuid` as the preference (it wasn't stored yet).
        let store: Bool
        /// Remove the legacy display-name preference.
        let clearLegacyName: Bool
    }

    /// The preferred display: the stored UUID; else the display whose name older builds stored (or the main one, if
    /// that name isn't connected); else the main display.
    static func preferredDisplay(storedUUID: String?, legacyName: String?, screens: [(name: String, uuid: String?)], mainUUID: String?) -> PreferredDisplay {
        if let storedUUID { return PreferredDisplay(uuid: storedUUID, store: false, clearLegacyName: false) }
        if let legacyName {
            let named = screens.first { $0.name == legacyName }?.uuid
            return PreferredDisplay(uuid: named ?? mainUUID, store: true, clearLegacyName: true)
        }
        return PreferredDisplay(uuid: mainUUID, store: true, clearLegacyName: false)
    }

    /// One full-screen space: the display it is on and the bundle ids running in it.
    struct FullscreenSpace: Equatable {
        let displayUUID: String?
        let apps: [String]
    }

    /// Which displays count as full screen. With "now playing only", a full-screen space counts only when the known
    /// music app runs in it; with no music app known, or any other option, every full-screen space counts. Every
    /// display passed in gets an entry.
    static func fullscreen(spaces: [FullscreenSpace], displays: [String], option: HideNotchOption, musicBundle: String?) -> [String: Bool] {
        var status: [String: Bool] = [:]
        for display in displays { status[display] = false }
        for space in spaces {
            guard let uuid = space.displayUUID else { continue }
            let counts = option != .nowPlayingOnly || musicBundle.map { space.apps.contains($0) } ?? true
            status[uuid] = (status[uuid] ?? false) || counts
        }
        return status
    }

    /// Hidden while closed: full screen on this display, unless hiding is turned off.
    static func hiddenWhileClosed(option: HideNotchOption, fullscreen: Bool) -> Bool {
        option != .never && fullscreen
    }
}
