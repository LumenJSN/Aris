//
//  ArisWakeTake.swift
//  Aris
//
//  Whether one recorded take of 호출어 녹음 is worth keeping: there is a voice in it, it is not clipped, and the voice is
//  not cut off by the window's edges. A quiet or far call is allowed to be quiet (that is the point of it), and over
//  music the edges are always loud, so they are not judged there. Foundation only (tested).
//

import Foundation

enum ArisWakeTake {
    enum Verdict: Equatable {
        case ok
        /// No voice loud enough to be a take.
        case tooQuiet
        /// The microphone ran out of range.
        case clipped
        /// The voice runs into the window's start or end: said too early or too long.
        case cutOff
    }

    static let hop = 160

    /// The loudest 10 ms the take must reach: a near call is well above it, a whisper across the room still above
    /// a silent room's hiss (about 0.0004).
    static func minimumPeak(_ prompt: ArisWakePrompt) -> Float {
        if prompt.style == .quiet || prompt.distance == .far { return 0.004 }
        return 0.01
    }

    static func verdict(_ samples: [Float], prompt: ArisWakePrompt) -> Verdict {
        let levels = stride(from: 0, to: max(0, samples.count - hop + 1), by: hop).map { start -> Float in
            var sum: Float = 0
            for index in start..<(start + hop) { sum += samples[index] * samples[index] }
            return (sum / Float(hop)).squareRoot()
        }
        guard let peak = levels.max(), peak >= minimumPeak(prompt) else { return .tooQuiet }
        let clipped = samples.filter { abs($0) >= 0.99 }.count
        if clipped > max(8, samples.count / 1000) { return .clipped }
        guard prompt.background != .music, levels.count > 20 else { return .ok }
        // The first and last 100 ms: louder than a third of the peak means the voice was there already, or still.
        let edge = 10, loud = peak / 3
        if levels.prefix(edge).contains(where: { $0 > loud }) || levels.suffix(edge).contains(where: { $0 > loud }) { return .cutOff }
        return .ok
    }

    /// What the sheet says about a take it did not keep.
    static func retryLine(_ verdict: Verdict) -> String? {
        switch verdict {
        case .ok: nil
        case .tooQuiet: "잘 안 들렸어요. 한 번 더 불러 주세요."
        case .clipped: "소리가 너무 커서 깨졌어요. 조금 떨어져서 다시요."
        case .cutOff: "말이 잘렸어요. 숫자가 바뀐 뒤에 짧게 말해 주세요."
        }
    }
}
