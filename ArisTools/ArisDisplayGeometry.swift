//
//  ArisDisplayGeometry.swift
//  aris-tools
//
//  Windows on any display (QA BUG-33: TextEdit on an external display left of and above the main one, at -2222,-38,
//  wasn't typed into). Accessibility and the window server measure from the primary display's top left with y down;
//  AppKit's screens from its bottom left with y up. Both are global, so one flip with the primary's height converts any
//  display's frame, negative origins included. Pure, so the tests run it.
//

import CoreGraphics

enum ArisDisplayGeometry {
    /// A top-left frame (Accessibility, the window server) in AppKit's bottom-left terms.
    static func bottomLeft(_ frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// An AppKit frame in top-left terms (the same flip).
    static func topLeft(_ frame: CGRect, primaryHeight: CGFloat) -> CGRect { bottomLeft(frame, primaryHeight: primaryHeight) }

    /// Which of `screens` (AppKit frames) holds most of `window` (a top-left frame); nil when none holds any of it.
    static func display(for window: CGRect, screens: [CGRect], primaryHeight: CGFloat) -> Int? {
        let frame = bottomLeft(window, primaryHeight: primaryHeight)
        let areas = screens.map { screen -> CGFloat in
            let shared = screen.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }

    /// Where `window left|right|full|center` puts a window (top-left terms, for Accessibility): on the display that holds
    /// most of it (any display, negative origins included), in that display's visible frame; the first display when the
    /// window is on none. `screens`: AppKit frames and visible frames, the primary first. Nil for an unknown layout.
    static func layoutFrame(_ layout: String, window: CGRect?, screens: [(frame: CGRect, visible: CGRect)], primaryHeight: CGFloat) -> CGRect? {
        guard !screens.isEmpty else { return nil }
        let index = window.flatMap { display(for: $0, screens: screens.map(\.frame), primaryHeight: primaryHeight) } ?? 0
        let visible = screens[index].visible
        let frame: CGRect
        switch layout {
        case "left": frame = CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case "right": frame = CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case "full", "maximize": frame = visible
        case "center": frame = visible.insetBy(dx: visible.width * 0.15, dy: visible.height * 0.1)
        default: return nil
        }
        return topLeft(frame, primaryHeight: primaryHeight)
    }
}
