//
//  ArisWindowAtPoint.swift
//  Aris
//
//  Which window is under each of a circle's five hit-test samples (plan D5): the on-screen window list, front to
//  back, layer 0, visible, never Aris's own (the overlay is on top of everything). Titles need only the Screen
//  Recording grant. The window list is read once per circle; only the matching is pure.
//

import AppKit
import CoreGraphics

enum ArisWindowAtPoint {
    /// The circle's samples (Quartz global points, top-left origin) against the live window list.
    @MainActor
    static func hits(at samples: [CGPoint]) -> [ArisWindowHit] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var bundles: [Int32: String?] = [:]
        return match(samples, windows: windows, ownPid: getpid()) { pid in
            if let known = bundles[pid] { return known }
            let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            bundles[pid] = .some(id)
            return id
        }
    }

    /// The window under one click (ArisWindowPicker), Quartz global points; nil for the desktop.
    @MainActor
    static func hit(at point: CGPoint) -> ArisWindowHit? { hits(at: [point]).first }

    /// The frontmost layer-0, visible window containing `point`, never `ownPid`'s (the pick overlay is Aris's own).
    static func front(at point: CGPoint, windows: [[String: Any]], ownPid: Int32, bundle: (Int32) -> String?) -> ArisWindowHit? {
        match([point], windows: windows, ownPid: ownPid, bundle: bundle).first
    }

    /// One hit per sample (the frontmost layer-0, visible window containing it, never `ownPid`'s), grouped by window
    /// with sample counts and the centre flag (`ArisGestureGeometry.groupHits`). `windows` is front to back, as
    /// `CGWindowListCopyWindowInfo` returns it. An owner whose bundle can't be resolved keeps a nil id: the session
    /// refuses it (fail closed).
    static func match(_ samples: [CGPoint], windows: [[String: Any]], ownPid: Int32,
                      bundle: (Int32) -> String?) -> [ArisWindowHit] {
        var candidates: [ArisWindowHit] = []
        for window in windows {
            guard let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  frame.width > 0, frame.height > 0 else { continue }
            candidates.append(ArisWindowHit(id: number, pid: pid, app: window[kCGWindowOwnerName as String] as? String,
                                            title: window[kCGWindowName as String] as? String, frame: frame,
                                            samples: 0, hitCenter: false, bundleId: bundle(pid)))
        }
        let perSample = samples.map { point in candidates.first { $0.frame.contains(point) } }
        return ArisGestureGeometry.groupHits(perSample)
    }
}
