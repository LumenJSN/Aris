//
//  ArisVoiceClip.swift
//  Shared/Core (app, tests)
//
//  The audio an utterance's voice vector is read from (F1): 16 kHz mono, the silence before and after cut off, how many
//  seconds of it are voice, and the model's fixed window filled with it. The embedding model reads exactly 10 s; a
//  shorter utterance is repeated to fill them (zeros would be read as part of the voice: in the bench a padded clip
//  scored other voices at 0.75 against 0.19 repeated), and a longer one gives its first 10 s. Pure (no Accelerate:
//  the loops are short and run once per turn).
//

import Foundation

enum ArisVoiceClip {
    static let sampleRate = 16_000
    /// The model's window: 10 s.
    static let window = 160_000
    /// 25 ms frames every 10 ms.
    static let frame = 400
    static let hop = 160
    /// A frame is voice when it is within 26 dB of the loudest (and over the floor below).
    static let belowPeak: Float = 0.05
    /// Quieter than this is never voice, however quiet the clip.
    static let floor: Float = 0.002

    /// RMS of every frame.
    static func levels(_ samples: [Float]) -> [Float] {
        guard samples.count >= frame else { return [] }
        return stride(from: 0, through: samples.count - frame, by: hop).map { start in
            var sum: Float = 0
            for index in start..<(start + frame) { sum += samples[index] * samples[index] }
            return (sum / Float(frame)).squareRoot()
        }
    }

    /// The line a frame must pass to be voice.
    static func line(_ levels: [Float]) -> Float { max(floor, (levels.max() ?? 0) * belowPeak) }

    /// Seconds of voice in the clip.
    static func voicedSeconds(_ samples: [Float]) -> Double {
        let levels = levels(samples)
        let line = line(levels)
        return Double(levels.filter { $0 > line }.count * hop) / Double(sampleRate)
    }

    /// From the first to the last voiced frame; empty when nothing is voice.
    static func trimmed(_ samples: [Float]) -> [Float] {
        let levels = levels(samples)
        let line = line(levels)
        guard let first = levels.firstIndex(where: { $0 > line }), let last = levels.lastIndex(where: { $0 > line }) else { return [] }
        return Array(samples[(first * hop)..<min(samples.count, last * hop + frame)])
    }

    /// The model's 10 s, filled with the clip (repeated when shorter, its start when longer); nil for no audio.
    static func filled(_ samples: [Float]) -> [Float]? {
        guard !samples.isEmpty else { return nil }
        if samples.count >= window { return Array(samples.prefix(window)) }
        var out = [Float]()
        out.reserveCapacity(window)
        while out.count < window { out.append(contentsOf: samples.prefix(window - out.count)) }
        return out
    }
}
