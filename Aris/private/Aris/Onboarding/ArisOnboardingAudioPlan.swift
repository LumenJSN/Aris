//
//  ArisOnboardingAudioPlan.swift
//  Aris
//
//  What the onboarding's sound needs to know about its clips, measured from the decoded samples (mockups/onboarding2/
//  js/audio.js), so picture and sound share one clock and file padding never shifts the sync:
//  - a cue lands its transient ("hit", the first 10 ms window within −12 dB of the peak) or its loudest moment ("peak")
//    exactly on the beat, and a cue more than 80 ms late is dropped;
//  - a voice clip's sentences start on its own pauses (the longest silences between speech runs), so the captions trail
//    the voice by 150 ms;
//  - the mix: voice 0 dB, cues −6 dB, the ambient bed ducked −8 dB under the voice, looped on an equal-power crossfade;
//  - nothing plays while muted or while Aris's microphone listens.
//  Pure: samples in, numbers out.
//

import Foundation

enum ArisOnboardingAudioPlan {
    /// −6 dB relative to the voice.
    static let cueGain: Float = 0.5
    static let ambientGain: Float = 0.55
    /// −8 dB.
    static let duck: Float = 0.4
    /// Seconds of the bed's loop crossfade.
    static let loopFade = 2.0
    /// A cue this late is dropped rather than heard off the beat.
    static let lateLimit = 0.08

    static func dbToAmp(_ db: Double) -> Double { pow(10, db / 20) }

    /// Windowed RMS of a mono signal.
    static func envelope(_ samples: [Float], rate: Double, window: Double) -> [Float] {
        let n = max(1, Int(rate * window))
        var out: [Float] = []
        out.reserveCapacity(samples.count / n)
        var i = 0
        while i + n <= samples.count {
            var s: Float = 0
            for j in i..<(i + n) { s += samples[j] * samples[j] }
            out.append((s / Float(n)).squareRoot())
            i += n
        }
        return out
    }

    struct Meta: Equatable {
        /// The transient, the loudest moment, and the active region (−30 dB), in seconds.
        var hit: Double
        var peak: Double
        var from: Double
        var to: Double
    }

    static func analyse(_ samples: [Float], rate: Double) -> Meta {
        let win = 0.01, env = envelope(samples, rate: rate, window: win)
        guard let peak = env.max(), peak > 0, let peakI = env.firstIndex(of: peak) else { return Meta(hit: 0, peak: 0, from: 0, to: Double(samples.count) / rate) }
        let hitI = env.firstIndex { Double($0) >= Double(peak) * dbToAmp(-12) } ?? 0
        let floor = Double(peak) * dbToAmp(-30)
        let first = env.firstIndex { Double($0) >= floor } ?? 0
        let last = env.lastIndex { Double($0) >= floor } ?? (env.count - 1)
        return Meta(hit: Double(hitI) * win, peak: Double(peakI) * win, from: Double(first) * win, to: Double(last + 1) * win)
    }

    struct Run: Equatable {
        var start: Double
        var end: Double
    }

    /// Speech runs: 20 ms windows above peak − 26 dB, joined across gaps under 140 ms.
    static func speechRuns(_ samples: [Float], rate: Double) -> [Run] {
        let win = 0.02, env = envelope(samples, rate: rate, window: win)
        let peak = Double(env.max() ?? 0)
        guard peak > 1e-6 else { return [] }
        let threshold = peak * dbToAmp(-26), joinGap = 7
        var runs: [(Int, Int)] = []
        for (i, v) in env.enumerated() where Double(v) >= threshold {
            if let last = runs.last, i - last.1 <= joinGap { runs[runs.count - 1].1 = i } else { runs.append((i, i)) }
        }
        return runs.map { Run(start: Double($0.0) * win, end: Double($0.1 + 1) * win) }
    }

    /// Sentence starts inside a clip: the (k − 1) longest silences split it; else proportional to the text's length.
    static func sentenceStarts(runs: [Run], duration: Double, sentences: [String]) -> [Double] {
        let k = sentences.count
        guard k > 1 else { return [runs.first?.start ?? 0] }
        if runs.count >= k {
            let gaps = (1..<runs.count).map { (index: $0, length: runs[$0].start - runs[$0 - 1].end) }
            let cuts = gaps.sorted { $0.length > $1.length }.prefix(k - 1).map(\.index).sorted()
            if let shortest = cuts.map({ runs[$0].start - runs[$0 - 1].end }).min(), shortest >= 0.12 {
                return [runs[0].start] + cuts.map { runs[$0].start }
            }
        }
        let from = runs.first?.start ?? 0, to = runs.last?.end ?? duration
        let weights = sentences.map { Double($0.filter { !$0.isWhitespace }.count) }
        let total = max(1, weights.reduce(0, +))
        var acc = 0.0
        return weights.map { w in
            defer { acc += w }
            return from + (to - from) * acc / total
        }
    }

    struct CueStart: Equatable {
        /// When the buffer starts (seconds, the shared clock) and how far into it.
        var when: Double
        var skip: Double
    }

    /// A cue whose `offset` (its hit or peak) must sound at `at`; nil when it's too late to be on the beat.
    static func cueStart(at: Double, offset: Double, now: Double) -> CueStart? {
        let when = at - offset
        if when >= now { return CueStart(when: when, skip: 0) }
        let skip = now - when
        return skip > offset + lateLimit ? nil : CueStart(when: now, skip: skip)
    }

    /// Nothing plays while muted or while Aris's microphone is listening.
    static func audible(muted: Bool, micListening: Bool) -> Bool { !muted && !micListening }

    struct LoopFade: Equatable {
        var rise: Float
        var fall: Float
    }

    /// The equal-power crossfade baked into the bed's loop (`fade` samples).
    static func loopCrossfade(count: Int, fade: Int) -> [LoopFade] {
        let n = max(2, min(fade, count / 2))
        return (0..<n).map { i in
            let x = Double(i) / Double(n - 1) * Double.pi / 2
            return LoopFade(rise: Float(sin(x)), fall: Float(cos(x)))
        }
    }

    /// The notch's five bars from the voice's envelope at `time` (a floor so they read as speaking, never a dot).
    static func barLevels(envelope: [Float], at time: Double, window: Double, bars: Int) -> [Float] {
        guard !envelope.isEmpty, time >= 0 else { return Array(repeating: 0, count: bars) }
        let i = min(envelope.count - 1, Int(time / window))
        let peak = max(envelope.max() ?? 1, 1e-4)
        let level = min(1, envelope[i] / peak)
        // Each bar takes a neighbour's level, shaped so the middle bars move most (as the band's spectrum does).
        let shape: [Float] = [0.62, 0.86, 1, 0.8, 0.58]
        return (0..<bars).map { b in
            let j = min(envelope.count - 1, max(0, i + b - bars / 2))
            let v = (level + min(1, envelope[j] / peak)) / 2
            return min(1, pow(v, 1.2) * 1.25 * shape[b % shape.count])
        }
    }
}
