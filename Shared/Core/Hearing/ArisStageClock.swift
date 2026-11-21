//
//  ArisStageClock.swift
//  Aris (Shared/Core, Foundation only)
//
//  One clock per turn, from the key press or the wake word to the first sound of the answer, so the latency targets are
//  read from turns.jsonl instead of guessed. Each stage is kept the first time it happens (`voiceEnd` and the ends are
//  set once more if a speculation was cancelled and the turn went on). The line has each stage in ms since the turn
//  began (`<stage>AtMs`) and the gaps the targets name:
//
//    speechEndToRequestMs  voice end → request sent      (what the endpoint and the second listen cost)
//    speechEndToAudioMs    voice end → first audio        (target 1: p50 ≤ 1200, p90 ≤ 2000)
//

import Foundation

struct ArisStageClock: Equatable, Sendable {
    enum Stage: String, CaseIterable, Sendable {
        /// The key went down, or the wake word / a conversation's voice began the turn.
        case start
        case firstVoice
        /// The last voice before the end that committed (the end of speech).
        case voiceEnd
        case plausibleEnd
        case firmEnd
        /// The words the turn goes on with are final (second listen done or out of budget).
        case transcriptFinal
        case requestSent
        case firstDelta
        /// The first sentence went to the voice.
        case firstSentence
        case firstAudio

        var field: String { "\(rawValue)AtMs" }
    }

    /// Stages that move when a speculation was cancelled and the turn went on.
    private static let movable: Set<Stage> = [.voiceEnd, .plausibleEnd, .firmEnd, .transcriptFinal, .requestSent]

    private(set) var origin: ContinuousClock.Instant?
    private(set) var marks: [Stage: ContinuousClock.Instant] = [:]

    /// A new turn's clock, from `instant`.
    mutating func begin(at instant: ContinuousClock.Instant) {
        origin = instant
        marks = [.start: instant]
    }

    /// The stage happened at `instant` (the first time counts, unless `again` for a stage the turn can move past).
    mutating func mark(_ stage: Stage, at instant: ContinuousClock.Instant = .now, again: Bool = false) {
        guard origin != nil else { return }
        if marks[stage] != nil, !(again && Self.movable.contains(stage)) { return }
        marks[stage] = instant
    }

    /// A speculation was cancelled: what it marked is forgotten (the turn's real end comes later).
    mutating func forgetSpeculation() {
        for stage in [Stage.plausibleEnd, .transcriptFinal, .requestSent, .firstDelta] { marks[stage] = nil }
    }

    func milliseconds(_ stage: Stage) -> Int? {
        guard let origin, let mark = marks[stage] else { return nil }
        return Self.ms(mark - origin)
    }

    /// The turn's stage fields for turns.jsonl.
    func fields() -> [String: Int] {
        var line: [String: Int] = [:]
        for stage in Stage.allCases where stage != .start {
            if let value = milliseconds(stage) { line[stage.field] = value }
        }
        if let end = marks[.voiceEnd] {
            if let sent = marks[.requestSent] { line["speechEndToRequestMs"] = Self.ms(sent - end) }
            if let audio = marks[.firstAudio] { line["speechEndToAudioMs"] = Self.ms(audio - end) }
        }
        return line
    }

    /// Every number field the line can carry (aris-agent keeps only fields it knows: ArisTurnLog).
    static let fieldNames: Set<String> = Set(Stage.allCases.filter { $0 != .start }.map(\.field))
        .union(["speechEndToRequestMs", "speechEndToAudioMs"])

    private static func ms(_ duration: Duration) -> Int { Int(duration / .milliseconds(1)) }
}
