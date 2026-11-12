//
//  ArisPanTracker.swift
//  Aris
//
//  The arithmetic of a directional swipe (see ArisPan.swift): which way, how far, when it begins.
//

import AppKit

enum PanDirection {
    case left, right, up, down

    var isVertical: Bool { self == .up || self == .down }
    /// +1 when the direction is down or right.
    var sign: CGFloat { self == .down || self == .right ? 1 : -1 }
}

/// One swipe. Every value it reports is a distance along the swipe's own direction (never negative): a left swipe
/// reports positive distances to the "left" handler.
struct ArisPanTracker {
    static let noise: CGFloat = 0.2

    let direction: PanDirection
    let threshold: CGFloat
    private(set) var total: CGFloat = 0
    private(set) var began = false
    /// Scroll events arrived since the last end.
    private(set) var active = false

    init(direction: PanDirection, threshold: CGFloat) {
        self.direction = direction
        self.threshold = threshold
    }

    /// One scroll movement along the axis (screen-signed: + is down / right). Toward the direction it adds up and
    /// reports .began at the threshold, then .changed; against it the total starts over (.changed with 0 once begun).
    mutating func move(_ delta: CGFloat) -> (CGFloat, NSEvent.Phase)? {
        active = true
        guard abs(delta) > Self.noise else { return nil }
        let toward = delta * direction.sign
        if toward <= 0 {
            total = 0
            return began ? (0, .changed) : nil
        }
        total += toward
        if !began {
            guard total >= threshold else { return nil }
            began = true
            return (total, .began)
        }
        return (total, .changed)
    }

    /// The scroll is over (its "ended" phase, or quiet): .ended with the total, 0 if it never began. Nothing when no
    /// scroll was going on. Starts afresh either way.
    mutating func end() -> (CGFloat, NSEvent.Phase)? {
        defer { total = 0; began = false; active = false }
        guard active else { return nil }
        return (began ? total : 0, .ended)
    }

    /// A drag's report for its translation from the start (screen-signed): the distance, once it is toward the
    /// direction and at least the threshold; nothing otherwise. Drags never report .began; release reports .ended, 0.
    static func dragDistance(_ translation: CGFloat, direction: PanDirection, threshold: CGFloat) -> CGFloat? {
        let distance = translation * direction.sign
        return distance >= threshold && distance > 0 ? distance : nil
    }

    /// A scroll event's movement along the axis, or nil when the other axis dominates (it must be 1.5×). Mouse-wheel
    /// (non-precise) deltas count 8×; with `normalize`, the sign follows the fingers whatever natural scrolling is.
    static func scrollDelta(dx: CGFloat, dy: CGFloat, precise: Bool, invertedFromDevice: Bool, normalize: Bool,
                            vertical: Bool) -> CGFloat? {
        let along = vertical ? dy : dx, across = vertical ? dx : dy
        guard abs(along) >= abs(across) * 1.5 else { return nil }
        var delta = precise ? along : along * 8
        if normalize && !invertedFromDevice { delta = -delta }
        return delta
    }
}
