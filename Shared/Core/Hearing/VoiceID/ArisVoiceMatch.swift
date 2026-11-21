//
//  ArisVoiceMatch.swift
//  Shared/Core (app, tests)
//
//  Whether an utterance is the owner's (F1): its vector's cosine to the owner's print, read against two lines with
//  an unsure band between them. Short audio says less about a voice, so under `longFrom` seconds of voice the band is
//  wider; under `fewestSeconds` nothing is decided at all.
//  The lines come from tests/voiceid-bench (9 Korean system voices × 14 phrases × 2 rates; each voice in turn the
//  owner, its print made from the name and five sentences): the owner's requests and sentences scored 0.73–0.88 (all
//  over 0.60), a different voice's at most 0.55 (median 0.22); a spoken "응 보내 줘" of the owner 0.43–0.75 (never under
//  0.38: never refused), of a different voice at most 0.46 (89 % refused, none taken). A lone "아리스" has under 0.4 s
//  of voice and decides nothing. The voices that crossed the lines were pairs from one synthesizer with another pitch
//  setting (Eddy/Reed, Flo/Shelley/Grandma), which are closer than two people. Real voices through a real microphone
//  are the user's to judge (ARCHITECTURE F1: a by-ear session). Pure.
//

import Foundation

enum ArisVoiceVerdict: String, Codable, Equatable, Sendable {
    /// Over the owner line: the owner speaking.
    case owner
    /// Under the other line: clearly someone or something else.
    case notOwner
    /// In between, too little voice, or no print to compare with.
    case unsure
}

struct ArisVoiceMatch: Equatable, Sendable {
    /// The cosine to the print; nil when nothing was compared.
    let score: Float?
    /// Seconds of voice the score was read from.
    let seconds: Double
    let verdict: ArisVoiceVerdict
    /// Why, for the log: "owner", "not-owner", "between", "too-short", "no-print", "no-vector".
    let why: String

    static func unsure(_ why: String, seconds: Double = 0) -> ArisVoiceMatch {
        ArisVoiceMatch(score: nil, seconds: seconds, verdict: .unsure, why: why)
    }
}

enum ArisVoiceMatcher {
    /// Less voice than this decides nothing.
    static let fewestSeconds = 0.4
    /// From this much voice the long lines hold.
    static let longFrom = 1.5

    struct Lines: Equatable, Sendable {
        /// At or over: the owner.
        let owner: Float
        /// Under: not the owner.
        let other: Float
    }

    static let long = Lines(owner: 0.60, other: 0.40)
    static let short = Lines(owner: 0.62, other: 0.38)

    static func lines(seconds: Double) -> Lines { seconds >= longFrom ? long : short }

    /// The verdict for a vector of `seconds` of voice against `profile` (nil: no print).
    static func match(_ vector: [Float]?, seconds: Double, profile: ArisVoiceProfile?) -> ArisVoiceMatch {
        guard let profile, profile.isEnrolled else { return .unsure("no-print", seconds: seconds) }
        guard seconds >= fewestSeconds else { return .unsure("too-short", seconds: seconds) }
        guard let vector, let score = ArisVoiceVector.cosine(vector, profile.centroid) else { return .unsure("no-vector", seconds: seconds) }
        return verdict(score: score, seconds: seconds)
    }

    static func verdict(score: Float, seconds: Double) -> ArisVoiceMatch {
        let lines = lines(seconds: seconds)
        if score >= lines.owner { return ArisVoiceMatch(score: score, seconds: seconds, verdict: .owner, why: "owner") }
        if score < lines.other { return ArisVoiceMatch(score: score, seconds: seconds, verdict: .notOwner, why: "not-owner") }
        return ArisVoiceMatch(score: score, seconds: seconds, verdict: .unsure, why: "between")
    }
}
