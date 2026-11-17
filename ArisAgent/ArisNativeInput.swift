//
//  ArisNativeInput.swift
//  aris-agent
//
//  Aris's own engine, its input half: keys and text for one app's process (CGEventPostToPid: the app gets them, the
//  front app and the user's pointer don't change), a click by the element's own action, and, for an app that doesn't take
//  input in the background (measured in the VM: Chromium and Electron apps, Warp), a brief turn in front: the app and
//  its window are brought forward, the keys go, and the app and window that were in front are put back. The user's pointer
//  is never moved for keys; a pointer click (the last way, only when the user's card said it may come forward) puts it
//  back where it was.
//

import AppKit
import ApplicationServices
import Foundation

enum ArisNativeInput {
    // MARK: - Which way an app takes input

    /// Apps measured (VM, 2026-11-16) to drop keys posted to their process while in the background.
    static let foregroundOnly: Set<String> = ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview", "dev.warp.Warp"]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var learnedForeground: Set<String> = []

    /// Whether keys posted to the app's process reach it while another app is in front: not for a Chromium or Electron
    /// shell, Warp, or an app a background type was seen to miss.
    static func takesBackgroundKeys(bundle: String?, bundleURL: URL?) -> Bool {
        if let bundle, foregroundOnly.contains(bundle) || lock.withLock({ learnedForeground.contains(bundle) }) { return false }
        return !ArisAX.isWebShell(bundleURL: bundleURL)
    }

    /// A background type was read back and hadn't arrived: that app goes in front from now on (this agent run).
    static func learnForeground(_ bundle: String?) {
        guard let bundle else { return }
        _ = lock.withLock { learnedForeground.insert(bundle) }
    }

    // MARK: - Keys

    /// Names past ArisKeyChord's own.
    private static let extraKeys: [String: CGKeyCode] = [
        "backspace": 51, "forwarddelete": 117, "fwd-delete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "kp_enter": 76, "keypadenter": 76,
    ]

    /// A chord as the controller writes it ("cmd+a", "return", "shift+tab"): its key and flags; nil for one it doesn't know.
    static func chord(_ text: String) -> (key: CGKeyCode, flags: CGEventFlags)? {
        let parts = text.lowercased().split(separator: "+").map(String.init).map { ["meta", "super"].contains($0) ? "cmd" : $0 }
        guard let last = parts.last else { return nil }
        let normal = parts.joined(separator: "+")
        if let parsed = ArisKeyChord.parse(normal, layout: { command in Thread.isMainThread ? ArisKeyLayout.current(command: command) : [:] }) {
            return (parsed.key, parsed.flags)
        }
        guard let key = extraKeys[last] else { return nil }
        var flags: CGEventFlags = []
        let modifiers = Set(parts.dropLast())
        if modifiers.contains("cmd") || modifiers.contains("command") { flags.insert(.maskCommand) }
        if modifiers.contains("shift") { flags.insert(.maskShift) }
        if !modifiers.isDisjoint(with: ["opt", "option", "alt"]) { flags.insert(.maskAlternate) }
        if !modifiers.isDisjoint(with: ["ctrl", "control"]) { flags.insert(.maskControl) }
        return (key, flags)
    }

    /// Where an event goes: the app's process (background), or the system's input stream (the app is in front).
    enum Route { case process(Int32), front }

    private static func post(_ event: CGEvent, _ route: Route) {
        switch route {
        case .process(let pid): event.postToPid(pid)
        case .front: event.post(tap: .cghidEventTap)
        }
    }

    static func press(_ key: CGKeyCode, flags: CGEventFlags = [], route: Route) {
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        post(down, route)
        usleep(12_000)
        post(up, route)
        usleep(8_000)
    }

    /// The pieces typed text goes in: runs of characters (as Unicode, whatever the layout), and the keys Peekaboo's
    /// escapes name (\n return, \t tab, \b delete, \e escape; \\ a backslash). Pure.
    enum Piece: Equatable {
        case text(String)
        case key(CGKeyCode)
    }

    static func pieces(_ literal: String, chunk: Int = 16) -> [Piece] {
        var result: [Piece] = []
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            var current = ""
            for character in run {
                if current.utf16.count + String(character).utf16.count > chunk { result.append(.text(current)); current = "" }
                current.append(character)
            }
            if !current.isEmpty { result.append(.text(current)) }
            run = ""
        }
        var characters = Array(literal)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count {
                let next = characters[index + 1]
                let keys: [Character: CGKeyCode] = ["n": 36, "t": 48, "b": 51, "e": 53]
                if let key = keys[next] { flush(); result.append(.key(key)); index += 2; continue }
                if next == "\\" { run.append("\\"); index += 2; continue }
            }
            if character == "\n" || character == "\r" { flush(); result.append(.key(36)); index += 1; continue }
            if character == "\t" { flush(); result.append(.key(48)); index += 1; continue }
            run.append(character)
            index += 1
        }
        characters.removeAll()
        flush()
        return result
    }

    /// Types `literal` (Peekaboo's escapes) as Unicode key events in chunks.
    static func type(_ literal: String, route: Route) {
        let source = CGEventSource(stateID: .privateState)
        for piece in pieces(literal) {
            switch piece {
            case .key(let key): press(key, route: route)
            case .text(let text):
                let units = Array(text.utf16)
                for down in [true, false] {
                    guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                    event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                    post(event, route)
                }
                usleep(10_000)
            }
        }
    }

    // MARK: - Clicks

    /// The element's own action (no pointer, no focus taken): AXPress, else the first of its press-like actions.
    static func axPress(_ element: AXUIElement) -> Bool {
        // AXPress first even when it isn't listed (Chromium's list rows take it without naming it: VM, 2026-11-16); then
        // the element's own confirm, pick or open. Never its menu: that isn't a click.
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { return true }
        let actions = ArisAX.actions(element)
        guard let action = ["AXConfirm", "AXPick", "AXOpen"].first(where: actions.contains) else { return false }
        return AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// A control with no action of its own, clicked the way its container takes it: a list row, outline row or cell
    /// (the element or one of its first parents) selected by AXSelected; else the nearest parent that presses. The
    /// delivery used, or nil.
    static func selectOrPressAncestor(_ element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        for depth in 0..<5 {
            guard let node = current else { return nil }
            let role = ArisAX.role(node)
            if ["AXRow", "AXOutlineRow", "AXCell"].contains(role) || ArisAX.string(node, kAXSubroleAttribute as String) == "AXOutlineRow" {
                if ArisAX.settable(node, kAXSelectedAttribute as String),
                   AXUIElementSetAttributeValue(node, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success { return "ax-select" }
            }
            if depth > 0, axPress(node) { return "ax-press-parent" }
            current = ArisAX.element(node, kAXParentAttribute as String)
        }
        return nil
    }

    /// A slider or stepper moved to `value` by its own increment and decrement actions (at most 200 steps).
    static func step(_ element: AXUIElement, to value: Double) -> Bool {
        for _ in 0..<200 {
            guard let now = (ArisAX.value(element, kAXValueAttribute as String) as? NSNumber)?.doubleValue else { return false }
            if abs(now - value) < 0.0001 { return true }
            let action = now < value ? "AXIncrement" : "AXDecrement"
            guard AXUIElementPerformAction(element, action as CFString) == .success else { return false }
            guard let after = (ArisAX.value(element, kAXValueAttribute as String) as? NSNumber)?.doubleValue, after != now else { return false }
            // Overshot: as near as its steps go.
            if (now < value) != (after < value) { return true }
        }
        return false
    }

    /// A click posted to the app's process at a global point in one of its windows (the window under the click named, so
    /// the app routes it there): no pointer moves. Double and right clicks too.
    static func postClick(pid: Int32, at point: CGPoint, window: Int, double: Bool = false, right: Bool = false) {
        let source = CGEventSource(stateID: .privateState)
        let types: (CGEventType, CGEventType) = right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        for click in 1...(double ? 2 : 1) {
            for type in [types.0, types.1] {
                guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: right ? .right : .left) else { continue }
                event.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                // kCGMouseEventWindowUnderMousePointer and …ThatCanHandleThisEvent: the window the app routes it to.
                event.setIntegerValueField(CGEventField(rawValue: 91)!, value: Int64(window))
                event.setIntegerValueField(CGEventField(rawValue: 92)!, value: Int64(window))
                event.postToPid(pid)
                usleep(25_000)
            }
        }
    }

    /// A real pointer click at a global point (the app in front), the pointer put back where it was at once.
    static func pointerClick(at point: CGPoint, double: Bool = false, right: Bool = false) {
        let before = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .privateState)
        let types: (CGEventType, CGEventType) = right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        for click in 1...(double ? 2 : 1) {
            for type in [types.0, types.1] {
                guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: right ? .right : .left) else { continue }
                event.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                event.post(tap: .cghidEventTap)
                usleep(30_000)
            }
        }
        if let before { CGWarpMouseCursorPosition(before) }
    }

    /// A scroll posted to the app's process at a global point (lines; positive is up).
    static func postScroll(pid: Int32, at point: CGPoint, dx: Int32, dy: Int32) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.location = point
        event.postToPid(pid)
    }
}

/// A brief turn in front for an app that needs it, with everything put back after: the app (and its window) that had the
/// keyboard, whatever display it is on. With a second display the target window comes forward where it is (it isn't
/// moved, nor the pointer); either way the front app and window come back after the step.
struct ArisNativeForeground {
    let previousPid: Int32?
    let previousWindow: AXUIElement?
    let targetPid: Int32
    /// The target window is on another display than the one the user works on (their pointer's and their front window's).
    let otherDisplay: Bool

    /// Brings `pid` (and its window `window`, when given) forward; nil when it couldn't be brought forward within a second.
    static func borrow(pid: Int32, window: AXUIElement?) -> ArisNativeForeground? {
        let previous = ArisFrontLive.frontPid()
        let previousWindow = previous.flatMap { ArisAX.element(ArisAX.app($0), kAXFocusedWindowAttribute as String) }
        let other = window.flatMap(ArisAX.frame).map { ArisNativeDisplays.isOtherThanWorking($0, front: previousWindow.flatMap(ArisAX.frame)) } ?? false
        let app = ArisAX.app(pid)
        if let window {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate()
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if ArisFrontLive.frontPid() == pid { return ArisNativeForeground(previousPid: previous, previousWindow: previousWindow, targetPid: pid, otherDisplay: other) }
            usleep(20_000)
        }
        let made = ArisNativeForeground(previousPid: previous, previousWindow: previousWindow, targetPid: pid, otherDisplay: other)
        made.restore()
        return nil
    }

    /// The app and window that were in front, back in front (not when it was the target itself, or nothing was).
    func restore() {
        guard let previousPid, previousPid != targetPid, NSRunningApplication(processIdentifier: previousPid) != nil else { return }
        if let previousWindow {
            AXUIElementSetAttributeValue(previousWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(previousWindow, kAXRaiseAction as CFString)
        }
        // An app that was just activated can take the front back a moment later (Warp did, in the VM): the front is
        // asked again after a pause, and given back again, a few times.
        for _ in 0..<4 {
            AXUIElementSetAttributeValue(ArisAX.app(previousPid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: previousPid)?.activate()
            let deadline = Date().addingTimeInterval(0.8)
            while Date() < deadline, ArisFrontLive.frontPid() != previousPid { usleep(20_000) }
            usleep(250_000)
            if ArisFrontLive.frontPid() == previousPid { return }
        }
    }
}

/// Which display is which: the one the user works on is the one with their pointer (and, when it differs, their front window's).
enum ArisNativeDisplays {
    /// Every display's frame, in global top-left points (CGDisplayBounds).
    static var frames: [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }

    /// The display holding most of `rect`.
    static func display(of rect: CGRect, in displays: [CGRect]) -> Int? {
        let areas = displays.enumerated().map { ($0.offset, $0.element.intersection(rect)) }.filter { !$0.1.isNull }
        return areas.max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?.0
    }

    /// Whether `window` is on a display other than the one the user works on (pointer's display; their front window's when the
    /// pointer's can't be read). Pure in its parts (`displays`, `pointer`).
    static func isOther(_ window: CGRect, front: CGRect?, pointer: CGPoint?, displays: [CGRect]) -> Bool {
        guard displays.count > 1, let target = display(of: window, in: displays) else { return false }
        let working = pointer.flatMap { point in displays.firstIndex { $0.contains(point) } } ?? front.flatMap { display(of: $0, in: displays) }
        return working.map { $0 != target } ?? false
    }

    static func isOtherThanWorking(_ window: CGRect, front: CGRect?) -> Bool {
        isOther(window, front: front, pointer: CGEvent(source: nil)?.location, displays: frames)
    }
}
