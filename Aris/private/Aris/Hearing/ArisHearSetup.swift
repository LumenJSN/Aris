//
//  ArisHearSetup.swift
//  Aris
//
//  What the pure hearing plan (ArisHearPlan, Shared/Core) is made from on this Mac: the engine chosen in Settings ›
//  Talking to Aris › 듣기, which cloud keys are saved, which engines are resting after failures, the languages turned
//  on and the words to expect. And the engines themselves behind the one seam (ArisTurnRecogniser, ArisLiveHearing).
//

import AppKit
import Defaults
import Foundation

@MainActor
enum ArisHearSetup {
    /// Each cloud recogniser as Aris last found it (ArisCloudBreaker: two failures in a row rest it for a while).
    /// Scribe's is ArisCloudHealth.listening, as before.
    static var health: [ArisHearEngine: ArisCloudBreaker] = [:]

    static var choice: ArisHearEngine {
        let defaults = UserDefaults.standard
        return ArisHearEngine.chosen(stored: defaults.string(forKey: ArisAIPrefKey.hearEngine),
                                     cloudSwitch: defaults.object(forKey: ArisAIPrefKey.cloudListening) as? Bool)
    }

    static var repairOn: Bool {
        ArisHearRepairSetting.isOn(stored: UserDefaults.standard.object(forKey: ArisHearRepairSetting.key) as? Bool, choice: choice)
    }

    static func hasKey(_ engine: ArisHearEngine) -> Bool { engine.keyName.flatMap(ArisKeyFile.load) != nil }

    static func mayTry(_ engine: ArisHearEngine) -> Bool {
        engine == .scribe ? ArisCloudHealth.listening.mayTry(at: .now) : (health[engine] ?? ArisCloudBreaker()).mayTry(at: .now)
    }

    /// An answer (even one with no words) counts for the engine; none at all counts against it.
    static func note(_ engine: ArisHearEngine, answered: Bool) {
        if engine == .scribe {
            if answered { ArisCloudHealth.listening.succeeded() } else { ArisCloudHealth.listening.failed(at: .now) }
            return
        }
        var breaker = health[engine] ?? ArisCloudBreaker()
        if answered { breaker.succeeded() } else { breaker.failed(at: .now) }
        health[engine] = breaker
    }

    static func plan() -> ArisHearPlan {
        ArisHearPlan.make(choice: choice, keys: Set(ArisHearEngine.cloud.filter(hasKey)), resting: Set(ArisHearEngine.cloud.filter { !mayTry($0) }))
    }

    /// The languages turned on as the engines take them: base codes, each once, the main one first.
    static var languages: [String] {
        Defaults[.arisLanguages].map(ArisLanguages.baseCode).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// The names of the apps on this Mac, once they have been listed (ArisController.installedApps).
    private static var installed: [String] = []
    private static var listing = false

    /// Everything a recogniser may be told to expect. Only names Aris keeps as names: nothing read from a window.
    static func hintSources() -> ArisHearHints.Sources {
        if installed.isEmpty, !listing {
            listing = true
            Task { installed = await ArisController.installedApps.value }
        }
        let taught = try? Data(contentsOf: URL(fileURLWithPath: ArisKeyFile.folder + "aris/taught.json"))
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.localizedName)
        return ArisHearHints.Sources(owner: ArisUserName.current, words: ArisVocabulary.load(), lessons: ArisHearHints.lessonNames(in: taught),
                                     runningApps: running, installedApps: installed)
    }

    static func request() -> ArisHearRequest {
        ArisHearRequest(languages: languages, hints: ArisHearHints.build(hintSources(), bounds: .soniox))
    }

    /// The owner's pairs, then what dictation learned from his fixes (each misheard form → the word).
    static func pairs() -> [ArisHeardPair] {
        let learned = ArisLearnedDictionary.load(from: ArisLearnedDictionary.file(home: UserHome.path)).words
        return ArisVocabulary.loadPairs() + learned.flatMap { word in word.heard.map { ArisHeardPair(heard: $0, meant: word.text) } }
    }

    // MARK: - The engines

    /// A session streaming the turn to `engine`; nil when it doesn't stream or has no key.
    nonisolated static func live(_ engine: ArisHearEngine, _ request: ArisHearRequest) -> (any ArisLiveHearing)? {
        switch engine {
        case .scribe: ArisScribe.make(languages: request.languages, keyterms: request.hints)
        case .soniox: ArisSoniox.make(request)
        case .auto, .openai, .whisper, .apple: nil
        }
    }

    /// The engine that reads a finished recording. Apple has none: its reading of a turn is the live text the
    /// microphone's recogniser wrote while it was spoken, which every caller already holds.
    nonisolated static func recogniser(_ engine: ArisHearEngine) -> (any ArisTurnRecogniser)? {
        switch engine {
        case .scribe, .soniox: ArisStreamedRecording(engine: engine) { live(engine, $0) }
        case .openai: ArisOpenAITranscribe.make()
        case .whisper: ArisWhisperRecording()
        case .auto, .apple: nil
        }
    }
}

/// Whisper on the Mac behind the seam (it takes no hints: a prompt would fix its language).
struct ArisWhisperRecording: ArisTurnRecogniser {
    let engine = ArisHearEngine.whisper

    func transcribe(_ samples: [Float], request: ArisHearRequest, timeout: Duration) async -> ArisHeard? {
        let text = try? await ArisDeadline.within(timeout) { try await ArisWhisper.shared.transcribe(samples) }
        return (text ?? nil).map { ArisHeard(text: $0, language: nil) }
    }
}
