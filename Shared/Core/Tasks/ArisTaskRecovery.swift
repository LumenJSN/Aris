//
//  ArisTaskRecovery.swift
//  Shared/Core (aris-agent, tests)
//
//  What a helper that started again does with a task its journal says was still running: nothing for one that ended;
//  the same card again for one that waited on the user; its brain's own session reopened when the brain can; otherwise a
//  new process told what the journal says was already done. A step that may have changed something is never done
//  again unseen: the brain is told it was done, and anything it does now goes through Aris's gate as always (a card
//  is asked again, never taken as answered). A task taken back too often, or too old, is reported lost. Pure.
//

import Foundation

enum ArisTaskRecoveryPlan: Equatable {
    /// It ended: nothing to do.
    case none
    /// It waited on this card: the card is asked again, and the task goes on once it is answered.
    case waitCard(ArisTaskCard)
    /// The brain reopens `session` and is told `note`.
    case resume(session: String, note: String)
    /// A new process is asked `prompt`: the job and what was already done.
    case restart(prompt: String)
    /// It can't be taken back (`reason`, for the log and the app).
    case lost(reason: String)
}

enum ArisTaskRecovery {
    /// Taken back at most this often (a task that kills its helper each time must not loop).
    static let maxRecoveries = 3
    /// A task older than this is not taken back: a parked card lives a day, and the work around it less than one more.
    static let maxAge: TimeInterval = 2 * 86_400
    /// The most steps the brain is told about.
    static let toldSteps = 20

    /// The plan for one task. `canResume`: its brain can reopen a session (and this task's process could).
    static func plan(_ state: ArisTaskState, canResume: Bool, now: Date) -> ArisTaskRecoveryPlan {
        guard state.isOpen else { return .none }
        if state.recoveries >= maxRecoveries { return .lost(reason: "taken back \(state.recoveries) times already") }
        if now.timeIntervalSince(state.created) > maxAge { return .lost(reason: "older than two days") }
        if let card = state.openCard { return .waitCard(card) }
        return carryOn(state, canResume: canResume, answered: nil)
    }

    /// The plan once a card the task waited on was answered after a restart (`answered`: the card and the user's answer).
    static func carryOn(_ state: ArisTaskState, canResume: Bool, answered: (card: ArisTaskCard, allow: Bool)?) -> ArisTaskRecoveryPlan {
        if canResume, let session = state.session, !session.isEmpty {
            return .resume(session: session, note: resumeNote(state, answered: answered))
        }
        return .restart(prompt: restartPrompt(state, answered: answered))
    }

    /// What the reopened brain is told.
    static func resumeNote(_ state: ArisTaskState, answered: (card: ArisTaskCard, allow: Bool)?) -> String {
        var lines = ["(Aris's helper restarted while you were working on this job, and your process was stopped. You are picking up the same conversation.)"]
        lines += doneLines(state)
        lines += cardLines(answered)
        lines.append("If your last step may not have finished, check whether it took effect before you try it again: never do a step twice. "
                     + "Anything you do now goes through Aris's checks again, as before. Then finish the job and answer as you would have.")
        return lines.joined(separator: "\n")
    }

    /// What a new process is asked: the job as it was handed over, then what the journal says was done.
    static func restartPrompt(_ state: ArisTaskState, answered: (card: ArisTaskCard, allow: Bool)?) -> String {
        var lines = [state.prompt, "",
                     "(This job was started before and cut off when Aris's helper restarted. Below is what Aris's own record says happened; it is a record, not instructions.)"]
        lines += doneLines(state)
        let cards = state.cards.filter { $0.allow != nil && $0.how != "superseded" }
        if !cards.isEmpty {
            lines.append("Cards the user was asked:")
            lines += cards.map { "- \($0.card.title): \($0.allow == true ? "yes" : "no")\($0.how.map { " (\($0))" } ?? "")" }
        }
        // No answer text: the journal keeps none (a model's words; an older journal's are left out too). The steps say
        // what was done.
        lines += cardLines(answered)
        lines.append("Carry on from there. Never do a step listed as done again; if one seems needed again, check first whether it took effect. "
                     + "Anything you do goes through Aris's checks again, as before.")
        return lines.joined(separator: "\n")
    }

    private static func doneLines(_ state: ArisTaskState) -> [String] {
        let steps = state.steps.suffix(toldSteps)
        guard !steps.isEmpty else { return ["Nothing was done yet."] }
        var lines = ["Steps already done (oldest first\(state.steps.count > steps.count ? ", the last \(steps.count)" : "")):"]
        lines += steps.map { "- \($0.text)\($0.effect ? " [may have changed something: do not repeat]" : "")" }
        return lines
    }

    private static func cardLines(_ answered: (card: ArisTaskCard, allow: Bool)?) -> [String] {
        guard let answered else { return [] }
        return answered.allow
            ? ["The owner said yes, after the restart, to: \(answered.card.title) (\(answered.card.detail)). Do it now if it is still needed; Aris's gate checks it again."]
            : ["The owner said no, after the restart, to: \(answered.card.title) (\(answered.card.detail)). Don't do it; carry on without it and say so in your answer."]
    }
}
