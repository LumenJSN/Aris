//
//  ArisController+Turn.swift
//  Aris
//
//  When you pause, Smart Turn (ArisTurnDetector) listens to how the turn so far sounds: finished, unsure or
//  mid-thought, which sets how long a pause ends the turn (ArisEndpointPolicy). Each pause is scored once, 0.2 s in
//  (the silence the model was trained to be run after: pipecat's VAD stop; it takes ~4 ms); talking again throws the
//  score away, and the end is looked at again as soon as the score is in. Every decision goes to endpoint-log.jsonl.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// How far into a pause the turn is scored: long enough to be a pause (Smart Turn is run after 0.2 s of silence
    /// upstream), before the earliest plausible end (0.25 s).
    static let scoreAfterQuiet: Duration = .milliseconds(200)

    /// The score for the current pause, if it's been scored (and you haven't talked since).
    var currentPauseScore: Float? {
        guard let pauseScore, pauseScore.voiceAt == lastVoiceAt else { return nil }
        return pauseScore.score
    }

    func scorePauseIfNeeded(sinceVoice: Duration?) {
        guard let sinceVoice, sinceVoice >= Self.scoreAfterQuiet, !scoringPause,
              let voiceAt = lastVoiceAt, pauseScore?.voiceAt != voiceAt,
              let listener = listener as? ArisListener else { return }
        scoringPause = true
        let samples = listener.recentSamples(ArisTalkKey.turnWindowSamples)
        Task.detached(priority: .userInitiated) {
            let score = ArisTurnDetector.shared.score(samples)
            await MainActor.run {
                self.scoringPause = false
                if let score { self.pauseScore = (voiceAt, score) }
                self.endpointLook()
            }
        }
    }

    func logEndpoint(score: Float?, sinceVoice: Duration?, sinceWords: Duration?, complete: Bool, hanging: Bool, said: String,
                     endCase: String? = nil, decision: String? = nil) {
        let ms = { (gap: Duration?) in gap.map { Int($0 / .milliseconds(1)) } ?? -1 }
        var line: [String: Any] = ["quietMs": ms(sinceVoice), "noNewWordsMs": ms(sinceWords), "finished": complete,
                                   "hanging": hanging, "characters": said.count, "followUp": followingUp]
        if let score { line["smartTurn"] = Double(score) }
        if let endCase { line["case"] = endCase }
        if let decision { line["decision"] = decision }
        ArisTuningLog.append(line, to: "endpoint-log.jsonl")
    }
}
