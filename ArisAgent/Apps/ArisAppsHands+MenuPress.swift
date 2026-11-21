//
//  ArisAppsHands+MenuPress.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  A menu item pressed by Accessibility, in the background where the app allows it (fifth VM run, D1: a replay's
//  "Edit › Select All" failed with TextEdit behind Finder, "“Select All” is greyed out right now"). A Cocoa app checks
//  most of its items against its key window, and an app that isn't active has none, so such an item is greyed out
//  until the app is in front. Then, and only then, the app is brought forward, the very same item (the same path the
//  call named, read again and pressed only once it is enabled) is pressed. An item still greyed out with the app in
//  front is greyed out for real: nothing is pressed and that is said. After a press, a window the item opens is waited
//  for a moment (fifth VM run, D5: File › New's window came after the next step had already read the old one).
//
//  Sixth VM run, item 2: "Wrap to Page" taught, the document since wrapped to the page, so its item reads "Wrap to
//  Window". In the background TextEdit had not checked its items again since (it does that when it is active), so
//  the menu bar still read "Wrap to Page", greyed out for want of a key window. The earlier fix brought TextEdit
//  forward, its menu was checked, the item now read "Wrap to Window", the wait for "Wrap to Page" to be enabled ran out,
//  and the first read's "greyed out" was said: wrong half the time (whenever the background read was stale). An item
//  whose exact name is gone once the app is in front is a miss: said as one (with what the app shows instead), nothing
//  is pressed, and the app goes back. An item that isn't there in the background at all is a miss at once: nothing is
//  brought forward for it.
//
//  Sixth VM run, item 4: the app that was in front goes back once, when the call (or the replay it is part of) ends,
//  never after each press (a replay's next steps may need the app in front too), and only while the app brought
//  forward is still the one in front (he may have switched himself). Never Aris itself (ArisAppsOwnerFront).
//

import Foundation

extension ArisAppsHands {
    /// The item at exactly `path` pressed: in the background, or with the app in front when the item is enabled only
    /// there. The path is never changed or looked up again by another name. `app`: the app's name, for the miss.
    func pressMenuItem(pid: Int32, path: [String], app: String) -> (ok: Bool, message: String) {
        let first = ax.pressMenu(pid: pid, path: path)
        guard !first.ok else { return first }
        guard let bar = ax.menuBar(pid: pid) else { return first }
        // Not there by its exact name: a miss, said as one; nothing is brought forward or pressed.
        guard let item = bar.item(at: path) else { return (false, Self.missing(path, in: bar, app: app)) }
        guard item.enabled == false else { return first }
        // In front already: greyed out for real.
        guard system.frontmost()?.pid != pid else { return first }
        let owner = system.ownerFront()
        // The windows as he has them now, before anything is brought forward: what goes back (ArisAppsWindowOrder).
        let order = system.windowOrder()
        guard system.activate(pid: pid) else { return first }
        broughtForward(pid, owner: owner, order: order)
        var gone = 0
        let ready = waitFor {
            guard self.system.frontmost()?.pid == pid, let now = self.ax.menuBar(pid: pid) else { return false }
            guard now.item(at: path) != nil else {
                // Its name changed once the app checked its menus in front: read gone twice running, it is a miss.
                gone += 1
                return gone >= 2
            }
            gone = 0
            return now.item(at: path)?.enabled == true
        }
        if gone >= 2 { return (false, Self.missing(path, in: ax.menuBar(pid: pid) ?? bar, app: app)) }
        let pressed = ready ? ax.pressMenu(pid: pid, path: path) : first
        return pressed
    }

    /// Why an item isn't pressed when its exact name isn't in `bar`: the miss in the app layer's words (with the item
    /// the same menu shows instead), never "greyed out".
    static func missing(_ path: [String], in bar: ArisApps.MenuBar, app: String) -> String {
        if case .missing(let why) = ArisApps.Exact.menu(path.joined(separator: " › "), key: nil, in: ArisApps.Commands.fromMenu(bar), app: app) { return why }
        return "that menu item isn't there now in \(app)"
    }

    /// Aris's own processes (the app and its helper), by bundle id.
    static func isAris(_ bundle: String) -> Bool {
        let id = bundle.lowercased()
        return id == "com.lumenjsn.aris" || id.hasPrefix("com.lumenjsn.aris.")
    }

    // MARK: - Putting the owner's app back

    /// A call (or a replay of several) is under way: an app brought forward stays in front until the last one ends.
    func beginFrontHold() { lock.withLock { frontHolds += 1 } }

    /// The call (or replay) ended, however it ended: when it was the last, the owner's app goes back in front if an app
    /// was brought forward and is still the one in front.
    func endFrontHold() {
        let back = lock.withLock { () -> FrontReturn? in
            frontHolds = max(0, frontHolds - 1)
            guard frontHolds == 0, let back = frontReturn else { return nil }
            frontReturn = nil
            return back
        }
        if let back { putBack(back) }
    }

    /// A replay waits on a card (a step's, or the go-on question): the owner's app goes back in front now, if an app
    /// was brought forward and is still the one in front (he may have switched himself), never Aris (seventh VM run,
    /// item 8: TextEdit stayed in front through the failure and the whole go-on card). The hold stays open: a later
    /// step that needs its app in front brings it forward again (pressMenuItem, only for an item greyed out in the
    /// background), and that app goes back when the hold ends. Nothing is activated when nothing was brought forward.
    func yieldFront() {
        let back = lock.withLock { () -> FrontReturn? in
            let back = frontReturn
            frontReturn = nil
            return back
        }
        if let back { putBack(back) }
    }

    /// `pid` was brought forward; `owner` was the owner's app before and `order` his windows then (both kept from the
    /// first time in a hold: a later reading already has an app of Aris's bringing in it).
    private func broughtForward(_ pid: Int32, owner: ArisAppsRunning?, order: [ArisAppsWindowPlace]) {
        lock.withLock {
            if let kept = frontReturn {
                frontReturn = FrontReturn(owner: kept.owner, brought: pid, order: kept.order, all: kept.all.union([pid]))
            } else if let owner, owner.pid != pid {
                frontReturn = FrontReturn(owner: owner, brought: pid, order: order, all: [pid])
            }
        }
    }

    private func putBack(_ back: FrontReturn) {
        // He switched apps himself meanwhile: his choice stands.
        guard system.ownerFront()?.pid == back.brought, !Self.isAris(back.owner.bundle),
              system.runningApps().contains(where: { $0.pid == back.owner.pid }) else { return }
        // First the windows that lay over the app brought forward go over it again, in the order they had (ninth VM
        // run, item 2: with only the desktop focused Finder has no main window to raise, and TextEdit's stayed on top).
        // Before his app is made active, so the focus it had (the desktop) is its own to take back.
        let aris = Set(system.runningApps().filter { Self.isAris($0.bundle) }.map(\.pid))
        let above = ArisAppsWindowOrder.toRaise(before: back.order, brought: back.all, skip: aris)
        if !above.isEmpty { system.raise(above) }
        guard system.activate(pid: back.owner.pid) else { return }
        // Activation alone left the window of the app that was brought forward on top (eighth VM run, item 5,
        // cap8/F1-flicker.jpg: Finder active again, TextEdit's window still above Finder's): his app's own main window
        // is raised too, by Accessibility, which the helper already has.
        system.raiseMainWindow(pid: back.owner.pid)
    }

    /// The app to go back to, and the one that was brought forward instead of it.
    struct FrontReturn {
        let owner: ArisAppsRunning
        let brought: Int32
        /// The windows on screen before the first app was brought forward, front to back.
        var order: [ArisAppsWindowPlace] = []
        /// Every app brought forward in this hold.
        var all: Set<Int32> = []
    }

    /// The app's windows once a press has had its effect: at once when its mark already flipped or the windows changed,
    /// else after waiting up to `settleSeconds` for a window to come, go, or take the front (a new document's window).
    /// Nil when the list couldn't be read.
    func settledWindows(of bundle: String, before: [WindowInfo], marked: Bool) -> [WindowInfo]? {
        var after = listedWindows(of: bundle)
        if let read = after, marked || Self.windowsChanged(before, read) && !Self.allGone(before, read) { return read }
        let end = Date().addingTimeInterval(settleSeconds)
        while Date() < end {
            Thread.sleep(forTimeInterval: 0.1)
            after = listedWindows(of: bundle)
            if let read = after, Self.windowsChanged(before, read), !Self.allGone(before, read) { break }
        }
        return after
    }

    /// Every window gone at once: what a list read while the app is busy (just brought forward, or put back) can say
    /// (sixth VM run, item 4: "TextEdit now has 0 windows" after Edit › Select All, with one open). Read once more
    /// before it is believed.
    static func allGone(_ before: [WindowInfo], _ after: [WindowInfo]) -> Bool { !before.isEmpty && after.isEmpty }

    /// A window came or went, or another listed one is in front now. A front window gone from the front with none
    /// listed in its place is the focus already on a window the list doesn't show yet: not settled.
    static func windowsChanged(_ before: [WindowInfo], _ after: [WindowInfo]) -> Bool {
        if Set(before.map(\.id)) != Set(after.map(\.id)) { return true }
        let was = before.first(where: \.front)?.id, now = after.first(where: \.front)?.id
        if now == nil, was != nil { return false }
        return was != now
    }
}
