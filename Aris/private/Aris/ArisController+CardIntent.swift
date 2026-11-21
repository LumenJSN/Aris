//
//  ArisController+CardIntent.swift
//  Aris
//
//  A listening card's second reading (ArisCardIntent): words the word rules call no answer go to the model the quick
//  understanding uses (설정 › 짧은 명령 빨리 알아듣기: TypeSafe's Jev, or an API profile through aris-agent, which holds
//  its key), and its reading is taken into the card's loop here. An approve becomes a spoken yes like any other (the
//  hold, the owner's voice, the final transcript all still apply in cardWait); a decline a spoken no; a revise goes
//  through the spoken-change rules and only re-shows the card; anything else leaves the card as it was.
//

import Foundation
import os
import SwiftUI

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisCardIntent {
    /// Asks the model the quick understanding uses. Throws `NoModel` when that is the keyword rules or no profile is
    /// connected; nil for any answer that can't be read.
    @MainActor
    static func ask(_ question: Question) async throws -> Verdict? {
        let choice = ArisRouterModels.choice(UserDefaults.standard.string(forKey: ArisRouterModels.preferenceKey))
        let route = ArisDeciders.route()
        switch route {
        case .rules: throw NoModel()
        case .jev, .decision:
            // A decision model (Jev or another) reads approve, decline, change or unrelated through the same seam.
            guard let decider = ArisDeciders.decider(route.logName), let ask = ArisDecisionAsk(systemOne: question.jev),
                  let data = try? await decider.decide(ask, timeout: timeoutSeconds), let verdict = verdict(jev: data) else { return nil }
            // It can't write a change's field and value: that part alone goes to a chat profile, when one is connected.
            guard needsChat(verdict) else { return verdict }
            return revised(verdict, chat: await askChat(question, pick: ArisRouterModels.chat(choice)))
        case .api(let profile):
            guard case .success(let object) = await ArisAgentClient.sendAPIBrains(routeBody(question, profile: profile), timeout: timeoutSeconds + 0.5) else { return nil }
            if object["none"] as? Bool == true { throw NoModel() }
            return (object["text"] as? String).flatMap(verdict(json:))
        }
    }

    /// Whether the log already said that no chat profile is connected for a card change's value.
    @MainActor private static var saidNoChat = false

    /// The chat profile's reading of the same reply, for a change's field and value; nil when none is connected (said
    /// once in the log: the change then stays one without a value, as with Jev alone before) or it gave no answer.
    @MainActor
    private static func askChat(_ question: Question, pick: ArisRouterModels.ChatPick) async -> Verdict? {
        let body = ArisRouterModels.routeBody(pick, ["op": "route", "system": question.system, "user": question.user, "schema": question.schema, "timeout": timeoutSeconds])
        guard case .success(let object) = await ArisAgentClient.sendAPIBrains(body, timeout: timeoutSeconds + 0.5) else { return nil }
        if object["none"] as? Bool == true {
            if !saidNoChat { log.notice("card change: no chat profile is connected, so a spoken change's value is not read (a decision model only picks)") }
            saidNoChat = true
            return nil
        }
        return (object["text"] as? String).flatMap(verdict(json:))
    }
}

extension ArisController {
    /// The judge for this card's spoken replies; nil for a card the model never reads (ArisCardIntent.usesModel).
    func cardJudge(_ ask: ArisConfirmation, voiceYes: Bool, ownerContent: Bool) -> ArisCardJudge? {
        guard ArisCardIntent.usesModel(ask, voiceYes: voiceYes) else { return nil }
        return ArisCardJudge(card: ArisCardIntent.card(ask, ownerContent: ownerContent), note: { log.notice("\($0, privacy: .public)") },
                             ask: { try await ArisCardIntent.ask($0) })
    }

    /// One turn of a listening card's loop for the model's reading: what was heard, as the reading leaves it, and
    /// until when the card listens.
    func judgeStep(_ judge: ArisCardJudge?, heard: ArisCardListening, ask: ArisConfirmation, editor: ArisCardEditor,
                   deadline: ContinuousClock.Instant, wait: Duration) -> (heard: ArisCardListening, deadline: ContinuousClock.Instant) {
        guard let judge else { return (heard, deadline) }
        let now = Self.uptime
        var heard = heard, deadline = deadline
        let ear = ArisCardEar.shared
        if let reading = judge.step(heard, at: now) {
            var note = ArisCardHearing.listening
            switch reading {
            case .allow: heard = heard.judging(allow: true)
            case .decline: heard = heard.judging(allow: false)
            case .notAnswer: break
            case .revise(let field, let value):
                // Only through the spoken-change rules: the card is shown again with the change and waits; it never sends.
                if let change = ArisCardRevise.apply(field: field, value: value, fields: ask.fields, values: editor.values(for: ask), now: Date(), calendar: .current) {
                    log.notice("the card changed by voice: \(change.keys.sorted().joined(separator: ","), privacy: .public)")
                    withAnimation(ArisGlass.resize) { editor.revise(change) }
                    heard = heard.consumed(at: now)
                } else {
                    heard = heard.passed()
                    note = .missedChange
                }
                deadline = ContinuousClock.now + wait
            }
            ear.set(note, card: ask.id)
        } else if let note = ArisCardIntentWait.note(thinking: judge.showsThinking(at: now), shown: ear.state.hearing(card: ask.id)) {
            ear.set(note, card: ask.id)
        }
        let remaining = Double((deadline - ContinuousClock.now) / .milliseconds(1)) / 1000
        if judge.keeps(heard, at: now, remaining: remaining) { deadline = max(deadline, ContinuousClock.now + .milliseconds(300)) }
        return (heard, deadline)
    }
}
