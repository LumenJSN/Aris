// Acceptance tests for the clean-room notch state (cleanroom-specs/03-notch-state-and-navigation.md).
import AppKit
import SwiftUI

func runStateTests() {
    typealias R = ArisNotchRules
    // 1–2. Opening and closing.
    check(R.opening(isOpen: false, firstLaunch: false, approvalPending: false) == .init(selectClaude: false, opens: true), "open: a closed notch opens")
    check(!R.opening(isOpen: false, firstLaunch: true, approvalPending: false).opens, "open: refused during the first launch")
    check(R.opening(isOpen: true, firstLaunch: false, approvalPending: true) == .init(selectClaude: true, opens: false),
          "open: already open with an approval pending -> Claude page, no reopen")
    check(R.opening(isOpen: false, firstLaunch: true, approvalPending: true).selectClaude, "open: the Claude page is chosen even on the first launch")
    check(R.pageAfterClose(current: .shelf, rememberLastTab: false) == .home && R.pageAfterClose(current: .claude, rememberLastTab: false) == .home,
          "close: back to home")
    check(R.pageAfterClose(current: .shelf, rememberLastTab: true) == nil, "close: the last tab stays when it is remembered")
    check(R.pageAfterClose(current: .aris, rememberLastTab: false) == nil, "close: the Aris page stays (Aris restores it itself)")

    // 4. Heights.
    for hidden in [false, true] {
        for hasNotch in [false, true] {
            let height = R.effectiveClosedHeight(hidden: hidden, connected: true, hasNotch: hasNotch, closedHeight: 32)
            check(height == (hidden && !hasNotch ? 0 : 32), "height: hidden \(hidden), notch \(hasNotch) -> \(height)")
        }
    }
    check(R.effectiveClosedHeight(hidden: true, connected: false, hasNotch: true, closedHeight: 32) == 0, "height: a hidden notch on a gone display is 0")
    check(R.chinHeight(hideTitleBar: true, connected: true, closed: true, effectiveHeight: 32, menuBarHeight: 37) == 5, "chin: down to the menu bar's bottom")
    check(R.chinHeight(hideTitleBar: false, connected: true, closed: true, effectiveHeight: 32, menuBarHeight: 37) == 0
          && R.chinHeight(hideTitleBar: true, connected: true, closed: false, effectiveHeight: 32, menuBarHeight: 37) == 0
          && R.chinHeight(hideTitleBar: true, connected: true, closed: true, effectiveHeight: 0, menuBarHeight: 37) == 0
          && R.chinHeight(hideTitleBar: true, connected: false, closed: true, effectiveHeight: 32, menuBarHeight: 37) == 0
          && R.chinHeight(hideTitleBar: true, connected: true, closed: true, effectiveHeight: 40, menuBarHeight: 37) == 0,
          "chin: none with the setting off, open, flat, without a display, or taller than the menu bar")

    // 5. Tab settings.
    check(R.alwaysShowTabsChanged(to: false, rememberLastTab: true, shelfEmpty: false, openShelfByDefault: true)
          == .init(alwaysShowTabs: false, rememberLastTab: false, selectHome: false), "tabs: off also stops remembering the last tab")
    check(R.alwaysShowTabsChanged(to: false, rememberLastTab: false, shelfEmpty: true, openShelfByDefault: true).selectHome
          && R.alwaysShowTabsChanged(to: false, rememberLastTab: false, shelfEmpty: false, openShelfByDefault: false).selectHome,
          "tabs: off goes home when the shelf is empty or doesn't open by default")
    check(R.alwaysShowTabsChanged(to: true, rememberLastTab: false, shelfEmpty: true, openShelfByDefault: false) == .init(alwaysShowTabs: true, rememberLastTab: false),
          "tabs: on changes nothing else")
    check(R.rememberLastTabChanged(to: true, alwaysShowTabs: false) == .init(alwaysShowTabs: true, rememberLastTab: true)
          && R.rememberLastTabChanged(to: false, alwaysShowTabs: false) == .init(alwaysShowTabs: false, rememberLastTab: false),
          "tabs: remembering the last tab turns the tabs on")

    // 6. Preferred display.
    let screens: [(name: String, uuid: String?)] = [("Built-in", "A"), ("Studio Display", "B")]
    check(R.preferredDisplay(storedUUID: "B", legacyName: "Built-in", screens: screens, mainUUID: "A") == .init(uuid: "B", store: false, clearLegacyName: false),
          "display: a stored UUID wins")
    check(R.preferredDisplay(storedUUID: nil, legacyName: "Studio Display", screens: screens, mainUUID: "A") == .init(uuid: "B", store: true, clearLegacyName: true),
          "display: a legacy name is found, stored as a UUID, and cleared")
    check(R.preferredDisplay(storedUUID: nil, legacyName: "Projector", screens: screens, mainUUID: "A") == .init(uuid: "A", store: true, clearLegacyName: true),
          "display: a legacy name that isn't connected falls back to the main display")
    check(R.preferredDisplay(storedUUID: nil, legacyName: nil, screens: screens, mainUUID: "A") == .init(uuid: "A", store: true, clearLegacyName: false),
          "display: nothing stored -> the main display, stored")

    // 7. Peeks.
    check(ArisPeekBoard.targets("B", displays: ["A", "B"], main: "A") == ["B"] && ArisPeekBoard.targets(nil, displays: ["A", "B"], main: "A") == ["A", "B"]
          && ArisPeekBoard.targets(nil, displays: [], main: "A") == ["A"] && ArisPeekBoard.targets(nil, displays: [], main: nil).isEmpty,
          "peek: one display, all of them, or the main one when none are listed")
    var board = ArisPeekBoard()
    check(!board.state(for: "A").show && !board.state(for: nil).show && !board.anyShowing, "peek: unknown displays read as hidden")
    let first = board.show(.music, value: 0, icon: "", accent: nil, on: ["A", "B"])
    check(board.state(for: "A").show && board.state(for: "B").show && board.anyShowing && board.state(for: "B").targetScreenUUID == "B",
          "peek: all-displays fan-out")
    let second = board.show(.music, value: 0, icon: "", accent: nil, on: ["A"])
    board.hide("A", show: first[0].show)
    check(board.state(for: "A").show, "peek: an earlier show's auto-hide doesn't cut a later one short")
    board.hide("A", show: second[0].show)
    board.hide("B", show: first[1].show)
    check(!board.state(for: "A").show && !board.state(for: "B").show && !board.anyShowing && board.state(for: "A").type == .music,
          "peek: the last show's auto-hide hides it (type back to music)")
    _ = board.show(.music, value: 0, icon: "", accent: nil, on: ["Gone"])
    check(board.state(for: "Gone").show, "peek: a display that no longer exists keeps its state without trouble")
    board.hide("Gone")
    check(!board.state(for: "Gone").show, "peek: a hide without a number always hides")

    // 8. Full screen.
    let spaces = [R.FullscreenSpace(displayUUID: "A", apps: ["com.apple.Safari"]), R.FullscreenSpace(displayUUID: "B", apps: ["com.spotify.client"])]
    check(R.fullscreen(spaces: spaces, displays: ["A", "B", "C"], option: .always, musicBundle: nil) == ["A": true, "B": true, "C": false],
          "fullscreen: always -> any full-screen space counts")
    check(R.fullscreen(spaces: spaces, displays: ["A", "B", "C"], option: .nowPlayingOnly, musicBundle: "com.spotify.client") == ["A": false, "B": true, "C": false],
          "fullscreen: now playing only -> only the space running the music app")
    check(R.fullscreen(spaces: spaces, displays: ["A", "B"], option: .nowPlayingOnly, musicBundle: nil) == ["A": true, "B": true],
          "fullscreen: now playing only with no music app known -> any full-screen space counts")
    check(R.fullscreen(spaces: spaces, displays: ["A", "B"], option: .never, musicBundle: "com.spotify.client") == ["A": true, "B": true],
          "fullscreen: other options count every space (never is applied by the hidden rule)")
    check(R.fullscreen(spaces: [R.FullscreenSpace(displayUUID: nil, apps: [])], displays: ["A", "A"], option: .always, musicBundle: nil) == ["A": false],
          "fullscreen: a space without a display is skipped; repeated displays are fine")
    check(R.hiddenWhileClosed(option: .always, fullscreen: true) && R.hiddenWhileClosed(option: .nowPlayingOnly, fullscreen: true)
          && !R.hiddenWhileClosed(option: .never, fullscreen: true) && !R.hiddenWhileClosed(option: .always, fullscreen: false),
          "fullscreen: hidden unless hiding is off")
}
