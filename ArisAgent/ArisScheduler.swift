//
//  ArisScheduler.swift
//  aris-agent
//
//  Runs scheduled jobs (schedules.json, made by `aris-tools schedule add` after the user's yes) when they are due, and
//  leaves what they produce in the inbox (inbox.jsonl) with a nudge to the app (com.lumenjsn.aris.inbox), which says
//  it when the user is there, even if the app was closed when the job ran. A job's prompt was written by a model, so every
//  run is untrusted, runs behind its brain's gate for outside words (whichever AI can run here: ArisJobBrain), and
//  carries no words of the user's (no target is known, nothing is a dictated message); its questions park for the user (a day at most) like any background task's. A wall-clock timer
//  ticks every 30 seconds; an idle tick only looks at the store's modification time. A run missed while the Mac slept
//  (or the agent was down) runs once, not once per missed time, and says it is late. A failed run is tried again after
//  2, 10 and 30 minutes; a one-time job is never dropped for a failure. A store that can't be used (not the user's private
//  file) is said in the inbox once. Removing a schedule (or undoing its creation) cancels its run.
//

import Foundation

final class ArisScheduler {
    static let shared = ArisScheduler()

    static let interval: TimeInterval = 30
    static let notification = "com.lumenjsn.aris.inbox"
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.agent.scheduler", qos: .utility)
    private var timer: DispatchSourceTimer?
    /// Everything below is touched on `queue` only.
    /// Jobs running now, with their runner once it started.
    private var running: Set<UUID> = []
    private var runners: [UUID: ArisAgentRunner] = [:]
    /// A run's questions waiting for the user, and a long result's saved file, by running job.
    private var parked: [UUID: [String]] = [:]
    private var files: [UUID: String] = [:]
    /// The time a running job was due, when it started late (the Mac slept, the agent was down).
    private var lateSince: [UUID: Date] = [:]
    /// The user was told the store can't be used (reportRefusal).
    private var refusalTold = false
    private var watch = ArisScheduleWatch()
    /// The time zone the stored run times were last checked in (nil until the first tick).
    private var zone: String?
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private var store: URL { ArisScheduleStore.file(home: home) }
    private var inbox: URL { ArisInbox.file(home: home) }

    /// At the agent's start: what the last run left over is settled, then the timer starts.
    func start() {
        queue.async { [self] in
            recover()
            // The app may have looked before the agent was up.
            if !ArisInbox.load(file: inbox).isEmpty { notifyApp() }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(wallDeadline: .now() + 5, repeating: Self.interval, leeway: .seconds(5))
            timer.setEventHandler { [weak self] in self?.check() }
            timer.resume()
            self.timer = timer
        }
    }

    /// Runs that were going, and questions that were parked, when the agent stopped are over: the user is told, the
    /// questions count as declined (never asked again: their ids belong to the last launch), and none is resumed.
    private func recover() {
        var interrupted: [ArisScheduledJob] = []
        ArisScheduleStore.update(file: store) { jobs in
            let recovered = ArisSchedule.recovered(jobs)
            interrupted = recovered.interrupted
            return recovered.jobs
        }
        ArisInbox.removeAllQuestions(file: inbox)
        for job in interrupted {
            for question in job.parked {
                ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "expired (agent restarted)", "question": question]), key: "schedule")
            }
            let declined = job.parked.isEmpty ? "" : " 기다리던 확인은 거절로 처리했어요."
            // A one-time job whose run was cut off is kept, stopped (ArisSchedule.recovered): part of it may be done.
            let kept = job.nextRun == nil ? " 한 번만 하는 예약이라 다시 하지는 않고, 지우지 않고 남겨 뒀어요. 다시 하려면 말해 주세요." : ""
            ArisInbox.append(entry(.note, job: job, text: "‘\(job.title)’ 예약 작업이 Aris가 다시 시작되면서 중단됐어요.\(declined)\(kept)"), file: inbox)
        }
    }

    /// The store is there but can't be used (ArisScheduleStore.refusal): no schedule runs, and the user is told once (again
    /// only after it was fine in between).
    private func reportRefusal() {
        let reason = ArisScheduleStore.refusal(file: store)
        defer { refusalTold = reason != nil }
        guard let reason, !refusalTold else { return }
        try? FileHandle.standardError.write(contentsOf: Data("aris-agent: schedules can't run: \(store.path): \(reason)\n".utf8))
        ArisInbox.append(ArisInboxEntry(id: UUID(), date: Date(), kind: .note, schedule: nil, title: "예약 작업이 멈췄어요",
                                        text: "예약 파일(schedules.json)의 권한이 맞지 않아서(\(reason)) 예약 작업을 하나도 실행하지 못하고 있어요. "
                                            + "그 파일이 내 것이고 나만 읽고 쓸 수 있게(chmod 600) 되어 있는지 확인해 주세요.",
                                        file: nil, confirm: nil), file: inbox)
        notifyApp()
    }

    /// One tick: cancels runs whose schedule was removed, drops one-time jobs that are done, and starts the due jobs
    /// (at most ArisSchedule.maxConcurrent at once), only once the store saved that they started.
    private func check() {
        let now = Date()
        reportRefusal()
        retimeIfMoved(now)
        let stamp = ArisScheduleWatch.stamp(of: store)
        guard watch.needsLook(stamp: stamp, now: now, running: running.count) else { return }
        let jobs = ArisScheduleStore.load(file: store)
        watch.saw(stamp: stamp, jobs: jobs)
        for id in ArisSchedule.orphaned(running: running, jobs: jobs) {
            // Its parked questions are declined as cancelled; the run then ends (ended()) without a failure entry.
            runners.removeValue(forKey: id)?.cancelTask()
        }
        let finished = jobs.contains(where: ArisSchedule.isDone)
        guard finished || !ArisSchedule.due(jobs, now: now, running: running.count, excluding: running).isEmpty else { return }
        var due: [ArisScheduledJob] = []
        var starting: [ArisScheduledJob] = []
        let saved = ArisScheduleStore.update(file: store) { current in
            let kept = ArisSchedule.pruned(current)
            // A job still running here (removed and brought back meanwhile) never starts twice.
            due = ArisSchedule.due(kept, now: now, running: running.count, excluding: running)
            starting = due.map { ArisSchedule.started($0, at: now, calendar: .current) }
            return kept.map { job in starting.first { $0.id == job.id } ?? job }
        }
        guard saved != nil else { return }
        // A run missed while the Mac slept or the agent was down runs once now (started() counts the next from now),
        // and says it is late.
        for job in due {
            if let at = job.nextRun, now.timeIntervalSince(at) > ArisSchedule.lateAfter { lateSince[job.id] = at }
        }
        for job in starting { run(job, at: now) }
    }

    /// The Mac's time zone changed (or the agent just started): daily and weekly jobs get their next run at their time
    /// here, not where they were set (ArisSchedule.retimed). Written only when a run time really moves.
    private func retimeIfMoved(_ now: Date) {
        NSTimeZone.resetSystemTimeZone()
        let here = TimeZone.current.identifier
        guard here != zone else { return }
        zone = here
        let calendar = Calendar.current
        guard ArisScheduleStore.load(file: store).contains(where: { ArisSchedule.retimed($0, now: now, calendar: calendar) != $0 }) else { return }
        ArisScheduleStore.update(file: store) { jobs in jobs.map { ArisSchedule.retimed($0, now: now, calendar: calendar) } }
        try? FileHandle.standardError.write(contentsOf: Data("aris-agent: the time zone is \(here) now; scheduled run times were moved to it\n".utf8))
    }

    private func run(_ job: ArisScheduledJob, at now: Date) {
        running.insert(job.id)
        // A teammate's schedule keeps that teammate's scopes (N5); one for a teammate no longer stored never runs as Aris.
        let home = NSHomeDirectory()
        let mate: ArisTeammate?
        switch ArisTeammateJobs.scheduled(job.teammate, in: ArisTeammateStore.load(file: ArisTeammateStore.file(home: home))) {
        case .aris: mate = nil
        case .teammate(let stored): mate = stored
        case .missing: return ended(job, .failure("그 팀원을 찾지 못했어요. 팀원 설정을 확인해 주세요."))
        }
        let korean = ArisBrainTrouble.isKorean(job.title + " " + job.prompt)
        // Never locked to one AI (audit sched-1): its teammate's own brain, else the one it was made with, else whoever
        // can run on this Mac. Untrusted (a model wrote the prompt), so each runs behind its own gate for outside words
        // (ArisJobBrain), web search off (security review C1). With no AI at all the inbox says what to set up.
        guard let brain = ArisJobBrain.scheduled(teammate: mate, madeWith: job.brain, usable: ArisSealedOneShot.available) else {
            return ended(job, .failure(ArisBrainTrouble(brain: nil, missing: .any).line(korean: korean)))
        }
        // A scheduled job is model-written and runs unattended: no memories go with it (ArisMemoryLearning.mayRecall).
        // A teammate's run carries who it is, how the user wants it to work and its notes, as its other jobs do.
        let mateBlock = mate.map { ArisTeamPrompt.job($0, notes: ArisNotesStore.teammateFile(home: home, id: $0.id).map(ArisNotesStore.load) ?? []) }
        // One of the user's routines ("출근 루틴 해 줘"): its steps are asked one after another, each a scheduled run like any
        // other (ArisRoutineChain); every other job is asked whole.
        let chain = ArisRoutineChain.routine(forPrompt: job.prompt, in: ArisRoutineStore.load(file: ArisRoutineStore.file(home: home)))
            .map { ArisRoutineChain(routine: $0, korean: korean) }
        ask(chain?.first ?? job.prompt, of: job, chain: chain, brain: brain, mate: mate, notes: mateBlock, korean: korean, at: now)
    }

    /// Asks `words` as one scheduled run of `job`. With a routine's chain, a step's end starts the next step in a run of
    /// its own, and only the routine's account at the end is the job's result.
    private func ask(_ words: String, of job: ArisScheduledJob, chain: ArisRoutineChain?, brain: ArisBrain, mate: ArisTeammate?, notes: String?,
                     korean: Bool, at now: Date) {
        // The owner's rule about paying is the last word of every scheduled run's words (ArisPaymentBoundary).
        let prompt = ArisAgentStream.prompt(request: ArisPaymentBoundary.taskWords(words, task: true, english: !korean), context: context(for: job, now: now),
                                            memory: nil, notes: notes)
        guard let runner = ArisAgentRunner.task(brain: brain, model: ArisThinking.jobModel(brain, auto: brain.model(tier: .work), choices: ArisModelChoiceBox.shared.current), title: job.title, untrusted: true, teammate: mate) else {
            return ended(job, .failure(korean ? "예약 작업을 시작하지 못했어요." : "The scheduled job couldn't start."))
        }
        runners[job.id] = runner
        // No request: the user said nothing in this turn, so the gate knows no target and sees no dictated message.
        runner.ask(prompt, tier: .work, request: "", untrusted: true) { [weak self] reply in
            self?.queue.async {
                switch chain?.take(reply) ?? .pass {
                case .pass: self?.heard(reply, from: job)
                case .next(let step): self?.ask(step, of: job, chain: chain, brain: brain, mate: mate, notes: notes, korean: korean, at: now)
                case .end(let last): self?.heard(last, from: job)
                }
            }
        }
    }

    private func context(for job: ArisScheduledJob, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd (E) HH:mm"
        // A run that is late (the Mac slept, the agent was down) runs once, and the brain knows it.
        let late = lateSince[job.id].map { " It was due at \(formatter.string(from: $0)) and runs late now (the Mac was asleep or Aris wasn't running): " +
            "do it as of now, and say briefly that it is late if the time matters." } ?? ""
        return """
            Now: \(formatter.string(from: now))
            This is a scheduled job ("\(job.title)", \(ArisSchedule.describe(job.rule, calendar: .current))) the user set up earlier.\(late) \
            The user is not waiting at the Mac: do what it says and give the result as your answer; it is said to them later. \
            Anything that needs their yes waits for them.
            """
    }

    private func heard(_ reply: ArisAgentReply, from job: ArisScheduledJob) {
        switch reply {
        case .status, .stepFailed, .delta, .turn, .launched, .untrusted, .refusedJobs, .shownOnly, .operating, .skill, .helperAnswers, .savedSteps, .work: break
        case .file(let path): files[job.id] = path
        case .confirm(let ask):
            // The runner parks it (a day at most); the app asks the user when they're there. Kept with the job, so a restart
            // can report it as declined.
            parked[job.id, default: []].append(ask.id)
            ArisScheduleStore.update(file: store) { jobs in
                jobs.map { stored in
                    guard stored.id == job.id else { return stored }
                    var copy = stored
                    copy.parked.append(ask.id)
                    return copy
                }
            }
            ArisInbox.append(entry(.confirm, job: job, text: "", question: ArisInboxEntry.Question(id: ask.id, title: ask.title, detail: ask.detail, full: ask.full)),
                             file: inbox)
            notifyApp()
        case .answer, .failure:
            ended(job, reply)
        }
    }

    /// The run is over: its questions leave the inbox, its result (or failure) goes in unless the schedule was removed
    /// meanwhile, and the job waits for its next time (a one-time job that went through leaves the store). A failed
    /// run is tried again after a pause (ArisSchedule.failed), with no failure in the inbox until the last try; a
    /// one-time job whose every try failed is kept, stopped.
    private func ended(_ job: ArisScheduledJob, _ reply: ArisAgentReply) {
        running.remove(job.id)
        runners[job.id] = nil
        let file = files.removeValue(forKey: job.id)
        let questions = parked.removeValue(forKey: job.id) ?? []
        let late = lateSince.removeValue(forKey: job.id)
        var stillScheduled = false
        // Kept with the schedule, for the day-end list: whether this run failed.
        var failed = false
        if case .failure = reply { failed = true }
        var retry: Date?
        var tries = 0
        var stopped = false
        let now = Date()
        ArisScheduleStore.update(file: store) { jobs in
            jobs.compactMap { stored in
                guard stored.id == job.id else { return stored }
                stillScheduled = true
                guard failed else { return ArisSchedule.finished(stored, failed: false) }
                let after = ArisSchedule.failed(stored, now: now)
                (retry, tries, stopped) = (after.retry, after.tries, ArisSchedule.isStopped(after.job))
                return after.job
            }
        }
        ArisInbox.removeQuestions(Set(questions), file: inbox)
        guard stillScheduled else {
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "cancelled (schedule removed)", "question": "schedule " + job.id.uuidString]),
                                       key: "schedule")
            return
        }
        let korean = ArisBrainTrouble.isKorean(job.title + " " + job.prompt)
        switch reply {
        case .answer(let answer):
            let note = ArisSchedule.lateNote(due: late, now: now, korean: korean, calendar: .current).map { $0 + "\n\n" } ?? ""
            ArisInbox.append(entry(.result, job: job, text: note + answer, file: file), file: inbox)
        case .failure(let message):
            try? FileHandle.standardError.write(contentsOf: Data("aris-agent: scheduled job failed (try \(tries)): \(message)\n".utf8))
            if let retry {
                ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "failed, tried again at \(ISO8601DateFormatter().string(from: retry))",
                                                                      "question": "schedule " + job.id.uuidString]), key: "schedule")
                return
            }
            ArisInbox.append(entry(.failure, job: job, text: String(message.prefix(300)) + ArisSchedule.gaveUp(tries: tries, stopped: stopped, korean: korean)), file: inbox)
        default: return
        }
        notifyApp()
    }


    private func entry(_ kind: ArisInboxEntry.Kind, job: ArisScheduledJob, text: String, file: String? = nil,
                       question: ArisInboxEntry.Question? = nil) -> ArisInboxEntry {
        ArisInboxEntry(id: UUID(), date: Date(), kind: kind, schedule: job.id, title: job.title, text: text, file: file, confirm: question)
    }

    /// The app fetches the inbox (POST /inbox) when nudged, and at its own start.
    private func notifyApp() {
        DistributedNotificationCenter.default().postNotificationName(.init(Self.notification), object: nil, userInfo: nil, deliverImmediately: true)
    }
}
