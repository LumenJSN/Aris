//
//  ArisFollowRules.swift
//  Aris
//
//  The pure decisions behind ArisWindowFollower: which press arms drag tracking, when tracking has settled, when
//  the display link has gone quiet, and which display shows a window. Window frames are CG coordinates; the pointer
//  and screens are AppKit coordinates.
//

import CoreGraphics
import QuartzCore

enum ArisFollowRules {
    /// A press arms drag tracking only on the followed window or within `slop` of it.
    static func armsDrag(pointer: CGPoint, window: CGRect?, primaryHeight: CGFloat, slop: CGFloat) -> Bool {
        guard let window else { return false }
        let pointerCG = CGPoint(x: pointer.x, y: primaryHeight - pointer.y)
        return window.insetBy(dx: -slop, dy: -slop).contains(pointerCG)
    }

    /// True once `after` seconds have passed with no change.
    static func settled(now: CFTimeInterval, lastChange: CFTimeInterval, after: CFTimeInterval) -> Bool {
        now - lastChange >= after
    }

    /// True when the display link hasn't ticked for more than `after` seconds.
    static func isStale(lastTick: CFTimeInterval, now: CFTimeInterval, after: CFTimeInterval) -> Bool {
        now - lastTick > after
    }

    /// The display holding the window's centre.
    static func screenIndex(windowCG: CGRect, screens: [CGRect], primaryHeight: CGFloat) -> Int? {
        let frame = ArisPerchGeometry.toAppKit(windowCG, primaryHeight: primaryHeight)
        return ArisPerchGeometry.screenIndex(of: CGPoint(x: frame.midX, y: frame.midY), screens: screens)
    }
}
