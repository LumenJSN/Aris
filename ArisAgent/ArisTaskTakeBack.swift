//
//  ArisTaskTakeBack.swift
//  aris-agent
//
//  At the helper's start, after what an earlier helper left running was stopped (ArisChildLedger.sweep): every task
//  whose journal has no end is taken back as ArisTaskRecovery plans it. A task that waited on a card waits on the same
//  card again (a new id: ArisRecoveredCards), and goes on once the user answers it; one that can reopen its brain's session
//  does; the rest start again told what was done; one that can't be taken back says so. Its replies go to the inbox
//  under its job's id (ArisTaskFollow), so the app follows it by id. How a task is started is `Hooks.launch`
//  (ArisTaskRecoveryLive: a runner behind the same gates), so the tests run every branch with a fake.
//
//  What each brain can take back (claude 2.1.327 `--help`, codex-cli 0.169.0 `app-server generate-json-schema`):
//  · the open Claude's job keeps its session (`--session-id`, persisted), reopened with `-p --resume <id>` in
//    stream-json, in the same folder (a missing one ends at once with "No conversation found", no model call);
//  · Codex's job thread is not ephemeral, reopened with `thread/resume {threadId}`;
//  · the sealed or hands-free Claude (its folder goes with it), the API brain and Antigravity keep nothing: a new
//    process is told what was done.
//

import Foundation

enum ArisTaskTakeBack {
    struct Hooks {
        /// Starts the task: `prompt` for its brain, `session` to reopen (nil: a new process). Returns how it was taken
        /// back (`.resumed` only when the same brain reopens it), or nil when it couldn't start (the reason).
        var launch: (_ state: ArisTaskState, _ prompt: String, _ session: String?) -> Result<ArisTaskRecord.Recovery, ArisTakeBackRefusal>
        /// One line for actions.log.
        var audit: (String) -> Void = { _ in }
        /// What nudges the app after an inbox entry.
        var nudge: (() -> Void)? = ArisTaskFollow.nudgeApp
    }

    /// Whether this task's brain can reopen its session here.
    static func canResume(_ state: ArisTaskState) -> Bool {
        switch ArisBrain(rawValue: state.brain) {
        case .claude?: return !state.origin.sealedHandsFree
        case .codex?: return true
        default: return false
        }
    }

    /// Every open journal, taken back. Called once, at start, before the app can ask. The plans, in order (for the log
    /// and the tests).
    @discardableResult
    static func run(home: String, now: Date = Date(), hooks: Hooks, cards: ArisRecoveredCards = .shared) -> [ArisTaskRecoveryPlan] {
        ArisTaskJournal.prune(home: home, now: now)
        // A job's card in the inbox belongs to the last launch: it is asked again below under a new id, or not at all.
        ArisInbox.removeJobQuestions(file: ArisInbox.file(home: home))
        cards.audit = hooks.audit
        cards.inbox = ArisInbox.file(home: home)
        cards.carryOn = { state, card, allow, how in
            ArisTaskJournal.append(.answer(card.id, allow: allow, how: allow ? nil : how == "expired" ? "expired after the restart" : "after the restart"),
                                   job: state.job, home: home)
            let fresh = ArisTaskJournal.state(job: state.job, home: home) ?? state
            start(fresh, plan: ArisTaskRecovery.carryOn(fresh, canResume: canResume(fresh), answered: (card, allow)), home: home, hooks: hooks, cards: cards)
        }
        var plans: [ArisTaskRecoveryPlan] = []
        for state in ArisTaskJournal.all(home: home) where state.isOpen {
            let plan = ArisTaskRecovery.plan(state, canResume: canResume(state), now: now)
            plans.append(plan)
            start(state, plan: plan, home: home, hooks: hooks, cards: cards)
        }
        return plans
    }

    /// Carries out one plan.
    static func start(_ state: ArisTaskState, plan: ArisTaskRecoveryPlan, home: String, hooks: Hooks, cards: ArisRecoveredCards = .shared) {
        let follow = ArisTaskFollow(job: state.job, title: state.title, inbox: ArisInbox.file(home: home), live: nil, nudge: hooks.nudge)
        switch plan {
        case .none:
            return
        case .lost(let reason):
            lose(state, reason: reason, follow: follow, home: home)
        case .waitCard(let card):
            ArisTaskJournal.append(.recovered(.waiting), job: state.job, home: home)
            let parked = cards.park(state, card: card)
            ArisTaskJournal.append(.card(parked), job: state.job, home: home)
            hooks.audit(auditLine("asked again after the helper restarted", job: state.job))
            follow.deliver(.confirm(ArisConfirmation(id: parked.id, title: parked.title, detail: parked.detail, full: parked.full)))
        case .resume(let session, let note):
            launch(state, prompt: note, session: session, follow: follow, home: home, hooks: hooks)
        case .restart(let prompt):
            launch(state, prompt: prompt, session: nil, follow: follow, home: home, hooks: hooks)
        }
    }

    private static func launch(_ state: ArisTaskState, prompt: String, session: String?, follow: ArisTaskFollow, home: String, hooks: Hooks) {
        switch hooks.launch(state, prompt, session) {
        case .success(let how):
            hooks.audit(auditLine(how == .resumed ? "resumed after the helper restarted" : "restarted after the helper restarted", job: state.job))
        case .failure(.cancelled):
            ArisTaskJournal.append(.ended(.cancelled), job: state.job, home: home)
        case .failure(.refused(let reason)):
            lose(state, reason: reason, follow: follow, home: home)
        }
    }

    static func lose(_ state: ArisTaskState, reason: String, follow: ArisTaskFollow, home: String) {
        ArisTaskJournal.append(.ended(.lost, line: reason), job: state.job, home: home)
        try? FileHandle.standardError.write(contentsOf: Data("aris-agent: job \(state.job.prefix(8)) not taken back: \(reason)\n".utf8))
        follow.deliver(.failure(lostLine(state.title)))
    }

    /// What the app hears of a job that couldn't be taken back.
    static func lostLine(_ title: String) -> String {
        let korean = title.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
        return korean ? "Aris가 다시 시작되면서 ‘\(title)’ 일을 이어서 하지 못했어요. 다시 맡겨 주세요."
                      : "Aris restarted and couldn't pick up “\(title)” again. Hand it over again."
    }

    private static func auditLine(_ answer: String, job: String) -> String {
        let object = ["answer": answer, "question": "job " + job]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

enum ArisTakeBackRefusal: Error, Equatable {
    /// The job was cancelled meanwhile.
    case cancelled
    /// It can't run as it ran (its teammate is gone).
    case refused(String)
}

/// POST /tasks {"op": "list", "jobs": ["<uuid>", …]}: each job as its journal and the helper know it, so the app can
/// show "picked up again" in place of "cut off", and wait for the inbox.
enum ArisTaskRoutes {
    static let listLimit = 200

    /// `running(job)`: a runner of this launch has it. `live(job)`: the card it showed on its stream that still waits
    /// (ArisTaskFollow.waitingCard). A job waiting on a card says so, with the card (its id is what POST /confirm takes).
    static func list(_ jobs: [String], home: String, running: (String) -> Bool, cards: ArisRecoveredCards = .shared,
                     live: (String) -> ArisConfirmation? = { _ in nil }) -> Data {
        let rows: [[String: Any]] = jobs.prefix(listLimit).compactMap { job in
            guard UUID(uuidString: job) != nil else { return nil }
            guard let state = ArisTaskJournal.state(job: job, home: home) else { return ["job": job, "state": "unknown"] }
            let isRunning = running(job)
            let card = cards.waitingCard(job: job) ?? (isRunning ? live(job).map { ArisTaskCard(id: $0.id, title: $0.title, detail: $0.detail, full: $0.full) } : nil)
            var row: [String: Any] = ["job": job, "state": word(state, running: isRunning, waiting: card != nil), "title": state.title]
            if state.isOpen, let card {
                var fields: [String: Any] = ["id": card.id, "title": card.title, "detail": card.detail]
                if let full = card.full { fields["full"] = full }
                row["card"] = fields
            }
            if let recovery = state.lastRecovery { row["recovered"] = recovery.rawValue }
            if let line = state.endLine { row["line"] = line }
            return row
        }
        return (try? JSONSerialization.data(withJSONObject: ["tasks": rows], options: .sortedKeys)) ?? Data(#"{"tasks":[]}"#.utf8)
    }

    /// The word for a job's state.
    static func word(_ state: ArisTaskState, running: Bool, waiting: Bool) -> String {
        if let ending = state.ending {
            switch ending {
            case .answered: return "done"
            case .failed, .timedOut, .stopped: return "failed"
            case .cancelled: return "cancelled"
            case .lost: return "lost"
            }
        }
        if waiting { return "waiting" }
        return running ? "running" : "lost"
    }
}
