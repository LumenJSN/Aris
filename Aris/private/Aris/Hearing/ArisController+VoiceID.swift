//
//  ArisController+VoiceID.swift
//  Aris
//
//  Where the owner's voice (F1, ArisVoiceID) meets a turn. At a heard turn's end its audio is checked off the main
//  thread while the transcript is made (no wait added): a turn the talk key was held for teaches the print; a turn
//  heard without the key (by the name, a conversation's next turn, a tap) whose voice is clearly not the owner's
//  closes quietly before its request runs, as a turn that wasn't for Aris does today; any other turn goes on, and its
//  speaker rides with the request for the trust table (ArisTurnSpeaker). A spoken yes on a card in a clearly other
//  voice is not taken: Aris says so and the card waits for a click or Y. With the switch off, or no print yet, none of
//  this changes anything.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "voiceid")

/// The turn the talk key was held down for, from its press to its release (keyUp's finish).
@MainActor
enum ArisVoiceTurnMarks {
    static var keyHeld: ArisTurnID?
}

extension ArisController {
    /// keyUp: the key was held for the whole turn that is ending now.
    func noteKeyHeldTurn() { ArisVoiceTurnMarks.keyHeld = kernel.current }

    /// How the turn that is ending came in.
    func voiceEntry() -> ArisTurnEntry {
        if turnByWakeWord { return .wakeWord }
        if followingUp { return .followUp }
        if let held = ArisVoiceTurnMarks.keyHeld, held == (ArisTurnScope.current ?? kernel.current) { return .keyHeld }
        return .tapped
    }

    /// The turn's audio for its voice: the whole recording, else its last 10 s (a turn longer than the recording holds).
    private func voiceAudio(_ listener: ArisListener) -> [Float] {
        let whole = listener.secondListenSamples
        return whole.isEmpty ? listener.recentSamples(ArisVoiceClip.window) : whole
    }

    /// Starts the voice check of a turn's audio (nil when the switch is off): its verdict is read by `voiceClosesTurn`.
    /// With a print and no usable audio the verdict is unsure (ArisVoiceDecisions.noAudio), never "nothing checked".
    func startVoiceCheck(_ listener: ArisListener) -> Task<(ArisTurnEntry, ArisVoiceMatch?), Never>? {
        let entry = voiceEntry()
        ArisVoiceTurnMarks.keyHeld = nil
        let voice = ArisVoiceID.shared
        guard voice.isOn else { return nil }
        let recording = voiceAudio(listener)
        return Task.detached(priority: .userInitiated) { (entry, voice.turnEnded(recording, entry: entry)) }
    }

    /// The last look before the request runs: true when the turn was closed for its voice. Notes the turn's speaker,
    /// which the request carries and an early request must agree with (ArisVoiceDecisions.sameTag).
    func voiceClosesTurn(_ check: Task<(ArisTurnEntry, ArisVoiceMatch?), Never>?) async -> Bool {
        guard let check else { return false }
        let (entry, match) = await check.value
        let voice = ArisVoiceID.shared
        if let match {
            log.notice("voice id: \(entry.rawValue, privacy: .public) turn, \(match.verdict.rawValue, privacy: .public) (\(match.why, privacy: .public), score \(match.score.map { String(format: "%.2f", $0) } ?? "none", privacy: .public), \(String(format: "%.1f", match.seconds), privacy: .public) s)")
        }
        voice.note(ArisVoiceDecisions.speaker(entry, match: match), for: ArisTurnScope.current ?? kernel.current)
        guard ArisVoiceDecisions.wake(match, entry: entry, lastClose: voice.lastVoiceClose, now: Self.uptime) == .closeNotOwner else { return false }
        voice.closedForVoice(at: Self.uptime)
        ArisTuningLog.append(["path": ArisWakeDoubt.QuietEnd.notOwner.path, "entry": entry.rawValue,
                              "voiceScore": match?.score.map(Double.init) ?? -1], to: "wake-log.jsonl")
        if turnByWakeWord {
            closeWakeTurnQuietly(.notOwner)
        } else {
            log.notice("voice id: not the owner's voice: not a turn")
            dropFalseStart()
        }
        // Never a silent lock-out: one quiet line (no sound, at most every ten minutes) says the key always works.
        if voice.takeNotice(at: Self.uptime) {
            let line = ArisVoiceDecisions.closedLine(english: ArisUILanguage.english)
            Task { await self.notify(ArisNotice(key: "voiceid.closed", kind: .system, title: "Aris", body: line, showsWithin: 30, showsFor: 8)) }
        }
        return true
    }

    /// Whether a turn whose voice is checked may send its request before it is over: only when the voice so far is the
    /// owner's, and then that verdict is noted for the turn before the request is built (with no print, or the switch
    /// off, as today).
    func voiceAllowsEarlyRequest() async -> Bool {
        let voice = ArisVoiceID.shared
        guard voice.isOn, ArisVoiceDecisions.checks(voiceEntry()) else { return true }
        let samples = (listener as? ArisListener).map(voiceAudio) ?? []
        let match = await Task.detached(priority: .userInitiated) { voice.check(samples) }.value
        guard ArisVoiceDecisions.early(match) else { return false }
        if match != nil { voice.note(.voiceMatched, for: ArisTurnScope.current ?? kernel.current) }
        return true
    }

    /// The owner-or-not the turn's speaker has now, for the early request's key (ArisEarlyKey.voiceOwner).
    func voiceOwnerTag() -> Bool { ArisVoiceDecisions.ownerTag(ArisVoiceID.shared.speaker(for: ArisTurnScope.current ?? kernel.current)) }

    /// A spoken yes on a card: whether it counts (always, unless the voice is clearly not the owner's).
    func spokenYesCounts(_ samples: [Float]) async -> Bool {
        let voice = ArisVoiceID.shared
        guard voice.isOn else { return true }
        let match = await Task.detached(priority: .userInitiated) { voice.check(samples) }.value
        guard !ArisVoiceDecisions.yesCounts(match) else { return true }
        log.notice("voice id: a spoken yes in another voice (score \(match?.score.map { String(format: "%.2f", $0) } ?? "none", privacy: .public)): not taken")
        return false
    }
}
