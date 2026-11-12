//
//  ArisWindowLocator.swift
//  Aris
//
//  Finds another app's window frame through CGWindowListCopyWindowInfo, which works inside the sandbox and needs no
//  permission for frames. Frames are CG coordinates (origin at the top left of the primary screen, y down).
//  Privacy: only the window number, owner pid, layer, bounds, alpha and on-screen flag are read. Window names and
//  contents never are.
//

import CoreGraphics

enum ArisWindowPresence: Equatable {
    case onScreen(CGRect)
    case offScreen
    case closed
}

enum ArisWindowLocator {
    /// Smaller windows are helpers (drag images, tooltips, status items), not something to sit on.
    static let minimumSide: CGFloat = 40

    /// The frame of `windowNumber` when it belongs to `pid`, is a normal (layer 0) window and is on screen; nil when
    /// it is gone, minimised or on another Space.
    static func frame(pid: Int32, windowNumber: Int) -> CGRect? {
        guard windowNumber > 0, windowNumber <= Int(UInt32.max) else { return nil }
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]] ?? []
        return frame(in: list, pid: pid, windowNumber: windowNumber)
    }

    /// `pid`'s front-most normal window that is on screen.
    static func frontWindow(pid: Int32) -> (number: Int, frame: CGRect)? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return frontWindow(in: list, pid: pid)
    }

    /// Whether `windowNumber` of `pid` is on screen, off it (minimised, hidden, on another Space) or closed. Read
    /// without the on-screen filter, so a window that is only out of sight is told from one that is gone.
    /// A window list that came back empty or not at all is "closed" only while the window server is answering: a
    /// hiccup of the call (nothing back for any window) reads as out of sight, never as a window that is gone for good
    /// (that would send its figure home and end a Claude Code job watching it).
    static func presence(pid: Int32, windowNumber: Int) -> ArisWindowPresence {
        guard windowNumber > 0, windowNumber <= Int(UInt32.max) else { return .closed }
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]]
        return presence(in: list, pid: pid, windowNumber: windowNumber) {
            // Something is always on screen (the menu bar, the Dock, the desktop): none at all means the call failed.
            !((CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []).isEmpty
        }
    }

    /// Every normal-sized layer-0 window of `pid`: those on screen first, front to back, then the ones out of sight
    /// (minimised, hidden, on another Space). A quiet launch finds its new window by what was not here before.
    static func windows(pid: Int32) -> [Int] {
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows(onScreen: onScreen, all: all, pid: pid)
    }

    /// The front normal window on screen and the app it belongs to.
    static func topWindow() -> (pid: Int32, number: Int)? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.lazy.compactMap(Entry.init).first { $0.isNormal && $0.isVisible }.map { ($0.pid, $0.number) }
    }

    // MARK: - Reading the list (pure, tested)

    static func windows(onScreen: [[String: Any]], all: [[String: Any]], pid: Int32) -> [Int] {
        var seen = Set<Int>()
        return (onScreen + all).compactMap(Entry.init).filter { $0.pid == pid && $0.layer == 0 && $0.isVisible && seen.insert($0.number).inserted }.map(\.number)
    }

    /// `list`: what the window server gave for that one window (nil: nothing came back). `serverAnswers`: whether it
    /// lists any window at all right now, asked only when `list` doesn't hold the window.
    static func presence(in list: [[String: Any]]?, pid: Int32, windowNumber: Int, serverAnswers: () -> Bool) -> ArisWindowPresence {
        let found = presence(in: list ?? [], pid: pid, windowNumber: windowNumber)
        guard found == .closed, list?.isEmpty != false else { return found }
        return serverAnswers() ? .closed : .offScreen
    }

    static func presence(in list: [[String: Any]], pid: Int32, windowNumber: Int) -> ArisWindowPresence {
        guard let entry = list.lazy.compactMap(Entry.init).first(where: { $0.number == windowNumber && $0.pid == pid && $0.layer == 0 })
        else { return .closed }
        return entry.onScreen ? .onScreen(entry.frame) : .offScreen
    }

    static func frame(in list: [[String: Any]], pid: Int32, windowNumber: Int) -> CGRect? {
        list.lazy.compactMap(Entry.init).first { $0.number == windowNumber && $0.pid == pid && $0.isNormal }?.frame
    }

    /// The list is ordered front to back, so the first fitting window is the front one.
    static func frontWindow(in list: [[String: Any]], pid: Int32) -> (number: Int, frame: CGRect)? {
        guard let entry = list.lazy.compactMap(Entry.init).first(where: { $0.pid == pid && $0.isNormal && $0.isVisible })
        else { return nil }
        return (entry.number, entry.frame)
    }

    private struct Entry {
        let number: Int, pid: Int32, layer: Int, frame: CGRect, onScreen: Bool, alpha: Double

        init?(_ info: [String: Any]) {
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            self.number = number
            self.pid = pid
            self.layer = layer
            self.frame = frame
            onScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            alpha = info[kCGWindowAlpha as String] as? Double ?? 1
        }

        var isNormal: Bool { layer == 0 && onScreen }
        var isVisible: Bool { alpha > 0 && frame.width >= ArisWindowLocator.minimumSide && frame.height >= ArisWindowLocator.minimumSide }
    }
}
