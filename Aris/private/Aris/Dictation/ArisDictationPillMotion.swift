//
//  ArisDictationPillMotion.swift
//  Aris
//
//  The pill's moving marks as numbers, without drawing (ArisDictationPillParts draws them), all measured from the
//  reference pill:
//  - the level while listening: 10 bars 2 wide, 2 apart, radius .5, standing 2 tall and scaled by the voice
//    (max(1, 5 × the smoothed level)), by a bulge that is tallest in the middle, and by a 1 s wave
//    (1 → 1.2 → 1.5 → 1.1 → 1.3 → 1, ease-in-out each step) staggered 0.1 s from bar to bar;
//  - the level itself: each sample's dB over an adaptive floor (the quietest seen, never under -60) across 20 dB,
//    averaged every 150 ms, then eased each 60 Hz frame (0.85 of the last, 0.15 of the new, in steps of 0.01);
//  - the spinner while the words are written down and typed: 8 spokes 2 × 5 round 1, 6 out from the centre, each fading
//    .88 → .15 over 1.1 s, one 0.1375 s behind the next;
//  - the cubic curves the pill moves on (CSS cubic-bezier), solved for a time.
//

import CoreGraphics
import Foundation

// MARK: - Curves

/// A CSS cubic-bezier(x1, y1, x2, y2) timing curve: the eased share at a linear share of the time.
struct ArisDictationPillCurve: Equatable {
    let x1: Double, y1: Double, x2: Double, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    /// CSS `ease-in-out`.
    static let easeInOut = ArisDictationPillCurve(0.42, 0, 0.58, 1)
    /// CSS `ease`.
    static let ease = ArisDictationPillCurve(0.25, 0.1, 0.25, 1)

    private static func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    private static func slope(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
    }

    /// The eased share at `x` (0…1) of the time: Newton steps, then halving if they stall.
    func value(at x: Double) -> Double {
        let x = min(1, max(0, x))
        if x == 0 || x == 1 { return x }
        var t = x
        for _ in 0..<8 {
            let error = Self.bezier(t, x1, x2) - x
            if abs(error) < 1e-7 { return Self.bezier(t, y1, y2) }
            let d = Self.slope(t, x1, x2)
            if abs(d) < 1e-6 { break }
            t -= error / d
        }
        var low = 0.0, high = 1.0
        t = x
        for _ in 0..<40 {
            let v = Self.bezier(t, x1, x2)
            if abs(v - x) < 1e-7 { break }
            if v < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return Self.bezier(t, y1, y2)
    }
}

// MARK: - The level's bars

enum ArisDictationPillWave {
    /// Measured from the reference pill (status.js:9372): ten bars.
    static let count = 10
    /// Each bar 2 wide and at least 2 tall, rounded .5 (bars.css:2).
    static let barWidth: CGFloat = 2
    static let baseHeight: CGFloat = 2
    static let barRadius: CGFloat = 0.5
    /// 2 between bars (states.css:368), 4 at each end, 18 tall (states.css:683).
    static let gap: CGFloat = 2
    static let sidePadding: CGFloat = 4
    static let boxHeight: CGFloat = 18
    /// 4 + 10 × 2 + 9 × 2 + 4 = 46.
    static var width: CGFloat { 2 * sidePadding + CGFloat(count) * barWidth + CGFloat(count - 1) * gap }

    /// The bulge (status.js:9412): 1 - (distance from the middle)² × 1/48, so the ends stand .578 of the middle.
    static let bulge = 1.0

    static func heightScale(_ bar: Int, count: Int = count) -> Double {
        let middle = Double(count - 1) / 2
        let distance = abs(middle - Double(bar))
        return max(0, 1 - distance * distance * (bulge / 48))
    }

    /// The wave (bars.css:52): 1 s, these keys, ease-in-out between each two.
    static let period = 1.0
    static let keyframes: [(at: Double, scale: Double)] = [(0, 1), (0.2, 1.2), (0.4, 1.5), (0.8, 1.1), (0.9, 1.3), (1, 1)]
    /// 0.1 s from bar to bar (status.js:9384): the first half later by 0, .1 … .4, the second half earlier by .5 … .1.
    static let stagger = 0.1

    static func delay(_ bar: Int, count: Int = count) -> Double {
        let half = (count + 1) / 2
        return stagger * Double(bar < half ? bar : bar - count)
    }

    /// The wave's factor for `bar` at `t` seconds after it started: 1 before a late bar's start (CSS draws its base
    /// transform until then).
    static func multiplier(at t: Double, bar: Int, count: Int = count) -> Double {
        let local = t - delay(bar, count: count)
        guard local >= 0 else { return 1 }
        let phase = local.truncatingRemainder(dividingBy: period) / period
        for index in 1..<keyframes.count where phase <= keyframes[index].at {
            let a = keyframes[index - 1], b = keyframes[index]
            let share = (phase - a.at) / (b.at - a.at)
            return a.scale + (b.scale - a.scale) * ArisDictationPillCurve.easeInOut.value(at: share)
        }
        return keyframes[keyframes.count - 1].scale
    }

    /// A bar's drawn height: 2 × the voice × the bulge × (the wave while it runs).
    static func height(bar: Int, audioScale: Double, t: Double, waving: Bool) -> CGFloat {
        let wave = waving ? multiplier(at: t, bar: bar) : 1
        return baseHeight * CGFloat(audioScale * heightScale(bar) * wave)
    }

    /// Every bar's height at `t`.
    static func heights(audioScale: Double, t: Double, waving: Bool) -> [CGFloat] {
        (0..<count).map { height(bar: $0, audioScale: audioScale, t: t, waving: waving) }
    }
}

/// The voice's level for the bars, stepped once a frame (a class so the drawing can advance it).
final class ArisDictationPillLevel {
    /// The floor never goes under -60 dB and the level spans 20 dB over it (main.js@E: scale).
    static let floorLimit = -60.0
    static let range = 20.0
    /// Averaged over 150 ms and sent at that pace (main.js: setInterval 150).
    static let window = 0.15
    /// Each 60 Hz frame keeps .85 of the last, takes .15 of the new, in steps of .01 (status.js:10027).
    static let keep = 0.85
    static let quantum = 0.01
    static let frame = 1.0 / 60
    /// The bars' scale is 5 × that, never under 1 (status.js:13206 gain 5, floor on).
    static let gain = 5.0

    private(set) var floor = 0.0
    private(set) var published = 0.0
    private(set) var smoothed = 0.0
    private var samples: [Double] = []
    private var windowStart: Double?
    private var lastFrame: Double?
    /// 60 Hz frames owed (a display at 120 Hz steps every other call, a pause catches up to half a second).
    private var pending = 0.0
    /// When this dictation's level started: the wave's clock.
    private(set) var startedAt: Double?

    /// A new dictation: the floor, the average and the easing start over.
    func reset() {
        floor = 0; published = 0; smoothed = 0
        samples = []; windowStart = nil; lastFrame = nil; pending = 0; startedAt = nil
    }

    /// One sample's level, 0…1, over the adaptive floor.
    func level(db: Double) -> Double {
        if db < floor { floor = max(Self.floorLimit, db) }
        return min(1, max(0, (db - floor) / Self.range))
    }

    /// An RMS (0…1) in dB.
    static func decibels(rms: Double) -> Double { 20 * log10(max(0, rms) + 1e-10) }

    /// One eased frame toward `target`.
    static func ease(_ value: Double, toward target: Double) -> Double {
        (100 * (keep * value + target * (1 - keep))).rounded(.down) / 100
    }

    static func audioScale(_ smoothed: Double) -> Double { max(1, gain * smoothed) }

    /// Takes `rms` at `now` (seconds) and returns the bars' scale.
    @discardableResult
    func step(at now: Double, rms: Double) -> Double {
        if startedAt == nil { startedAt = now }
        let sample = level(db: Self.decibels(rms: rms))
        if let start = windowStart, now - start >= Self.window {
            published = samples.isEmpty ? sample : samples.reduce(0, +) / Double(samples.count)
            samples = []
            windowStart = now
        } else if windowStart == nil {
            windowStart = now
        }
        samples.append(sample)
        // The 60 Hz frames since the last call.
        let elapsed = lastFrame.map { max(0, now - $0) } ?? Self.frame
        lastFrame = now
        pending = min(30, pending + elapsed / Self.frame + 1e-9)
        let frames = Int(pending)
        pending -= Double(frames)
        for _ in 0..<frames { smoothed = Self.ease(smoothed, toward: published) }
        return Self.audioScale(smoothed)
    }
}

// MARK: - The spinner

enum ArisDictationPillSpinner {
    /// Where the words are: written down, going in, typed (the pill shows the spinner for each).
    enum Stage: Equatable {
        case charging
        case releasing
        case done
    }

    /// Measured from the reference pill (spinner.css:2): a 16 box, 8 spokes 2 × 5 round 1, each 6 from the centre.
    static let size: CGFloat = 16
    static let spokes = 8
    static let spokeWidth: CGFloat = 2
    static let spokeLength: CGFloat = 5
    static let spokeRadius: CGFloat = 1
    static let reach: CGFloat = 6
    /// rgb(163, 148, 199), fading .88 → .15 in 1.1 s, linear (spinner.css:10, 30).
    static let red = 163.0 / 255, green = 148.0 / 255, blue = 199.0 / 255
    static let brightest = 0.88
    static let faintest = 0.15
    static let period = 1.1
    /// One spoke 0.1375 s behind the next (status.js:8963): delay -0.1375 × (7 - spoke).
    static let lag = 0.1375

    static func delay(_ spoke: Int) -> Double { -lag * Double(spokes - 1 - spoke) }

    /// A spoke's angle from the top, clockwise.
    static func angle(_ spoke: Int) -> Double { 45 * Double(spoke) }

    /// A spoke's opacity `t` seconds in.
    static func alpha(_ spoke: Int, at t: Double) -> Double {
        let local = t - delay(spoke)
        let phase = (local.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period) / period
        return brightest + (faintest - brightest) * phase
    }
}
