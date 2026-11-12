//
//  ArisScreenTarget.swift
//  aris-tools
//
//  Whose window `screen` reads, and when `screen --around` reads nothing (security review 3, L1). `screen` reads the
//  app in front. `screen --pid <n>` reads the window of the process named: aris-agent's own look asks that way when
//  Aris itself or a macOS prompt is in front (ArisLookTarget), and nobody else may: the flag counts only with the mark
//  aris-agent alone puts in the environment of that one run (as `activity log` has ARIS_LOCAL_LOG), and both gates
//  rate an AI's `screen --pid` never (ArisRiskPolicy, ArisTurnGate). A pid that is no running app fails; it used to
//  fall back to whatever was in front. `screen --around x,y,w,h` captures a part of the screen, whoever's windows are
//  in it: it takes no pid, and reads nothing while any on-screen window of a private app (a password manager,
//  ArisCaptureRules) overlaps the rectangle, the rule the helper's look already had for the pointer
//  (ArisLook.privateWindow). Foundation only (tested).
//

import Foundation

enum ArisScreenTarget {
    /// Set by aris-agent alone, for its look's `screen --pid` (ArisLookTarget.helperKey).
    static let helperKey = "ARIS_HELPER_LOOK"

    static let pidRefusal = "screen --pid is aris-agent's own, for its look; screen reads the app in front"
    static let pidUsage = "usage: screen [--image] | screen --around x,y,w,h"
    static func notRunning(_ pid: String) -> String { "no running app has the pid \(pid)" }
    static let privateThere = "a private app's window is there; I don't read it"

    enum Named: Equatable {
        /// The app in front.
        case front
        /// That running app.
        case pid(Int32)
        /// Nothing is read: why.
        case refused(String)
    }

    /// `flagged`: the words hold --pid; `value`: what follows it (nil: nothing); `around`: the words hold --around;
    /// `runs`: whether a pid is a running app.
    static func named(flagged: Bool, value: String?, around: Bool, environment: [String: String], runs: (Int32) -> Bool) -> Named {
        guard flagged else { return .front }
        guard environment[helperKey] == "1" else { return .refused(pidRefusal) }
        // A part of the screen is whoever's windows are in it: no pid moves the private check off the app in front.
        if around { return .front }
        guard let value else { return .refused(pidUsage) }
        guard let pid = Int32(value), pid > 0, runs(pid) else { return .refused(notRunning(value)) }
        return .pid(pid)
    }

    static let windowUsage = "usage: screen --pid <n> [--window <id>]"
    static func windowGone(_ id: String) -> String { "the window \(id) is no longer that app's own window on screen" }

    /// One window of the window server's list, front to back: its number, whose it is and its layer (0: an app's own).
    struct Listed: Equatable {
        let number: Int
        let pid: Int32
        let layer: Int
    }

    enum Picked: Equatable {
        case window(Int)
        case refused(String)
    }

    /// The window `screen --pid` captures. `requested`: what follows --window (nil: no --window; "": nothing after it).
    /// Without --window, the app's topmost own window; with it, exactly that window, and only while it is still the
    /// app's own and on screen (the look names the window it means: a window of another app is never read in its
    /// place, second upgrade run, bug 1). nil: the app shows no window.
    static func window(requested: String?, pid: Int32, windows: [Listed]) -> Picked? {
        guard let requested else { return windows.first { $0.pid == pid && $0.layer == 0 }.map { .window($0.number) } }
        guard let number = Int(requested), number > 0 else { return .refused(windowUsage) }
        guard windows.contains(where: { $0.number == number && $0.pid == pid && $0.layer == 0 }) else { return .refused(windowGone(requested)) }
        return .window(number)
    }

    /// A window on screen: whose it is (its app's bundle id) and where (global points from the top left).
    struct Window: Equatable {
        let bundleId: String?
        let frame: CGRect
    }

    /// Whether any on-screen window of a private app overlaps `rect`.
    static func coversPrivate(_ rect: CGRect, windows: [Window], isPrivate: (String?) -> Bool) -> Bool {
        windows.contains { isPrivate($0.bundleId) && $0.frame.intersects(rect) }
    }
}
