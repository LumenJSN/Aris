//
//  ArisController+Turn.swift
//  Aris
//
//  When you pause, Smart Turn (ArisTurnDetector) listens to how the turn so far sounds: finished, unsure or
//  mid-thought, which sets how long a pause ends the turn (ArisTalkKey). Each pause is scored once, ~0.3 s in;
//  talking again throws the score away. An end that wasn't certain gets a grace moment of listening first.
//  Every decision goes to endpoint-log.jsonl for tuning.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// How far into a pause the turn is scored: long enough to be a pause, well before the shortest end (0.5 s).
    static let scoreAfterQuiet: Duration = .milliseconds(300)

    /// The score for the current pause, if it's been scored (and you haven't talked since).
    var currentPauseScore: Float? {
        guard let pauseScore, pauseScore.voiceAt == lastVoiceAt else { return nil }
        return pauseScore.score
    }

    func scorePauseIfNeeded(sinceVoice: Duration?) {
        guard #available(macOS 26.0, *), let sinceVoice, sinceVoice >= Self.scoreAfterQuiet, !scoringPause,
              let voiceAt = lastVoiceAt, pauseScore?.voiceAt != voiceAt,
              let listener = listener as? ArisListener else { return }
        scoringPause = true
        let samples = listener.recentSamples(ArisTalkKey.turnWindowSamples)
        Task.detached(priority: .userInitiated) {
            let score = ArisTurnDetector.shared.score(samples)
            await MainActor.run {
                self.scoringPause = false
                if let score { self.pauseScore = (voiceAt, score) }
            }
        }
    }

    func logEndpoint(score: Float?, sinceVoice: Duration?, sinceWords: Duration?, complete: Bool, hanging: Bool, said: String) {
        let ms = { (gap: Duration?) in gap.map { Int($0 / .milliseconds(1)) } ?? -1 }
        var line: [String: Any] = ["quietMs": ms(sinceVoice), "noNewWordsMs": ms(sinceWords), "finished": complete,
                                   "hanging": hanging, "characters": said.count, "followUp": followingUp]
        if let score { line["smartTurn"] = Double(score) }
        ArisTuningLog.append(line, to: "endpoint-log.jsonl")
    }
}

extension ArisController {
    /// The grace moment after a hands-free end: Aris keeps listening (the notch still shows it) while Whisper reads
    /// the turn so far. True when you started talking again: the turn goes on and nothing was asked yet.
    func heldUpByGrace(confident: Bool) async -> Bool {
        preparedWhisper?.task.cancel()
        preparedWhisper = nil
        guard #available(macOS 26.0, *), let listener = listener as? ArisListener else { return false }
        // A turn longer than one of Whisper's windows is read once, when it ends (ArisLongTurn).
        if scribe == nil, ArisLongTurn.readsDuringGrace(seconds: listener.recordedSeconds) {
            let recording = listener.recordedSamples
            preparedWhisper = (lastVoiceAt, Task { await self.whisperTranscript(recording) })
        }
        let grace = ArisTalkKey.grace(confident: confident)
        guard grace > .zero else { return false }
        graceVoiceFrames = 0
        try? await Task.sleep(for: grace)
        guard !Task.isCancelled, session.phase == .listening, ArisTalkKey.resumedTalking(voiceFrames: graceVoiceFrames) else { return false }
        preparedWhisper?.task.cancel()
        preparedWhisper = nil
        log.notice("kept talking: listening on")
        ArisTuningLog.append(["graceResumed": true, "followUp": followingUp], to: "endpoint-log.jsonl")
        return true
    }
}
