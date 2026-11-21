// Tests for jv-fixhelper: the review findings on the helper's tasks, drains and taint. A job taken back is outside
// text whatever its journal says; an interrupted Claude turn keeps its taint unless a tool came in, and a dropped
// question is rewound out of the conversation; a question the app dropped while it waited on a drain never runs; an
// abort while draining stops the process; each drain's grace is its own; a job's quiet limit outlasts its brain's
// longest silent call; a card shown live reaches the inbox when the stream goes and POST /tasks says the job waits on
// it; a card asked again after a restart is logged, expires and leaves the inbox; an answer during the helper's exit
// is the job's end, reported once; a finished job keeps no transcript, a hands-free one never had one, and the journal
// keeps no answer text; a swapped-in spare's audit lines count as the conversation's. Fake files only, no model.
// Called from main.swift; uses its check().
import Foundation

private let fixRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func fixSource(_ path: String) -> String { (try? String(contentsOf: fixRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

private func fixHome() -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fixhelper-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    // The real path (/var is a link to /private/var), as the helper's own folders are.
    return folder.resolvingSymlinksInPath().path
}

private func fixCreated(_ job: String, origin: ArisTaskOrigin = ArisTaskOrigin(tier: "work"), at: Date = Date()) -> ArisTaskRecord {
    .created(job: job, title: "정리", request: "정리해 줘", prompt: "정리해 줘", brain: "claude", model: "sonnet", origin: origin, at: at)
}

func runFixHelperTests() {
    fixResumedUntrustedTests()
    fixInterruptTaintTests()
    fixRewindTests()
    fixDrainTests()
    fixJobQuietTests()
    fixLiveCardTests()
    fixRecoveredCardTests()
    fixShutdownEndTests()
    fixTranscriptTests()
    fixJournalPrivacyTests()
    fixSpareKeyTests()
}

private let initLine = #"{"type":"system","subtype":"init","tools":["Bash","Read","WebFetch","WebSearch"],"mcp_servers":[]}"#
private let cutResult = #"{"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":2}"#
private let partial = ##"{"type":"assistant","message":{"content":[{"type":"text","text":"# The History of Lighth"}]}}"##
private let interruptedNote = #"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#

/// An open Claude conversation driver past its init, asked one question (its turn begun).
private func askedClaude(task: Bool = false) -> (ArisClaudeDriver, [Data]) {
    let claude = ArisClaudeDriver(model: "sonnet", tools: "/x/aris-tools", task: task)
    _ = claude.read(initLine)
    let lines = claude.ask("등대의 역사 써 줘", tier: .quick)
    claude.questionStarted()
    return (claude, lines)
}

// MARK: - 1. A job taken back is outside text

private func fixResumedUntrustedTests() {
    let live = fixSource("ArisAgent/ArisTaskRecoveryLive.swift")
    check(live.contains("static let marksUntrusted = true") && live.contains("untrusted: Self.marksUntrusted,")
          && !live.contains("taint == .outsideText || !resumed"),
          "take back: a resumed job is outside text from its first word, as a restarted one (never only when its journal says so)")
    let runner = fixSource("ArisAgent/ArisAgentRunner.swift")
    let put = runner.range(of: "private func put(_ question: Question)").map { String(runner[$0.lowerBound...].prefix(900)) } ?? ""
    let mark = put.range(of: "driver.markUntrusted()")?.lowerBound, write = put.range(of: "write(opened)")?.lowerBound
    check(mark != nil && write != nil && mark! < write!, "take back: the mark is set before the question reaches the reopened session")
    // The open Claude's turn gate is marked too (its hook reads the mark before every call), not just the driver's flag.
    let job = ArisClaudeDriver(model: "sonnet", tools: "/x/aris-tools", task: true)
    job.markUntrusted()
    check(job.turnMarked && job.taint == .outsideText, "take back: the open Claude's turn gate is marked, and its taint is outside text")
}

// MARK: - 2. An interrupted Claude turn

private func fixInterruptTaintTests() {
    // The turn Aris cut off, plain text only: the taint is what it was.
    let (clean, _) = askedClaude()
    _ = clean.interruptLines()
    [partial, interruptedNote, cutResult].forEach { _ = clean.read($0) }
    check(clean.taint == .none, "interrupt: a cut-off turn that only wrote text stays clean (error_during_execution after Aris's interrupt brings nothing in)")
    _ = clean.ask("다음 질문", tier: .quick)
    clean.questionStarted()
    _ = clean.read(#"{"type":"result","subtype":"error_during_execution","is_error":true}"#)
    check(clean.taint == .outsideText, "interrupt: the same failure with no interrupt asked for is outside text, as before")
    // Seen the screen before: still screenSeen, no more.
    let (screen, _) = askedClaude()
    screen.markScreenSeen()
    _ = screen.interruptLines()
    _ = screen.read(cutResult)
    check(screen.taint == .screenSeen, "interrupt: the taint the conversation had before the interrupt is kept, not raised")
    // A tool call in the turn (one that brings nothing in by itself): the failed turn is outside text.
    let (tooled, _) = askedClaude()
    _ = tooled.read(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"/x/aris-tools timer 5m"}}]}}"#)
    let before = tooled.taint
    _ = tooled.interruptLines()
    _ = tooled.read(cutResult)
    check(tooled.taint == .outsideText, "interrupt: a turn that called a tool is outside text once cut off (before: \(before))")
    // A tool call and its result arriving while draining count too.
    let (drained, _) = askedClaude()
    _ = drained.interruptLines()
    _ = drained.read(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"/x/aris-tools timer 5m"}}]}}"#)
    _ = drained.read(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":"x"}]}}"#)
    _ = drained.read(cutResult)
    check(drained.taint == .outsideText, "interrupt: a tool call and its result that come in during the drain make it outside text")
    // Another failure subtype after an interrupt is never let off.
    let (other, _) = askedClaude()
    _ = other.interruptLines()
    _ = other.read(#"{"type":"result","subtype":"error_max_turns","is_error":true}"#)
    check(other.taint == .outsideText, "interrupt: only error_during_execution is let off; any other failure is outside text")
    // An interrupt answered by no result (it came after the turn ended) never lets off the next turn's failure.
    let (stale, _) = askedClaude()
    _ = stale.interruptLines()
    _ = stale.ask("새 질문", tier: .quick)
    stale.questionStarted()
    _ = stale.read(cutResult)
    check(stale.taint == .outsideText, "interrupt: a new question clears the interrupt; its own failure counts as before")
}

// MARK: - The cut-off question taken out (rewind_conversation)

private func fixRewindTests() {
    let (claude, lines) = askedClaude()
    let question = lines.last.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let uuid = question?["uuid"] as? String
    check(question?["type"] as? String == "user" && uuid.flatMap(UUID.init(uuidString:)) != nil, "rewind: every question carries its own message id")
    _ = claude.interruptLines()
    _ = claude.read(cutResult)
    let rewind = claude.dropLines()?.first.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let request = rewind?["request"] as? [String: Any]
    check(rewind?["type"] as? String == "control_request" && request?["subtype"] as? String == "rewind_conversation" && request?["target_message_uuid"] as? String == uuid,
          "rewind: the dropped question's turn is rewound to its question (Claude Code's rewind_conversation)")
    let id = rewind?["request_id"] as? String ?? ""
    check(claude.dropAnswer(#"{"type":"control_response","response":{"subtype":"success","request_id":"other","response":{}}}"#).answered == false
          && claude.dropAnswer(#"{"type":"control_response","response":{"subtype":"success","request_id":"\#(id)","response":{"rewound":true}}}"#) == (true, true),
          "rewind: only its own control_response ends the wait, and says whether it rewound")
    check(claude.dropLines() == nil, "rewind: once per question")
    // A turn that called a tool stays in the conversation (what it did must not be done again unknowingly).
    let (tooled, _) = askedClaude()
    _ = tooled.read(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t9","name":"Bash","input":{"command":"/x/aris-tools timer 5m"}}]}}"#)
    check(tooled.dropLines() == nil, "rewind: never for a turn that called a tool")
    let codex = ArisCodexDriver(model: "gpt", tools: "/x/aris-tools", instructions: "")
    check(codex.dropLines() == nil && codex.dropAnswer("{}").answered == false, "rewind: a brain that can't keeps its turn (the app's note stays the mitigation)")
    // An error answer (an older CLI) also ends the wait: the drain never hangs on it.
    let (old, _) = askedClaude()
    _ = old.interruptLines()
    _ = old.read(cutResult)
    let oldId = (old.dropLines()?.first.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["request_id"] as? String ?? ""
    check(old.dropAnswer(#"{"type":"control_response","response":{"subtype":"error","request_id":"\#(oldId)","error":"unsupported"}}"#) == (true, false),
          "rewind: an error answer ends the wait and keeps the question")
    let runner = fixSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("interruptOrStop(dropTurn: true)") && runner.contains("drain.awaitDrop()") && runner.contains("dropAnswer(line)")
          && runner.contains("(driver as? ArisClaudeDriver)?.questionStarted()"),
          "rewind: only the dropped (abandoned) question is rewound, after its stop, and the drain waits for the answer within the grace")
}

// MARK: - 3, 4, 5. Drains

private func fixDrainTests() {
    var drain = ArisTurnDrain()
    final class Owner {}
    let first = Owner(), second = Owner()
    var ran: [String] = [], dropped: [String] = []
    let generation = drain.begin()
    drain.afterDrain(owner: first, dropped: { dropped.append("first") }) { ran.append("first") }
    drain.afterDrain(owner: second, dropped: { dropped.append("second") }) { ran.append("second") }
    drain.drop(owner: first).forEach { $0() }
    check(dropped == ["first"] && drain.drop(owner: Owner()).isEmpty, "drain: a question the app dropped while it waited is taken out (its listener told)")
    drain.end().forEach { $0() }
    check(ran == ["second"], "drain: a dropped queued question never starts after the drain; the others do")
    let runner = fixSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("abandoned.add(owner)") && runner.contains("for dropped in drain.drop(owner: owner) { dropped() }")
          && runner.contains("if let owner, abandoned.contains(owner) { return listener(") && runner.contains("NSHashTable<AnyObject>.weakObjects()"),
          "drain: abandon(owner:) drops its queued question, and one already on its way to start is refused (owners held weakly)")
    // Generations.
    let later = drain.begin()
    check(!drain.isCurrent(generation) && drain.isCurrent(later) && later == generation + 1, "drain: each drain has its own generation")
    _ = drain.end()
    check(!drain.isCurrent(later), "drain: an ended drain is no one's")
    check(runner.contains("let generation = drain.begin(dropTurn: dropTurn)") && runner.contains("self.drain.isCurrent(generation)")
          && !runner.contains("guard let self, self.drain.active, self.process === stopped"),
          "drain: an earlier drain's grace never stops a later one on the same process")
    // Abort.
    check(ArisTurnDrain.aborts([.delta("x"), .abort("멈췄어요")]) && !ArisTurnDrain.aborts([.result("x"), .failure("y")]), "drain: an abort is told apart")
    let branch = runner.range(of: "if drain.active {\n                // The sealed Claude's").map { String(runner[$0.lowerBound...].prefix(600)) } ?? ""
    check(branch.contains("if ArisTurnDrain.aborts(events)") && branch.contains("stopProcess()"),
          "drain: the rule backstop or an unchecked web result while draining stops the process, as outside a drain")
    var dropping = ArisTurnDrain()
    dropping.begin(dropTurn: true)
    check(dropping.dropsTurn && !dropping.awaitingDrop, "drain: a dropped question's drain will rewind")
    dropping.awaitDrop()
    check(!dropping.dropsTurn && dropping.awaitingDrop && dropping.active, "drain: it then waits for the rewind's answer")
    _ = dropping.end()
    check(!dropping.awaitingDrop && !dropping.active, "drain: and ends")
}

// MARK: - 6. A job's quiet limit

private func fixJobQuietTests() {
    let claude = ArisClaudeDriver(model: "sonnet", tools: "/x/aris-tools", task: true)
    let limits = ArisTurnLimits.job(longestSilentCall: claude.longestSilentCall)
    check(claude.environment["BASH_MAX_TIMEOUT_MS"] == "1800000" && claude.environment["BASH_DEFAULT_TIMEOUT_MS"] == "1800000"
          && claude.longestSilentCall == 1_800 && limits.silence > 1_800 && limits.silence == 1_920 && limits.ceiling == 4 * 3_600,
          "quiet: a Claude job is never ended inside a 30-minute Bash call (quiet limit 32 min), the 4 h ceiling kept")
    let codex = ArisCodexDriver(model: "gpt", tools: "/x/aris-tools", instructions: "", task: true)
    check(ArisTurnLimits.job(longestSilentCall: codex.longestSilentCall) == ArisTurnLimits.job, "quiet: Codex streams as it works: 10 minutes")
    let api = ArisAPIDriver(profile: nil, tools: "/x/aris-tools", task: true, hasKey: { false })
    check(ArisTurnLimits.job(longestSilentCall: api.longestSilentCall).silence > ArisSlowCalls.ownerWait, "quiet: the API helper's longest wait on a slow call is outlasted")
    let runner = fixSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("isTask ? .job(longestSilentCall: driver.longestSilentCall) : .chat") && runner.contains("ArisSilenceWatch(queue: queue, limits: limits)")
          && runner.contains("private var answerLimit: TimeInterval { limits.silence }"),
          "quiet: the runner's clock and its holds use the brain's own job limit")
}

// MARK: - 7. A card shown live, then the app quits

private func fixLiveCardTests() {
    let home = fixHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    let inbox = ArisInbox.file(home: home)
    let job = UUID().uuidString
    var open: Set<String> = ["c1", "c2"]
    var streamed: [ArisAgentReply] = []
    let follow = ArisTaskFollow(job: job, title: "정리", inbox: inbox, live: { streamed.append($0) }, nudge: nil, cardWaits: { open.contains($0) })
    let first = ArisConfirmation(id: "c1", title: "메시지 보내기", detail: "엄마에게: 곧 가"), second = ArisConfirmation(id: "c2", title: "파일 옮기기", detail: "a → b")
    follow.deliver(.confirm(first))
    follow.deliver(.confirm(second))
    open.remove("c2")
    check(streamed.count == 2 && ArisInbox.load(file: inbox).isEmpty && ArisTaskFollow.waitingCard(job: job)?.id == "c1",
          "live card: shown on the stream, nothing in the inbox yet; POST /tasks can name the card still waiting")
    // POST /tasks while it waits.
    [fixCreated(job), .started()].forEach { ArisTaskJournal.append($0, job: job, home: home) }
    let data = ArisTaskRoutes.list([job], home: home, running: { _ in true }, cards: ArisRecoveredCards(), live: ArisTaskFollow.waitingCard(job:))
    let row = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["tasks"] as? [[String: Any]])?.first
    check(row?["state"] as? String == "waiting" && (row?["card"] as? [String: Any])?["id"] as? String == "c1"
          && (row?["card"] as? [String: Any])?["title"] as? String == "메시지 보내기",
          "POST /tasks: a running job waiting on a card shown live says \"waiting\", with the card")
    let seen = ArisTaskSeen.decode(data)?.first
    check(seen?.state == .waiting && seen?.card == "c1" && seen?.goesOn == true, "app: the waiting card's id decodes (the row shows it waits)")
    // The app quits: the stream is gone.
    follow.detach()
    let entries = ArisInbox.load(file: inbox)
    check(entries.count == 1 && entries.first?.kind == .confirm && entries.first?.confirm?.id == "c1" && entries.first?.job == job
          && entries.first?.confirm?.detail == "엄마에게: 곧 가",
          "live card: on detach the card still waiting goes to the inbox under the job's id (an answered one doesn't)")
    check(!follow.attached && ArisTaskFollow.waitingCard(job: job) == nil, "live card: nothing is left shown live after detach")
    let runner = fixSource("ArisAgent/ArisAgentRunner.swift"), main = fixSource("ArisAgent/main.swift")
    check(main.contains("cardWaits: ArisAgentRunner.isWaiting") && main.contains("live: ArisTaskFollow.waitingCard(job:)")
          && runner.contains("if runner.isTask { ArisInbox.removeQuestions([id], file: ArisInbox.file(home: home)) }"),
          "live card: wired in main; answering a job's card takes it out of the inbox")
    let app = fixSource("Aris/private/Aris/ArisController+TaskFollow.swift")
    check(app.contains("if seen.state == .waiting, let card = seen.card") && app.contains(".awaitingApproval(id: card)"),
          "app: after a relaunch a job waiting on a card shows it waits, not \"carrying on\"")
}

// MARK: - 8. A card asked again after a restart

private func fixRecoveredCardTests() {
    let home = fixHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    let inbox = ArisInbox.file(home: home)
    let cards = ArisRecoveredCards()
    var audits: [String] = []
    var settled: [(Bool, String)] = []
    cards.audit = { audits.append($0) }
    cards.inbox = inbox
    cards.carryOn = { _, _, allow, how in settled.append((allow, how)) }
    let state = ArisTaskState.replay([fixCreated(UUID().uuidString)])!
    let parked = cards.park(state, card: ArisTaskCard(id: "old", title: "메시지 보내기", detail: "아빠에게", full: nil))
    ArisInbox.append(ArisInboxEntry(id: UUID(), date: Date(), kind: .confirm, schedule: nil, title: "정리", text: "", file: nil,
                                    confirm: ArisInboxEntry.Question(id: parked.id, title: parked.title, detail: parked.detail, full: nil), job: state.job), file: inbox)
    check(cards.waitingCard(job: state.job)?.id == parked.id, "recovered card: POST /tasks can name it")
    check(cards.answer(parked.id, allow: true) && settled.last?.0 == true && settled.last?.1 == "yes", "recovered card: the user's yes carries the task on")
    func logged(_ answer: String, _ id: String) -> Bool {
        audits.contains { line in
            let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: String]
            return object?["answer"] == answer && object?["question"] == id && object?["job"] == state.job
        }
    }
    check(logged("yes", parked.id),
          "recovered card: the user's answer is written to actions.log")
    check(!ArisInbox.load(file: inbox).contains { $0.confirm?.id == parked.id }, "recovered card: the answered card leaves the inbox")
    // Nobody answers for a day: it expires while the helper stays up.
    let stale = cards.park(state, card: ArisTaskCard(id: "old2", title: "파일 지우기", detail: "x", full: nil), now: Date() - 2 * 86_400)
    let fresh = cards.park(state, card: ArisTaskCard(id: "old3", title: "메일 보내기", detail: "y", full: nil))
    ArisInbox.append(ArisInboxEntry(id: UUID(), date: Date(), kind: .confirm, schedule: nil, title: "정리", text: "", file: nil,
                                    confirm: ArisInboxEntry.Question(id: stale.id, title: "x", detail: "x", full: nil), job: state.job), file: inbox)
    check(cards.expire() == 1 && settled.last?.0 == false && settled.last?.1 == "expired" && cards.isWaiting(fresh.id) && !cards.isWaiting(stale.id)
          && cards.card(stale.id) == nil,
          "recovered card: past a day it expires as a no (wall clock), the fresh one still waits")
    check(logged("expired", stale.id) && !ArisInbox.load(file: inbox).contains { $0.confirm?.id == stale.id },
          "recovered card: the expiry is logged and its card leaves the inbox")
    check(cards.cancel(job: state.job) && cards.waitingCard(job: state.job) == nil, "recovered card: a cancel takes the rest")
    let runner = fixSource("ArisAgent/ArisAgentRunner.swift"), takeBack = fixSource("ArisAgent/ArisTaskTakeBack.swift")
    check(runner.contains("ArisRecoveredCards.shared.expire()") && takeBack.contains("cards.audit = hooks.audit") && takeBack.contains("cards.inbox = ArisInbox.file(home: home)"),
          "recovered card: expired whenever a parked card is, logged through the take-back's audit, its inbox known")
}

// MARK: - 9. An answer during the helper's exit

private func fixShutdownEndTests() {
    let home = fixHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    let answered = UUID().uuidString, killed = UUID().uuidString
    let one = ArisTaskTrail(job: answered, home: home, tools: "/x/aris-tools"), two = ArisTaskTrail(job: killed, home: home, tools: "/x/aris-tools")
    one.created(title: "t", request: "r", prompt: "p", brain: .claude, model: "m", origin: ArisTaskOrigin(tier: "work"))
    two.created(title: "t", request: "r", prompt: "p", brain: .claude, model: "m", origin: ArisTaskOrigin(tier: "work"))
    ArisTaskTrail.shuttingDown = true
    one.session("ignored-while-exiting")
    let wrote = one.ended(.answered, line: "다 했어요")
    let dropped = two.ended(.failed, line: "killed by the exit")
    ArisTaskTrail.shuttingDown = false
    let state = ArisTaskJournal.state(job: answered, home: home)
    check(wrote && state?.ending == .answered && state?.isOpen == false && state?.session == nil,
          "exit: a job that answered during the SIGTERM grace ends answered (the helper's own end record), nothing else is written")
    check(!dropped && ArisTaskJournal.state(job: killed, home: home)?.isOpen == true, "exit: one its exit killed stays open to be taken back")
    // Reported once: a second result for the same job never reaches the inbox.
    let inbox = ArisInbox.file(home: home)
    let follow = ArisTaskFollow(job: answered, title: "t", inbox: inbox, live: nil, nudge: nil)
    follow.deliver(.answer("끝"))
    follow.deliver(.answer("끝 (again)"))
    follow.deliver(.failure("lost"))
    check(ArisInbox.load(file: inbox).filter { $0.job == answered }.count == 1, "exit: a job's result goes to the inbox once; a second report is dropped")
    check(ArisTaskFollowing.isRepeat(kind: "result", finished: true) && !ArisTaskFollowing.isRepeat(kind: "result", finished: false)
          && !ArisTaskFollowing.isRepeat(kind: "confirm", finished: true),
          "app: a finished job's second result is acknowledged and never said again")
    check(fixSource("Aris/private/Aris/ArisController+TaskFollow.swift").contains("if ArisTaskFollowing.isRepeat(kind: item.kind, finished: job.isFinished)"),
          "app: wired where the inbox finishes a job")
}

// MARK: - 10. What stays on disk

private func fixTranscriptTests() {
    let home = fixHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    let work = home + "/.config/aris/aris"
    try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
    let claudeFolder = ArisSessionTranscript.claudeFolder(workingFolder: work, home: home, environment: [:])
    check(claudeFolder.path == home + "/.claude/projects/" + work.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? String($0) : "-" }.joined()
          && claudeFolder.lastPathComponent.hasSuffix("--config-aris-aris"),
          "transcript: Claude Code's folder for the helper's working folder (every character but a letter or digit made \"-\", as seen live)")
    try? FileManager.default.createDirectory(at: claudeFolder, withIntermediateDirectories: true)
    let session = UUID().uuidString.lowercased(), other = UUID().uuidString.lowercased(), linked = UUID().uuidString.lowercased()
    let mine = claudeFolder.appendingPathComponent(session + ".jsonl"), theirs = claudeFolder.appendingPathComponent(other + ".jsonl")
    FileManager.default.createFile(atPath: mine.path, contents: Data("{}".utf8))
    FileManager.default.createFile(atPath: theirs.path, contents: Data("{}".utf8))
    let outside = home + "/keep.txt"
    FileManager.default.createFile(atPath: outside, contents: Data("keep".utf8))
    try? FileManager.default.createSymbolicLink(atPath: claudeFolder.appendingPathComponent(linked + ".jsonl").path, withDestinationPath: outside)
    let began = Date()
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: began)
    let day = home + String(format: "/.codex/sessions/%04d/%02d/%02d", parts.year!, parts.month!, parts.day!)
    try? FileManager.default.createDirectory(atPath: day, withIntermediateDirectories: true)
    let thread = UUID().uuidString.lowercased()
    let rollout = day + "/rollout-2026-11-18T01-00-00-\(thread).jsonl", near = day + "/rollout-2026-11-18T01-00-00-\(other).jsonl"
    FileManager.default.createFile(atPath: rollout, contents: Data("{}".utf8))
    FileManager.default.createFile(atPath: near, contents: Data("{}".utf8))
    check(ArisSessionTranscript.files(of: "../../etc", began: began, home: home, environment: [:], workingFolder: work).isEmpty
          && ArisSessionTranscript.files(of: linked, began: began, home: home, environment: [:], workingFolder: work).isEmpty,
          "transcript: only a UUID names one, and a link is never taken for one")
    let removed = ArisSessionTranscript.remove([session, thread, linked], began: began, home: home, environment: [:], workingFolder: work)
    let fm = FileManager.default
    check(removed == 2 && !fm.fileExists(atPath: mine.path) && !fm.fileExists(atPath: rollout) && fm.fileExists(atPath: theirs.path) && fm.fileExists(atPath: near)
          && (try? String(contentsOfFile: outside, encoding: .utf8)) == "keep",
          "transcript: the ended job's Claude session and Codex thread go; another id's stay; a link's target is untouched")
    // A folder on the way that is a link: nothing is removed through it.
    let elsewhere = home + "/elsewhere"
    try? fm.createDirectory(atPath: elsewhere, withIntermediateDirectories: true)
    let hidden = UUID().uuidString.lowercased()
    fm.createFile(atPath: elsewhere + "/\(hidden).jsonl", contents: Data("{}".utf8))
    let linkedHome = fixHome()
    defer { try? fm.removeItem(atPath: linkedHome) }
    try? fm.createDirectory(atPath: linkedHome + "/.claude", withIntermediateDirectories: true)
    let linkedFolder = ArisSessionTranscript.claudeFolder(workingFolder: work, home: linkedHome, environment: [:])
    try? fm.createSymbolicLink(atPath: linkedFolder.deletingLastPathComponent().path, withDestinationPath: elsewhere)
    try? fm.createDirectory(atPath: elsewhere + "/" + linkedFolder.lastPathComponent, withIntermediateDirectories: true)
    fm.createFile(atPath: elsewhere + "/" + linkedFolder.lastPathComponent + "/\(hidden).jsonl", contents: Data("{}".utf8))
    check(ArisSessionTranscript.remove([hidden], began: began, home: linkedHome, environment: [:], workingFolder: work) == 0
          && fm.fileExists(atPath: elsewhere + "/" + linkedFolder.lastPathComponent + "/\(hidden).jsonl"),
          "transcript: never through a linked folder")
    // Wiring: an end record takes the job's sessions with it; a start removes what a crash left.
    let journal = fixSource("ArisAgent/ArisTaskJournal.swift")
    check(journal.contains("ArisSessionTranscript.forgetLater(sessions(in: chain.records), began: began, home: home)")
          && journal.contains("ArisSessionTranscript.remove(sessions(in: records(job: state.job, home: home))"),
          "transcript: removed once the job's end is written (any ending: answered, failed, cancelled, lost, stopped), and at the next start")
    check(ArisTaskJournal.sessions(in: [fixCreated(UUID().uuidString), .session("a"), .step("x", effect: false), .session("b")]) == ["a", "b"],
          "transcript: every session a job taken back had")
    // Hands-free jobs keep none at all.
    let heard = ArisClaudeDriver(model: "sonnet", tools: "/x/aris-tools", task: true)
    heard.forgetsSession = true
    let codex = ArisCodexDriver(model: "gpt", tools: "/x/aris-tools", instructions: "", task: true)
    codex.forgetsThread = true
    let opening = codex.opening().compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }.first { ($0["method"] as? String) == "thread/start" }
    check(!heard.keepsSession && (opening?["params"] as? [String: Any])?["ephemeral"] as? Bool == true && codex.sessionHandle == nil,
          "hands-free: a job heard hands-free keeps no session (Claude: no persistence; Codex: an ephemeral thread)")
    if heard.launch() != nil { check(heard.launch()!.1.contains("--no-session-persistence"), "hands-free: Claude's command line says so") }
    let runner = fixSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("fresh || heardHandsFree ? nil : spares.removeValue") && runner.contains("(runner.driver as? ArisCodexDriver)?.forgetsThread = true")
          && fixSource("ArisAgent/main.swift").contains("heardHandsFree: handsFree,") && fixSource("ArisAgent/ArisTaskRecoveryLive.swift").contains("heardHandsFree: state.origin.handsFree"),
          "hands-free: never a spare (its thread is kept), and so when taken back too")
}

private func fixJournalPrivacyTests() {
    let home = fixHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    let job = UUID().uuidString
    let trail = ArisTaskTrail(job: job, home: home, tools: "/x/aris-tools")
    trail.created(title: "t", request: "r", prompt: "p", brain: .claude, model: "m", origin: ArisTaskOrigin(tier: "work"))
    for _ in 0..<50 { trail.saw(.delta(String(repeating: "비밀 ", count: 100))) }
    trail.ended(.failed, line: String(repeating: "왜 ", count: 1_000))
    let records = ArisTaskJournal.records(job: job, home: home)
    check(!records.contains { $0.kind == .output } && (records.last?.text?.count ?? 0) <= ArisTaskLimits.line && !records.contains { $0.text?.contains("비밀") == true },
          "journal: no answer text is kept while it runs, and a failure keeps only a short line")
}

// MARK: - 11. A swapped-in spare's audit lines

private func fixSpareKeyTests() {
    let spare = ArisLaunch.spareKey(3, brain: "claude", model: "sonnet")
    check(spare.hasPrefix(ArisLaunch.nonce + "/") && spare != ArisLaunch.sharedKey(brain: "claude", model: "sonnet") && spare.hasSuffix("/sonnet")
          && !spare.hasPrefix("spare"),
          "spare: its key opens with the launch's nonce, as every conversation runner's (\"why did you do that\" reads its lines), and is its own")
    check(fixSource("ArisAgent/ArisAgentRunner.swift").contains("ArisAgentRunner(key: ArisLaunch.spareKey(number, brain: brain.rawValue, model: model)")
          && fixSource("ArisAgent/ArisWhyDesk.swift").contains("guard key.hasPrefix(ArisLaunch.nonce + \"/\")"),
          "spare: the pool makes spares with that key")
}
