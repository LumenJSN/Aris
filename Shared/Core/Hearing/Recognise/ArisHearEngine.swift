//
//  ArisHearEngine.swift
//  Aris (Shared/Core, Foundation only)
//
//  Who writes down a turn (Settings › Talking to Aris › 듣기), and in what order they are tried. One choice is stored
//  (`arisHearEngine`); the plan for a turn is that choice and what is there right now (which keys are saved, which
//  cloud engine is resting after failures). A cloud engine that fails or is slow hands the turn to the next one, and
//  the Mac's own recognisers (Whisper, then Apple's live words) are always last, so a turn is never lost. Every
//  step-down is a line for the log: an engine never quietly stands in for another.
//

import Foundation

enum ArisHearEngine: String, CaseIterable, Equatable, Sendable {
    /// The best that is set up: ElevenLabs Scribe, then Soniox, then OpenAI, then the Mac.
    case auto
    case scribe
    case soniox
    /// The settings menu already listed it under this id.
    case openai = "openai-stt"
    case whisper
    case apple

    static let cloud: [ArisHearEngine] = [.scribe, .soniox, .openai]

    var isCloud: Bool { Self.cloud.contains(self) }

    /// Streams while the turn is spoken (its words show in the notch); the others read the recording afterwards.
    var streams: Bool { self == .scribe || self == .soniox }

    /// The key it needs, by its Keychain account and old file name (ArisKeyFile).
    var keyName: String? {
        switch self {
        case .scribe: "elevenlabs-key"
        case .soniox: "soniox-key"
        case .openai: "openai-key"
        case .auto, .whisper, .apple: nil
        }
    }

    /// As the log names it.
    var logName: String {
        switch self {
        case .auto: "Automatic"
        case .scribe: "ElevenLabs Scribe"
        case .soniox: "Soniox"
        case .openai: "OpenAI"
        case .whisper: "Whisper on this Mac"
        case .apple: "Apple"
        }
    }

    /// The stored choice. Nothing stored (or something this build doesn't know): Automatic, unless the old "hear with
    /// Scribe" switch was turned off, which meant "stay on this Mac".
    static func chosen(stored: String?, cloudSwitch: Bool?) -> ArisHearEngine {
        if let stored, let engine = ArisHearEngine(rawValue: stored) { return engine }
        return cloudSwitch == false ? .whisper : .auto
    }
}

struct ArisHearPlan: Equatable, Sendable {
    let choice: ArisHearEngine
    /// The cloud engines to try, in order.
    let cloud: [ArisHearEngine]
    /// Whisper on the Mac may read the recording after them (never with Apple chosen).
    let whisper: Bool
    /// What the log says about engines that were chosen but can't be used this turn.
    let notes: [String]

    /// The engine that streams during the turn: the first cloud engine, when it is one that streams.
    var live: ArisHearEngine? { cloud.first.flatMap { $0.streams ? $0 : nil } }

    /// The cloud engines that read the recording if `failed` gave nothing.
    func after(_ failed: ArisHearEngine?) -> [ArisHearEngine] {
        guard let failed, let index = cloud.firstIndex(of: failed) else { return cloud }
        return Array(cloud.dropFirst(index + 1))
    }

    /// `keys`: the cloud engines whose key is saved. `resting`: those that failed twice in a row a moment ago.
    static func make(choice: ArisHearEngine, keys: Set<ArisHearEngine>, resting: Set<ArisHearEngine> = []) -> ArisHearPlan {
        let wanted: [ArisHearEngine] = choice == .auto ? ArisHearEngine.cloud : choice.isCloud ? [choice] : []
        var notes: [String] = []
        var cloud: [ArisHearEngine] = []
        for engine in wanted {
            if !keys.contains(engine) {
                // Automatic simply skips what isn't set up; a chosen engine without its key is said.
                if choice != .auto { notes.append("\(engine.logName) is chosen but has no key: the Mac listens instead") }
            } else if resting.contains(engine) {
                notes.append("\(engine.logName) is resting after failures: the next one listens")
            } else {
                cloud.append(engine)
            }
        }
        return ArisHearPlan(choice: choice, cloud: cloud, whisper: choice != .apple, notes: notes)
    }

    // MARK: - Time limits

    /// How long a fallback cloud engine may take to read the recording after the one before it gave nothing.
    static let fallbackBudget: Duration = .milliseconds(2500)
    /// All the cloud fallbacks of one turn together: past this the Mac's own words go on.
    static let fallbackLimit: Duration = .milliseconds(4000)

    /// What the next fallback may still take: its own budget, cut to what is left of the turn's limit; nil: none left.
    static func fallbackTime(spent: Duration) -> Duration? {
        let left = fallbackLimit - spent
        guard left > .milliseconds(300) else { return nil }
        return min(fallbackBudget, left)
    }
}

/// One engine's reading of a turn.
struct ArisHeard: Equatable, Sendable {
    let text: String
    /// The language it was in, when the engine says ("ko", "en", Scribe's "kor").
    let language: String?
}
