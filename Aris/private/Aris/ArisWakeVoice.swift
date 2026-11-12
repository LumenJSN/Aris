//
//  ArisWakeVoice.swift
//  Aris
//
//  The wake word's first look at a sound that just started: is it a voice at all? A voice's vowels repeat at the
//  pitch of the speaker, 70 to 400 times a second; a key clack, a sleeve on the desk, a page turned, a breath on the
//  microphone do not. Until now loudness alone opened the gate, so each of those sounds started the speech
//  recognizer (and Whisper) for three seconds when the name is not trained. Now a sound with nothing voiced in its
//  first half second stops here. It errs towards letting things through: a hum, a chime and music pass, and so does
//  every phrase anyone says; what it stops for good is a whispered “아리스”, which has no pitch (the talk key hears a
//  whisper as before). It keeps and sends nothing: it reads the detector's own buffer and gives back two numbers per
//  10 ms. Foundation and Accelerate only, so it is tested from files.
//
//  (A hand-made outline of the name itself was tried here first: a voiced a-ri running into the hiss of s. Over 287
//  spoken names in 23 synthetic voices it stopped 13 to 23 % of them, because the hiss is 20 dB under the vowels and
//  40 ms long at a fast pace, and still let 73 % of other phrases through. It was dropped: telling the name from
//  other speech is the trained voice print's and the recognizer's work.)
//

import Accelerate
import Foundation

enum ArisWakeVoice {
    /// The preference that turns this look off ("off"): every sound loud enough is then handed on, as before.
    static let key = "arisWakeVoiceCheck"

    static func enabled(setting: String?) -> Bool { setting != "off" }

    /// One 25 ms frame, every 10 ms.
    struct Frame: Equatable {
        /// Mean square of the frame.
        var power: Float
        /// How strongly it repeats at a voice's pitch, 0...1.
        var voicing: Float
    }

    enum Verdict: Equatable {
        case voice
        case notVoice
        /// Not enough of the sound yet.
        case wait
    }

    static let frameLength = 400
    static let hop = 160
    /// A frame that repeats this strongly is voiced (noise stays under 0.3, a vowel is over 0.8).
    static let voicedAt: Float = 0.5
    /// Voiced frames needed (50 ms in all, not in a row), and the frames they must come within (half a second from
    /// the first loud one: “헤이 아리스” starts with a breath).
    static let voicedNeeded = 5
    static let within = 50

    /// The verdict on a sound from its frames so far. `lead`: frames before its first loud one (the room).
    /// `ended`: it is over, so `wait` is no longer an answer.
    static func verdict(_ frames: [Frame], lead: Int, ended: Bool) -> Verdict {
        let room = frames.prefix(lead).map(\.power).min() ?? 0
        let heard = frames.dropFirst(lead).prefix(within)
        let voiced = heard.filter { $0.voicing >= voicedAt && $0.power > room * 4 }.count
        if voiced >= voicedNeeded { return .voice }
        return ended || heard.count >= within ? .notVoice : .wait
    }

    /// The frames of 16 kHz audio, one every 10 ms.
    static func frames(_ samples: [Float]) -> [Frame] {
        guard samples.count >= frameLength else { return [] }
        return samples.withUnsafeBufferPointer { all in
            stride(from: 0, through: samples.count - frameLength, by: hop).map { start in
                frame(UnsafeBufferPointer(rebasing: all[start..<(start + frameLength)]))
            }
        }
    }

    /// Pitch periods looked for, in samples: 400 Hz down to 70 Hz.
    private static let lags = 40...228

    static func frame(_ samples: UnsafeBufferPointer<Float>) -> Frame {
        let count = samples.count
        guard count > lags.upperBound, let base = samples.baseAddress else { return Frame(power: 0, voicing: 0) }
        var mean: Float = 0
        vDSP_meanv(base, 1, &mean, vDSP_Length(count))
        var centred = [Float](repeating: 0, count: count)
        var negative = -mean
        vDSP_vsadd(base, 1, &negative, &centred, 1, vDSP_Length(count))
        var energy: Float = 0
        vDSP_svesq(centred, 1, &energy, vDSP_Length(count))
        guard energy > 0 else { return Frame(power: 0, voicing: 0) }
        return Frame(power: energy / Float(count), voicing: periodicity(centred, energy: energy))
    }

    /// The strongest autocorrelation over the pitch lags, as a share of the frame's energy.
    private static func periodicity(_ centred: [Float], energy: Float) -> Float {
        var best: Float = 0
        centred.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            for lag in stride(from: lags.lowerBound, through: lags.upperBound, by: 2) {
                var dot: Float = 0
                let overlap = buffer.count - lag
                vDSP_dotpr(base, 1, base + lag, 1, &dot, vDSP_Length(overlap))
                // Scaled to the overlap, so a long period is not marked down for having fewer samples.
                best = max(best, dot / energy * Float(buffer.count) / Float(overlap))
            }
        }
        return min(1, max(0, best))
    }
}
