//
//  ArisTeammateDesk.swift
//  aris-agent
//
//  POST /teammate {"job": "<uuid>", "teammate": "claude-code", "prompt": "...", "cwd": "...", "turn"?: "<uuid>",
//                  "request"?: "..."}
//    -> JSON lines (ArisAgentReply): {"status"} (waiting for the user, or the auto-launch notice), then {"launched": {...}}
//       once the window is open, and the stream stays open while the session works: the app closes it when the job is
//       over (its Stop hook), which deletes the prompt file and frees the slot. {"error"} ends it (refused, declined,
//       cancelled, the terminal couldn't be opened, or a day passed).
//  The folder is checked and resolved (ArisTeammateGate.place). The user is asked unless `turn` is their own untainted turn
//  with no outside text that dispatched exactly this job (ArisTeammateTurns), and neither the brief nor their words name
//  an outbound step; a folder outside the home folder is always asked about, on a card that names it. Any token holder
//  (a Claude Code session included) can call this, so without such a turn it always asks. The card never goes back to
//  the caller: it waits in the inbox for the app, which asks the user, and POST /confirm takes its answer only from the app
//  itself (ArisPeer). Never learned. At most two sessions at once; a third waits.
//  Only touched on the server's `queue`.
//

import Foundation
import Network

final class ArisTeammateDesk {
    static let shared = ArisTeammateDesk()

    private struct Live {
        let connection: NWConnection
        var file: URL?
        /// The job was asked for in English: what it says when it can't go on is said in English (ArisClaudeJobWords).
        var english = false
        /// What the app said about the user's terminal (the one pinned in Settings, the one they last ran Claude Code in).
        var terminal = ArisTerminalWish()
        /// The job's title, for the window's name ("Aris · <job>").
        var title: String?
        /// Once the window is open: which one, since when, the checked claude it runs, and whether the user looked at it.
        var opened: ArisQuietOpener.Opened?
        var openedAt = Date()
        var claude: String?
        var seen = false
    }

    private struct Question {
        let job: UUID
        let at: Date
        /// The card as made here: a yes counts only when the app showed exactly this (ArisShownCard).
        let card: ArisConfirmation
        /// The port the launch request came from: an answer on that connection is refused.
        let requesterPort: UInt16?
        let answer: (Bool) -> Void
    }

    /// What POST /confirm did with an answer.
    enum Answer {
        case decided, refused, unknown
    }

    private var turns = ArisTeammateTurns()
    private var slots = ArisTeammateSlots()
    private var live: [UUID: Live] = [:]
    private var questions: [String: Question] = [:]
    private var startWhenFree: [UUID: () -> Void] = [:]
    /// Jobs cancelled this launch (the latest few hundred): one whose cancel came first is refused.
    private var cancelled: [UUID] = []

    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    // MARK: - Turns

    /// Main Aris's turn `id` dispatched `specs` from the user's own untainted words (`request`): they may launch without
    /// asking. True when it dispatched a Claude Code job (the app then gets the id).
    func record(_ id: String, specs: [ArisJobSpec], request: String) -> Bool {
        guard specs.contains(where: { $0.assignee == .teammate(ArisTeammate.claudeCodeId) }) else { return false }
        turns.record(id, specs: specs, request: request, at: Date())
        return true
    }

    // MARK: - POST /teammate

    func handle(_ object: [String: Any], on connection: NWConnection) {
        guard let job = ArisTaskEnd.jobId(object["job"]).flatMap(UUID.init(uuidString:)),
              object["teammate"] as? String == ArisTeammate.claudeCodeId,
              let prompt = object["prompt"] as? String, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              prompt.count <= ArisTeammateGate.maxPrompt,
              let rawCwd = object["cwd"] as? String, rawCwd.count <= 1_024 else {
            return respond(connection, "400 Bad Request", Data())
        }
        guard live[job] == nil else { return respond(connection, "409 Conflict", Data()) }
        startStream(connection)
        keepAlive(connection)
        // The user's own words when the caller says them, else the brief written from them.
        live[job] = Live(connection: connection, file: nil, english: ArisGateWords.isEnglish((object["request"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? prompt),
                         terminal: ArisTerminalWish(pinned: object["terminal"] as? String, lastUsed: object["terminalUsed"] as? String),
                         title: (object["title"] as? String).map { String($0.prefix(200)) })
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: queue.async { self?.end(job) }
            default: break
            }
        }
        watchClose(connection)
        guard !cancelled.contains(job) else { return finish(job, "이 작업은 취소됐어요.") }
        // A folder outside the home folder isn't refused: it goes to the user's card, which names it (audit gate-20).
        guard let place = ArisTeammateGate.place(rawCwd, home: home) else {
            return finish(job, "Claude Code를 열 폴더가 아니에요: \(rawCwd.prefix(200)) (없는 폴더이거나, 시스템 폴더나 Aris가 지키는 폴더예요)")
        }
        let cwd = place.path
        // What `claude` gets always starts with the launcher's fixed line, so a brief may start with a path, "#123" or
        // "@src/…" (it was refused: audit gate-20); the argument itself is still checked.
        guard ArisTeammateGate.isSafePrompt(ArisTeammateLauncher.argument(for: prompt)) else {
            return finish(job, "Claude Code 프롬프트가 기호(-, !, / 같은)로 시작해서 열지 않았어요.")
        }
        guard !ArisTeammateGate.mentionsOutsideFiles(prompt, cwd: cwd, home: home) else {
            return finish(job, "Claude Code 프롬프트가 프로젝트 밖 파일(@~, @/, @..)을 가리켜서 열지 않았어요. ‘@’ 없이 경로만 적어서 다시 맡겨 주세요.")
        }
        // The user's words: the vouching turn's own record; otherwise what the caller says they were (only ever adds a step).
        let words = turns.vouch(turn: object["turn"] as? String, prompt: prompt, cwd: rawCwd, now: Date())
        let outbound = ArisTeammateGate.outbound(prompt: prompt, request: words ?? (object["request"] as? String).map { String($0.prefix(maxText)) })
        // Vouched only with the checked claude at a tested version (its mention handling is what the gate matches).
        let binary = ArisTeammateGate.claudeBinary(home: home)
        let vouched = ArisTeammateGate.launchVouched(words: words, binary: binary)
        let needsYes = ArisTeammateGate.needsYes(vouched: vouched, outbound: outbound, outsideHome: place.outsideHome)
        audit(["answer": (vouched ? "vouched" : words != nil ? "not vouched (claude \(binary?.version ?? "unknown"))" : "not vouched")
                   + (place.outsideHome ? ", a folder outside home: asked" : ""),
               "question": "teammate \(job.uuidString) in \(cwd)",
               "outbound": outbound.joined(separator: ", ")])
        stream(ArisTeammateGate.requesterReply(needsYes: needsYes), on: connection)
        guard needsYes else { return claimSlot(job, place: place, prompt: prompt, claude: binary?.path) }
        let id = ArisTeammateGate.questionPrefix + "\(ArisLaunch.nonce)/\(UUID().uuidString)"
        let card = ArisTeammateGate.card(id: id, cwd: cwd, prompt: prompt, outbound: outbound,
                                         note: ArisTeammateGate.cardNote(outsideHome: place.outsideHome,
                                                                         version: ArisTeammateGate.versionNote(words: words, binary: binary)))
        questions[id] = Question(job: job, at: Date(), card: card, requesterPort: Self.remotePort(of: connection)) { [weak self] allow in
            if allow { self?.claimSlot(job, place: place, prompt: prompt, claude: binary?.path) } else { self?.finish(job, "Claude Code를 열지 않았어요.") }
        }
        ArisInbox.append(ArisInboxEntry(id: UUID(), date: Date(), kind: .confirm, schedule: nil, title: card.title, text: "",
                                        file: nil, confirm: ArisInboxEntry.Question(id: id, title: card.title, detail: card.detail, full: card.full)),
                         file: inbox)
        DistributedNotificationCenter.default().postNotificationName(.init(ArisScheduler.notification), object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
        queue.asyncAfter(wallDeadline: .now() + ArisApprovalQueue.lifetime + 1) { [weak self] in self?.expireQuestions() }
    }

    private var inbox: URL { ArisInbox.file(home: home) }

    /// The other end's port of a connection the agent accepted.
    static func remotePort(of connection: NWConnection) -> UInt16? {
        guard case .hostPort(_, let port) = connection.endpoint else { return nil }
        return port.rawValue
    }

    // MARK: - the user's answers (POST /confirm, /permissions waiting)

    /// The user's answer, taken only from the Aris app (`pid`, `started`) on `connection`, for the card exactly as made here
    /// (`detail`, `full`: what the app showed); anything else is refused and the question keeps waiting.
    func decide(_ id: String, allow: Bool, pid: Int32?, started: Double?, detail: String?, full: String?, on connection: NWConnection) -> Answer {
        guard let question = questions[id] else { return .unknown }
        if let failure = ArisPeer.failure(pid: pid, started: started, remotePort: Self.remotePort(of: connection), agentPort: port.rawValue,
                                          requesterPort: question.requesterPort) {
            audit(["answer": "refused (\(failure.rawValue))", "question": id])
            return .refused
        }
        guard ArisShownCard.matches(allow: allow, detail: detail, full: full, expectedDetail: question.card.detail,
                                    expectedFull: question.card.full) else {
            audit(["answer": "refused (the card shown isn't the card made)", "question": id])
            return .refused
        }
        questions[id] = nil
        ArisInbox.removeQuestions([id], file: inbox)
        let fresh = Date().timeIntervalSince(question.at) <= ArisApprovalQueue.lifetime
        audit(["answer": !fresh ? "expired" : allow ? "yes" : "no", "question": id])
        question.answer(allow && fresh)
        return .decided
    }

    /// Nil when `id` isn't a launch question; else whether it still waits.
    func isWaiting(_ id: String) -> Bool? {
        guard id.hasPrefix(ArisTeammateGate.questionPrefix) else { return nil }
        return questions[id].map { Date().timeIntervalSince($0.at) <= ArisApprovalQueue.lifetime } ?? false
    }

    private func expireQuestions() {
        let now = Date()
        for (id, question) in questions where now.timeIntervalSince(question.at) > ArisApprovalQueue.lifetime {
            questions[id] = nil
            ArisInbox.removeQuestions([id], file: inbox)
            audit(["answer": "expired", "question": id])
            question.answer(false)
        }
    }

    // MARK: - POST /cancel

    /// The app cancelled the job: it never launches, or stops being tracked. A session already open is ended and its
    /// window closed like a finished one's, unless the user looked at the window (then it stays their).
    func cancel(job: String) {
        finished(job: job) { _ in }
        guard let job = UUID(uuidString: job) else { return }
        cancelled = Array((cancelled + [job]).suffix(500))
        finish(job, "이 작업은 취소됐어요.")
    }

    // MARK: - The window after the job (POST /cancel {"job", "done": true})

    /// The app says the job's session is over (its Stop hook came), or the job was cancelled: a window the user never
    /// looked at has its session ended and closes itself; one he looked at is left alone (ArisQuietSession.end).
    /// Nil when the job has no open window here. A stream that merely drops (the app quit) never comes this way:
    /// that session may still be working, and its window stays.
    /// `then` gets the answer on the server's queue (ending a session waits for it to leave: never on that queue).
    func finished(job: String, then: @escaping (ArisQuietLaunch.End?) -> Void) {
        guard let job = UUID(uuidString: job), var state = live[job], let opened = state.opened else { return then(nil) }
        let seen = state.seen, claude = state.claude
        state.opened = nil
        live[job] = state
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let end = ArisQuietSession.end(opened, seen: seen, claude: claude)
            queue.async {
                self?.audit(["answer": "window \(end.rawValue) (\(opened.terminal.title)\(seen ? ", he looked at it" : ""))", "question": "teammate \(job.uuidString)"])
                then(end)
            }
        }
    }

    /// One look a second while the job's window is open: once the user has it in front, it is their.
    private func watchLooks(_ job: UUID) {
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, var state = self.live[job], let opened = state.opened, !state.seen else { return }
            guard ArisQuietSession.isLooking(opened, since: state.openedAt) else { return self.watchLooks(job) }
            state.seen = true
            self.live[job] = state
        }
    }

    // MARK: - Launching

    /// `claude`: the checked binary's path when the launch was decided (nil: the bare `claude`).
    private func claimSlot(_ job: UUID, place: ArisTeammateGate.Place, prompt: String, claude: String?) {
        guard let state = live[job] else { return }
        guard slots.claim(job) else {
            stream(.status("Claude Code 두 개가 일하는 중이라 기다려요"), on: state.connection)
            startWhenFree[job] = { [weak self] in self?.launch(job, place: place, prompt: prompt, claude: claude) }
            return
        }
        launch(job, place: place, prompt: prompt, claude: claude)
    }

    private func launch(_ job: UUID, place: ArisTeammateGate.Place, prompt: String, claude: String?) {
        let cwd = place.path
        guard var state = live[job] else { return release(job) }
        // The binary must still be the one the decision (or the user's yes) was about.
        guard ArisTeammateGate.claudeBinary(home: home)?.path == claude else {
            return finish(job, "Claude Code가 그사이 바뀌어서 열지 않았어요. 다시 맡겨 주세요.")
        }
        // Hours may have passed since the check (a parked card): the folder must still resolve to exactly the same place.
        guard ArisTeammateGate.isUnchanged(cwd, home: home, outsideHome: place.outsideHome) else {
            return finish(job, "Claude Code를 열려던 폴더가 바뀌었거나 없어져서 열지 않았어요: \(cwd.prefix(200))")
        }
        // And the brief must still name nothing outside the project (a link or a folder made since the check).
        guard !ArisTeammateGate.mentionsOutsideFiles(prompt, cwd: cwd, home: home) else {
            return finish(job, "Claude Code 프롬프트가 가리키는 파일이 그사이 프로젝트 밖이 돼서 열지 않았어요.")
        }
        let file: URL
        do {
            file = try ArisTeammateLauncher.writePrompt(prompt, in: ArisTeammateLauncher.launchFolder(home: home), id: UUID())
        } catch {
            return finish(job, error.localizedDescription)
        }
        state.file = file
        live[job] = state
        stream(.status("Claude Code 여는 중"), on: state.connection)
        let command = ArisClaudeLaunch.command(promptFile: file.path, cwd: cwd, claude: claude)
        let at = Date(), wish = state.terminal, title = state.title, english = state.english
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Without coming to the front (ArisQuietOpener); a line for the row comes before macOS's own question.
            let opened = Result {
                try ArisTeammateLauncher.launchQuietly(command: command, title: title, wish: wish, english: english) { line in
                    queue.async { if let state = self?.live[job] { stream(.status(line), on: state.connection) } }
                }
            }
            queue.async {
                guard let self, var state = self.live[job] else { return }
                switch opened {
                case .success(let window):
                    self.audit(["answer": "launched in \(window.terminal.title)" + (window.pick.passedOver.map { " (\($0.title) can't be handed a command)" } ?? "")
                                    + (window.pick.inFront.map { " (he is in \($0.title))" } ?? "")
                                    + (window.lostFront.map { ", the terminal was in front for \(Int($0 * 1000)) ms" } ?? "")
                                    + ", window \(window.place.rawValue)",
                                "question": "teammate \(job.uuidString) in \(cwd)"])
                    state.opened = window
                    state.openedAt = Date()
                    state.claude = claude
                    self.live[job] = state
                    self.watchLooks(job)
                    // Without Claude Code's hooks the app never hears this session stop: it is told, so it doesn't wait a day.
                    let hooks = ArisClaudeHookCheck.reports(home: self.home)
                    if !hooks { self.audit(["answer": "no Claude hooks: the app can't see this session end", "question": "teammate \(job.uuidString)"]) }
                    // A terminal that came first but couldn't be handed a command is named in the job's first line.
                    // Why it is not in his terminal, when it isn't; else where its window is.
                    let note = ArisQuietLaunch.note(window.pick, english: state.english)
                        ?? ArisQuietLaunch.placeWords(window.place, terminal: window.terminal, english: state.english)
                    stream(.launched(ArisTeammateLaunch(job: job, pid: window.pid, cwd: cwd, at: at, window: window.windowNumber, hooks: hooks, note: note)),
                           on: state.connection)
                    queue.asyncAfter(wallDeadline: .now() + ArisTeammateLauncher.fileLifetime) { [weak self] in
                        self?.finish(job, "하루가 지나서 이 Claude Code 작업은 더 기다리지 않아요.")
                    }
                case .failure(let error):
                    FileHandle.standardError.write(Data("aris-agent: teammate launch failed: \(error)\n".utf8))
                    self.finish(job, (error as? LocalizedError)?.errorDescription ?? "터미널을 열지 못했어요.")
                }
            }
        }
    }

    /// Ends the job's stream with `message` (when it is still open) and lets it go.
    private func finish(_ job: UUID, _ message: String) {
        guard let state = live[job] else { return }
        stream(.failure(ArisClaudeJobWords.said(message, english: state.english)), on: state.connection)
        end(job)
    }

    /// The job is over (or its stream closed): its question is dropped, its prompt file deleted, its slot freed.
    private func end(_ job: UUID) {
        guard let state = live.removeValue(forKey: job) else { return }
        let dropped = Set(questions.filter { $0.value.job == job }.keys)
        questions = questions.filter { !dropped.contains($0.key) }
        if !dropped.isEmpty { ArisInbox.removeQuestions(dropped, file: inbox) }
        if let file = state.file { ArisTeammateLauncher.remove(file) }
        release(job)
    }

    private func release(_ job: UUID) {
        startWhenFree[job] = nil
        if let next = slots.release(job) { startWhenFree.removeValue(forKey: next)?() }
    }

    private func audit(_ fields: [String: String]) {
        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(fields), key: "teammate")
    }
}
