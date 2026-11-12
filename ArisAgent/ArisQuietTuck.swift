//
//  ArisQuietTuck.swift
//  aris-agent
//
//  A teammate's window in a terminal that can't put itself away (Warp has no scripting and can't be minimised or
//  closed from outside any other way): through Accessibility, which the helper has with the app's own switch.
//  Nothing is ever asked for here: without Accessibility the window stays where it opened, behind the app the user is in.
//  - Only the one window the launch opened is spoken to: it is found by its window number (the one that was not
//    there before the launch), never by its place in a list, its title or its frame.
//  - It is minimised, and the Dock is believed only when the window then reads as minimised. Refused: on a Mac with
//    a second display it is moved to the display the user's front window is not on; else it stays behind their windows,
//    and the job's row says where it is (ArisQuietLaunch.placeWords).
//  - Nothing is raised, focused or activated; every call to the terminal is cut off after a second.
//  - At the job's end the window is closed with its own close button, and "closed" is said only when it is gone
//    (a sheet asking about a running program leaves it there: then it stays and the last line says so).
//  NOT RUN on the Mac this was written on (Accessibility was off limits there): the steps to check it with the
//  installed app are in the branch's report.
//

import AppKit
import ApplicationServices

enum ArisQuietTuck {
    /// How long one Accessibility call to the terminal may take.
    static let callTimeout: Float = 1
    /// How long the window is given to really be in the Dock, or really be gone.
    static let settle: TimeInterval = 1.5

    /// Puts the launch's window out of the way; where it ended up. `title`: the name this launch gave its tab.
    /// The window is touched only when that name is read back from it (`own`): one with another title could be
    /// The user's, and stays where it is (security review 7, M3).
    static func putAway(pid: Int32, window: Int, title: String) -> (place: ArisQuietLaunch.Place, own: Bool) {
        guard AXIsProcessTrusted(), let element = element(pid: pid, window: window),
              ArisQuietLaunch.titleMatches(read: text(element, kAXTitleAttribute), expected: title) else { return (.behind, false) }
        return (place(element, pid: pid, window: window), true)
    }

    private static func place(_ element: AXUIElement, pid: Int32, window: Int) -> ArisQuietLaunch.Place {
        if AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success,
           wait({ flag(element, kAXMinimizedAttribute) == true }) {
            return .docked
        }
        guard let frame = ArisWindowLocator.frame(pid: pid, windowNumber: window),
              let target = ArisQuietLaunch.otherDisplay(window: frame, front: frontFrame(), displays: displays()) else { return .behind }
        var origin = CGPoint(x: target.minX + ArisQuietLaunch.displayInset, y: target.minY + ArisQuietLaunch.displayInset)
        guard let value = AXValueCreate(.cgPoint, &origin), AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success,
              wait({ ArisWindowLocator.frame(pid: pid, windowNumber: window).map { target.contains(CGPoint(x: $0.minX + 1, y: $0.minY + 1)) } ?? false }) else { return .behind }
        return .otherDisplay
    }

    /// Presses the window's own close button. True only when the window is then gone. `title`: when given, the
    /// window must show it now (a window whose command never started); nil: its title was matched when it opened.
    static func close(pid: Int32, window: Int, title: String?) -> Bool {
        guard AXIsProcessTrusted(), let element = element(pid: pid, window: window) else { return false }
        if let title, !ArisQuietLaunch.titleMatches(read: text(element, kAXTitleAttribute), expected: title) { return false }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success, let button,
              CFGetTypeID(button) == AXUIElementGetTypeID(),
              AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success else { return false }
        return wait { self.element(pid: pid, window: window) == nil }
    }

    /// The app's window with exactly this window number.
    private static func element(pid: Int32, window: Int) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, callTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { return nil }
        return windows.first { element in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(element, &id) == .success && Int(id) == window
        }
    }

    private static func text(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func flag(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private static func wait(_ done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(settle)
        while Date() < end {
            if done() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return done()
    }

    /// The user's front window (not a terminal's teammate window: this runs while they is somewhere else).
    private static func frontFrame() -> CGRect? {
        ArisWindowLocator.topWindow().flatMap { ArisWindowLocator.frame(pid: $0.pid, windowNumber: $0.number) }
    }

    private static func displays() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }
}
