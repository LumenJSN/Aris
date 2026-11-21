//
//  ArisController+Scribe.swift
//  Aris
//
//  The turn's live cloud recogniser. The plan for the turn (ArisHearPlan: the engine chosen in Settings, the keys
//  saved, who is resting after failures) names the engine that streams while you talk: ElevenLabs Scribe or Soniox.
//  Its words replace Apple's in the notch, and its take on the whole turn, with its language, is what Aris answers.
//  Why a chosen engine isn't listening is always a line in the log. When it gives no answer the next engines read the
//  recording (ArisController+Hear).
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "scribe")

extension ArisController {
    /// How long to wait for the live engine's whole turn after you stop (it usually takes about 0.1 s).
    static let scribeTimeout: Duration = .milliseconds(2500)

    /// Starts streaming `listener`'s audio to the plan's live engine; `replaying` is audio already recorded (the wake word's phrase).
    func startScribe(for listener: ArisListener, replaying recorded: [Float] = []) {
        stopScribe()
        let plan = ArisHearSetup.plan()
        hearPlan = plan
        liveFailed = nil
        for note in plan.notes { log.notice("\(note, privacy: .public)") }
        guard let engine = plan.live, let scribe = ArisHearSetup.live(engine, ArisHearSetup.request()) else {
            return log.notice("hearing (\(plan.choice.logName, privacy: .public)): nothing streams this turn; \(plan.cloud.first?.logName ?? "the Mac", privacy: .public) reads the recording")
        }
        scribe.onText = { [weak self, weak scribe] text in
            guard let self, let scribe, self.scribe === scribe, self.session.phase == .listening, !text.isEmpty else { return }
            if text != self.session.heard { self.lastWordsAt = .now }
            self.scribeIsHearing = true
            self.setSession(self.session.hearing(text))
        }
        scribe.start()
        if !recorded.isEmpty { scribe.append(recorded) }
        listener.onSamples = { [weak scribe] samples in scribe?.append(samples) }
        self.scribe = scribe
        log.notice("hearing (\(plan.choice.logName, privacy: .public)): streaming to \(engine.logName, privacy: .public) (\(ArisHearSetup.languages.joined(separator: ","), privacy: .public))")
    }

    func stopScribe() {
        scribe?.cancel()
        scribe = nil
        scribeIsHearing = false
    }

    /// The live engine's whole turn, or nil (none this turn, it failed, or it was too slow).
    func finishScribe() async -> ArisHeard? {
        guard let scribe else { return nil }
        let start = ContinuousClock.now
        let heard = await scribe.finish(timeout: Self.scribeTimeout)
        if self.scribe === scribe { self.scribe = nil }
        scribeIsHearing = false
        let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
        let name = scribe.engine.logName
        // No answer at all (it failed, or took too long) counts against the engine; an answer, even an empty one, for it.
        ArisHearSetup.note(scribe.engine, answered: heard != nil)
        guard let heard else {
            liveFailed = scribe.engine
            log.notice("\(name, privacy: .public) gave no answer after \(milliseconds, privacy: .public) ms")
            return nil
        }
        guard !heard.text.isEmpty else {
            log.notice("\(name, privacy: .public) heard no words (\(milliseconds, privacy: .public) ms); Whisper listens")
            return nil
        }
        log.notice("\(name, privacy: .public): \(heard.text.count, privacy: .public) characters in \(heard.language ?? "?", privacy: .public), \(milliseconds, privacy: .public) ms")
        return heard
    }
}
