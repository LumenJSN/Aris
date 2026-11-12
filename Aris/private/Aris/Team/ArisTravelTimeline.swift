//
//  ArisTravelTimeline.swift
//  Aris
//
//  A trip in time. The hop plays its legs one at a time, each in 0.42 s with a contact between and a landing at the
//  end; a glide plays them all as one curve (ArisGlideCurve) on one easing, then settles: G rocking, G1 squashing about
//  the feet as its sparkle pops. The animator hands the keyframes to the render server whole, so nothing is computed
//  per frame. Pure.
//

import CoreGraphics

/// Something the animator plays: a pose for every moment of a fixed duration (a trip, or the 낑낑 strain clip).
protocol ArisMotionTrack {
    var duration: Double { get }
    func pose(at time: Double) -> ArisTravelPose
    /// What the render server plays, linear between keyframes.
    func keyframes(rate: Double) -> [ArisTravelKeyframe]
    /// When G1's sparkle pops (touchdown); nil for a track without one.
    var sparkleTime: Double? { get }
}

extension ArisMotionTrack {
    var sparkleTime: Double? { nil }

    /// Evenly spaced, 0 to the end.
    func keyframes(rate: Double) -> [ArisTravelKeyframe] {
        guard duration > 0 else { return [ArisTravelKeyframe(time: 0, pose: pose(at: 0))] }
        let n = max(1, Int((duration * rate).rounded(.up)))
        return (0...n).map { i in let t = duration * Double(i) / Double(n); return ArisTravelKeyframe(time: t, pose: pose(at: t)) }
    }
}

struct ArisTravelKeyframe: Equatable {
    let time: Double
    let pose: ArisTravelPose
}

struct ArisTravelTimeline: ArisMotionTrack {
    /// Keyframes a second: linear between them, they stay within hundredths of a point of the path at 60 and 120 Hz.
    static let keyRate = 240.0

    let legs: [ArisTravelLeg]
    let style: ArisTravelStyle
    /// When each leg begins.
    let starts: [Double]
    let duration: Double
    /// The glide's: its curve over every leg, the slide's time (before the settle), its direction.
    private let glide: ArisGlideCurve?
    private let slide: Double
    private let direction: Double

    init(_ legs: [ArisTravelLeg], style: ArisTravelStyle) {
        self.legs = legs
        self.style = style
        switch style {
        case .glide, .glidePop:
            let curve = ArisGlideCurve(legs), slide = legs.isEmpty ? 0 : ArisGlidePath.slideDuration(legs)
            glide = curve
            self.slide = slide
            direction = legs.first.flatMap { f in legs.last.map { ArisGlidePath.direction(from: f.start, to: $0.end) } } ?? 0
            let ease = style == .glidePop ? ArisGlideLanding.ease : ArisGlidePath.ease
            starts = curve.legStarts.map { ArisGlidePath.uneased($0, ease: ease) * slide }
            duration = legs.isEmpty ? 0 : slide + style.arrival
        case .hop:
            glide = nil
            slide = 0
            direction = 0
            var t = 0.0
            var starts: [Double] = []
            for (i, leg) in legs.enumerated() {
                starts.append(t)
                t += style.duration(of: leg) + (i < legs.count - 1 ? style.pause : 0)
            }
            self.starts = starts
            duration = legs.isEmpty ? 0 : t + style.arrival
        }
    }

    /// G1's touchdown, where its sparkle pops.
    var sparkleTime: Double? { style == .glidePop && !legs.isEmpty ? slide : nil }

    func pose(at time: Double) -> ArisTravelPose {
        guard let first = legs.first, let last = legs.last else { return ArisTravelPose(position: .zero) }
        if let glide { return glidePose(glide, at: time, last: last) }
        guard time > 0 else { return style.pose(in: first, progress: 0) }
        if time >= duration { return style.arrivalPose(after: last, progress: 1) }
        let i = starts.lastIndex { $0 <= time } ?? 0
        let leg = legs[i], local = time - starts[i], length = style.duration(of: leg)
        if local < length - 1e-9 { return style.pose(in: leg, progress: local / length) }
        if i < legs.count - 1 { return style.pausePose(after: leg, progress: style.pause > 0 ? (local - length) / style.pause : 1) }
        return style.arrivalPose(after: leg, progress: style.arrival > 0 ? (local - length) / style.arrival : 1)
    }

    /// A glide: on the curve at the eased time, leaning; then on the perch, rocking (G) or squashing about the feet
    /// (G1); turning to face the way it goes over the first moments and back to the front as it settles.
    private func glidePose(_ curve: ArisGlideCurve, at time: Double, last: ArisTravelLeg) -> ArisTravelPose {
        if time >= duration { return ArisTravelPose(position: last.end) }
        let t = max(0, time), pops = style == .glidePop, settle = style.arrival
        let facing = { (turned: Double) in CGFloat(self.direction) * ArisGlidePath.facing * CGFloat(ArisEase.symmetric(min(1, max(0, turned)))) }
        if t < slide {
            let u = t / slide
            let s = pops ? ArisGlideLanding.ease(u) : ArisGlidePath.ease(u)
            let lean = pops ? ArisGlideLanding.lean(direction: direction, progress: u) : ArisGlidePath.lean(direction: direction, progress: u)
            return ArisTravelPose(position: curve.position(at: s), rotation: lean, yaw: facing(t / ArisGlidePath.turnIn))
        }
        let settled = t - slide, yaw = facing((settle - settled) / ArisGlidePath.turnOut)
        if pops {
            let squash = ArisGlideLanding.squash(progress: settled / settle)
            return ArisTravelPose(position: last.end, scaleX: squash.x, scaleY: squash.y, yaw: yaw)
        }
        return ArisTravelPose(position: last.end, rotation: ArisGlidePath.rock(direction: direction, progress: settled / settle), yaw: yaw)
    }

    /// Evenly spaced keyframes from 0 to the end, plus one at each leg's start and end (for the hop, where the motion
    /// turns: linear between keyframes, a corner cut there would stray most of a point off the path), a step wherever
    /// a leg starts somewhere else than the last one ended (displays apart), so the character never slides across a
    /// display, and one at G1's touchdown, so it is pressed at that instant, not over a keyframe's time before it.
    func keyframes(rate: Double) -> [ArisTravelKeyframe] {
        guard duration > 0 else { return legs.isEmpty ? [] : [ArisTravelKeyframe(time: 0, pose: pose(at: 0))] }
        let n = max(1, Int((duration * rate).rounded(.up)))
        var times = (0...n).map { duration * Double($0) / Double(n) }
        var steps: [Double: ArisTravelPose] = [:]
        if let touchdown = sparkleTime { times += [touchdown - 1e-6, touchdown] }
        for (i, leg) in legs.enumerated() {
            if glide == nil { times += [starts[i], starts[i] + style.duration(of: leg)] }
            if i > 0, leg.start != legs[i - 1].end {
                times += [starts[i] - 1e-6, starts[i]]
                var after = pose(at: starts[i])
                after.position = leg.start
                steps[starts[i]] = after
            }
        }
        let sorted = times.sorted()
        let kept = zip(sorted.indices, sorted).filter { $0.0 == 0 || $0.1 - sorted[$0.0 - 1] > 1e-9 }.map(\.1)
        return kept.map { ArisTravelKeyframe(time: $0, pose: steps[$0] ?? pose(at: $0)) }
    }

    /// The displays the character's box touches at some point of `track` (each needs a copy of it for the crossing).
    static func screensTouched(_ track: ArisMotionTrack, size: CGFloat, screens: [CGRect]) -> Set<Int> {
        let n = max(1, Int((track.duration * keyRate).rounded(.up)))
        return (0...n).reduce(into: Set<Int>()) { touched, i in
            touched.formUnion(screensTouched(at: track.pose(at: track.duration * Double(i) / Double(n)).position, size: size, screens: screens))
        }
    }

    /// The displays a box of `size` centred on `p` overlaps.
    static func screensTouched(at p: CGPoint, size: CGFloat, screens: [CGRect]) -> Set<Int> {
        let box = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        return Set(screens.indices.filter { let o = screens[$0].intersection(box); return !o.isNull && o.width > 0 && o.height > 0 })
    }

    /// The display holding the character's centre at `time`; nil while it is between displays.
    static func hostScreen(_ track: ArisMotionTrack, at time: Double, screens: [CGRect]) -> Int? {
        let p = track.pose(at: time).position
        return screens.firstIndex { $0.minX <= p.x && p.x <= $0.maxX && $0.minY <= p.y && p.y <= $0.maxY }
    }
}

/// A copy of the character in another display's panel plays the sprite's own animations on the same clock.
enum ArisTravelCopy {
    /// A copied animation's begin time in the copy's time space: the same moment in media time as the source's.
    static func beginTime(sourceBegin: Double, sourceToMedia: (Double) -> Double, mediaToCopy: (Double) -> Double) -> Double {
        mediaToCopy(sourceToMedia(sourceBegin))
    }
}
