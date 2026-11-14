//
//  ArisController+Team.swift
//  Aris
//
//  Jobs the main brain split off: they run side by side (up to the queue's cap) and report like background tasks.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

/// How a job runs (its ArisJobPlan), and the task running it.
struct ArisJobRun {
    let tier: ArisTier
    let plan: ArisJobPlan
    let browser: Bool
    var brain: ArisBrain { plan.brain }
    var task: Task<Void, Never>?
    /// The agent's stream for this job has ended (it finished, or the agent restarted): a parked card never shows.
    var streamEnded = false
}

extension ArisJob {
    /// The history and context view of this job.
    var backgroundTask: ArisBackgroundTask {
        let view: ArisBackgroundTask.State
        switch state {
        case .queued: view = .working("대기 중")
        case .running(let step): view = .working(step)
        case .awaitingApproval: view = .working("확인 중")
        case .done(let answer): view = .done(answer)
        case .failed(let message): view = .failed(message)
        case .cancelled: view = .failed("취소됨")
        }
        return ArisBackgroundTask(id: id, title: title, state: view)
    }

    var isFinished: Bool {
        switch state {
        case .queued, .running, .awaitingApproval: return false
        case .done, .failed, .cancelled: return true
        }
    }
}

extension ArisController {
    /// The teammates the main brain may name in a jobs block: the user's list (the 팀원 page), Claude Code always.
    static var teammateIds: Set<String> { ArisDispatch.teammateIds(ArisTeamModel.shared.teammates) }

    /// Hands a turn's work out as ArisHandOutPlan says and returns the line Aris says (ArisHandoffLine), and the job when
    /// it was one (its result updates the turn's 기록 entry). `specs` empty: one job of the user's words ("해 놔", or a jobs
    /// block the agent refused). `browser`: website work, for Aside.
    func handOut(_ specs: [ArisJobSpec], turn: ArisHandOutPlan.Turn, tier: ArisTier, korean: Bool, browser: Bool = false) -> (line: String, job: UUID?) {
        // Aris's own schedules, to-dos, memory, teammates, timers and settings stay in the main turn (QA BUG-60): nothing
        // is dispatched, whoever asked for the hand-out (the brain's jobs block, the router's website work, "해 놔").
        if ArisHandOutPlan.keepsInTurn(specs, turn: turn) {
            log.notice("hand-out kept: it is about Aris's own data")
            return (ArisHandOutPlan.keptLine(korean: korean), nil)
        }
        let brains = Dictionary(ArisTeamModel.shared.teammates.map { ($0.id, ArisBrain.named($0.brain)) }, uniquingKeysWith: { first, _ in first })
        // Which brains are set up on this Mac, as the agent last said (asked again as each turn starts): a teammate whose
        // own brain isn't hands its job to Aris itself, said in the line, and an untrusted job asks for a gated brain
        // that is here (audit imp-4, team-7: ArisJobRouting).
        let ready = ArisTeamModel.shared.brains
        let (specs, fellBack) = ArisJobRouting.withoutUnreadyTeammates(specs, brains: brains, ready: ready)
        // Helpers number on from the ones still at work, each with a face of its own (N14).
        let plans = ArisHandOutPlan.plan(specs, turn: turn, brains: brains, helpersTaken: ArisHelpers.taken(jobs), ready: ready)
        let single = plans.count == 1 && plans[0].spec.assignee == .clone
        log.notice("handing out \(plans.count, privacy: .public) job(s)\(plans.contains { $0.provenance.untrusted } ? " (untrusted)" : "", privacy: .public)")
        let created = dispatch(plans, tier: single ? (tier == .critical ? .critical : .work) : tier, browser: browser)
        let job = created.count == 1 ? created.first : nil
        if browser { return (ArisHandoffLine.line(["Aside"], korean: korean), job) }
        let notes = fellBack.compactMap { id in
            brains[id].map { ArisJobRouting.fallbackLine(name: teammateName(.teammate(id)) ?? id, brain: $0, korean: korean) }
        }
        if !fellBack.isEmpty { log.notice("\(fellBack.count, privacy: .public) teammate job(s) went to Aris: the teammate's brain isn't set up") }
        return (([ArisHandoffLine.line(plans.map(\.spec.assignee).map(teammateName), korean: korean)] + notes).joined(separator: " "), job)
    }

    /// Who took a job, as the user named them (a helper by its number); nil for Aris itself.
    private func teammateName(_ assignee: ArisJobAssignee) -> String? {
        if case .helper(let index) = assignee { return ArisHelpers.name(index) }
        guard case .teammate(let id) = assignee else { return nil }
        return (ArisTeamModel.shared.teammates + [ArisTeammate.claudeCode]).first { $0.id == id }?.name ?? id
    }

    /// Creates a job for each plan and starts as many as the queue allows; the rest wait their turn. Returns their ids.
    @discardableResult
    func dispatch(_ plans: [ArisJobPlan], tier: ArisTier, browser: Bool = false) -> [UUID] {
        let created = plans.map { plan in
            (ArisJob(id: UUID(), title: plan.spec.title, prompt: plan.spec.prompt, assignee: plan.spec.assignee, cwd: plan.spec.cwd,
                     appHint: plan.spec.appHint, target: .notch, state: .queued, created: Date()), plan)
        }
        let kept = jobs.filter(\.isFinished).suffix(Self.keptTasks) + jobs.filter { !$0.isFinished }
        jobs = Array(kept) + created.map(\.0)
        let ids = Set(jobs.map(\.id))
        jobFiles = jobFiles.filter { ids.contains($0.key) }
        seenDone = seenDone.intersection(ids)
        for (job, plan) in created {
            jobRuns[job.id] = ArisJobRun(tier: tier, plan: plan, browser: browser, task: nil)
        }
        log.notice("dispatching \(created.count, privacy: .public) jobs")
        // What is under way is kept on disk, so a quit or a crash can say what it cut off (ArisJobLedger).
        ArisJobLedger.note(jobs)
        for id in jobQueue.admit(created.map(\.0.id)) { start(id) }
        return created.map(\.0.id)
    }

    /// Stops a job: a waiting one never starts, a running one is interrupted and its slot goes to the next.
    func cancelJob(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), !job.isFinished else { return }
        // The agent is told by POST /cancel (its parked questions are declined and its AI stops): closing the stream
        // alone no longer ends a task while the app runs.
        if jobRuns[id]?.task != nil {
            var parked: String?
            if case .awaitingApproval(let question) = job.state { parked = question }
            Task { [weak self] in await self?.cancelInAgent(id, parked: parked) }
        }
        setState(id, .cancelled)
        jobRuns[id]?.task?.cancel()
        jobQueue.cancel(id)
        finish(id)
    }

    /// POST /cancel, tried `ArisJobCancel.attempts` times with backoff. When the agent never confirms it, the parked
    /// question (if any) is answered no and the job says it may still be running. True when the agent confirmed.
    @discardableResult
    func cancelInAgent(_ id: UUID, parked: String?, markUnconfirmed: Bool = true) async -> Bool {
        for attempt in 1...ArisJobCancel.attempts {
            if await ArisAgentClient.cancel(job: id) { return true }
            if attempt < ArisJobCancel.attempts { try? await Task.sleep(for: ArisJobCancel.delay(after: attempt)) }
        }
        log.error("the agent didn't confirm a job's cancel")
        if let parked { _ = await ArisAgentClient.confirm(parked, allow: false) }
        if markUnconfirmed {
            // Past the cancelled guard in setState: this is what the job really is now.
            jobs = jobs.map { job in
                guard job.id == id else { return job }
                var changed = job
                changed.state = .failed(ArisJobCancel.unconfirmed)
                return changed
            }
            ArisJobLedger.note(jobs)
        }
        return false
    }

    /// Frees the job's slot (if it had one) and starts the next waiting job.
    func finish(_ id: UUID) {
        jobRuns[id] = nil
        if let next = jobQueue.finished(id) { start(next) }
    }

    func setState(_ id: UUID, _ state: ArisJobState) {
        jobs = jobs.map { job in
            // A cancelled job stays cancelled, whatever its process says on the way out.
            guard job.id == id, job.state != .cancelled else { return job }
            var changed = job
            changed.state = state
            return changed
        }
        ArisJobLedger.note(jobs)
    }

    private func start(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), var run = jobRuns[id], job.state != .cancelled else {
            finish(id)
            return
        }
        setState(id, .running(step: ""))
        run.task = Task { [weak self] in
            if case .teammate(ArisTeammate.claudeCodeId) = job.assignee {
                await self?.runTeammate(job, run)
            } else {
                await self?.run(job, run)
            }
            self?.finish(id)
        }
        jobRuns[id] = run
    }

    /// Runs one job in its own AI process and speaks up when it needs an answer or is done. A teammate other than
    /// Claude Code (runTeammate) runs here too, under its own name and face (the agent logs its id). Its answer is
    /// never parsed as a dispatch. An answer is a job done only by ArisJobVerdict: a job that did nothing is asked once
    /// more with a firmer instruction, then reported as not done (never a green tick: seventh VM pass).
    private func run(_ job: ArisJob, _ run: ArisJobRun) async {
        var prompt = job.prompt
        for attempt in 0..<2 {
            guard let ended = await runOnce(job, run, prompt: prompt) else { return }
            switch ArisJobVerdict.judge(task: job.prompt, answer: ended.answer, work: ended.work) {
            case .done:
                return await reportDone(job, answer: ended.answer, file: ended.file)
            case .notDone(let why):
                if attempt == 0, ArisJobVerdict.retries(why, work: ended.work), !Task.isCancelled {
                    log.notice("background task not done (\(why.rawValue, privacy: .public)): asked once more")
                    setState(job.id, .running(step: ""))
                    prompt = job.prompt + ArisJobVerdict.firmer(korean: ArisSpeech.language(of: job.title) == "ko-KR")
                    continue
                }
                return await reportNotDone(job, run, answer: ended.answer, why: why)
            }
        }
    }

    /// One ask of a job's AI process: its answer, saved file and counted work; nil when it ended otherwise (a failure,
    /// said already; a cancel; a cut-off stream, said already).
    private func runOnce(_ job: ArisJob, _ run: ArisJobRun, prompt: String) async -> (answer: String, file: String?, work: ArisJobWork?)? {
        var savedFile: String?
        var work: ArisJobWork?
        let teammate: String? = if case .teammate(let id) = job.assignee { id } else { nil }
        // A helper's name, so the 한 일 tab files its rows under "도우미 N", not its brain (N14).
        let helper: String? = if case .helper(let index) = job.assignee { ArisHelpers.name(index) } else { nil }
        let plan = run.plan
        let source = ArisAgentClient.ask(prompt, context: await currentContext(conversation: !plan.cleanContext), tier: run.tier, brain: plan.brain,
                                         task: job.title, job: job.id, browser: run.browser, untrusted: plan.provenance.untrusted, request: plan.request,
                                         screenConversation: plan.provenance.screenConversation,
                                         outsideConversation: plan.provenance.outsideConversation, handsFree: plan.provenance.handsFree,
                                         teammate: teammate, helper: helper)
        // Relayed, so the end of the agent's stream is noted even while a question is parked here.
        let (replies, relay) = AsyncStream.makeStream(of: ArisAgentReply.self)
        jobRuns[job.id]?.streamEnded = false
        let pump = Task { [weak self] in
            for await reply in source { relay.yield(reply) }
            self?.jobRuns[job.id]?.streamEnded = true
            relay.finish()
        }
        defer { pump.cancel() }
        // Only this job's own "working on this window" overlay comes down with it.
        defer { ArisOperatingOverlay.shared.end(owner: job.id) }
        for await reply in replies {
            guard !Task.isCancelled else { return nil }
            switch reply {
            case .status(let status):
                setState(job.id, .running(step: status))
            case .delta:
                break
            case .file(let path):
                savedFile = path
            case .confirm(let ask):
                guard await settle(ask, of: job) else { return nil }
            case .work(let counted):
                work = counted
            case .stepFailed, .turn, .launched, .untrusted, .refusedJobs, .shownOnly, .skill, .helperAnswers, .savedSteps:
                break
            case .operating(let target):
                // A job working in another app's window: the same overlay, and its step in the job's row.
                ArisOperatingOverlay.shared.show(target, owner: job.id)
                setState(job.id, .running(step: target.line))
            case .answer(let answer):
                return (answer, savedFile, work)
            case .failure(let message):
                // The stream may have failed while the task still runs in the agent: make sure it stops.
                Task { [weak self] in await self?.cancelInAgent(job.id, parked: nil, markUnconfirmed: false) }
                // A stream that died with the agent already says so by name (ArisJobLoss, from the error's code); any
                // other failure is said with the agent's own reason (audit team-3).
                await reportFailure(job, message)
                return nil
            }
        }
        // The stream ended without an answer or a failure: don't leave the job running forever, here or in the agent,
        // and say so (it used to end as "중단됨" in the tray with nothing said and its 기록 entry unchanged).
        if jobs.first(where: { $0.id == job.id })?.isFinished == false {
            Task { [weak self] in await self?.cancelInAgent(job.id, parked: nil, markUnconfirmed: false) }
            await reportFailure(job, ArisJobFailure.cutOff(korean: ArisSpeech.language(of: job.title) == "ko-KR"))
        }
        return nil
    }

    /// A job whose answer isn't a job done (ArisJobVerdict): its tray row fails with why, its 기록 entry says so, and its
    /// card is a problem's (never the green tick) with what it answered and 다시 시도, which hands it out again.
    func reportNotDone(_ job: ArisJob, _ run: ArisJobRun, answer: String, why: ArisJobVerdict.Why) async {
        log.notice("background task not done: \(why.rawValue, privacy: .public)")
        let korean = ArisSpeech.language(of: job.title) == "ko-KR"
        let english = ArisUIWords.english
        let reason = ArisJobVerdict.reason(why, korean: korean)
        let report = ArisSpeakable.report(answer, korean: korean)
        let shown = [reason, report.shown].filter { !$0.isEmpty }.joined(separator: " ")
        setState(job.id, .failed(reason))
        finish(job.id)
        flashTaskDone()
        notDoneJobs[job.id] = run
        pastTurns = ArisHistory.finishing(job: job.id, title: job.title, shown: ArisJobFailure.shown(reason: shown, korean: korean), file: nil, in: pastTurns)
        ArisHistory.save(pastTurns)
        let card = ArisNoticeRoute.jobNotDone(title: job.title, shown: shown, job: job.id, english: english)
        let said = ArisJobFailure.said(title: job.title, reason: reason, korean: korean)
        await notify(card, saying: ArisSpeakable.speakable(said), parking: said)
    }

    /// The not-done card's 다시 시도: the same job, handed out again as it ran.
    func retryNotDone(_ id: UUID) {
        guard let run = notDoneJobs.removeValue(forKey: id) else { return }
        log.notice("background task handed out again")
        dispatch([run.plan], tier: run.tier, browser: run.browser)
    }

    /// A job's question parks (the agent holds it for a day) until Aris is free and the user is at the Mac; meanwhile its
    /// slot goes to the next job, and it comes back when the question is settled. A card his turn covered, or one nobody
    /// answered, waits in 확인 대기 and is never sent as his no (ArisController+CardPark). False when the job was cancelled.
    func settle(_ ask: ArisConfirmation, of job: ArisJob) async -> Bool {
        setState(job.id, .awaitingApproval(id: ask.id))
        if let next = jobQueue.pause(job.id) { start(next) }
        defer { jobQueue.resume(job.id) }
        let handsFree = jobRuns[job.id]?.plan.provenance.handsFree ?? true
        let settled = await settleCard(ask, title: job.title, job: job.id, handsFree: handsFree) { [weak self] in
            self?.jobRuns[job.id]?.streamEnded ?? true
        }
        guard settled != .cancelled, !Task.isCancelled else { return false }
        setState(job.id, .running(step: ""))
        return true
    }

    func reportDone(_ job: ArisJob, answer: String, file: String?) async {
        log.notice("background task done")
        // Work Aris did itself (no teammate): counted by kind, once a hand-out, for the offer to make a teammate (ArisTeamSuggestion).
        if let plan = jobRuns[job.id]?.plan, plan.countsTowardSuggestion { noteFinishedJob(plan.request) }
        // Shown without code or data blocks, never read aloud as code (ArisSpeakable), like any answer.
        let report = ArisSpeakable.report(answer, korean: ArisSpeech.language(of: job.title) == "ko-KR")
        setState(job.id, .done(report.shown))
        finish(job.id)
        flashTaskDone()
        // The hand-out turn's entry becomes the result's, so the 기록 tab lists the request once.
        pastTurns = ArisHistory.finishing(job: job.id, title: job.title, shown: report.shown, file: file, in: pastTurns)
        ArisHistory.save(pastTurns)
        // The long rest, saved by the agent, opens in Aris's reader (it used to open in the .md's default app).
        if let file {
            jobFiles[job.id] = file
            ArisBoard.shared.read(file: file)
        }
        // On a card under the notch at the next pause, one at a time (in a conversation: when neither the user nor Aris is
        // talking), and said once when Aris may speak.
        let card = ArisNoticeRoute.jobDone(title: job.title, shown: report.shown, job: job.id, english: ArisUIWords.english)
        await notify(card, saying: report.spoken, parking: report.shown) {
            // An untrusted job's answer in the context is outside text: the conversation dispatches nothing after it.
            self.outsideConversation = true
            self.history = ArisContext.remembering(ArisContext.Turn(heard: job.title, reply: report.shown), after: self.history)
        }
    }

    /// A job that didn't finish: its tray row and its 기록 entry say why (the hand-out turn's entry used to keep
    /// "맡았어요" for good), and Aris says it at the next pause, with the agent's own reason ("Gemini 로그인이 필요해요…")
    /// rather than only "못 끝냈어요" (audit team-3). `said`: the whole line to say instead, when the caller has one.
    func reportFailure(_ job: ArisJob, _ message: String, said: String? = nil) async {
        log.error("background task failed: \(message, privacy: .public)")
        setState(job.id, .failed(message))
        finish(job.id)
        flashTaskDone()
        let korean = ArisSpeech.language(of: job.title) == "ko-KR"
        // The reason as it can be shown and read: no code or data block, one short paragraph (ArisSpeakable).
        let reason = ArisJobFailure.reason(ArisSpeakable.shown(message, korean: korean))
        pastTurns = ArisHistory.finishing(job: job.id, title: job.title, shown: ArisJobFailure.shown(reason: reason, korean: korean), file: nil, in: pastTurns)
        ArisHistory.save(pastTurns)
        let said = said ?? ArisJobFailure.said(title: job.title, reason: reason, korean: korean)
        let spoken = ArisSpeakable.speakable(said)
        let card = ArisNoticeRoute.jobFailed(title: job.title, shown: ArisJobFailure.shown(reason: reason, korean: korean))
        await notify(card, saying: spoken.isEmpty ? said : spoken, parking: said)
    }
}
