//
//  ArisNotchShape.swift
//  Aris
//
//  The notch's outline: a concave flare at each top corner (where the notch meets the menu bar), straight sides,
//  convex bottom corners. Every corner is one cubic Bézier whose control points sit a fraction `handle` of the way
//  from its ends toward the corner's sharp vertex: 2/3 at circularity 0 (a tighter, squircle-like turn), the
//  circle constant at circularity 1. The three inputs animate, so closed and open morph into each other. The user's rim
//  (ArisRimOutline) traces the same corners as a polyline.
//
//  The notch draws it at circularity 1 in every state: quarter-circle cubics with κ = 0.5522847498307936, the two
//  top ones concave, and each radius held to min(r, width / 4, height / 2). The path always has the same elements
//  (four curves, four lines), so one state's outline slides into another's point by point.
//

import SwiftUI

struct NotchShape: Shape, Equatable {
    /// The circle constant 4/3 · (√2 − 1): control points at this fraction draw a
    /// near-circular quarter arc.
    static let circleHandle: CGFloat = 0.5522847498307936
    static let squircleHandle: CGFloat = 2.0 / 3.0

    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var circular: CGFloat

    init(topCornerRadius: CGFloat? = nil, bottomCornerRadius: CGFloat? = nil, circular: CGFloat = 0) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
        self.circular = circular
    }

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(topCornerRadius, AnimatablePair(bottomCornerRadius, circular)) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second.first
            circular = newValue.second.second
        }
    }

    /// Where the corner control points sit, between the squircle and the circle.
    var handle: CGFloat {
        let blend = min(1, max(0, circular))
        return Self.squircleHandle + (Self.circleHandle - Self.squircleHandle) * blend
    }

    /// The radii as drawn in `rect`: never more than a quarter of the width or half the height, so
    /// a notch too small for its corners (mid-way through closing, or a flat one) keeps a clean outline.
    func radii(in rect: CGRect) -> (top: CGFloat, bottom: CGFloat) {
        let most = max(0, min(rect.width / 4, rect.height / 2))
        return (min(max(0, topCornerRadius), most), min(max(0, bottomCornerRadius), most))
    }

    func path(in rect: CGRect) -> Path {
        let (top, bottom) = radii(in: rect), h = handle
        var path = Path()
        var pen = CGPoint(x: rect.minX, y: rect.minY)
        path.move(to: pen)
        func turn(to end: CGPoint, around vertex: CGPoint) {
            path.addCurve(to: end,
                          control1: CGPoint(x: pen.x + (vertex.x - pen.x) * h, y: pen.y + (vertex.y - pen.y) * h),
                          control2: CGPoint(x: end.x + (vertex.x - end.x) * h, y: end.y + (vertex.y - end.y) * h))
            pen = end
        }
        func straight(to end: CGPoint) {
            path.addLine(to: end)
            pen = end
        }
        let left = rect.minX + top, right = rect.maxX - top
        turn(to: CGPoint(x: left, y: rect.minY + top), around: CGPoint(x: left, y: rect.minY))
        straight(to: CGPoint(x: left, y: rect.maxY - bottom))
        turn(to: CGPoint(x: left + bottom, y: rect.maxY), around: CGPoint(x: left, y: rect.maxY))
        straight(to: CGPoint(x: right - bottom, y: rect.maxY))
        turn(to: CGPoint(x: right, y: rect.maxY - bottom), around: CGPoint(x: right, y: rect.maxY))
        straight(to: CGPoint(x: right, y: rect.minY + top))
        turn(to: CGPoint(x: rect.maxX, y: rect.minY), around: CGPoint(x: right, y: rect.minY))
        // Back along the top edge; left open (not closeSubpath), so a stroke meets the start without a join.
        straight(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }

    /// The outline as points from the left shoulder's tip to the right one (never along the top edge), for the rim.
    func outlinePoints(in rect: CGRect) -> [CGPoint] {
        let (top, bottom) = radii(in: rect)
        return ArisRimOutline.points(in: rect, top: top, bottom: bottom, handle: handle)
    }
}
