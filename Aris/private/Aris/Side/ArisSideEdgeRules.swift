//
//  ArisSideEdgeRules.swift
//  Aris
//
//  The side notches at an edge two displays share (a laptop and a monitor side by side). The pointer doesn't stop at
//  such an edge, it crosses: so the sliver doesn't come out (and the trackpad doesn't tap) for a pointer that is only
//  passing, on either display. It comes out once the pointer rests at the edge or on the sliver's place for a moment.
//  An edge with nothing beyond it works as before: the sliver is out the moment the pointer reaches it.
//  Also where an open panel is: on the display it was opened on, wherever the pointer has gone since.
//  Foundation only (tested).
//

import Foundation

enum ArisSideEdgeRules {
    /// How far past the edge another display must begin for the edge to count as shared.
    static let reach: CGFloat = 2
    /// How long the pointer rests at a shared edge before the sliver comes out. Crossing takes less.
    static let restAtSharedEdge: TimeInterval = 0.15

    /// Another display continues past this side of `frame` at the pointer's height (`y`, screen coordinates).
    static func isShared(_ edge: ArisSideEdge, of frame: CGRect, at y: CGFloat, displays: [CGRect]) -> Bool {
        let beyond = CGPoint(x: edge == .left ? frame.minX - reach : frame.maxX + reach, y: y)
        return displays.contains { $0.contains(beyond) }
    }

    /// Whether the sliver is out. `near`: the pointer is at the edge or on the sliver's place, and has been for
    /// `restedFor`. At an edge of its own that is enough; at a shared edge it must have rested there.
    static func comesOut(near: Bool, shared: Bool, restedFor: TimeInterval) -> Bool {
        near && (!shared || restedFor >= restAtSharedEdge)
    }

    /// A press in a panel opened Aris's Settings: an open panel folds out of the window's way, but for one the user locked
    /// open.
    static func stepsAside(open: Bool, pinned: Bool) -> Bool { open && !pinned }

    /// The open panel on its display (`frame`): against the edge, centred down the side.
    static func panelRect(_ edge: ArisSideEdge, in frame: CGRect, size: CGSize) -> CGRect {
        let x = edge == .left ? frame.minX : frame.maxX - size.width
        return CGRect(x: x, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }
}
