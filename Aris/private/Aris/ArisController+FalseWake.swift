//
//  ArisController+FalseWake.swift
//  Aris
//
//  A wake by voice print that came to nothing (2026-11-14: "왜 갑자기 못 들었어요"): the turn closes the way it would
//  have if it had never opened. No line, no sound, nothing in the history or the AI's context; music comes back and
//  the conversation the wake opened closes. A borderline sure wake (ArisWakeDoubt.opening) is opened at once and
//  checked by Whisper meanwhile; without evidence that it was the user (ArisWakeEvidence) it closes the same way. Both are logged, and written to
//  wake-log.jsonl, so the next false wake can be seen.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// The wake-word turn ends without a word. `whisper`: Whisper's text of the candidate, when it read one (wake log).
    /// A borderline wake's own evidence adds why (music, this Mac playing, the judge's word): text only, never audio.
    func closeWakeTurnQuietly(_ end: ArisWakeDoubt.QuietEnd, whisper: String? = nil) {
        log.notice("\(end.logLine, privacy: .public)")
        let (score, sure) = wakeCandidate
        var line: [String: Any] = ["score": score.map(Double.init) ?? -1, "sure": sure, "path": end.path,
                                   "whisper": ArisWakeRest.kept(whisper ?? wakeEvidence?.whisperText, path: end.path)]
        line.merge(wakeEvidenceLogFields()) { kept, _ in kept }
        ArisTuningLog.append(line, to: "wake-log.jsonl")
        // 하루 소리 모으기, when on: the candidate's clip is labelled a false wake.
        ArisWakeCollectLive.shared.falseWake()
        wakeDoubleCheck?.cancel()
        endQuietLap()
        turnByWakeWord = false
        gestureCancelled()
        finishTurn("unheard")
        releaseListener()
        level = 0
        session = ArisSession()
        // The conversation this wake opened never had a turn: it closes (the music comes back with it).
        if wakeOpenedConversation, conversation.isOpen { return closeConversation(.falseWake) }
        resumeMusicIfPaused()
    }

    /// A borderline sure wake was opened (it has evidence to wait for, ArisWakeEvidence): Whisper checks the
    /// candidate phrase, and music in the seconds around it is read meanwhile; both go to its evidence together.
    func doubleCheckAfterOpening(detector: ArisWakeDetector, score: Float?) {
        wakeDoubleCheck?.cancel()
        guard let id = wakeEvidence?.id else { return }
        wakeDoubleCheck = Task {
            let audio = await Self.wakeClip(from: detector)
            async let music = Self.musicAround(detector)
            let heard = audio.isEmpty ? nil : (try? await ArisWhisper.shared.checkName(audio, language: Self.wakeCheckLanguage)) ?? nil
            let overMusic = await music
            guard !Task.isCancelled, self.wakeEvidence?.id == id else { return }
            self.wakeEvidence?.whisper = heard.map(ArisWakeEvidence.Whisper.heard) ?? .unavailable
            self.wakeEvidence?.music = overMusic
            let shown = score.map { String(format: "%.2f", $0) } ?? "none"
            log.notice("wake word: borderline \(shown, privacy: .public): Whisper \(heard == nil ? "not ready" : "read it", privacy: .public), music \(overMusic, privacy: .public)")
            self.settleWakeEvidence()
        }
    }
}
