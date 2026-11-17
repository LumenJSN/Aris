//
//  ArisController+QuietWake.swift
//  Aris
//
//  The wake word's quiet lap (ArisQuietWake, the owner's pick "C · 한 바퀴"): a wake-word turn listens in the closed band
//  while the rim's light makes one lap. The user's voice in that lap opens the notch (wakeLap .heard, the notch's
//  turnNeedsPanel); a lap with no voice ends the turn through false-wake's quiet close: no line, no sound, nothing in
//  the history. Key presses and taps never start a lap. A borderline wake's lap is held until its evidence is in
//  (ArisWakeEvidence, ArisController+WakeEvidence): the evidence lives and ends with the lap.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// A wake-word turn begins: its lap starts now, or it is heard at once when the check already had words after the name.
    /// `evidence`: a borderline wake, held until it is in.
    func startQuietLap(saidMore: Bool, evidence: ArisWakeEvidence? = nil) {
        endQuietLap()
        let lap = ArisQuietWake(wokeAt: Self.uptime, saidMore: saidMore, held: evidence != nil)
        quietWake = lap
        wakeLap = lap.state
        wakeEvidence = evidence
        if evidence != nil {
            ArisWakeAddressed.prewarm()
            log.notice("wake word: borderline: the notch waits for Whisper's check (playing \(evidence?.playing ?? false, privacy: .public))")
        }
        guard lap.state == .waiting else { return log.notice("wake word: words came with the call: the notch opens") }
        log.notice("wake word: one quiet lap (\(ArisQuietWake.lap, privacy: .public) s), the notch stays closed")
        quietLapTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ArisQuietWake.lap))
            guard !Task.isCancelled else { return }
            self?.stepQuietLap { $0.tick(at: Self.uptime) }
        }
    }

    /// One reading of the turn's microphone (`voice`: over the turn's gate, ArisTalkKey.isVoice).
    func quietLapLevel(voice: Bool) {
        stepQuietLap { $0.level(voice: voice, at: Self.uptime) }
    }

    /// The recognizer wrote words beyond the call.
    func quietLapWords() {
        stepQuietLap { $0.words(at: Self.uptime) }
    }

    /// The borderline wake's evidence is in and it was the user: the held lap lets go (ArisQuietWake.release).
    func releaseQuietLap() {
        stepQuietLap { $0.release() }
    }

    /// No lap (a key press's turn, a conversation's voice turn, a turn that ended): nothing of it shows, and a
    /// borderline wake's evidence ends with it.
    func endQuietLap() {
        quietLapTimer?.cancel()
        quietLapTimer = nil
        quietWake = nil
        if wakeLap != nil { wakeLap = nil }
        wakeEvidence = nil
        wakeJudge?.cancel()
        wakeJudge = nil
        scribeAfterWakeEvidence = false
    }

    private func stepQuietLap(_ step: (inout ArisQuietWake) -> Void) {
        guard var lap = quietWake, lap.state == .waiting, turnByWakeWord, session.phase == .listening else { return }
        step(&lap)
        quietWake = lap
        guard lap.state != .waiting else { return }
        quietLapTimer?.cancel()
        quietLapTimer = nil
        wakeLap = lap.state
        let into = Int((Self.uptime - lap.wokeAt) * 1000)
        switch lap.state {
        case .heard:
            log.notice("wake word: you started talking \(into, privacy: .public) ms into the lap: the notch opens")
        case .unheard:
            closeWakeTurnQuietly(.quietLap)
        case .waiting:
            break
        }
    }
}
