//
//  ArisVoiceEnrolment.swift
//  Aris
//
//  The rules of 내 목소리 등록하기 (F1): how long a sentence's take lasts, whether it has enough voice to keep, and which
//  of 호출어 녹음's own recordings go into the print with the sentences (the contract's "the recordings the wake-word
//  training already takes"): calls of the name said as usual, near the Mac, with no music, on the Mac's microphone,
//  where the owner's voice is clearest. Takes stay in memory and are dropped once the print has them. Foundation only
//  (tested).
//

import Foundation

enum ArisVoiceEnrolment {
    /// A sentence's window, and the voice it must have.
    static let takeSeconds = 4.5
    static let leastVoice = 0.8
    /// 호출어 녹음 takes added, at most.
    static let mostCalls = 10
    /// Sentences the print must have taken for the enrolment to count.
    static let leastKept = 3

    static func keeps(_ take: [Float]) -> Bool { ArisVoiceClip.voicedSeconds(take) >= leastVoice }

    /// The corpus files (relative to its folder) whose calls go into the print.
    static func wakeCalls(_ manifest: ArisWakeManifest) -> [String] {
        let fitting = manifest.entries.filter { entry in
            entry.label == .call && entry.speaker == nil && entry.style == ArisWakePrompt.Style.normal.rawValue
                && entry.distance == ArisWakePrompt.Distance.near.rawValue && entry.background != ArisWakePrompt.Background.music.rawValue
                && entry.mic != ArisWakePrompt.Mic.airPods.rawValue && !entry.file.contains("..") && !entry.file.hasPrefix("/")
        }
        return Array(fitting.suffix(mostCalls).map(\.file))
    }

    /// The sentences, in the app's language.
    static func sentences(english: Bool) -> [String] { english ? ArisVoiceIDRows.englishSentences : ArisVoiceIDRows.sentences }
}
