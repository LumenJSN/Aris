//
//  ArisDictationPillMotion.swift
//  Aris
//
//  The pill's two moving marks, as measured, without drawing (ArisDictationPillParts draws them):
//  - the level while listening: 7 bars 2.5 wide with 1.5 either side in an 18-tall slot, 2 to 17 tall, a new height every
//    58 ms entering on the right, grey 110 → white by (height)^1.5; the same gate / root / knee / attack / release / gain /
//    jitter as the notch's bars;
//  - the ring while the words are written down and typed: 16 across, stroke 2.5, track white .045, arc grey 185, from
//    the top clockwise with round caps. It charges toward 0.975 at a pace set by how long the recording was, sweeps on
//    with a jerk-limited spring once the words are in hand (target 1.05), fills when they are typed, and holds 100 ms.
//

import CoreGraphics
import Foundation

enum ArisDictationPillRing {
    enum Stage: Equatable {
        /// Whisper is writing the words down.
        case charging
        /// The words are in hand and going in.
        case releasing
        /// Typed: full, for the hold.
        case done
    }

    static let size: CGFloat = 16
    static let stroke: CGFloat = 2.5
    static let trackWhite = 0.045
    static let arcGrey = 185.0 / 255
    static let completeHold: Duration = .milliseconds(100)

    static let joinSeconds = 0.4
    static let asymptote = 0.975
    static let settleSeconds = 0.25
    static let cruiseEnd = 0.88
    /// Recording seconds → seconds the charge takes to reach the cruise's end.
    static let anchors: [(Double, Double)] = [(0, 1.6), (10, 1.6), (22.5, 1.7), (45, 2.25), (90, 2.6), (180, 4.8), (600, 12)]
    static let releaseTarget = 1.05
    static let releaseResponse = 20.0
    static let releaseMaxAcceleration = 16.0
    static let releaseMaxJerk = 240.0

    static func opening(_ t: Double) -> Double { 0.75 * (1 - exp(-t / 0.3)) + 0.225 * (1 - exp(-t / 1.5)) }
    static let joinProgress = opening(joinSeconds)
    static let joinVelocity = 0.75 / 0.3 * exp(-joinSeconds / 0.3) + 0.225 / 1.5 * exp(-joinSeconds / 1.5)
    static let joinAcceleration = -8.333333333333334 * exp(-joinSeconds / 0.3) - 0.225 / (1.5 * 1.5) * exp(-joinSeconds / 1.5)

    struct Profile: Equatable {
        let target: Double
        let cruiseVelocity: Double
    }

    static func profile(recordingSeconds: Double) -> Profile {
        let seconds = recordingSeconds.isFinite ? max(0, recordingSeconds) : 0
        var target = anchors[anchors.count - 1].1
        for index in 1..<anchors.count where seconds <= anchors[index].0 {
            let (s0, t0) = anchors[index - 1], (s1, t1) = anchors[index]
            target = t0 + (seconds - s0) / (s1 - s0) * (t1 - t0)
            break
        }
        let s = settleSeconds
        let velocity = (cruiseEnd - joinProgress - joinVelocity * s / 2 - joinAcceleration * s * s / 12) / (target - joinSeconds - s / 2)
        return Profile(target: target, cruiseVelocity: velocity)
    }

    static func settling(_ elapsed: Double, cruise: Double) -> Double {
        let u = elapsed / settleSeconds, s = settleSeconds
        return s * (joinVelocity * (u - pow(u, 3) + pow(u, 4) / 2)
                    + s * joinAcceleration * (u * u / 2 - 2 * pow(u, 3) / 3 + pow(u, 4) / 4)
                    + cruise * (pow(u, 3) - pow(u, 4) / 2))
    }

    /// The charge `t` seconds after the recording ended.
    static func charge(at t: Double, profile p: Profile) -> Double {
        let t = max(0, t)
        if t <= joinSeconds { return opening(t) }
        let past = t - joinSeconds
        if past < settleSeconds { return joinProgress + settling(past, cruise: p.cruiseVelocity) }
        if t < p.target { return cruiseEnd - p.cruiseVelocity * (p.target - t) }
        let room = asymptote - cruiseEnd
        return cruiseEnd + 2 * room / .pi * atan(.pi * p.cruiseVelocity * (t - p.target) / (2 * room))
    }

    struct Release: Equatable {
        let progress: Double
        let velocity: Double
        let acceleration: Double
        let done: Bool
    }

    static func release(progress: Double, velocity: Double, dt: Double, acceleration: Double) -> Release {
        let step = max(0, min(0.05, dt))
        let wanted = (releaseTarget - progress) * releaseResponse
        let pull = step > 0 ? (wanted - velocity) / step : 0
        let goal = max(-releaseMaxAcceleration, min(releaseMaxAcceleration, pull))
        let current = max(-releaseMaxAcceleration, min(releaseMaxAcceleration, acceleration))
        let jerk = releaseMaxJerk * step
        let next = current + max(-jerk, min(jerk, goal - current))
        let speed = max(0, velocity + next * step)
        let moved = progress + speed * step
        return Release(progress: moved >= 1 ? 1 : moved, velocity: speed, acceleration: next, done: moved >= 1)
    }

    /// The drawn share of the arc, its round caps taken off so it never looks fuller than it is.
    static func cappedArc(_ progress: Double, circumference: Double, stroke: Double) -> Double {
        let p = max(0, min(1, progress))
        if circumference <= 0 || p == 1 { return p }
        return max(0, p - max(0, stroke) / circumference)
    }

    static var circumference: Double { 2 * .pi * Double((size - stroke) / 2) }
}

/// The ring's state between frames (a class so the drawing can advance it).
final class ArisDictationPillRingMotion {
    private(set) var progress = 0.0
    private var velocity = 0.0
    private var acceleration = 0.0
    private var started: Double?
    private var lastFrame: Double?
    private(set) var swept = false
    let profile: ArisDictationPillRing.Profile

    init(recordingSeconds: Double) {
        profile = ArisDictationPillRing.profile(recordingSeconds: recordingSeconds)
    }

    /// Advances to `now` (seconds) in `stage`; returns the arc's drawn share.
    @discardableResult
    func step(at now: Double, stage: ArisDictationPillRing.Stage) -> Double {
        if started == nil { started = now }
        let dt = lastFrame.map { max(1.0 / 240, min(0.1, now - $0)) } ?? 1.0 / 60
        lastFrame = now
        let previous = progress, previousVelocity = velocity
        var next: Double
        var springing = false
        switch stage {
        case .done:
            next = 1
            springing = true
            swept = true
        case .releasing:
            let r = ArisDictationPillRing.release(progress: previous, velocity: previousVelocity, dt: dt, acceleration: acceleration)
            next = r.progress
            velocity = r.velocity
            acceleration = r.acceleration
            springing = true
            if r.done { swept = true }
        case .charging:
            next = max(previous, ArisDictationPillRing.charge(at: now - (started ?? now), profile: profile))
        }
        if !springing {
            let speed = max(0, (next - previous) / dt)
            let smoothed = previousVelocity * 0.35 + speed * 0.65
            acceleration = acceleration * 0.35 + (smoothed - previousVelocity) / dt * 0.65
            velocity = smoothed
        }
        progress = next
        return ArisDictationPillRing.cappedArc(next, circumference: ArisDictationPillRing.circumference, stroke: Double(ArisDictationPillRing.stroke))
    }
}

/// The level's bars between frames.
final class ArisDictationPillBars {
    static let count = 7
    static let barWidth: CGFloat = 2.5
    static let gap: CGFloat = 1.5
    static let slotHeight: CGFloat = 18
    static let minHeight: CGFloat = 2
    static let maxHeight: CGFloat = 17
    static let tick = 0.058
    static let greyFloor = 110.0 / 255
    /// The bars' own width (no outer margins).
    static let width = CGFloat(count) * (barWidth + 2 * gap)

    private(set) var heights = Array(repeating: minHeight, count: count)
    private var loudness = 0.0
    private var lastTick = 0.0
    private var lastFrame = 0.0

    /// `level` is the listener's 0…1 (RMS × 8); the measured mapping takes raw RMS.
    func step(at now: Double, level: Float, jitter: () -> Double = { Double.random(in: 0.85...1.15) }) {
        if lastFrame > 0, now - lastFrame > 0.25 {
            heights = Array(repeating: Self.minHeight, count: Self.count)
            loudness = 0
        }
        lastFrame = now
        let raw = Double(level) / 8
        let above = max(0, raw - 0.012)
        let root = above > 0 ? above.squareRoot() : 0
        let target = root < 0.08 ? root * root / 0.08 : root
        loudness += (target - loudness) * (target > loudness ? 0.45 : 0.14)
        guard now - lastTick >= Self.tick else { return }
        let drive = min(1, min(1, loudness * 2.4) * (loudness > 0 ? jitter() : 1))
        heights.removeFirst()
        heights.append(Self.minHeight + CGFloat(drive) * (Self.maxHeight - Self.minHeight))
        lastTick = now
    }

    /// A bar's grey, 110 at rest to white at full height.
    static func grey(_ height: CGFloat) -> Double {
        let normalized = Double(min(1, max(0, (height - minHeight) / (maxHeight - minHeight))))
        return (110 + pow(normalized, 1.5) * (255 - 110)).rounded() / 255
    }
}
