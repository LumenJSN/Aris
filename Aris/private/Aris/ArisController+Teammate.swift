//
//  ArisController+Teammate.swift
//  Aris
//
//  The Claude Code teammate's job: aris-agent opens it in a terminal window (asking the user first, through the inbox,
//  unless his own untainted turn dispatched it and it pushes, publishes or sends nothing), and the job is done when that
//  session's Stop hook arrives (ArisTeammateCompletion). Then Aris reports what Claude Code last said.
//  A Stop that is a question for the user is said as one and the job goes on (audit imp-3), for ten minutes at most. On a Mac whose Claude Code has
//  no hooks, no Stop can ever come: the job ends half a minute after the window opened, saying it is open and that
//  Aris can't see when it finishes (audit team-4, ArisTeammateSilence). A window closed under it ends it too.
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

/// How a launched teammate's wait ended.
enum ArisTeammateEnd: Equatable {
    /// Its session stopped; Claude Code's last message.
    case finished(String?)
    /// Its session or its window closed before it stopped; `asked`: with a question of its own still open.
    case closed(asked: Bool)
    /// The window is open, but this Mac's Claude Code has no hooks: nothing will say when it stops.
    case unwatched
    /// It stopped on a question (the text) that stayed open too long: Aris stops watching, Claude Code still waits.
    case unanswered(String?)
    /// The agent ended the stream (a day passed, or it restarted); its message, if any.
    case streamEnded(String?)
    case cancelled
}

extension ArisController {
    /// Claude hook events reach the teammate watch, and the user's teammate list is read (the jobs block may name them).
    func watchTeammates() {
        ClaudeStore.shared.onEvent = { [weak self] event, now in self?.heardClaude(event, at: now) }
        director.onWindowClosed = { [weak self] id in self?.teammateWindowClosed(id) }
        ArisTeamModel.shared.refresh()
        ArisTeamModel.shared.refreshBrains()
        // The jobs the last run of the app left unfinished (it quit, crashed or was relaunched under them).
        Task { [weak self] in self?.reportLostJobs() }
    }

    /// Jobs that were under way when the app last stopped are gone with it (the agent ends a job whose app is gone).
    /// They are never run again by themselves, since a job half done may already have sent or changed something: each
    /// is shown in the done chip and its 기록 entry as cut off, and Aris says so once (audit team-2).
    func reportLostJobs() {
        let lost = ArisJobLedger.load()
        guard !lost.isEmpty else { return }
        log.notice("\(lost.count, privacy: .public) job(s) were cut off when the app last stopped")
        let isKorean = { (title: String) in ArisSpeech.language(of: title) == "ko-KR" }
        jobs += ArisJobLedger.lostJobs(lost, korean: isKorean)
        // Nothing is under way any more: the file goes, so this is told once.
        ArisJobLedger.note(jobs)
        for record in lost {
            pastTurns = ArisHistory.finishing(job: record.id, title: record.title, shown: ArisJobLedger.lostLine(record, korean: isKorean(record.title)),
                                              file: nil, in: pastTurns)
        }
        ArisHistory.save(pastTurns)
        flashTaskDone()
        let korean = isKorean(lost[0].title)
        let title = ArisJobLedger.lostTitle(lost, korean: korean), said = ArisJobLedger.lostSaid(lost, korean: korean)
        Task { [weak self] in
            guard let self else { return }
            _ = await self.announce { await self.speakUp(title, saying: said) { await self.speak { await self.speaker.speak(said) } } }
        }
    }

    /// Before a turn reaches the brain: the list again when it isn't in yet (the agent was still starting), so the turn's
    /// jobs block can name the user's teammates. It arrives long before the answer does.
    func readTeammatesIfMissing() {
        if ArisTeamModel.shared.load != .ready { ArisTeamModel.shared.refresh() }
        // Which brains are set up here, for a hand-out this turn may make (ArisJobRouting); asked at most once a minute.
        ArisTeamModel.shared.refreshBrains()
    }

    /// Where the teammate's window is: the job's target is already set to it, so the director sends the teammate's
    /// character there now (it perches on the terminal Claude Code runs in).
    func onTeammateWindow(pid: Int32, windowNumber: Int) {
        director.update(jobs)
    }

    func runTeammate(_ job: ArisJob, _ run: ArisJobRun) async {
        var cwd = job.cwd ?? "", turn = run.plan.turn
        if ArisTeammateFolder.isMissing(job.cwd) {
            // No folder was named (audit imp-2): the most recent Claude Code session's is proposed. Aris chose it, so the
            // launch isn't sent as vouched by the user's turn: the agent's card asks, with the folder on it.
            let korean = ArisSpeech.language(of: job.title) == "ko-KR"
            let sessions = ClaudeStore.shared.sessions.values.map { ArisTeammateFolder.Session(cwd: $0.cwd, lastEvent: $0.lastEvent, agent: $0.agent) }
            guard let proposed = ArisTeammateFolder.proposed(sessions, home: UserHome.path) else {
                let said = ArisTeammateFolder.noFolder(korean: korean)
                await reportFailure(job, said, said: said)
                return
            }
            log.notice("teammate job: no folder named, proposing the most recent session's")
            cwd = proposed
            turn = nil
            setState(job.id, .running(step: ArisTeammateFolder.proposingStep(proposed, home: UserHome.path, korean: korean)))
        }
        let source = ArisAgentClient.teammate(job: job.id, teammate: ArisTeammate.claudeCodeId, prompt: job.prompt, cwd: cwd,
                                              turn: turn, request: run.plan.request, title: job.title)
        let (replies, relay) = AsyncStream.makeStream(of: ArisAgentReply.self)
        // Relayed, so the end of the agent's stream is noted (and wakes a wait for Stop) even while nothing reads it.
        let pump = Task { [weak self] in
            var lastError: String?
            for await reply in source {
                if case .failure(let message) = reply { lastError = message }
                relay.yield(reply)
            }
            self?.jobRuns[job.id]?.streamEnded = true
            self?.resumeTeammate(job.id, .streamEnded(lastError))
            relay.finish()
        }
        defer {
            pump.cancel()
            teammateWatch.forget(job: job.id)
        }
        for await reply in replies {
            guard !Task.isCancelled else { return }
            switch reply {
            case .status(let status):
                setState(job.id, .running(step: status))
            case .confirm(let ask):
                guard await settle(ask, of: job) else { return }
            case .launched(let launch):
                // The agent's own line when the window isn't in the terminal that came first (ArisTerminalWords).
                setState(job.id, .running(step: launch.note ?? "Claude Code 작업 중"))
                let end = await waitForTeammate(job, launch)
                // A session that finished has its window closed by the agent, unless the user looked at it (then it is their).
                var window: ArisQuietLaunch.End?
                if case .finished = end { window = await ArisAgentClient.teammateFinished(job: job.id).flatMap(ArisQuietLaunch.End.init(rawValue:)) }
                // Closing the stream lets the agent delete the prompt file and free the slot.
                pump.cancel()
                await report(job, end, window: window)
                return
            case .answer(let answer):
                await reportDone(job, answer: answer, file: nil)
                return
            case .failure(let message):
                await reportFailure(job, message, said: message)
                return
            case .stepFailed, .delta, .file, .turn, .untrusted, .refusedJobs, .shownOnly, .operating, .skill, .helperAnswers:
                break
            }
        }
        // The stream ended before the launch with no answer and no error: said and written to 기록 like any failure
        // (it used to end as "중단됨" in the tray with nothing said: audit team-3).
        if jobs.first(where: { $0.id == job.id })?.isFinished == false {
            await reportFailure(job, ArisJobFailure.cutOff(korean: ArisSpeech.language(of: job.title) == "ko-KR"))
        }
    }

    private func report(_ job: ArisJob, _ end: ArisTeammateEnd, window: ArisQuietLaunch.End? = nil) async {
        let korean = ArisSpeech.language(of: job.title) == "ko-KR"
        switch end {
        case .finished(let message):
            // What became of the terminal window is said when it is still there.
            let left = window.flatMap { ArisQuietLaunch.endWords($0, korean: korean) }
            await reportDone(job, answer: [ArisTeammateWords.finished(message, korean: korean), left].compactMap { $0 }.joined(separator: " "), file: nil)
        case .closed(let asked):
            let said = ArisTeammateWords.closed(asked: asked, korean: korean)
            await reportFailure(job, said, said: said)
        case .unwatched:
            // Aris's own part is done (the window is open with the brief); the line says it can't see the rest.
            log.notice("teammate job: no Claude hooks on this Mac, not waiting for a Stop")
            await reportDone(job, answer: ArisTeammateWords.unwatched(korean: korean), file: nil)
        case .unanswered(let question):
            log.notice("teammate job: its question stayed open, not watching any longer")
            await reportDone(job, answer: ArisTeammateWords.unanswered(question, korean: korean), file: nil)
        case .streamEnded(let message):
            let said = message ?? ArisTeammateWords.lost(korean: korean)
            await reportFailure(job, said, said: said)
        case .cancelled:
            log.notice("teammate job cancelled")
        }
    }

    /// The window is noted (and handed to Task 10's perch), then the job waits for its session's Stop.
    private func waitForTeammate(_ job: ArisJob, _ launch: ArisTeammateLaunch) async -> ArisTeammateEnd {
        let id = job.id
        // Only the window the agent named: the terminal's front window is the user's own (the figure waits in the notch then).
        if let window = launch.window {
            jobs = jobs.map { job in
                guard job.id == id else { return job }
                var changed = job
                changed.target = .window(pid: launch.pid, windowNumber: window)
                return changed
            }
            onTeammateWindow(pid: launch.pid, windowNumber: window)
        }
        teammateWatch.expect(job: id, cwd: launch.cwd, launchedAt: launch.at)
        guard jobRuns[id]?.streamEnded != true else { return .streamEnded(nil) }
        // One look a little later: was the session ever heard starting? (No hooks: never.)
        let korean = ArisSpeech.language(of: job.title) == "ko-KR"
        let silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ArisTeammateSilence.wait(hooks: launch.hooks)))
            guard !Task.isCancelled else { return }
            self?.teammateSilent(id, hooks: launch.hooks, korean: korean)
        }
        defer { silence.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { return continuation.resume(returning: .cancelled) }
                teammateWaits[id] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resumeTeammate(id, .cancelled) }
        }
    }

    func resumeTeammate(_ id: UUID, _ end: ArisTeammateEnd) {
        teammateWaits.removeValue(forKey: id)?.resume(returning: end)
    }

    /// The job's terminal window was closed (ArisDirector saw it go for good): a job still waiting on it ends.
    func teammateWindowClosed(_ id: UUID) {
        // Looked at once more here: only a window that is really gone ends the job, never one out of sight.
        guard teammateWaits[id] != nil, case .window(let pid, let number)? = jobs.first(where: { $0.id == id })?.target,
              ArisWindowLocator.presence(pid: pid, windowNumber: number) == .closed else { return }
        log.notice("teammate job: its window closed")
        resumeTeammate(id, .closed(asked: teammateWatch.asked(job: id)))
    }

    /// The look after the launch (ArisTeammateSilence): a job whose session was never heard ends as unwatched when
    /// this Mac has no hooks, else its row says where to look and it keeps waiting.
    private func teammateSilent(_ id: UUID, hooks: Bool?, korean: Bool) {
        guard teammateWaits[id] != nil else { return }
        switch ArisTeammateSilence.decide(hooks: hooks, started: teammateWatch.started(job: id)) {
        case .none: break
        case .endUnwatched: resumeTeammate(id, .unwatched)
        case .nudge:
            log.notice("teammate job: no session heard yet")
            setState(id, .running(step: ArisTeammateSilence.nudgeStep(korean: korean)))
        }
    }

    private func heardClaude(_ event: ClaudeHookEvent, at now: Date) {
        // The terminal the user runs Claude Code in themselves is remembered for the next teammate (never a teammate's own
        // session: that window was Aris's choice, and would only confirm itself).
        if let used = ArisTerminalMemory.used(event: event.name, agent: event.agent, terminal: event.terminal,
                                              teammate: teammateWatch.isTeammate(session: event.sessionId)),
           Defaults[.arisClaudeTerminal] != used.rawValue {
            Defaults[.arisClaudeTerminal] = used.rawValue
        }
        let asking = Set(teammateWaits.keys.filter { teammateWatch.asked(job: $0) })
        let question = event.name == "Stop" ? ArisTeammateCompletion.question(in: event.lastMessageEnd) : nil
        let outcome = teammateWatch.observe(event.name, session: event.sessionId, cwd: event.cwd, agent: event.agent, source: event.source,
                                            asks: question != nil, at: now)
        switch outcome {
        case .finished(let id)?: resumeTeammate(id, .finished(event.lastMessage))
        case .closed(let id)?: resumeTeammate(id, .closed(asked: asking.contains(id)))
        case .asked(let id)?: teammateAsked(id, question)
        case nil:
            // A session heard after the "no word yet" line: the row says it is working again.
            guard event.name == "SessionStart" else { break }
            for job in jobs where teammateWaits[job.id] != nil && teammateWatch.started(job: job.id) {
                let korean = ArisSpeech.language(of: job.title) == "ko-KR"
                if job.state == .running(step: ArisTeammateSilence.nudgeStep(korean: korean)) { setState(job.id, .running(step: "Claude Code 작업 중")) }
            }
        }
    }

    /// Claude Code stopped on a question for the user: said once at the next pause, and the job keeps waiting (its wait is
    /// not resumed, so a Stop that follows at once is never missed).
    private func teammateAsked(_ id: UUID, _ question: String?) {
        guard teammateWaits[id] != nil, let job = jobs.first(where: { $0.id == id }) else { return }
        let korean = ArisSpeech.language(of: job.title) == "ko-KR"
        log.notice("teammate job: Claude Code stopped on a question")
        setState(id, .running(step: ArisTeammateWords.askingStep(korean: korean)))
        let said = ArisTeammateWords.asks(question, korean: korean)
        Task { [weak self] in
            guard let self else { return }
            _ = await self.announce { await self.speakUp(job.title, saying: said) { await self.speak { await self.speaker.speak(said) } } }
        }
        // Not for ever: a question left open (often just an offer after finished work) frees the job's slots in time.
        guard let askedAt = teammateWatch.askedAt(job: id) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(ArisTeammateSilence.askedWait))
            guard let self, self.teammateWaits[id] != nil,
                  ArisTeammateSilence.askedOut(askedAt: askedAt, latest: self.teammateWatch.askedAt(job: id)) else { return }
            self.resumeTeammate(id, .unanswered(question))
        }
    }
}
