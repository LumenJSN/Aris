//
//  ArisVoiceFallback.swift
//  Aris
//
//  When ElevenLabs lets Aris down. A sentence whose voice fails in the middle of an answer is asked for once more;
//  if that fails too, the system voice reads it and the rest (they used to be skipped without a word, each after
//  waiting out two requests: audit voice-8). And after two failures in a row Aris stops asking ElevenLabs for a few
//  minutes: the voice and the listening go straight to the Mac's own instead of waiting four seconds before every
//  answer and two and a half after every turn (audit voice-imp-4). Also the reading of an answer sentence by
//  sentence, which the system voice does (ArisSentenceReader). Pure, so the rules are tested without a network or a
//  voice.
//

import Foundation

/// What the cloud voice does after one sentence's request failed.
enum ArisVoiceFallback: Equatable {
    /// Ask for the sentence once more.
    case retry
    /// Part of it already played: asking again would repeat it. On to the next sentence.
    case skipSentence
    /// The system voice reads this sentence and every one after it.
    case systemVoice

    /// `attempt`: 1 or 2. `playedOfSentence`: some of this sentence's audio already played. `playedAnything`: any
    /// audio of this answer played. `lastSentenceBroke`: the sentence before this one broke off part-way.
    static func afterFailure(attempt: Int, playedOfSentence: Bool, playedAnything: Bool, lastSentenceBroke: Bool) -> ArisVoiceFallback {
        // Nothing has played yet (no network, a first byte that never came): the system voice takes over now, not
        // after every sentence has failed in turn.
        if !playedAnything { return .systemVoice }
        if playedOfSentence { return .skipSentence }
        // The connection broke in the last sentence and this one got nothing: it is down, not hiccuping.
        if attempt >= 2 || lastSentenceBroke { return .systemVoice }
        return .retry
    }
}

/// An answer read one sentence at a time as its sentences arrive, by whatever voice `say` is. It stops for good the
/// moment the reading is no longer current (the voice was stopped, or a newer answer took over): a sentence that
/// arrives after that is never said (audit voice-3), and one reader can pick a stream up where another left it
/// (audit voice-8: the system voice after ElevenLabs).
enum ArisSentenceReader {
    @MainActor
    static func read(first: [String] = [], then sentences: AsyncStream<String>, isCurrent: @MainActor () -> Bool,
                     say: @MainActor (String) async -> Void) async {
        for sentence in first {
            guard isCurrent() else { return }
            await say(sentence)
        }
        for await sentence in sentences {
            guard isCurrent() else { return }
            await say(sentence)
        }
    }
}

/// The system voice's language while an answer is read sentence by sentence: that of everything said so far, so a
/// Korean answer keeps its Korean voice through a sentence that happens to be all English.
struct ArisAnswerVoice {
    private var said = ""

    mutating func language(for sentence: String, among languages: [String]) -> String {
        said += (said.isEmpty ? "" : " ") + sentence
        return ArisSpeech.language(of: said, among: languages)
    }
}

/// Whether to ask ElevenLabs at all right now. Two failures in a row open it: nothing is asked for two minutes, then
/// one try; each further failure doubles the pause, up to ten minutes. Any success closes it.
struct ArisCloudBreaker {
    static let failuresToOpen = 2
    static let firstPause: Duration = .seconds(120)
    static let longestPause: Duration = .seconds(600)

    private(set) var failures = 0
    private var backoff = ArisRetryBackoff(first: firstPause, longest: longestPause)

    func mayTry(at now: ContinuousClock.Instant) -> Bool { backoff.mayTry(at: now) }

    /// Whether a failed request says ElevenLabs itself is in trouble. `status`: the HTTP status it answered with, nil
    /// when it never answered (no network, a first byte that came too late). No answer, a refused key, no credit left,
    /// too many requests or a server error do; a request it turned down for what was in it (400, 404, 422: these
    /// words, this voice) says nothing about the next one.
    static func counts(status: Int?) -> Bool {
        guard let status else { return true }
        return [401, 402, 403, 408, 429].contains(status) || status >= 500
    }

    mutating func failed(at now: ContinuousClock.Instant) {
        failures += 1
        if failures >= Self.failuresToOpen { backoff.failed(at: now) }
    }

    mutating func succeeded() {
        failures = 0
        backoff.succeeded()
    }
}

/// ElevenLabs' two services as Aris last found them: the voice (text to speech) and the listening (Scribe). Apart,
/// because one can be down, or out of credit, while the other works.
@MainActor
enum ArisCloudHealth {
    static var voice = ArisCloudBreaker()
    static var listening = ArisCloudBreaker()
}
