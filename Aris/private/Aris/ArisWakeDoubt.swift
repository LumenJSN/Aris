//
//  ArisWakeDoubt.swift
//  Aris
//
//  When a wake by voice print may have been wrong (2026-11-14: four "sure" wakes, scores 12.2–15.9 under the sure line
//  of 16.1, opened a turn that heard nothing and said "못 들었어요"). Three rules, pure so they are tested:
//  - A turn the wake word started that hears no speech closes without a word, sound or history entry; only a key
//    press or tap, where the user meant to talk, says "못 들었어요".
//  - A sure wake in the upper part of the sure band still opens at once, and Whisper checks the candidate phrase in
//    parallel; a no from it closes the turn the same quiet way unless the words after the name are a request to Aris
//    (ArisWakeEvidence: sound going on, a song's vocals, never keeps it).
//  - A near spelling of the name ("Iris", "알리스") counts in the wake check only with a fairly close voice print.
//

import Foundation

enum ArisWakeDoubt {
    // MARK: - The band

    /// At or below this fraction of the threshold a sure wake is strong: the model's threshold is 2.5 × the widest
    /// distance between the owner's own recordings, so 0.4 × threshold is that distance itself (10.74 tonight). Every
    /// real wake tonight at or below it was real (8.2, 9.3, 9.3, 9.9); all four false ones were above it (12.2–15.9).
    static let strongFraction: Float = 0.4
    /// A near spelling of the name counts up to this fraction of the threshold: halfway between the sure line (0.6)
    /// and the threshold.
    static let nearFraction: Float = 0.8

    static func strongCut(threshold: Float) -> Float { threshold * strongFraction }

    enum Opening: Equatable {
        case instant
        /// Opened at once, and Whisper checks the candidate after.
        case checkAfterOpening
    }

    /// How a sure wake opens. `interrupting`: a barge-in, for which Aris already stopped talking (never checked again).
    static func opening(score: Float?, threshold: Float?, interrupting: Bool) -> Opening {
        guard !interrupting, let score, let threshold else { return .instant }
        return score <= strongCut(threshold: threshold) ? .instant : .checkAfterOpening
    }

    /// A near spelling counts as the name for this candidate (never without a voice print): with a fairly close one,
    /// or at any candidate score during a second chance.
    static func nearAllowed(score: Float?, threshold: Float?, secondChance: Bool = false) -> Bool {
        guard let score, let threshold else { return false }
        return secondChance || score <= threshold * nearFraction
    }

    // MARK: - A second chance

    /// After a candidate was rejected, a repeated call this soon is read more kindly (the system wake phrase's
    /// second chance): tonight's repeats came 2–5 s apart (21:54:54 → :59, 22:03:31 → :41).
    static let secondChanceSeconds: Double = 5

    static func secondChance(lastRejectionAt: Double?, now: Double) -> Bool {
        guard let lastRejectionAt, now >= lastRejectionAt else { return false }
        return now - lastRejectionAt <= secondChanceSeconds
    }

    // MARK: - Barge-in

    /// A barge-in that must be checked by Whisper before Aris stops: any that isn't sure, and over the speakers a sure
    /// one too (Aris's own voice reaches the microphone there; there's no echo cancelling). With headphones a sure
    /// match stops it at once, as before.
    static func bargeInNeedsCheck(sure: Bool, headphones: Bool) -> Bool { !sure || !headphones }

    // MARK: - After opening

    // What keeps a borderline wake open once it has opened (Whisper's verdict, the words after the name, music and
    // this Mac's own playback) is ArisWakeEvidence: sound going on alone never does (2026-11-15, a song's vocals).

    // MARK: - A turn that heard nothing

    enum Unheard: Equatable { case notHeard, closeQuietly }

    static func unheard(byWakeWord: Bool) -> Unheard { byWakeWord ? .closeQuietly : .notHeard }

    /// The line an empty turn shows: none for one the wake word started.
    static func unheardLine(byWakeWord: Bool, korean: Bool) -> String? {
        unheard(byWakeWord: byWakeWord) == .notHeard ? ArisTranscript.notHeard(korean: korean) : nil
    }

    /// The soft tick when listening ends: on voice, as before, and for a wake-word turn only once it has words beyond
    /// the name.
    static func ticks(byWakeWord: Bool, heardSoFar: String, voiceHeard: Bool) -> Bool {
        guard voiceHeard else { return false }
        guard byWakeWord else { return true }
        return ArisWakeWord.strippedCall(heardSoFar).unicodeScalars.contains(where: CharacterSet.alphanumerics.contains)
    }

    /// How a wake-word turn ended quietly: its line in the unified log and its path in wake-log.jsonl.
    enum QuietEnd: String {
        case nothingSaid = "quiet-close"
        case notAris = "not-aris-after-open"
        /// The quiet lap ended with no voice (ArisQuietWake): the notch never opened.
        case quietLap = "quiet-lap"
        /// A borderline wake over music or singing (ArisWakeMusic) whose candidate Whisper didn't hear as the name.
        case music = "music"
        /// The same while this Mac itself played media or carried a call (ArisOtherAudio, Now Playing).
        case playing = "media-playing"
        /// Whisper didn't hear the name and the words after it weren't a request to Aris (ArisWakeAddressed).
        case notAddressed = "not-addressed"

        var path: String { rawValue }

        var logLine: String {
            switch self {
            case .nothingSaid: "wake word: closed quietly, nothing said"
            case .notAris: "wake word: not 아리스 after opening"
            case .quietLap: "wake word: one lap, nothing said: closed quietly"
            case .music: "wake word: borderline, over music, not 아리스: closed quietly"
            case .playing: "wake word: borderline, this Mac was playing, not 아리스: closed quietly"
            case .notAddressed: "wake word: borderline, not 아리스, and the words weren't for Aris: closed quietly"
            }
        }
    }

    // MARK: - Whisper's check of a candidate

    /// The language Whisper checks in: the first one turned on. Left to guess, it wrote Korean "아리스" as English,
    /// Japanese or Russian (3,673 of the wake log's 6,988 rejected texts were Latin script, 193 Japanese or Chinese).
    static func checkLanguage(_ languages: [String]) -> String? { languages.first }

    /// The prompt Whisper starts from: the name as that language writes it.
    static func checkPrompt(language: String?) -> String { language == "ko" ? "아리스" : "Aris" }

    struct CheckedSegment: Equatable {
        let text: String
        let avgLogprob: Float
    }

    /// Below this average log-probability a piece is a guess (Whisper's own line for trying again hotter).
    static let unsure: Float = -1.0
    /// What Whisper writes for silence in the languages it guessed (subtitle endings), besides ArisTranscript's.
    private static let silence: Set = ["ありがとうございました", "ご視聴ありがとうございました", "продолжение следует", "субтитры сделал dimatorzok"]

    /// Whisper's text of the candidate with guesses and silence's phrases left out ("" is no speech): 1,167 of the
    /// rejected texts were "Thank you.". (This WhisperKit computes no no-speech probability: it is always 0.)
    static func checkedText(_ segments: [CheckedSegment]) -> String {
        let text = segments.filter { $0.avgLogprob >= unsure }.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!?。,~…'\" ").union(.whitespacesAndNewlines))
        guard text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains), !ArisTranscript.soundsMadeUp(text),
              !silence.contains(plain) else { return "" }
        return text
    }

    // MARK: - Whisper's clip

    /// Whisper reads at least 1.5 s (ArisTranscript.paddedForWhisper); the check waited for 1.2 s of the candidate, so
    /// its last 0.3 s were zeros. Now it waits for real audio for all of it (a filler before the name pushes it late).
    static let clipSeconds = ArisTranscript.shortestForWhisper
    static let clipWait: Duration = .milliseconds(1600)

    static func clipEnough(sampleRate: Double) -> Int { Int(sampleRate * clipSeconds) }
}
