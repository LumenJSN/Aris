//
//  ArisGestureDetector.swift
//  Aris
//
//  Spots a circle or a scribble in the pointer path while the user holds the talk key: `feed` takes each
//  pointer move and `detect` scans the recent path.
//  Circles fire on closure: the moment the pointer comes back to touch a point a near-full lap of turning behind
//  it. Scribbles are sharp back-and-forth reversals in the last 2.2 s. Pure, so the tests run it.
//
//  Coordinates are points on one display, in either orientation (the scan only uses turn magnitudes).
//  The caller feeds a point only when the pointer moved: the cursor pump skips a tick
//  whose position equals the last one. That keeps a motionless click from clearing the buffer.
//

import CoreGraphics
import Foundation

struct ArisGesturePoint: Equatable {
    var x, y: CGFloat
    var t: Double // ms
}

enum ArisGestureKind: String {
    case circle, scribble
}

struct ArisGesture: Equatable {
    let kind: ArisGestureKind
    let bbox: CGRect
    let points: [ArisGesturePoint]
}

struct ArisGestureDetector {
    private typealias C = ArisGestureConstants.Detector

    /// Off: points are not even kept.
    var enabled = true
    /// The mouse button is down. A move while it is down is a drag, not a gesture, and clears the buffer.
    var pointerDown = false
    /// The decimated, recent path the detector looks at.
    private(set) var points: [ArisGesturePoint] = []
    private var cooldownUntil = -Double.infinity
    /// The size ceiling: this display's diagonal.
    private let maxDiag: CGFloat

    init(displaySize: CGSize) {
        maxDiag = hypot(displaySize.width, displaySize.height)
    }

    /// One accepted pointer move. Returns a gesture when one completes.
    mutating func feed(x: CGFloat, y: CGFloat, t: Double) -> ArisGesture? {
        guard enabled else { return nil }
        if pointerDown { points.removeAll(); return nil }
        if t < cooldownUntil { points.removeAll(); return nil }
        if let last = points.last, hypot(x - last.x, y - last.y) < C.decimate { return nil }
        points.append(ArisGesturePoint(x: x, y: y, t: t))
        let cutoff = t - C.windowMs
        let firstRecent = points.firstIndex { $0.t >= cutoff } ?? points.count
        if firstRecent > 0 { points.removeFirst(firstRecent) }
        if points.count > C.maxPoints { points.removeFirst(points.count - C.maxPoints) }
        guard let gesture = Self.detect(points, maxDiag: maxDiag) else { return nil }
        points.removeAll()
        cooldownUntil = t + C.cooldownMs
        return gesture
    }

    // MARK: - Detection

    static func detect(_ pts: [ArisGesturePoint], maxDiag: CGFloat) -> ArisGesture? {
        guard pts.count >= C.minPoints else { return nil }
        let angles = headings(pts)
        return circle(pts, angles: angles, maxDiag: maxDiag) ?? scribble(pts, angles: angles, maxDiag: maxDiag)
    }

    /// Per-point direction of the segment ENDING at that point; segments under 1 pt keep the previous one.
    private static func headings(_ pts: [ArisGesturePoint]) -> [Double] {
        var angles = [Double](repeating: .nan, count: pts.count)
        for i in 1..<pts.count {
            let dx = Double(pts[i].x - pts[i - 1].x), dy = Double(pts[i].y - pts[i - 1].y)
            angles[i] = hypot(dx, dy) < C.headingMinSegment ? angles[i - 1] : atan2(dy, dx)
        }
        return angles
    }

    /// The closure scan, newest point backwards.
    private static func circle(_ pts: [ArisGesturePoint], angles: [Double], maxDiag: CGFloat) -> ArisGesture? {
        let n = pts.count, last = pts[n - 1]
        var acc = 0.0
        var minX = last.x, minY = last.y, maxX = last.x, maxY = last.y
        var lapCapIdx = -1
        for i in stride(from: n - 2, through: 0, by: -1) {
            let prevAngle = angles[i].isNaN ? angles[i + 1] : angles[i]
            let turnIn = norm(angles[i + 1] - prevAngle)
            if turnIn.isFinite && abs(turnIn) >= C.sharpRad { break }
            if turnIn.isFinite { acc += turnIn }
            let p = pts[i]
            minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            if abs(acc) < C.closeRad { continue }
            if lapCapIdx < 0 && abs(acc) >= C.lapCap { lapCapIdx = i }
            let diag = hypot(maxX - minX, maxY - minY)
            if diag < C.diagMin || diag > maxDiag { continue }
            if hypot(last.x - p.x, last.y - p.y) > closeTolerance(diag) { continue }
            // Clamp to one lap, cut any teleport gap, recompute the box from the final stroke, seal the seam.
            var startIdx = lapCapIdx >= 0 ? max(i, lapCapIdx) : i
            for g in stride(from: n - 1, to: startIdx, by: -1)
            where hypot(pts[g].x - pts[g - 1].x, pts[g].y - pts[g - 1].y) > C.strokeMaxGap {
                startIdx = g
                break
            }
            var stroke = Array(pts[startIdx...])
            if stroke.count < 3 { continue }
            let box = bounds(stroke)
            if hypot(last.x - stroke[0].x, last.y - stroke[0].y) <= closeTolerance(hypot(box.width, box.height)) * C.seamSeal {
                stroke.append(ArisGesturePoint(x: stroke[0].x, y: stroke[0].y, t: last.t))
            }
            return ArisGesture(kind: .circle, bbox: box, points: stroke)
        }
        return nil
    }

    /// Sharp reversals over the recent slice only.
    private static func scribble(_ pts: [ArisGesturePoint], angles: [Double], maxDiag: CGFloat) -> ArisGesture? {
        let n = pts.count, last = pts[n - 1]
        let cutoff = last.t - C.scribbleWindowMs
        var start = n - 1
        while start > 0 && pts[start - 1].t >= cutoff { start -= 1 }
        if n - start < C.minPoints { return nil }
        var pathLen: CGFloat = 0
        var sharpTurns = 0, firstSharpIdx = -1
        for i in (start + 1)..<n {
            pathLen += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            guard i > start + 1 else { continue }
            let turn = norm(angles[i] - angles[i - 1])
            if turn.isFinite && abs(turn) >= C.sharpRad {
                sharpTurns += 1
                if firstSharpIdx < 0 { firstSharpIdx = i }
            }
        }
        let box = bounds(Array(pts[start...]))
        let diag = hypot(box.width, box.height)
        if diag < C.diagMin || diag > maxDiag { return nil }
        if pathLen < C.scribblePathMin { return nil }
        if sharpTurns < C.sharpMin || pathLen / diag < C.ratioMin { return nil }
        let stroke = Array(pts[max(start, firstSharpIdx - 4)...])
        return ArisGesture(kind: .scribble, bbox: bounds(stroke), points: stroke)
    }

    /// Into (-pi, pi]. NaN stays NaN.
    private static func norm(_ d: Double) -> Double {
        var d = d
        while d > .pi { d -= 2 * .pi }
        while d <= -.pi { d += 2 * .pi }
        return d
    }

    private static func closeTolerance(_ diag: CGFloat) -> CGFloat {
        min(C.closeTolMax, max(C.closeTolMin, diag * C.closeTolFrac))
    }

    private static func bounds(_ stroke: [ArisGesturePoint]) -> CGRect {
        guard let first = stroke.first else { return .null }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for q in stroke {
            minX = min(minX, q.x); minY = min(minY, q.y); maxX = max(maxX, q.x); maxY = max(maxY, q.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
