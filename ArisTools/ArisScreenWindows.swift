//
//  ArisScreenWindows.swift
//  aris-tools
//
//  The windows on screen now, for `screen --around`'s private-app rule (ArisScreenTarget.coversPrivate): each
//  window's app and its place, as the window server lists them.
//

import AppKit

/// Every on-screen window (the desktop's own aside), front to back.
func onScreenWindows() -> [ArisScreenTarget.Window] {
    let listed = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return listed.compactMap { window in
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
        return ArisScreenTarget.Window(bundleId: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, frame: frame)
    }
}
