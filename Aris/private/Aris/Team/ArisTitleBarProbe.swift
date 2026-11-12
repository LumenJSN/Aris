//
//  ArisTitleBarProbe.swift
//  Aris
//
//  How tall another app's window title bar (with its toolbar) is, for the M2 perch under it, read through
//  Accessibility: the toolbar's bottom, else the close button's middle (ArisTitleBarRules). Nil when Aris isn't
//  trusted, the window isn't found or nothing plausible shows; the perch then takes 28 pt. Reads only roles, frames and
//  the close button: never a title or contents.
//

import AppKit
import ApplicationServices

enum ArisTitleBarProbe {
    /// The title bar's height of `pid`'s window at `windowCG` (CG coordinates).
    @MainActor
    static func height(pid: pid_t, windowCG: CGRect) -> CGFloat? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let windows = value(app, kAXWindowsAttribute) as? [AXUIElement],
              let window = windows.prefix(16).first(where: { frame($0).map { near($0, windowCG) } ?? false }) else { return nil }
        let toolbar = (value(window, kAXChildrenAttribute) as? [AXUIElement])?
            .first { (value($0, kAXRoleAttribute) as? String) == kAXToolbarRole }
            .flatMap(frame)
        let close = value(window, kAXCloseButtonAttribute).flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? frame($0 as! AXUIElement) : nil }
        return ArisTitleBarRules.height(windowTopCG: windowCG.minY, toolbarBottomCG: toolbar?.maxY, closeButtonMidYCG: close?.midY)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var out: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &out) == .success ? out : nil
    }

    /// An element's frame in CG coordinates (Accessibility's own: top left of the primary display, y down).
    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }
}
