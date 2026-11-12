//
//  ArisLongTurn.swift
//  Aris
//
//  A turn longer than Whisper's 30 seconds. The recording used to stop at 30 s, so Whisper read only the start of a
//  long instruction, and whenever that start held one English word its text won over Apple's whole one: the end of
//  the request ("…보내지는 말고 초안만") was dropped without a word (audit voice-5). Now the recording holds five
//  minutes, Whisper reads it window by window, each cut at the quietest moment near its end so no word is halved, and
//  a turn that outran even that is answered from the transcripts that heard all of it. Pure, so it's tested without
//  audio.
//

import Foundation

enum ArisLongTurn {
    /// How much of a turn is kept for Whisper (16 kHz mono: about 19 MB).
    static let recordedSeconds = 300.0
    /// Whisper reads at most this much at a time.
    static let windowSeconds = 30.0
    /// A window ends at the quietest moment in its last few seconds.
    static let cutSearchSeconds = 5.0
    /// The length of the moment whose loudness is compared.
    static let cutFrameSeconds = 0.2

    /// The most samples the recording holds.
    static func recordedLimit(sampleRate: Double) -> Int { Int(sampleRate * recordedSeconds) }

    /// Whether a recording of `recorded` samples holds the whole turn (it stops growing at the limit). One that
    /// doesn't is never handed to Whisper: its text would be the turn without its end.
    static func isWhole(recorded: Int, sampleRate: Double) -> Bool { recorded < recordedLimit(sampleRate: sampleRate) }

    /// The recording in windows Whisper can read, in order and without gaps or overlap; one window when it fits.
    static func windows(of samples: [Float], sampleRate: Double) -> [Range<Int>] {
        let window = Int(sampleRate * windowSeconds), search = Int(sampleRate * cutSearchSeconds)
        let frame = max(1, Int(sampleRate * cutFrameSeconds))
        guard window > search, search > frame else { return samples.isEmpty ? [] : [0..<samples.count] }
        var windows: [Range<Int>] = []
        var start = 0
        while samples.count - start > window {
            let cut = quietest(in: samples, from: start + window - search, to: start + window, frame: frame)
            windows.append(start..<cut)
            start = cut
        }
        if start < samples.count { windows.append(start..<samples.count) }
        return windows
    }

    /// The middle of the quietest `frame` between `from` and `to` (the first, when several are as quiet).
    private static func quietest(in samples: [Float], from: Int, to: Int, frame: Int) -> Int {
        var best = from, bestEnergy = Float.greatestFiniteMagnitude
        var at = from
        while at + frame <= to {
            var energy: Float = 0
            for index in at..<(at + frame) { energy += samples[index] * samples[index] }
            if energy < bestEnergy {
                bestEnergy = energy
                best = at
            }
            at += max(1, frame / 2)
        }
        return best + frame / 2
    }

    /// The windows' texts as one. A window Whisper filled with what it hears in silence ("시청해 주셔서 감사합니다") is
    /// left out: in a long turn a pause to think can fill most of one.
    static func joined(_ pieces: [String]) -> String {
        pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !ArisTranscript.soundsMadeUp(ArisTranscript.speechOnly($0)) }
            .joined(separator: " ")
    }

    /// The longest Whisper may take: `first` for one window, two seconds more for each further one.
    static let timeoutPerFurtherWindow: Duration = .seconds(2)
    /// However long the turn, Aris never waits longer than this for Whisper before going with the live transcript.
    static let longestTimeout: Duration = .seconds(12)

    static func whisperTimeout(samples: Int, sampleRate: Double, first: Duration) -> Duration {
        let further = max(0, Int((Double(samples) / sampleRate / windowSeconds).rounded(.up)) - 1)
        return min(first + timeoutPerFurtherWindow * further, max(first, longestTimeout))
    }

    /// Whether Whisper reads the turn during the grace moment after a pause: only while it fits one window. A longer
    /// one is read once, when the turn ends (each grace moment would start a read of minutes of audio).
    static func readsDuringGrace(seconds: Double) -> Bool { seconds <= windowSeconds }
}
