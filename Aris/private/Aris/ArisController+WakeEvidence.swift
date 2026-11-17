//
//  ArisController+WakeEvidence.swift
//  Aris
//
//  A borderline wake waits for its evidence (ArisWakeEvidence, the user 2026-11-15: a song that woke Aris went on
//  singing, opened the notch and its lyrics went to the AI). Until it is in, the notch stays the closed band
//  (ArisQuietWake held), nothing streams to Scribe, and the turn's request is never run: the turn's end waits for it
//  (wakeEvidenceAtEnd). Whisper's check of the candidate and the music read come back together
//  (doubleCheckAfterOpening); words after the call are judged as they come (ArisWakeAddressed), and a yes opens the
//  notch at once; a no is final only on the turn's whole words. A key press that ends the turn vouches for it.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// This Mac plays media or carries a call now (ArisOtherAudio.macPlays: Now Playing, a call, or real sound on the
    /// meter; never an idle open stream): the name may come from it.
    func thisMacPlays() -> Bool {
        ArisOtherAudio.macPlays(nowPlaying: ArisNowPlaying.shared.isPlaying, outputLevel: outputMeter.level,
                                ArisOtherAudio.processes(), ownPid: ProcessInfo.processInfo.processIdentifier)
    }

    /// Music in the few seconds the detector holds around the call (ArisWakeMusic), read off the main thread.
    nonisolated static func musicAround(_ detector: ArisWakeDetector) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            ArisWakeMusic.heard(in: ArisWakeMusic.tail(detector.held().samples, sampleRate: ArisVoicePrint.sampleRate))
        }.value
    }

    /// Looks again at a borderline wake while its turn listens: kept, closed, its words judged, or still waiting.
    func settleWakeEvidence() {
        guard var evidence = wakeEvidence, turnByWakeWord, !evidence.final, session.phase == .listening else { return }
        evidence.said = ArisWakeWord.strippedCall(session.heard)
        evidence.voiceGoing = userTalking
        wakeEvidence = evidence
        switch evidence.verdict {
        case .keep: keepWake(evidence, why: "kept")
        case .close(let end): closeWakeTurnQuietly(end)
        case .judge: judgeWakeWords(evidence)
        case .pending: break
        }
    }

    /// A key press ends a borderline wake's turn: the user is at the Mac and means it, so its request runs as before.
    func vouchForWakeTurn() {
        guard let evidence = wakeEvidence else { return }
        keepWake(evidence, why: "a key press vouches for it")
    }

    /// The last look before a borderline wake's request would run (the turn stopped listening, `said` are its whole
    /// words): nil goes on, a quiet end closes it. Waits for Whisper's check (at most ArisWakeEvidence.whisperWait)
    /// and for one judgement of the words (at most ArisWakeAddressed.timeout).
    func wakeEvidenceAtEnd(said: String) async -> ArisWakeDoubt.QuietEnd? {
        guard var evidence = wakeEvidence else { return nil }
        let id = evidence.id
        evidence.final = true
        evidence.said = said
        evidence.voiceGoing = false
        wakeEvidence = evidence
        wakeJudge?.cancel()
        wakeJudge = nil
        let deadline = ContinuousClock.now + ArisWakeEvidence.whisperWait
        while wakeEvidence?.id == id, wakeEvidence?.whisper == .waiting, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard var current = wakeEvidence, current.id == id else { return nil }
        if current.whisper == .waiting { current.whisper = .unavailable }
        if current.verdict == .judge {
            let verdict = await ArisWakeAddressed.judge(said)
            guard wakeEvidence?.id == id else { return nil }
            current.judged = .init(text: said, verdict: verdict)
        }
        wakeEvidence = current
        if case .close(let end) = current.verdict { return end }
        keepWake(current, why: "kept at the turn's end")
        return nil
    }

    private func judgeWakeWords(_ evidence: ArisWakeEvidence) {
        guard wakeJudge == nil, ArisWakeEvidence.judgeable(evidence.said) else { return }
        let said = evidence.said, id = evidence.id
        wakeJudge = Task { [weak self] in
            let verdict = await ArisWakeAddressed.judge(said)
            guard let self, !Task.isCancelled, self.wakeEvidence?.id == id else { return }
            self.wakeJudge = nil
            self.wakeEvidence?.judged = .init(text: said, verdict: verdict)
            log.notice("wake word: borderline, the words after the call judged \(String(describing: verdict), privacy: .public)")
            self.settleWakeEvidence()
        }
    }

    /// It was the user: the notch may open, Scribe hears the turn from its start, and its request will run.
    private func keepWake(_ evidence: ArisWakeEvidence, why: String) {
        log.notice("wake word: borderline, \(why, privacy: .public) (music \(evidence.music, privacy: .public), playing \(evidence.playing, privacy: .public))")
        wakeEvidence = nil
        wakeJudge?.cancel()
        wakeJudge = nil
        releaseQuietLap()
        guard scribeAfterWakeEvidence else { return }
        scribeAfterWakeEvidence = false
        if let listener = listener as? ArisListener { startScribe(for: listener, replaying: listener.recordedSamples) }
    }

    /// The wake log's fields for a borderline wake's evidence (text only, never audio).
    func wakeEvidenceLogFields() -> [String: Any] {
        guard let evidence = wakeEvidence else { return [:] }
        var fields: [String: Any] = ["music": evidence.music, "playing": evidence.playing]
        if let judged = evidence.judged { fields["judged"] = String(describing: judged.verdict) }
        return fields
    }
}
