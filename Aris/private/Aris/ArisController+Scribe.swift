//
//  ArisController+Scribe.swift
//  Aris
//
//  Every language you turned on: the turn streams to ElevenLabs Scribe while you talk (its words
//  replace Apple's Korean-only ones in the notch), and Scribe's take on the whole turn, with its language, is what
//  Aris answers. Without the key, the setting or the network, Whisper on the Mac listens as before; after two
//  failures in a row Scribe isn't tried for a few minutes (ArisCloudBreaker).
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "scribe")

extension ArisController {
    /// How long to wait for Scribe's whole turn after you stop (it usually takes about 0.1 s).
    static let scribeTimeout: Duration = .milliseconds(2500)

    /// Starts streaming `listener`'s audio to Scribe; `replaying` is audio already recorded (the wake word's phrase).
    @available(macOS 26.0, *)
    func startScribe(for listener: ArisListener, replaying recorded: [Float] = []) {
        stopScribe()
        // ElevenLabs failed twice in a row: for a few minutes the Mac's own recognisers listen, without the wait for
        // Scribe after every turn (audit voice-imp-4).
        guard ArisCloudHealth.listening.mayTry(at: .now) else { return log.notice("Scribe is resting after failures; the Mac listens") }
        guard let scribe = ArisScribe.make(languages: Defaults[.arisLanguages], keyterms: ArisVocabulary.load(),
                                           enabled: Defaults[.arisCloudListening]) else { return }
        scribe.onText = { [weak self, weak scribe] text in
            guard let self, let scribe, self.scribe === scribe, self.session.phase == .listening, !text.isEmpty else { return }
            if text != self.session.heard { self.lastWordsAt = .now }
            self.scribeIsHearing = true
            self.session = self.session.hearing(text)
        }
        scribe.start()
        if !recorded.isEmpty { scribe.append(recorded) }
        listener.onSamples = { [weak scribe] samples in scribe?.append(samples) }
        self.scribe = scribe
        log.notice("streaming to Scribe (\(Defaults[.arisLanguages].joined(separator: ","), privacy: .public))")
    }

    func stopScribe() {
        scribe?.cancel()
        scribe = nil
        scribeIsHearing = false
    }

    /// Scribe's whole turn, or nil (no Scribe this turn, it failed, or it was too slow).
    func finishScribe() async -> ArisScribe.Heard? {
        guard let scribe else { return nil }
        let start = ContinuousClock.now
        let heard = await scribe.finish(timeout: Self.scribeTimeout)
        if self.scribe === scribe { self.scribe = nil }
        scribeIsHearing = false
        let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
        // No answer at all (it failed, or took too long) counts against ElevenLabs; an answer, even an empty one, for it.
        if heard == nil { ArisCloudHealth.listening.failed(at: .now) } else { ArisCloudHealth.listening.succeeded() }
        guard let heard, !heard.text.isEmpty else {
            log.notice("Scribe had nothing after \(milliseconds, privacy: .public) ms; Whisper listens")
            return nil
        }
        log.notice("Scribe: \(heard.text.count, privacy: .public) characters in \(heard.language ?? "?", privacy: .public), \(milliseconds, privacy: .public) ms")
        return heard
    }
}
