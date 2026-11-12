//
//  ArisMemoryImportPacing.swift
//  Aris
//
//  설정 › 기억 › 다른 AI에서 가져오기, how the sheet moves, as numbers: which way a step change goes, when each row of
//  the preview starts to rise, how far along an eased curve is at a moment, and a note cut into one sentence a line.
//  The sheet's views (ArisMemoryImportMotion) animate with these same curves, and the offscreen frame strips sample
//  them, so what is drawn frame by frame is what plays. Foundation only (tested).
//

import Foundation

enum ArisMemoryImportPacing {
    /// A cubic-bezier timing curve and how long it runs: the same four numbers SwiftUI's `.timingCurve` takes.
    struct Curve: Equatable {
        let x1: Double, y1: Double, x2: Double, y2: Double
        let duration: Double

        /// How far along the curve is `seconds` after it started (0 before, 1 once it is over).
        func progress(at seconds: Double) -> Double {
            guard duration > 0 else { return 1 }
            let t = min(max(seconds / duration, 0), 1)
            return ArisMemoryImportPacing.bezier(t, x1, y1, x2, y2)
        }
    }

    // MARK: The curves (each named where it is used)

    /// The step change inside the sheet: the morph curve, 220 ms (0.32, 0.72, 0, 1): something already on screen
    /// changing shape, so an ease-in-out family curve, under 300 ms.
    static let step = Curve(x1: 0.32, y1: 0.72, x2: 0, y2: 1, duration: 0.22)
    /// The new step starts 50 ms in, once most of the old one has gone, so the two never read as one double image.
    static let stepDelay = 0.05
    /// The sheet's height between two steps: the notch's resize curve (0.45, 0, 0.55, 1) over the step's 220 ms: a
    /// size changing on screen eases in and out, where the front-loaded morph would read as a jump.
    static let resize = Curve(x1: 0.45, y1: 0, x2: 0.55, y2: 1, duration: 0.22)
    /// How long a whole step change runs: the delay, then the new step's curve.
    static var stepTotal: Double { stepDelay + step.duration }
    /// The step that leaves fades out quicker than the new one comes in: 120 ms ease-out (emil-design-eng: exits
    /// faster than entrances; the settings page swap's ease-out, shortened so it is gone before the new step shows).
    static let leave = Curve(x1: 0, y1: 0, x2: 0.58, y2: 1, duration: 0.12)
    /// A preview row rising in: the house entrance, 340 ms (0.22, 1, 0.36, 1), rows 40 ms apart (the same as the
    /// settings pages' ArisRise).
    static let rise = Curve(x1: 0.22, y1: 1, x2: 0.36, y2: 1, duration: 0.34)
    static let riseGap = 0.04
    /// Only the first rows stagger; the rest come in with the last of them (a long list never trickles in).
    static let riseRows = 6
    /// A tick: the box's fill and border change over 150 ms on Tailwind's default curve (0.4, 0, 0.2, 1).
    static let tick = Curve(x1: 0.4, y1: 0, x2: 0.2, y2: 1, duration: 0.15)
    /// The tick mark drawing itself: 150 ms on the animate skill's strong ease-out (0.23, 1, 0.32, 1).
    static let draw = Curve(x1: 0.23, y1: 1, x2: 0.32, y2: 1, duration: 0.15)
    /// 되돌리기 taking the receipt back: the notch's close, 200 ms (0.45, 0, 0.55, 1).
    static let undo = Curve(x1: 0.45, y1: 0, x2: 0.55, y2: 1, duration: 0.2)
    /// The receipt's check landing: ArisLandingCheck's land, 460 ms (0.34, 1.56, 0.64, 1), the one overshoot allowed
    /// (a check mark landing).
    static let land = Curve(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1, duration: 0.46)
    /// Reduce Motion: every change is a 150 ms fade and nothing moves (the settings window's reduced path).
    static let reduced = Curve(x1: 0, y1: 0, x2: 0.58, y2: 1, duration: 0.15)

    /// How far a new step slides in from the side it comes from, in points: content comes in with 4–6 pt offsets;
    /// a step change says its direction, so a little more.
    static let stepShift = 8.0
    /// How far a row rises: ArisRise's 6 pt.
    static let riseShift = 6.0

    // MARK: Direction and stagger

    /// The steps in the order the sheet goes through them.
    static let order = ["copy", "paste", "preview", "done"]

    /// Whether going from `old` to `new` moves forward (the new step comes in from the right) or back (from the left).
    static func forward(from old: String, to new: String) -> Bool {
        (order.firstIndex(of: new) ?? 0) >= (order.firstIndex(of: old) ?? 0)
    }

    /// When the row at `index` (0 first, in the order shown) starts to rise.
    static func riseDelay(_ index: Int) -> Double { Double(min(max(index, 0), riseRows)) * riseGap }

    // MARK: Words

    /// A note as one sentence a line: cut after a full stop, question or exclamation mark followed by a space. A dot
    /// inside a word (".txt", "3.5") does not cut.
    static func sentences(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            if character.isWhitespace, let previous, ".?!".contains(previous) {
                lines.append(current)
                current = ""
            } else if !(current.isEmpty && character.isWhitespace) {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { lines.append(current) }
        return lines.filter { !$0.isEmpty }
    }

    // MARK: The curve itself

    /// The y of a cubic bezier from (0,0) to (1,1) with control points (x1,y1), (x2,y2), at x = `t` (CSS's
    /// cubic-bezier, solved for x by Newton's method with a bisection fallback).
    static func bezier(_ t: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        func sample(_ s: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
        }
        func slope(_ s: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * a + 6 * u * s * (b - a) + 3 * s * s * (1 - b)
        }
        var s = t
        for _ in 0..<8 {
            let error = sample(s, x1, x2) - t
            if abs(error) < 1e-7 { return sample(s, y1, y2) }
            let d = slope(s, x1, x2)
            if abs(d) < 1e-6 { break }
            s -= error / d
        }
        var low = 0.0, high = 1.0
        s = t
        for _ in 0..<40 {
            let x = sample(s, x1, x2)
            if abs(x - t) < 1e-7 { break }
            if x < t { low = s } else { high = s }
            s = (low + high) / 2
        }
        return sample(s, y1, y2)
    }
}
