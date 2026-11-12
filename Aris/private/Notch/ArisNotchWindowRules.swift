//
//  ArisNotchWindowRules.swift
//  Aris
//
//  The arithmetic and choices of the notch windows, as plain functions: where a window sits, which display a
//  single-display mode uses, whether the display set changed, where drags open the notch, and the window's spaces
//  behaviour.
//

import AppKit

enum ArisNotchWindowRules {
    /// Centred on the screen, top edge flush with the screen's top.
    static func origin(screenFrame: CGRect, windowSize: CGSize) -> CGPoint {
        CGPoint(x: screenFrame.midX - windowSize.width / 2, y: screenFrame.maxY - windowSize.height)
    }

    /// The rectangle an open notch covers on a screen (where a drag opens it).
    static func openNotchRegion(screenFrame: CGRect, openSize: CGSize) -> CGRect {
        CGRect(x: screenFrame.midX - openSize.width / 2, y: screenFrame.maxY - openSize.height,
               width: openSize.width, height: openSize.height)
    }

    /// Where a content drag counts as over the closed notch: `width` wide and ArisNotchDecisions.dragHoverDepth down
    /// from the top, centred.
    static func dragHoverRegion(screenFrame: CGRect, width: CGFloat) -> CGRect {
        let depth = ArisNotchDecisions.dragHoverDepth
        return CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - depth, width: width, height: depth)
    }

    /// The display of a single-display mode, or nil when there is none to show (preferred display unplugged).
    static func display(mode: DisplayMode, preferred: String?, screens: [String], main: String?) -> String? {
        let preferredHere = preferred.flatMap { screens.contains($0) ? $0 : nil }
        switch mode {
        case .preferredDisplay: return preferredHere
        case .fallbackIfPreferredUnavailable: return preferredHere ?? main
        case .activeDisplay, .allDisplays: return main
        }
    }

    /// What decides whether the windows must be rebuilt: how many screens, which ones, and where.
    struct ScreenSet: Equatable {
        let count: Int
        let uuids: Set<String>
        let frames: Set<CGRectKey>

        init(_ screens: [(uuid: String?, frame: CGRect)]) {
            count = screens.count
            uuids = Set(screens.compactMap(\.uuid))
            frames = Set(screens.map { CGRectKey($0.frame) })
        }
    }

    struct CGRectKey: Hashable {
        let x, y, width, height: CGFloat
        init(_ rect: CGRect) { (x, y, width, height) = (rect.minX, rect.minY, rect.width, rect.height) }
    }

    /// Joins all spaces over full-screen apps, stays put, skips window cycling; leaves Mission Control on displays
    /// without a notch when that setting is on.
    static func collectionBehavior(hideNonNotchedFromMissionControl: Bool, hasNotch: Bool) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        if hideNonNotchedFromMissionControl && !hasNotch { behavior.insert(.transient) }
        return behavior
    }
}
