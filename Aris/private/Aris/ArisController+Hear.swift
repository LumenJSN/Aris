//
//  ArisController+Hear.swift
//  Aris
//
//  After the live recogniser: the plan's other cloud engines read the recording when the first gave no answer (each
//  within ArisHearPlan's short limit, each step said in the log), and the words are then repaired by the fast model
//  (ArisHeardRepair) when that is on. Whatever fails here, the turn goes on with the words it already has.
//

import AppKit
import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "hearing")

extension ArisController {
    /// The recording read by the cloud engines after the live one, in the plan's order; nil when none of them answered
    /// with words (or there is none): Whisper and Apple's live words are next.
    func cloudFallback(_ recording: [Float]) async -> ArisHeard? {
        let plan = hearPlan ?? ArisHearSetup.plan()
        // An engine that answered "no words" is believed (silence, noise): only one that gave no answer is stood in for.
        let rest = plan.live == nil ? plan.cloud : liveFailed.map { plan.after($0) } ?? []
        guard !rest.isEmpty else { return nil }
        let voiceEnds = listeningSince.flatMap { since in lastVoiceAt.map { $0 - since + recordingLead } }
        let speech = ArisTranscript.trimmed(recording, voiceEndsAfter: voiceEnds, sampleRate: ArisWhisper.sampleRate)
        let request = ArisHearSetup.request()
        let start = ContinuousClock.now
        var before = liveFailed
        for engine in rest {
            guard let time = ArisHearPlan.fallbackTime(spent: .now - start) else { break }
            guard let recogniser = ArisHearSetup.recogniser(engine) else { continue }
            if let before {
                log.notice("\(before.logName, privacy: .public) gave no answer: \(engine.logName, privacy: .public) reads the recording")
            }
            let asked = ContinuousClock.now
            let heard = await recogniser.transcribe(speech, request: request, timeout: time)
            let milliseconds = Int((ContinuousClock.now - asked) / .milliseconds(1))
            ArisHearSetup.note(engine, answered: heard != nil)
            if let heard {
                log.notice("\(engine.logName, privacy: .public): \(heard.text.count, privacy: .public) characters in \(heard.language ?? "?", privacy: .public), \(milliseconds, privacy: .public) ms")
                return heard.text.isEmpty ? nil : heard
            }
            before = engine
        }
        log.notice("\(before?.logName ?? "the cloud", privacy: .public) gave no answer: the Mac's own recognisers have the turn")
        return nil
    }

    /// `words` repaired by the fast model when "repair what was heard" is on: one log line a turn, never the words.
    func repairedWords(_ words: String, apple: String) async -> String {
        guard ArisHearSetup.repairOn, !words.isEmpty, !ArisTranscript.isNotHeard(words) else { return words }
        if let until = Self.repairOffUntil, Date() < until { return words }
        let start = ContinuousClock.now
        let recent = pastTurns.prefix(2).filter { Date().timeIntervalSince($0.date) < Self.repairRemembers }.reversed()
        let context = ArisHeardRepair.Context(hints: ArisHearHints.build(ArisHearSetup.hintSources(), bounds: .repair), pairs: ArisHearSetup.pairs(),
                                              frontApp: NSWorkspace.shared.frontmostApplication?.localizedName,
                                              turns: recent.map { .init(said: $0.heard, answered: $0.reply) }, readings: [apple])
        let outcome = await ArisHeardRepair.run(raw: words, context: context) { system, user in await Self.askRepair(system: system, user: user) }
        let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
        log.notice("repair: \(words.count, privacy: .public) characters, \(outcome.note, privacy: .public), \(milliseconds, privacy: .public) ms")
        return outcome.text
    }

    /// While no chat profile is connected the repair is not asked for; one is looked for again after this long.
    static let repairLooksAgain: TimeInterval = 300
    private static var repairOffUntil: Date?

    /// Only a conversation this fresh is shown to the repair (older turns are about something else).
    static let repairRemembers: TimeInterval = 600

    /// The fast model the quick understanding already uses (aris-agent's "route": it holds the key): the API profile
    /// picked for it in Settings, else the cheapest connected one. Nil when there is none or it fails.
    private static func askRepair(system: String, user: String) async -> String? {
        let parts = ArisHeardRepair.limit.components
        let body: [String: Any] = ["op": "route", "system": system, "user": user, "schema": ArisHeardRepair.schema,
                                   "timeout": Double(parts.seconds) + Double(parts.attoseconds) / 1e18]
        // Only a chat profile can rewrite words (a decision model only picks): the one chosen, else the cheapest connected.
        let pick = ArisRouterModels.chat(ArisRouterModels.choice(UserDefaults.standard.string(forKey: ArisRouterModels.preferenceKey)))
        guard case .success(let object) = await ArisAgentClient.sendAPIBrains(ArisRouterModels.routeBody(pick, body), timeout: 2) else { return nil }
        if object["none"] as? Bool == true {
            // No chat profile is connected: the repair stays off, said once, and is looked for again later.
            log.notice("repair is off: no chat profile is connected (a decision model can't rewrite words)")
            repairOffUntil = Date().addingTimeInterval(repairLooksAgain)
            return nil
        }
        return object["text"] as? String
    }
}
