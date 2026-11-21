//
//  ArisDesktopWindowMerge.swift
//  aris-agent
//
//  Which windows an app has, for the engine: the window server's on-screen list alone missed every window on another
//  Space, minimized into the Dock or of a hidden app, so "the Notes window behind" was invisible to Aris while the user
//  worked full screen. Now the window server's whole list (on screen or not) is merged with what Accessibility lists
//  for the app (its minimized and hidden windows, and, by their remote tokens, its windows on other Spaces:
//  ArisAXRemote): the on-screen ones first, front to back as before (so "the front window" is unchanged), then the
//  others, each marked, so a look or an action can work them in the background. The merge is pure.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum ArisDesktopWindowMerge {
    /// One window as Accessibility has it.
    struct AXWindow: Equatable {
        let id: Int
        let frame: CGRect
        var title: String? = nil
        var minimized = false
    }

    /// The smallest a real window is (points).
    static let minSize = CGSize(width: 60, height: 40)

    private static func frame(_ info: [String: Any]) -> CGRect? {
        guard let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    /// `list`: the window server's list of every window (front to back for those on screen); `ax`: the app's windows by
    /// Accessibility. The process's real windows (layer 0, not tiny): on screen first in the list's order, then the
    /// ones off screen that Accessibility knows (minimized, hidden, another Space), then those only Accessibility lists.
    static func merge(list: [[String: Any]], pid: Int32, ax: [AXWindow]) -> [ArisDesktopWindow] {
        let byId = Dictionary(ax.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<Int> = []
        var onScreen: [ArisDesktopWindow] = [], offScreen: [ArisDesktopWindow] = []
        for info in list {
            guard info[kCGWindowOwnerPID as String] as? Int32 == pid, info[kCGWindowLayer as String] as? Int == 0,
                  let number = info[kCGWindowNumber as String] as? Int, !seen.contains(number), let frame = frame(info) else { continue }
            let visible = info[kCGWindowIsOnscreen as String] as? Bool == true
            let known = byId[number]
            // Off screen, only a window Accessibility knows as the app's: the server keeps other off-screen buffers too.
            guard visible || known != nil else { continue }
            let size = known?.frame.size ?? frame.size
            guard size.width >= minSize.width, size.height >= minSize.height else { continue }
            if visible, (info[kCGWindowAlpha as String] as? Double ?? 1) <= 0 { continue }
            seen.insert(number)
            let title = known?.title ?? info[kCGWindowName as String] as? String
            let window = ArisDesktopWindow(id: number, frame: known?.frame ?? frame, title: title, onScreen: visible, minimized: known?.minimized ?? false)
            if visible { onScreen.append(window) } else { offScreen.append(window) }
        }
        let onlyAX = ax.filter { !seen.contains($0.id) && $0.frame.width >= minSize.width && $0.frame.height >= minSize.height }
            .map { ArisDesktopWindow(id: $0.id, frame: $0.frame, title: $0.title, onScreen: false, minimized: $0.minimized) }
        return onScreen + offScreen + onlyAX
    }

    /// How a window list names a window that isn't on screen.
    static func note(_ window: ArisDesktopWindow) -> String? {
        if window.onScreen { return nil }
        return window.minimized ? "minimized" : "not on screen: another Space or hidden"
    }

    // MARK: - Live

    /// The app's windows by Accessibility: those it lists, and when the window server has off-screen windows of the app
    /// that it doesn't list (another Space), those found by their remote tokens.
    static func accessibilityWindows(pid: Int32, list: [[String: Any]]) -> [AXWindow] {
        guard AXIsProcessTrusted() else { return [] }
        var elements = ArisAX.windows(pid: pid)
        let listed = Set(elements.compactMap(ArisAX.windowId))
        let missing = list.contains { info in
            info[kCGWindowOwnerPID as String] as? Int32 == pid && info[kCGWindowLayer as String] as? Int == 0
                && info[kCGWindowIsOnscreen as String] as? Bool != true && (info[kCGWindowNumber as String] as? Int).map { !listed.contains($0) } == true
                && (frame(info).map { $0.width >= minSize.width && $0.height >= minSize.height } ?? false)
        }
        if missing { elements += ArisAXRemote.windows(pid: pid).filter { ArisAX.windowId($0).map { !listed.contains($0) } ?? false } }
        return elements.compactMap { element in
            guard let id = ArisAX.windowId(element), let frame = ArisAX.frame(element) else { return nil }
            return AXWindow(id: id, frame: frame, title: ArisAX.string(element, kAXTitleAttribute as String),
                            minimized: ArisAX.bool(element, kAXMinimizedAttribute as String) == true)
        }
    }

    static func live(pid: Int32) -> [ArisDesktopWindow] {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return merge(list: list, pid: pid, ax: accessibilityWindows(pid: pid, list: list))
    }
}

/// An Accessibility element made from its remote token (HIServices; no public equivalent).
@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

/// An app's windows on other Spaces: Accessibility lists only those on the current one, but every element of the app
/// can be reached by its remote token (the app's pid, a marker and the element's id), and its windows are the elements
/// whose role is a window. Tried for a short while only (the ids are small numbers), the found ones timed.
enum ArisAXRemote {
    static let maxId: UInt64 = 1_000
    static let limit: TimeInterval = 0.3

    /// The token for element `id` of `pid`: pid (4 bytes), 0 (4), "coco" (4), the id (8).
    static func token(pid: Int32, id: UInt64) -> Data {
        var data = Data()
        withUnsafeBytes(of: pid) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(0)) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(0x636f636f)) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: id) { data.append(contentsOf: $0) }
        return data
    }

    /// A search is kept a few seconds (one step asks for the app's windows several times).
    static let keep: TimeInterval = 4
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recent: [Int32: (at: Date, windows: [AXUIElement])] = [:]

    static func windows(pid: Int32) -> [AXUIElement] {
        if let kept = lock.withLock({ recent[pid] }), Date().timeIntervalSince(kept.at) < keep { return kept.windows }
        let found = search(pid: pid)
        lock.withLock {
            recent = recent.filter { Date().timeIntervalSince($0.value.at) < keep }
            recent[pid] = (Date(), found)
        }
        return found
    }

    private static func search(pid: Int32) -> [AXUIElement] {
        let deadline = Date().addingTimeInterval(limit)
        var found: [AXUIElement] = []
        for id in 0..<maxId where Date() < deadline {
            guard let element = _AXUIElementCreateWithRemoteToken(token(pid: pid, id: id) as CFData)?.takeRetainedValue() else { continue }
            ArisAX.timed(element)
            guard ArisAX.role(element) == kAXWindowRole as String else { continue }
            found.append(element)
        }
        return found
    }

    /// The app's window with this window-server id among them.
    static func window(pid: Int32, id: Int) -> AXUIElement? {
        windows(pid: pid).first { ArisAX.windowId($0) == id }
    }
}
