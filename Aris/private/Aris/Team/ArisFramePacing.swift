//
//  ArisFramePacing.swift
//  Aris
//
//  Task 9's smoothness bar, counted the same way offline (synthetic display-link ticks) and on the real app (the
//  animator's frame log): frames late by more than 1.5 frames, the path's error, and per-frame displacement outliers.
//  Pure.
//

import CoreGraphics

enum ArisFramePacing {
    /// Ticks of a display running at `rate` Hz from `start`, covering `duration` seconds.
    static func ticks(start: Double, rate: Double, through duration: Double) -> [Double] {
        let n = Int((duration * rate).rounded(.up))
        return (0...max(0, n)).map { start + Double($0) / rate }
    }

    /// Gaps between consecutive timestamps longer than 1.5 × the frame duration.
    static func lateFrames(_ timestamps: [Double], frameDuration: Double) -> Int {
        zip(timestamps, timestamps.dropFirst()).filter { $1 - $0 > 1.5 * frameDuration }.count
    }

    /// The farthest the keyframes, linear between them as the render server plays them, stray from `exact` at `times`.
    static func pathError(keyframes: [ArisTravelKeyframe], at times: [Double], exact: (Double) -> CGPoint) -> CGFloat {
        guard let first = keyframes.first, let last = keyframes.last else { return .infinity }
        return times.reduce(0) { worst, t in
            let p: CGPoint
            if t <= first.time { p = first.pose.position } else if t >= last.time { p = last.pose.position } else {
                var lo = 0, hi = keyframes.count - 1
                while hi - lo > 1 { let mid = (lo + hi) / 2; if keyframes[mid].time <= t { lo = mid } else { hi = mid } }
                let a = keyframes[lo], b = keyframes[hi], f = CGFloat((t - a.time) / (b.time - a.time))
                p = CGPoint(x: a.pose.position.x + (b.pose.position.x - a.pose.position.x) * f,
                            y: a.pose.position.y + (b.pose.position.y - a.pose.position.y) * f)
            }
            let e = exact(t)
            return max(worst, hypot(p.x - e.x, p.y - e.y))
        }
    }

    /// Jumps: a frame whose displacement is more than twice both its neighbours' (and over half a point), or a frame
    /// that repeats the last in the middle of the motion (both neighbours moving on in about the same direction; a real
    /// stop, such as a hop's contact, turns).
    static func jumps(_ positions: [CGPoint]) -> [Int] {
        let v = zip(positions, positions.dropFirst()).map { CGVector(dx: $1.x - $0.x, dy: $1.y - $0.y) }
        let d = v.map { hypot($0.dx, $0.dy) }
        guard d.count >= 3 else { return [] }
        func onward(_ a: CGVector, _ b: CGVector) -> Bool {
            let la = hypot(a.dx, a.dy), lb = hypot(b.dx, b.dy)
            return la > 0.5 && lb > 0.5 && (a.dx * b.dx + a.dy * b.dy) / (la * lb) > 0.5
        }
        return (1..<(d.count - 1)).filter { i in
            (d[i] > 0.5 && d[i] > 2 * max(d[i - 1], d[i + 1])) || (d[i] < 0.01 && onward(v[i - 1], v[i + 1]))
        }.map { $0 + 1 }
    }
}
