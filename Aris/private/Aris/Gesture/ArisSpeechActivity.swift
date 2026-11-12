//
//  ArisSpeechActivity.swift
//  Aris
//
//  How much of a turn the user has actually been speaking, so a circle drawn mid-sentence can be marked at the word
//  they were saying. A chunk counts as voiced when its RMS reaches 380 on Int16 samples. Aris's mic gives Float
//  samples, so the threshold is 380/32768. Pure, so the tests run it.
//

import Foundation

struct ArisSpeechActivity {
    /// 380 on the Int16 scale, for Float samples in -1...1.
    static let rmsThreshold: Float = ArisGestureConstants.Speech.rmsThresholdInt16 / 32768

    private var startedAtMs: Double?
    private(set) var voicedMsNow: Double = 0
    private(set) var totalMsNow: Double = 0

    /// The turn starts (key-down or wake). Resets the counts.
    mutating func start(at ms: Double) {
        startedAtMs = ms
        voicedMsNow = 0
        totalMsNow = 0
    }

    /// One mic chunk stamped `at` (ms, same clock as `start`). Audio from before the turn started (pre-roll, or a
    /// chunk that arrives before `start`) is not counted.
    mutating func feed(_ samples: [Float], sampleRate: Double, at ms: Double) {
        guard let startedAtMs, ms >= startedAtMs, !samples.isEmpty, sampleRate > 0 else { return }
        var sumSquares: Float = 0
        for s in samples { sumSquares += s * s }
        let rms = (sumSquares / Float(samples.count)).squareRoot()
        let durationMs = Double(samples.count) / sampleRate * 1000
        totalMsNow += durationMs
        if rms >= Self.rmsThreshold { voicedMsNow += durationMs }
    }

    /// The turn's speech span and voiced total, for `ArisGestureMarkers.insert`. Nil when `start` was never called:
    /// there is no speech window, so the caller adds no markers.
    func summary(endedAt ms: Double) -> (startedAtMs: Double, endedAtMs: Double, totalVoicedMs: Double)? {
        guard let startedAtMs else { return nil }
        return (startedAtMs, ms, voicedMsNow)
    }
}
