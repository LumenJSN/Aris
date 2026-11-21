//
//  ArisBrowserLive.swift
//  aris-agent
//
//  Decision 2's live readers for the trust gate: a browser's front page address (its web area's AXURL, read through
//  Accessibility, so the card names the site's host), and the element a call acts on as the app layer last read it
//  (its label, whether it is a password field). Reading only: nothing is pressed or typed here.
//

import AppKit
import ApplicationServices
import Foundation

enum ArisBrowserLive {
    static func install(gate: ArisTrustGate = .shared) {
        gate.pageAddress = { app in address(of: app) }
        gate.element = { app, target in
            let hands = ArisAppsHands.shared
            let label = target.flatMap { hands.label(app: app, target: $0) }
            return (label, hands.role(app: app, target: target) == "secureTextField")
        }
    }

    /// The front page's address of a running browser by its name or bundle id; nil when it can't be read.
    static func address(of app: String) -> String? {
        let wanted = app.lowercased()
        guard let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == wanted || $0.bundleIdentifier?.lowercased() == wanted
        }) else { return nil }
        let element = AXUIElementCreateApplication(running.processIdentifier)
        var value: CFTypeRef?
        let window: AXUIElement
        if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success, let found = value,
           CFGetTypeID(found) == AXUIElementGetTypeID() {
            window = found as! AXUIElement
        } else if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement],
                  let first = windows.first {
            window = first
        } else {
            return nil
        }
        return ArisSessionDesktopLive.address(window)
    }
}
