//
//  ArisAppsLive+WindowOrder.swift
//  aris-agent (Core 2 app layer)
//
//  The live half of ArisAppsWindowOrder: the windows on screen as the window server lists them (owner and frame only),
//  and a window raised by Accessibility (the app's own window element at that frame, AXRaise). Nothing is drawn,
//  read or clicked.
//

import AppKit
import ApplicationServices
import Foundation

extension ArisAppsLiveSystem {
    /// The ordinary windows on screen, front to back: layer 0, visible, large enough to be a window.
    func windowOrder() -> [ArisAppsWindowPlace] {
        let listed = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return listed.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0, ((window[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int, let box = window[kCGWindowBounds as String] as? [String: Any],
                  let x = box["X"] as? Double, let y = box["Y"] as? Double, let width = box["Width"] as? Double, let height = box["Height"] as? Double,
                  width >= 40, height >= 40 else { return nil }
            return ArisAppsWindowPlace(pid: Int32(pid), x: x, y: y, width: width, height: height)
        }
    }

    /// Each window raised in turn (the last ends on top): the owner's window element whose frame is that one. A window
    /// that moved or closed meanwhile is left alone.
    func raise(_ windows: [ArisAppsWindowPlace]) {
        var apps: [Int32: [AXUIElement]] = [:]
        for place in windows {
            if apps[place.pid] == nil {
                let app = AXUIElementCreateApplication(place.pid)
                AXUIElementSetMessagingTimeout(app, 0.5)
                var value: CFTypeRef?
                AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
                apps[place.pid] = value as? [AXUIElement] ?? []
            }
            guard let window = apps[place.pid]?.first(where: { Self.frame(of: $0).map { ArisAppsWindowOrder.same(place, x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) } ?? false }) else { continue }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
