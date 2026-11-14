//
//  ArisSideMorph.swift
//  Aris
//
//  One morph of the side notch's outline as Core Animation runs it: every point slides in a straight line from where it
//  was to where it goes, by the timing curve's eased progress (a CABasicAnimation of a path whose points match). The
//  wash, the content's mask and the rim run as such animations on the render server; the glass under them can only be
//  given its outline from the main thread, frame by frame. It used to be given the outline on screen *now*
//  (`presentation()`), which is the frame before the one being drawn: closing, the glass stood up to a frame's travel
//  (some 35 points at 60 Hz mid-close) outside the wash, and that strip of bare glass, its lit edge and lensing showed
//  as a silver flash running in with the edge. A glass and a wash drawn from the same sample in the same
//  frame never show any. Here the glass is sampled from this morph at the moment the frame is shown, and while
//  the outline shrinks the wash starts two frames late and the glass is sampled three frames ahead (the glass's own
//  outline reaches the screen up to two frames late), so it is never outside the wash. CoreGraphics only.
//

import CoreGraphics
import QuartzCore

struct ArisSideMorph {
    let from: [CGPoint]
    let to: [CGPoint]
    /// In CACurrentMediaTime()'s clock.
    let begin: CFTimeInterval
    let timing: ArisSideLook.Timing

    init?(from: CGPath, to: CGPath, begin: CFTimeInterval, timing: ArisSideLook.Timing) {
        let a = Self.points(of: from), b = Self.points(of: to)
        guard !a.isEmpty, a.count == b.count else { return nil }
        self.from = a
        self.to = b
        self.begin = begin
        self.timing = timing
    }

    var end: CFTimeInterval { begin + timing.duration }

    /// The outline grows smaller (it closes or goes in): its box at the end has less room than at the start.
    var shrinks: Bool {
        func area(_ points: [CGPoint]) -> CGFloat {
            let xs = points.map(\.x), ys = points.map(\.y)
            return ((xs.max() ?? 0) - (xs.min() ?? 0)) * ((ys.max() ?? 0) - (ys.min() ?? 0))
        }
        return area(to) < area(from)
    }

    /// The eased progress at `time`, 0 before the morph and 1 after it.
    func progress(at time: CFTimeInterval) -> Double {
        guard timing.duration > 0 else { return 1 }
        return ArisSideLook.eased((time - begin) / timing.duration, timing)
    }

    func points(at time: CFTimeInterval) -> [CGPoint] {
        let p = CGFloat(progress(at: time))
        return zip(from, to).map { a, b in CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p) }
    }

    func path(at time: CFTimeInterval) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points(at: time))
        path.closeSubpath()
        return path
    }

    /// When the glass's outline for a frame shown at `shown` is taken: then, or `glassLead` frames later while the
    /// outline shrinks (the glass then sits inside the wash, never outside it).
    func glassTime(shown: CFTimeInterval, frame: CFTimeInterval) -> CFTimeInterval {
        shrinks ? shown + Double(Self.glassLead) * max(0, frame) : shown
    }

    /// A glass outline set from the main thread reaches the screen up to two frames after the wash's own frame
    /// (thirteenth VM pass: at the start of a close the glass kept the open outline for two frames, 33 ms at 60 Hz,
    /// while the wash already shrank). So a shrinking morph's wash, mask and rim start `washDelay` frames after the
    /// glass is first given its outline, and the glass is sampled `glassLead` frames ahead: one frame's travel inside
    /// the wash, which covers it. Growing morphs keep the glass on the frame's own outline (the wash then covers the
    /// glass's lag) and start at once.
    static let washDelay = 2
    static let glassLead = 3

    /// When a morph from `from` to `to` that is asked for at `now` starts on screen: later by `washDelay` frames when it
    /// shrinks, at once otherwise.
    static func begin(now: CFTimeInterval, frame: CFTimeInterval, shrinking: Bool) -> CFTimeInterval {
        shrinking ? now + Double(washDelay) * max(0, frame) : now
    }

    /// A polygon's points in order (the outline is lines only; a closing element adds none).
    static func points(of path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: points.append(element.pointee.points[0])
            default: break
            }
        }
        return points
    }
}
