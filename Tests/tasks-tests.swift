// Tests for jv-tasks (targets 5 and 7): background work that doesn't die or vanish. The task journal's format,
// replay and every recovery branch (a card surviving a restart among them); the inactivity clock against total time
// with fake brain processes that talk or go quiet; process groups stopped whole, children an earlier helper left
// stopped only when pid and start time both match; the brain's stdin written off the runner's queue with a bound; a
// timed-out turn interrupted rather than killed; and no turn handed to a second brain once it may have changed
// something. Fake brains are /bin/sh scripts; nothing reaches a model. Called from main.swift; uses its check().
import Foundation

private let tasksRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func tasksSource(_ path: String) -> String { (try? String(contentsOf: tasksRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runTasksTests() {
    taskRecordFormatTests()
    taskReplayTests()
    taskRecoveryPlanTests()
    silenceClockTests()
    silenceWatchFakeBrainTests()
    taskJournalStoreTests()
    taskTrailTests()
    taskTakeBackTests()
    taskRoutesTests()
    processGroupTests()
    childLedgerTests()
    inputPumpTests()
    turnInterruptTests()
    fallbackSideEffectTests()
    taskDriverSessionTests()
    taskAppFollowTests()
    taskWiringTests()
    taskSecurityTests()
}

private let jobA = "6F9619FF-8B86-D011-B42D-00C04FC964FF"

private func tempHome() -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-tasks-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.path
}

private func created(_ job: String = jobA, brain: String = "claude", prompt: String = "보고서 정리해 줘", origin: ArisTaskOrigin = ArisTaskOrigin(tier: "work"),
                     at: Date = Date()) -> ArisTaskRecord {
    .created(job: job, title: "보고서", request: "보고서 정리해 줘", prompt: prompt, brain: brain, model: "sonnet", origin: origin, at: at)
}

// MARK: - Format

private func taskRecordFormatTests() {
    let records: [ArisTaskRecord] = [created(), .started(), .session("abc"), .step("shell: aris-tools message 엄마 hi", effect: true), .status("메시지 보내는 중"),
                                     .card(ArisTaskCard(id: "k/1", title: "메시지 보내기", detail: "엄마에게: hi", full: nil)), .answer("k/1", allow: true),
                                     .output("반쯤 했어요"), .ended(.answered, line: "다 했어요", taint: "none")]
    let bytes = records.map(\.line).reduce(Data(), +)
    let back = ArisTaskRecord.records(in: bytes)
    check(back.count == records.count && zip(back, records).allSatisfy { $0.kind == $1.kind && $0.text == $1.text && $0.v == ArisTaskRecord.version },
          "journal: every record reads back as written, each with the format's version")
    check(String(decoding: records[0].line, as: UTF8.self).contains(#""v":1"#) && records.allSatisfy { $0.line.last == 0x0A && $0.line.filter { $0 == 0x0A }.count == 1 },
          "journal: one JSON line per record, carrying v")
    var newer = ArisTaskRecord.started()
    newer.v = 2
    let mixed = created().line + Data("not json\n".utf8) + newer.line + Data(#"{"kind":"started"}"#.utf8) + Data([0x0A]) + ArisTaskRecord.started().line
    check(ArisTaskRecord.records(in: mixed).map(\.kind) == [.created, .started], "journal: a damaged line, a newer format's line and a line without a version are skipped; the rest reads")
    let long = String(repeating: "가", count: 9_000)
    let cut = ArisTaskRecord.created(job: jobA, title: long, request: long, prompt: long, brain: "claude", model: "m", origin: ArisTaskOrigin(tier: "work"))
    check(cut.request!.count == ArisTaskLimits.words && cut.title!.count == ArisTaskLimits.line && cut.request!.contains("…"),
          "journal: the job's words are cut to the inbox's 4,000, its title to actions.log's 256, keeping start and end")
    check(ArisTaskRecord.step(long, effect: true).text!.count == ArisTaskLimits.step && ArisTaskRecord.output(long).text!.hasSuffix("가") && ArisTaskRecord.output(long).text!.count == ArisTaskLimits.words,
          "journal: a step is cut to actions.log's identifying 1,024, the answer so far keeps its last 4,000")
    let source = tasksSource("Shared/Core/Tasks/ArisTaskRecord.swift") + tasksSource("Shared/Core/Tasks/ArisTaskReplay.swift")
        + tasksSource("Shared/Core/Tasks/ArisTaskRecovery.swift") + tasksSource("Shared/Core/Tasks/ArisSilenceClock.swift")
    let imports = source.components(separatedBy: "\n").filter { $0.hasPrefix("import ") }
    check(!imports.isEmpty && imports.allSatisfy { $0 == "import Foundation" }, "journal: the core files import Foundation only")
}

// MARK: - Replay

private func taskReplayTests() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let records: [ArisTaskRecord] = [created(at: t0), .started(at: t0 + 1), .session("s-1", at: t0 + 2), .step("tool: WebSearch", effect: false, at: t0 + 3),
                                     .status("웹 검색 중", at: t0 + 3), .tainted("outsideText", at: t0 + 4), .output("첫 줄", at: t0 + 5),
                                     .card(ArisTaskCard(id: "k/7", title: "메일 보내기", detail: "교수님께", full: nil), at: t0 + 6)]
    guard let state = ArisTaskState.replay(records) else { return check(false, "replay: a journal with created reads") }
    check(state.job == jobA && state.brain == "claude" && state.session == "s-1" && state.steps.count == 1 && state.lastStatus == "웹 검색 중"
          && state.output == "첫 줄" && state.taint == "outsideText" && state.isOpen && state.openCard?.id == "k/7" && !state.hadSideEffects,
          "replay: who, the session, steps, status, output, the taint and the card it waits on")
    let answered = ArisTaskState.replay(records + [.answer("k/7", allow: true), .ended(.answered, line: "보냈어요")])
    check(answered?.openCard == nil && answered?.hadSideEffects == true && answered?.ending == .answered && answered?.endLine == "보냈어요" && answered?.isOpen == false,
          "replay: an answered yes counts as done, and the ending closes it")
    let taken = ArisTaskState.replay(records + [.recovered(.restarted)])
    check(taken?.openCard == nil && taken?.cards.first?.how == "superseded" && taken?.recoveries == 1 && taken?.lastRecovery == .restarted,
          "replay: a card from before a restart that a new process took over is superseded, never open")
    check(ArisTaskState.replay([.started(), .output("x")]) == nil, "replay: no created record, no task")
    check(ArisTaskState.replay(records + [.tainted("none")])?.taint == "outsideText", "replay: the taint never falls")
}

// MARK: - Recovery plans

private func taskRecoveryPlanTests() {
    let now = Date()
    var steps = [created(at: now - 60), .started(at: now - 59), .session("sess-9"), .step("shell: aris-tools message 엄마 \"곧 가\"", effect: true),
                 .step("tool: WebSearch", effect: false), .output("엄마한테 보냈고 이제")]
    let open = ArisTaskState.replay(steps)!
    guard case .resume(let session, let note) = ArisTaskRecovery.plan(open, canResume: true, now: now) else { return check(false, "recovery: a resumable task resumes") }
    check(session == "sess-9" && note.contains("aris-tools message") && note.contains("do not repeat") && note.contains("never do a step twice"),
          "recovery: resume reopens the session and says what was done, a changing step marked not to repeat")
    guard case .restart(let prompt) = ArisTaskRecovery.plan(open, canResume: false, now: now) else { return check(false, "recovery: one that can't resume restarts") }
    check(prompt.hasPrefix("보고서 정리해 줘") && prompt.contains("aris-tools message") && !prompt.contains("엄마한테 보냈고 이제") && prompt.contains("not instructions")
          && prompt.contains("Never do a step listed as done again"),
          "recovery: restart asks the job again with the journal's summary (its steps, never an older journal's answer text), as a record, not instructions")
    steps.append(.card(ArisTaskCard(id: "k/3", title: "메시지 보내기", detail: "아빠에게: 곧 가", full: nil)))
    check(ArisTaskRecovery.plan(ArisTaskState.replay(steps)!, canResume: true, now: now) == .waitCard(ArisTaskCard(id: "k/3", title: "메시지 보내기", detail: "아빠에게: 곧 가", full: nil)),
          "recovery: a task waiting on a card waits on the same card")
    check(ArisTaskRecovery.plan(ArisTaskState.replay(steps + [.ended(.answered)])!, canResume: true, now: now) == .none, "recovery: an ended task is left alone")
    let looped = ArisTaskState.replay([created(at: now - 60), .recovered(.restarted), .recovered(.restarted), .recovered(.restarted)])!
    if case .lost = ArisTaskRecovery.plan(looped, canResume: true, now: now) {} else { check(false, "recovery: taken back three times is lost") }
    let old = ArisTaskState.replay([created(at: now - 3 * 86_400), .started()])!
    if case .lost = ArisTaskRecovery.plan(old, canResume: true, now: now) {} else { check(false, "recovery: older than two days is lost") }
    let noSession = ArisTaskState.replay([created(at: now - 10), .started()])!
    if case .restart = ArisTaskRecovery.plan(noSession, canResume: true, now: now) {} else { check(false, "recovery: no session handle, a restart") }
    let card = ArisTaskCard(id: "r1", title: "메시지 보내기", detail: "아빠에게", full: nil)
    if case .resume(_, let yes) = ArisTaskRecovery.carryOn(open, canResume: true, answered: (card, true)),
       case .restart(let no) = ArisTaskRecovery.carryOn(open, canResume: false, answered: (card, false)) {
        check(yes.contains("The owner said yes") && yes.contains("gate checks it again") && no.contains("The owner said no") && no.contains("Don't do it"),
              "recovery: the card's answer after the restart is told to the brain; a yes still goes through the gate again")
    } else {
        check(false, "recovery: a settled card carries on")
    }
}

// MARK: - The clock

private func silenceClockTests() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    var talking = ArisSilenceClock(limits: ArisTurnLimits(silence: 10, ceiling: 100), at: t0)
    for second in stride(from: 5.0, through: 60, by: 5) { talking.heard(at: t0 + second) }
    check(talking.expired(at: t0 + 65) == nil && talking.expired(at: t0 + 70) == .silence,
          "clock: a brain that keeps talking lives past the quiet limit (a total limit of 10 s would have ended it at 10 s); it ends 10 s after its last word")
    var quiet = ArisSilenceClock(limits: ArisTurnLimits(silence: 10, ceiling: 100), at: t0)
    quiet.heard(at: t0 + 3)
    check(quiet.expired(at: t0 + 12.9) == nil && quiet.expired(at: t0 + 13) == .silence, "clock: quiet for the limit ends it")
    var chatty = ArisSilenceClock(limits: ArisTurnLimits(silence: 10, ceiling: 30), at: t0)
    for second in stride(from: 1.0, through: 40, by: 1) { chatty.heard(at: t0 + second) }
    check(chatty.expired(at: t0 + 29) == nil && chatty.expired(at: t0 + 30) == .ceiling, "clock: the hard ceiling ends a brain that never stops")
    var held = ArisSilenceClock(limits: ArisTurnLimits(silence: 10, ceiling: 30), at: t0)
    held.hold(for: 300, at: t0 + 5)
    check(held.expired(at: t0 + 200) == nil && held.expired(at: t0 + 314) == nil && held.expired(at: t0 + 315) == .silence,
          "clock: a card's wait stops the clock; the quiet counts from the hold's end, and the held time doesn't count toward the ceiling")
    held.hold(for: 0, at: t0 + 100)
    check(held.expired(at: t0 + 109) == nil && held.expired(at: t0 + 110) == .silence, "clock: an answered card ends the hold, and the usual quiet counts from then")
    var shorter = ArisSilenceClock(limits: ArisTurnLimits(silence: 10, ceiling: 30), at: t0)
    shorter.hold(for: 50, at: t0 + 5)
    shorter.hold(for: 0, at: t0 + 15)
    check(shorter.deadline.at == t0 + 25, "clock: only the time actually held extends the ceiling")
    check(ArisTurnLimits.chat == ArisTurnLimits(silence: 120, ceiling: 600) && ArisTurnLimits.job == ArisTurnLimits(silence: 600, ceiling: 14_400),
          "clock: chat 120 s quiet / 10 min in all, job 10 min quiet / 4 h in all")
}

/// A fake brain: /bin/sh with `script`, its stdout read line by line on `queue`.
private func fakeBrain(_ script: String, queue: DispatchQueue, input: Pipe? = nil, line: @escaping (String) -> Void = { _ in }) -> Process? {
    let process = ArisExactProcess()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", script]
    let out = Pipe()
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    process.standardInput = input ?? FileHandle.nullDevice
    var buffer = Data()
    out.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
        queue.async {
            buffer.append(chunk)
            while let end = buffer.firstIndex(of: 0x0A) {
                line(String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...end)
            }
        }
    }
    do { try process.run() } catch { return nil }
    return process
}

private func silenceWatchFakeBrainTests() {
    let queue = DispatchQueue(label: "aris-tasks-watch")
    // Talks for 2.4 s with a line every 0.3 s, then goes quiet: a 1 s quiet limit never ends it while it talks.
    let started = Date()
    var expiredAt: Date?
    var why: ArisSilenceClock.Why?
    var lines = 0
    let done = DispatchSemaphore(value: 0)
    let watch = ArisSilenceWatch(queue: queue, limits: ArisTurnLimits(silence: 1, ceiling: 30))
    queue.sync { watch.start { reason in expiredAt = Date(); why = reason; done.signal() } }
    let talker = fakeBrain("for i in 1 2 3 4 5 6 7 8; do echo tick $i; sleep 0.3; done; sleep 5", queue: queue) { _ in
        lines += 1
        watch.heard()
    }
    _ = done.wait(timeout: .now() + 8)
    let lived = expiredAt.map { $0.timeIntervalSince(started) } ?? 0
    check(talker != nil && lines == 8 && why == .silence && lived >= 2.1 + 0.9 && lived < 4.5,
          "inactivity, fake brain: talking for 2.1 s past a 1 s quiet limit isn't a timeout (a total limit would have ended it at 1 s); 1 s of silence after its last line is (\(String(format: "%.2f", lived)) s, \(lines) lines)")
    talker.map { ArisProcessEnd.end($0, grace: 0.2) }
    // Never quiet, but past its ceiling.
    let ceilingDone = DispatchSemaphore(value: 0)
    var ceilingWhy: ArisSilenceClock.Why?
    let ceilingStart = Date()
    var ceilingAt = Date.distantFuture
    let capped = ArisSilenceWatch(queue: queue, limits: ArisTurnLimits(silence: 5, ceiling: 1.2))
    queue.sync { capped.start { reason in ceilingWhy = reason; ceilingAt = Date(); ceilingDone.signal() } }
    let chatter = fakeBrain("while true; do echo x; sleep 0.1; done", queue: queue) { _ in capped.heard() }
    _ = ceilingDone.wait(timeout: .now() + 6)
    check(ceilingWhy == .ceiling && ceilingAt.timeIntervalSince(ceilingStart) < 2.5, "inactivity, fake brain: one that never stops ends at the ceiling")
    chatter.map { ArisProcessEnd.end($0, grace: 0.2) }
    // A card's hold: quiet longer than the limit while held is no timeout.
    let heldDone = DispatchSemaphore(value: 0)
    var heldAt = Date.distantPast
    let heldStart = Date()
    let held = ArisSilenceWatch(queue: queue, limits: ArisTurnLimits(silence: 0.5, ceiling: 30))
    queue.sync {
        held.start { _ in heldAt = Date(); heldDone.signal() }
        held.hold(for: 1.5)
    }
    _ = heldDone.wait(timeout: .now() + 5)
    check(heldAt.timeIntervalSince(heldStart) >= 1.9, "inactivity: a held clock (a card waiting) waits out the hold, then the quiet")
    let stopped = ArisSilenceWatch(queue: queue, limits: ArisTurnLimits(silence: 0.2, ceiling: 1))
    var fired = false
    queue.sync { stopped.start { _ in fired = true }; stopped.stop() }
    Thread.sleep(forTimeInterval: 0.4)
    queue.sync { check(!fired && !stopped.running, "inactivity: a finished turn's clock never fires") }
}

// MARK: - Journal on disk

private func taskJournalStoreTests() {
    let home = tempHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    check(ArisTaskJournal.append(created(), job: jobA, home: home) && ArisTaskJournal.append(.started(), job: jobA, home: home), "store: records are appended")
    let file = ArisTaskJournal.file(job: jobA, home: home)!
    let mode = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? Int) ?? 0
    let folderMode = ((try? FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path))?[.posixPermissions] as? Int) ?? 0
    check(mode == 0o600 && folderMode == 0o700 && file.lastPathComponent == jobA.lowercased() + ".jsonl" && file.path.hasSuffix(".config/aris/aris/tasks/" + jobA.lowercased() + ".jsonl"),
          "store: tasks/<job>.jsonl in the helper's folder, 0600 in 0700 (ArisPrivateFile's rule)")
    check(ArisTaskJournal.file(job: "../x", home: home) == nil && !ArisTaskJournal.append(.started(), job: "not-a-uuid", home: home),
          "store: only a UUID names a journal")
    check(ArisTaskJournal.state(job: jobA, home: home)?.started != nil && ArisTaskJournal.all(home: home).count == 1, "store: the journal replays")
    // A link put in its place is never written through.
    let other = UUID().uuidString
    let target = URL(fileURLWithPath: home).appendingPathComponent("elsewhere")
    FileManager.default.createFile(atPath: target.path, contents: Data())
    try? FileManager.default.createSymbolicLink(atPath: ArisTaskJournal.file(job: other, home: home)!.path, withDestinationPath: target.path)
    check(!ArisTaskJournal.append(created(other), job: other, home: home) && (try? Data(contentsOf: target))?.isEmpty == true, "store: never through a link")
    chmod(file.path, 0o644)
    check(ArisTaskJournal.state(job: jobA, home: home) == nil, "store: a journal others may read counts for nothing")
    chmod(file.path, 0o600)
    let gone = UUID().uuidString
    ArisTaskJournal.append(created(gone), job: gone, home: home)
    ArisTaskJournal.append(.ended(.answered, at: Date() - 8 * 86_400), job: gone, home: home)
    ArisTaskJournal.prune(home: home)
    check(ArisTaskJournal.state(job: gone, home: home) == nil && ArisTaskJournal.state(job: jobA, home: home) != nil, "store: a journal ended over a week ago goes; an open one stays")
}

private func taskTrailTests() {
    let home = tempHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    let tools = "/x/aris-tools"
    let trail = ArisTaskTrail(job: jobA, home: home, tools: tools)
    trail.created(title: "정리", request: "정리해 줘", prompt: "정리해 줘", brain: .codex, model: "gpt", origin: ArisTaskOrigin(tier: "work", untrusted: true))
    trail.started()
    trail.session("thread-1")
    trail.session("thread-1")
    trail.saw(.tools([ArisAgentStream.ToolCall(name: "Bash", command: "\(tools) files find 보고서"), ArisAgentStream.ToolCall(name: "Bash", command: "\(tools) message 엄마 안녕")]))
    trail.saw(.status("파일 찾는 중"))
    trail.saw(.status("파일 찾는 중"))
    trail.saw(.delta("반"))
    trail.taint(.outsideText)
    trail.card(ArisConfirmation(id: "k/1", title: "메시지 보내기", detail: "엄마에게: 안녕"))
    trail.answer("k/1", allow: false, how: "no")
    trail.ended(.answered, line: "끝")
    trail.saw(.status("after the end"))
    let records = ArisTaskJournal.records(job: jobA, home: home)
    let state = ArisTaskState.replay(records)
    check(state?.steps.map(\.effect) == [false, true] && state?.steps.last?.text == "shell: \(tools) message 엄마 안녕" && state?.session == "thread-1"
          && records.filter { $0.kind == .status && $0.text != nil }.count == 1 && records.filter { $0.kind == .session }.count == 1,
          "trail: steps as actions.log names them (a read marked as changing nothing), one record per new status and session")
    check(state?.output == "" && !records.contains { $0.kind == .output } && state?.endLine == nil && state?.taint == "outsideText"
          && state?.cards.first?.allow == false && state?.ending == .answered && !records.contains { $0.text == "after the end" },
          "trail: no answer text (neither so far nor at the end), the taint, the card and its answer, nothing after the end")
    let job2 = UUID().uuidString
    let shut = ArisTaskTrail(job: job2, home: home, tools: tools)
    shut.created(title: "t", request: "r", prompt: "p", brain: .claude, model: "m", origin: ArisTaskOrigin(tier: "work"))
    ArisTaskTrail.shuttingDown = true
    shut.ended(.failed, line: "brain killed by the helper's exit")
    ArisTaskTrail.shuttingDown = false
    check(ArisTaskJournal.state(job: job2, home: home)?.isOpen == true, "trail: a helper that is exiting writes no end, so the next one takes the task back")
}

// MARK: - Taking back

private func taskTakeBackTests() {
    let home = tempHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    let inbox = ArisInbox.file(home: home)
    let now = Date()
    func journal(_ job: String, _ records: [ArisTaskRecord]) { records.forEach { ArisTaskJournal.append($0, job: job, home: home) } }
    let ended = UUID().uuidString, waiting = UUID().uuidString, claude = UUID().uuidString, agy = UUID().uuidString, looped = UUID().uuidString,
        refused = UUID().uuidString
    journal(ended, [created(ended, at: now - 100), .started(), .ended(.answered, line: "끝")])
    journal(waiting, [created(waiting, at: now - 90), .started(), .step("shell: aris-tools message 아빠 곧 가", effect: false),
                      .card(ArisTaskCard(id: "task1-OLDNONCE/claude/m/c1", title: "메시지 보내기", detail: "아빠에게: 곧 가", full: nil))])
    journal(claude, [created(claude, at: now - 80), .started(), .session("sess-claude"), .step("shell: aris-tools files find x", effect: false)])
    journal(agy, [created(agy, brain: "antigravity", at: now - 70), .started(), .step("shell: aris-tools note 메모", effect: true), .output("메모 남겼고")])
    journal(looped, [created(looped, at: now - 60), .recovered(.restarted), .recovered(.restarted), .recovered(.restarted)])
    journal(refused, [created(refused, brain: "codex", at: now - 50), .started()])
    // The last launch left a job's card and a scheduled run's card in the inbox.
    ArisInbox.append(ArisInboxEntry(id: UUID(), date: now, kind: .confirm, schedule: nil, title: "old", text: "", file: nil,
                                    confirm: ArisInboxEntry.Question(id: "task1-OLD/c1", title: "x", detail: "y", full: nil), job: waiting), file: inbox)
    ArisInbox.append(ArisInboxEntry(id: UUID(), date: now, kind: .confirm, schedule: UUID(), title: "sched", text: "", file: nil,
                                    confirm: ArisInboxEntry.Question(id: "c9-OLD", title: "x", detail: "y", full: nil)), file: inbox)
    var launched: [(job: String, prompt: String, session: String?)] = []
    var audits: [String] = []
    let cards = ArisRecoveredCards()
    let hooks = ArisTaskTakeBack.Hooks(launch: { state, prompt, session in
        if state.job == refused { return .failure(.refused("its teammate is gone")) }
        launched.append((state.job, prompt, session))
        ArisTaskJournal.append(.recovered(session != nil ? .resumed : .restarted), job: state.job, home: home)
        return .success(session != nil ? .resumed : .restarted)
    }, audit: { audits.append($0) }, nudge: nil)
    let plans = ArisTaskTakeBack.run(home: home, now: now, hooks: hooks, cards: cards)
    check(plans.count == 5 && !launched.contains { $0.job == ended }, "take back: the five open journals are planned, the ended one is left alone")
    let resumed = launched.first { $0.job == claude }
    check(resumed?.session == "sess-claude" && resumed?.prompt.contains("picking up the same conversation") == true,
          "take back: the open Claude's job reopens its session with the note of what was done")
    let restarted = launched.first { $0.job == agy }
    check(restarted?.session == nil && restarted?.prompt.hasPrefix("보고서 정리해 줘") == true && restarted?.prompt.contains("aris-tools note 메모 [may have changed something: do not repeat]") == true
          && restarted?.prompt.contains("메모 남겼고") == false,
          "take back: Antigravity (no session) starts again with the job and the journal's summary")
    let entries = ArisInbox.load(file: inbox)
    let asked = entries.first { $0.kind == .confirm && $0.job == waiting }
    check(asked?.confirm?.title == "메시지 보내기" && asked?.confirm?.detail == "아빠에게: 곧 가" && asked?.confirm?.id.hasPrefix("r") == true
          && !entries.contains { $0.confirm?.id == "task1-OLD/c1" } && entries.contains { $0.confirm?.id == "c9-OLD" },
          "take back, card: a job waiting on a card waits on the same card (title, details) under a new id; the last launch's job card goes, a scheduled run's stays for its own sweep")
    check(!launched.contains { $0.job == waiting } && ArisTaskJournal.state(job: waiting, home: home)?.lastRecovery == .waiting
          && ArisTaskJournal.state(job: waiting, home: home)?.openCard?.id == asked?.confirm?.id,
          "take back, card: nothing runs until the card is answered; its journal waits on the new card")
    let lostEntry = entries.first { $0.kind == .failure && $0.job == looped }
    check(ArisTaskJournal.state(job: looped, home: home)?.ending == .lost && lostEntry?.text.contains("이어서 하지 못했어요") == true
          && ArisTaskJournal.state(job: refused, home: home)?.ending == .lost && entries.contains { $0.kind == .failure && $0.job == refused },
          "take back: a task taken back too often, or that can't run as it ran, ends lost and the app is told by its id")
    // The user answers the card that survived the restart.
    if let id = asked?.confirm?.id {
        check(cards.isWaiting(id) && cards.waitingJob(waiting), "card after restart: it waits")
        check(cards.answer(id, allow: true) && !cards.isWaiting(id), "card after restart: the user's yes settles it")
        let carried = launched.first { $0.job == waiting }
        check(carried?.prompt.contains("The owner said yes, after the restart, to: 메시지 보내기 (아빠에게: 곧 가)") == true && carried?.prompt.contains("gate checks it again") == true
              && carried?.session == nil,
              "card after restart: the task goes on told of the yes, and the action goes through the gate again (never run as answered)")
        check(ArisTaskJournal.records(job: waiting, home: home).contains { $0.kind == .answer && $0.allow == true && $0.card?.id == id },
              "card after restart: the answer is in its journal")
    }
    check(!cards.answer("nobody", allow: true), "card after restart: an unknown id isn't one")
    check(audits.contains { $0.contains("asked again after the helper restarted") } && audits.contains { $0.contains("resumed after the helper restarted") },
          "take back: actions.log hears each one")
    // An expired card is a no.
    let late = ArisRecoveredCards()
    var lateAllow: Bool?
    late.carryOn = { _, _, allow, _ in lateAllow = allow }
    let parked = late.park(ArisTaskState.replay([created()])!, card: ArisTaskCard(id: "x", title: "t", detail: "d", full: nil), now: now - 2 * 86_400)
    check(!late.isWaiting(parked.id) && late.answer(parked.id, allow: true) && lateAllow == false, "card after restart: past a day, it is a no")
    check(late.cancel(job: jobA) == false, "card after restart: a cancel with nothing waiting says so")
}

private func taskRoutesTests() {
    let home = tempHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    let running = UUID().uuidString, done = UUID().uuidString, cut = UUID().uuidString
    [created(running), .started()].forEach { ArisTaskJournal.append($0, job: running, home: home) }
    [created(done), .ended(.answered, line: "결과")].forEach { ArisTaskJournal.append($0, job: done, home: home) }
    [created(cut), .started()].forEach { ArisTaskJournal.append($0, job: cut, home: home) }
    let data = ArisTaskRoutes.list([running, done, cut, UUID().uuidString, "bad"], home: home, running: { $0 == running }, cards: ArisRecoveredCards())
    let rows = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["tasks"] as? [[String: Any]]) ?? []
    let words = rows.map { $0["state"] as? String ?? "" }
    check(words == ["running", "done", "lost", "unknown"] && rows[1]["line"] as? String == "결과",
          "POST /tasks: running, done (with its line), open with no runner is lost, no journal is unknown; a non-UUID is left out")
    let seen = ArisTaskSeen.decode(data) ?? []
    check(seen.count == 4 && seen[0].goesOn && !seen[1].goesOn && seen[1].line == "결과", "app: the helper's answer decodes")
}

// MARK: - Processes

private func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

private func waitGone(_ pids: [pid_t], within seconds: TimeInterval) -> Bool {
    let until = Date().addingTimeInterval(seconds)
    while pids.contains(where: alive), Date() < until { usleep(20_000) }
    return !pids.contains(where: alive)
}

/// A fake brain that starts a tool (a sleeping child in its own group) and prints the child's pid.
private func brainWithChild(queue: DispatchQueue) -> (Process, pid_t)? {
    let got = DispatchSemaphore(value: 0)
    var child: pid_t = 0
    guard let brain = fakeBrain("sleep 60 & echo $!; wait", queue: queue, line: { line in
        if child == 0, let pid = pid_t(line) { child = pid; got.signal() }
    }) else { return nil }
    _ = got.wait(timeout: .now() + 3)
    return child > 0 ? (brain, child) : nil
}

private func processGroupTests() {
    let queue = DispatchQueue(label: "aris-tasks-group")
    guard let (brain, child) = brainWithChild(queue: queue) else { return check(false, "process group: the fake brain started its tool") }
    let pid = brain.processIdentifier
    check(ArisProcessGroup.info(pid)?.group == pid && ArisProcessGroup.info(child)?.group == pid && ArisProcessGroup.members(pid).contains(child),
          "process group: the brain leads a group of its own, and its tool is in it")
    ArisProcessEnd.end(brain, grace: 0.5)
    check(waitGone([pid, child], within: 3), "process group: stopping the brain stops its tool too (the group is signalled)")
    check(ArisProcessGroup.signal(getpgrp(), since: 0, 0) == 0, "process group: never the helper's own group")
    // A member that started before the leader (a pid given to someone else) is never reached.
    guard let (other, otherChild) = brainWithChild(queue: queue) else { return check(false, "process group: a second fake brain") }
    let since = ArisProcessGroup.info(other.processIdentifier)!.started
    check(ArisProcessGroup.signal(other.processIdentifier, since: since + 60_000_000, SIGTERM) == 0 && alive(otherChild),
          "process group: only members that started no earlier than the brain are signalled")
    ArisProcessEnd.end(other, grace: 0.3)
    check(waitGone([other.processIdentifier, otherChild], within: 3), "process group: cleaned up")
}

private func childLedgerTests() {
    let queue = DispatchQueue(label: "aris-tasks-ledger")
    let home = tempHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    let file = ArisChildLedger.file(home: home)
    // The tests' fake brains have the test as their parent; a dead helper's brain would be launchd's.
    let orphan: (pid_t) -> Bool = { _ in true }
    // A helper starts a brain, then dies without stopping it.
    guard let (left, leftChild) = brainWithChild(queue: queue) else { return check(false, "ledger: a fake brain") }
    let previous = ArisChildLedger(home: home)
    previous.add(left.processIdentifier)
    check(previous.running.count == 1 && (try? Data(contentsOf: file)).map { String(decoding: $0, as: UTF8.self).contains("\(left.processIdentifier)") } == true,
          "ledger: a running brain's pid and start time are on disk")
    /// A list sealed as the helper of the current generation writes it.
    func writeList(_ entries: [ArisChildLedger.Entry], generation: Int? = nil) {
        let written = ArisChildLedger.Written(generation: generation ?? ArisChildLedger.generation(home: home), helper: .init(pid: 1, started: 0), entries: entries)
        try? ArisPrivateFile.write(ArisTaskSeal.sealedFile(try! JSONEncoder().encode(written), purpose: "children", home: home)!, to: file)
    }
    let saved = try? Data(contentsOf: file)
    // A list nobody sealed (a brain's write) names nothing to stop.
    try? ArisPrivateFile.write(try! JSONEncoder().encode(previous.running), to: file)
    check(ArisChildLedger.sweep(home: home, grace: 0.2, orphaned: orphan) == 0 && alive(left.processIdentifier),
          "ledger, security: an unsealed list (written by anyone but the helper) stops nothing")
    // The last helper's own list, put back after a later start: an older generation never opens.
    if let saved { try? ArisPrivateFile.write(saved, to: file) }
    check(ArisChildLedger.generation(home: home) == 1 && ArisChildLedger.sweep(home: home, grace: 0.2, orphaned: orphan) == 0 && alive(left.processIdentifier),
          "ledger, security: an old list replayed into a newer helper's start stops nothing (bound to the helper generation)")
    // A list sealed for another purpose (a journal's end mark's key context) doesn't open as one.
    try? ArisPrivateFile.write(ArisTaskSeal.sealedFile(try! JSONEncoder().encode(ArisChildLedger.Written(generation: ArisChildLedger.generation(home: home), helper: .init(pid: 1, started: 0),
                                                                                                       entries: previous.running)), purpose: "end", home: home)!, to: file)
    check(ArisChildLedger.sweep(home: home, grace: 0.2, orphaned: orphan) == 0 && alive(left.processIdentifier), "ledger, security: a seal made for anything else doesn't open it")
    writeList(previous.running)
    check(ArisChildLedger.sweep(home: home, grace: 0.2) == 0 && alive(left.processIdentifier),
          "ledger: a process that still has its parent (not a dead helper's) is left alone")
    // One whose start time no longer matches (its pid went to another process) is left alone.
    guard let (stranger, strangerChild) = brainWithChild(queue: queue) else { return check(false, "ledger: a second fake brain") }
    let wrong = ArisChildLedger.Entry(pid: stranger.processIdentifier, started: ArisProcessGroup.info(stranger.processIdentifier)!.started + 1)
    writeList(previous.running + [wrong])
    let stopped = ArisChildLedger.sweep(home: home, grace: 0.5, orphaned: orphan)
    check(stopped == 1 && waitGone([left.processIdentifier, leftChild], within: 3) && alive(stranger.processIdentifier) && alive(strangerChild),
          "ledger, next start: the brain an earlier helper left is stopped with its tool, only when pid and start time both match")
    check(ArisPrivateFile.read(file)?.isEmpty == true, "ledger: emptied after the sweep")
    // SIGTERM to the helper: every brain's group stops before it exits.
    let now = ArisChildLedger(home: home)
    now.add(stranger.processIdentifier)
    now.stopAll(grace: 1)
    check(waitGone([stranger.processIdentifier, strangerChild], within: 3) && now.running.isEmpty, "ledger, exit: every brain and its tools stop")
    now.add(99_999_999)
    check(now.running.isEmpty, "ledger: a pid that doesn't exist isn't written down")
}

private func inputPumpTests() {
    let queue = DispatchQueue(label: "aris-tasks-pump")
    // A brain that never reads its stdin: 1 MiB to it would block a plain write on a 64 KiB pipe.
    let stdin = Pipe()
    guard let deaf = fakeBrain("sleep 30", queue: queue, input: stdin) else { return check(false, "pump: a fake brain") }
    var failure: String?
    let pump = ArisInputPump(handle: stdin.fileHandleForWriting, owner: queue, limit: 2 * 1_024 * 1_024) { failure = $0 }
    let started = Date()
    queue.sync { pump.write([Data(repeating: 0x41, count: 1_024 * 1_024)]) }
    let took = Date().timeIntervalSince(started)
    var answered = false
    queue.sync { answered = true }
    check(took < 0.2 && answered && pump.backlog > 0, "pump: a write to a brain that doesn't read never holds the runner's queue (\(String(format: "%.3f", took)) s)")
    queue.sync { pump.write([Data(repeating: 0x42, count: 1_536 * 1_024)]) }
    queue.sync {}
    check(failure?.contains("stopped reading") == true, "pump: past the bound, the brain counts as gone (told once, on the runner's queue)")
    let before = failure
    queue.sync { pump.write([Data("more\n".utf8)]) }
    queue.sync {}
    check(failure == before, "pump: nothing more is written or reported after that")
    ArisProcessEnd.end(deaf, grace: 0.2)
    // A brain that reads gets every line, in order.
    let readerIn = Pipe()
    var got: [String] = []
    let readDone = DispatchSemaphore(value: 0)
    guard let reader = fakeBrain("while read l; do echo \"got $l\"; done", queue: queue, input: readerIn, line: { line in
        got.append(line)
        if got.count == 50 { readDone.signal() }
    }) else { return check(false, "pump: a reading fake brain") }
    let ordered = ArisInputPump(handle: readerIn.fileHandleForWriting, owner: queue) { _ in }
    queue.sync { for i in 1...50 { ordered.write([Data("\(i)\n".utf8)]) } }
    _ = readDone.wait(timeout: .now() + 3)
    check(queue.sync { got } == (1...50).map { "got \($0)" }, "pump: lines arrive whole and in order")
    ordered.close()
    ArisProcessEnd.end(reader, grace: 0.2)
}

// MARK: - Interrupt

private func turnInterruptTests() {
    let claude = ArisClaudeDriver(model: "sonnet", tools: "/x/aris-tools")
    let line = claude.interruptLines()?.first.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    check(line?["type"] as? String == "control_request" && (line?["request"] as? [String: Any])?["subtype"] as? String == "interrupt",
          "interrupt: Claude's is stream-json's control request with subtype interrupt")
    let codex = ArisCodexDriver(model: "gpt", tools: "/x/aris-tools", instructions: "")
    check(codex.interruptLines() == nil, "interrupt: Codex without a turn open has nothing to stop")
    check(ArisTurnDrain.ends([.result("x")]) && ArisTurnDrain.ends([.failure("interrupted")]) && !ArisTurnDrain.ends([.delta("x"), .status("s")]),
          "interrupt: a result or a failure ends the stopped turn; its pieces don't")
    check(ArisTurnDrain.replies([.delta("x"), .send(Data("a".utf8))]) == [Data("a".utf8)], "interrupt: only the protocol's replies go back while draining")
    var drain = ArisTurnDrain()
    var ran = 0
    drain.begin()
    drain.afterDrain { ran += 1 }
    drain.afterDrain { ran += 1 }
    drain.end().forEach { $0() }
    check(ran == 2 && !drain.active && drain.end().isEmpty, "interrupt: questions that came meanwhile run once the drain ends")
    // A fake brain that honours the interrupt: it ends the turn with a result and keeps running (its conversation kept).
    let queue = DispatchQueue(label: "aris-tasks-interrupt")
    let input = Pipe()
    var seen: [String] = []
    let ended = DispatchSemaphore(value: 0)
    guard let polite = fakeBrain(#"while read l; do case "$l" in *subtype*interrupt*) echo '{"type":"result","subtype":"error_during_execution","is_error":true}';; *) echo '{"type":"other"}';; esac; done"#,
                                 queue: queue, input: input, line: { line in
        seen.append(line)
        if ArisTurnDrain.ends([ArisAgentStream.parse(line) == .other ? .delta("") : .failure(line)]) { ended.signal() }
    }) else { return check(false, "interrupt: a fake brain") }
    let pump = ArisInputPump(handle: input.fileHandleForWriting, owner: queue) { _ in }
    pump.write(claude.interruptLines()!)
    let heard = ended.wait(timeout: .now() + 3) == .success
    check(heard && polite.isRunning, "interrupt, fake brain: the stopped turn ends with its result and the process (its conversation) lives on")
    pump.close()
    ArisProcessEnd.end(polite, grace: 0.2)
    // One that ignores it is stopped after the grace, as before.
    guard let stubborn = fakeBrain("trap '' INT; sleep 30", queue: queue) else { return check(false, "interrupt: a stubborn fake brain") }
    ArisProcessEnd.end(stubborn, grace: 0.3)
    check(waitGone([stubborn.processIdentifier], within: 3), "interrupt: a brain that doesn't stop its turn is stopped")
    let runner = tasksSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("guard !isTask, process != nil, let stopping = (driver as? ArisInterruptibleDriver)?.interruptLines()")
          && runner.contains("ArisTurnDrain.grace") && runner.contains("if drain.active {") && runner.contains("drain.afterDrain"),
          "interrupt: a conversation's timed-out turn is interrupted when its brain can, killed only when it doesn't respond")
}

// MARK: - Fallback

private func fallbackSideEffectTests() {
    let tools = "/x/aris-tools"
    let reads: [ArisAgentStream.ToolCall] = [.init(name: "WebSearch", command: nil), .init(name: "Read", command: nil), .init(name: "Bash", command: "\(tools) files find 보고서"),
                                            .init(name: "Bash", command: "uptime")]
    let writes: [ArisAgentStream.ToolCall] = [.init(name: "Bash", command: "\(tools) message 엄마 안녕"), .init(name: "Bash", command: "\(tools) files find x && rm y"),
                                             .init(name: "Bash", command: "touch /tmp/x"), .init(name: "Write", command: nil), .init(name: "mcpToolCall", command: nil)]
    check(reads.allSatisfy { !ArisTurnSideEffects.mayChange($0, tools: tools) }, "fallback: plain reads change nothing")
    check(writes.allSatisfy { ArisTurnSideEffects.mayChange($0, tools: tools) }, "fallback: a send, a chain, a shell write, a file write or a service call may have changed something")
    check(ArisTurnSideEffects.mayHandOff(acted: false, changed: false, isTask: false, canHandOff: true)
          && !ArisTurnSideEffects.mayHandOff(acted: false, changed: true, isTask: false, canHandOff: true)
          && !ArisTurnSideEffects.mayHandOff(acted: true, changed: false, isTask: false, canHandOff: true)
          && !ArisTurnSideEffects.mayHandOff(acted: false, changed: false, isTask: true, canHandOff: true),
          "fallback: a turn goes to another brain only when it did nothing that could have changed anything")
    let korean = ArisTurnSideEffects.stoppedLine(reason: "Claude 사용 한도에 닿았어요.", done: ["메시지 보내기", "메시지 보내기", "메모"], korean: true)
    let english = ArisTurnSideEffects.stoppedLine(reason: "Claude hit its limit.", done: [], korean: false)
    check(korean.contains("이미 한 일: 메시지 보내기, 메모") && korean.contains("다른 AI에게 넘기지 않았어요") && korean.contains("나머지는 하지 않았어요")
          && english.contains("wasn't handed to another AI") && english.contains("The rest wasn't done"),
          "fallback: it says plainly what was done and that the rest wasn't, and why it wasn't handed on")
    check(ArisTurnSideEffects.done(.init(name: "Bash", command: "\(tools) message 엄마 안녕"), tools: tools).hasSuffix("중") == false, "fallback: a step is named as done")
    // A fake brain's stream: a send, then the limit. The turn's record says it changed something: never handed off.
    let stream = [#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"\#(tools) message 엄마 안녕"}}]}}"#]
    var changed = false
    for line in stream {
        if case .tools(let calls) = ArisAgentStream.parse(line) { changed = changed || calls.contains { ArisTurnSideEffects.mayChange($0, tools: tools) } }
    }
    check(changed && !ArisTurnSideEffects.mayHandOff(acted: false, changed: changed, isTask: false, canHandOff: true),
          "fallback, fake brain stream: a send seen before the limit keeps the turn from being run again on another brain")
    let runner = tasksSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("ArisTurnSideEffects.mayHandOff(acted: acted, changed: changed") && runner.components(separatedBy: "limitReached(message)").count == 3
          && !runner.contains("let handsOff = !acted && !isTask && handOff != nil"),
          "fallback: both limit paths (a line, a death) go through the one rule")
}

// MARK: - Drivers keep a job's session

private func taskDriverSessionTests() {
    let job = ArisClaudeDriver(model: "sonnet", tools: "/x/aris-tools", task: true)
    let chat = ArisClaudeDriver(model: "sonnet", tools: "/x/aris-tools")
    let handsFree = ArisClaudeDriver(model: "sonnet", tools: "/x/aris-tools", task: true, handsFree: true)
    check(job.keepsSession && !chat.keepsSession && !handsFree.keepsSession, "claude: only the open Claude's job keeps its session")
    if job.launch() != nil {
        let first = job.launch()!.1
        let id = job.sessionHandle ?? ""
        check(first.contains("--session-id") && first.contains(id) && !first.contains("--no-session-persistence") && UUID(uuidString: id) != nil,
              "claude: a job starts with a session id of its own, persisted")
        job.resume(from: "0b9e2c55-1111-4222-8333-944455556666")
        let again = job.launch()!.1
        check(zip(again, again.dropFirst()).contains { $0 == "--resume" && $1 == "0b9e2c55-1111-4222-8333-944455556666" } && !again.contains("--session-id"),
              "claude: a job taken back reopens its session with --resume")
        check(chat.launch()!.1.contains("--no-session-persistence") && handsFree.launch()!.1.contains("--no-session-persistence"),
              "claude: conversations and the sealed Claude still keep nothing")
    } else {
        check(true, "claude: not installed here, its command line isn't looked at")
    }
    /// The thread request among a driver's opening lines: its method and params.
    func thread(_ driver: ArisCodexDriver) -> (method: String, params: [String: Any])? {
        for line in driver.opening() {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let method = object["method"] as? String,
                  method.hasPrefix("thread/") else { continue }
            return (method, object["params"] as? [String: Any] ?? [:])
        }
        return nil
    }
    let codexJob = ArisCodexDriver(model: "gpt", tools: "/x/aris-tools", instructions: "", task: true)
    let opening = thread(codexJob)
    check(opening?.method == "thread/start" && opening?.params["ephemeral"] as? Bool == false, "codex: a job's thread is kept (not ephemeral)")
    codexJob.reset()
    codexJob.resume(from: "thread-77")
    let reopened = thread(codexJob)
    check(reopened?.method == "thread/resume" && reopened?.params["threadId"] as? String == "thread-77", "codex: a job taken back reopens its thread")
    let codexChat = ArisCodexDriver(model: "gpt", tools: "/x/aris-tools", instructions: "")
    check(thread(codexChat)?.params["ephemeral"] as? Bool == true && codexChat.sessionHandle == nil, "codex: a conversation's thread stays ephemeral")
    check(ArisTaskTakeBack.canResume(ArisTaskState.replay([created(brain: "codex")])!) && !ArisTaskTakeBack.canResume(ArisTaskState.replay([created(brain: "api")])!)
          && !ArisTaskTakeBack.canResume(ArisTaskState.replay([created(origin: ArisTaskOrigin(tier: "work", sealedHandsFree: true))])!),
          "take back: Claude (open) and Codex resume; the API brain, Antigravity and the sealed Claude restart")
}

// MARK: - The app follows by id

private func taskAppFollowTests() {
    let going = UUID(), gone = UUID(), terminal = UUID()
    let records = [ArisJobRecord(id: going, title: "정리", claudeCode: false, created: Date()), ArisJobRecord(id: gone, title: "요약", claudeCode: false, created: Date()),
                   ArisJobRecord(id: terminal, title: "코드", claudeCode: true, created: Date())]
    let seen = [ArisTaskSeen(job: going, state: .running, recovered: "resumed", line: nil), ArisTaskSeen(job: gone, state: .lost, recovered: nil, line: nil),
                ArisTaskSeen(job: terminal, state: .running, recovered: nil, line: nil)]
    let split = ArisTaskFollowing.split(records, seen: seen)
    check(split.goOn.map(\.id) == [going] && split.lost.map(\.id) == [gone, terminal], "app: after a relaunch, a job the helper still has goes on; the rest are cut off")
    check(ArisTaskFollowing.split(records, seen: nil).lost.count == 3, "app: a helper that doesn't answer (or is too old) leaves today's cut-off lines")
    check(ArisTaskFollowing.pickedUpLine(recovered: "resumed", korean: true).contains("이어서") && ArisTaskFollowing.pickedUpSaid(Array(records.prefix(1)), korean: true).contains("‘정리’")
          && ArisTaskFollowing.pickedUpSaid(records, korean: false).contains("3 jobs"),
          "app: \"picked up again\" in place of \"cut off, hand it over again\"")
    let body = Data(#"{"items":[{"id":"\#(UUID().uuidString)","date":"2026-11-17T10:00:00Z","kind":"result","title":"정리","text":"끝","job":"\#(going.uuidString)"}]}"#.utf8)
    let item = ArisInboxItem.decode(body)?.first
    check(item?.jobId == going && ArisTaskFollowing.outcome(kind: item?.kind ?? "", text: item?.text ?? "", file: nil) == .done("끝", file: nil),
          "app: an inbox result under a job's id finishes that job")
    let old = ArisInboxItem.decode(Data(#"{"items":[{"id":"x","date":"2026-11-17T10:00:00Z","kind":"failure","title":"예약","text":"t"}]}"#.utf8))?.first
    check(old?.jobId == nil && old?.spoken.contains("예약한 일") == true, "app: a scheduled run's item reads as before")
}

// MARK: - Wiring

private func taskWiringTests() {
    let runner = tasksSource("ArisAgent/ArisAgentRunner.swift")
    let main = tasksSource("ArisAgent/main.swift")
    check(runner.contains("silence.heard()") && runner.contains("silence.start { [weak self] why in self?.timedOut(why) }") && !runner.contains("answerTimeout")
          && runner.contains("silence.hold(for:"),
          "runner: turns are timed by silence (any stdout or stderr), cards and judges hold the clock")
    check(runner.contains("ArisChildLedger.shared.add(process.processIdentifier)") && runner.contains("ArisChildLedger.shared.remove(pid)")
          && runner.contains("pump?.write(lines)") && !runner.contains("try input.write(contentsOf: line)"),
          "runner: brains are on the ledger, and stdin goes through the pump")
    check(runner.contains("trail?.card(shown)") && runner.contains("trail?.answer(key + \"/\" + id") && runner.contains("events.forEach(trail.saw)")
          && runner.contains("trail.ended(answer != nil ? .answered : endingNow ?? .failed"),
          "runner: every card, answer, step and ending of a job goes in its journal")
    check(runner.contains("let line = notStartedLine()") && runner.contains("Self.jobs.forget(owner: self)"), "runner: a job that never started leaves the registry")
    check(main.contains("ArisChildLedger.sweep(home: FileManager.default.homeDirectoryForCurrentUser.path)") && main.contains("ArisTaskRecoveryLive.run(")
          && main.contains("ArisTaskTrail.shuttingDown = true") && main.contains("ArisChildLedger.shared.stopAll()") && main.contains("follow.detach()")
          && !main.contains("runner.cancelTask() }") && main.contains(#"case "/tasks":"#),
          "main: the sweep and the take-back at start, children stopped on SIGTERM/SIGINT, a closed stream detaches a job (never cancels it), POST /tasks")
    check(tasksSource("ArisAgent/ArisProcessEnd.swift").contains("[SIGTERM, SIGINT]"), "helper: SIGINT stops it as SIGTERM does")
    let app = tasksSource("Aris/private/Aris/ArisController+Team.swift") + tasksSource("Aris/private/Aris/ArisController+Inbox.swift")
        + tasksSource("Aris/private/Aris/ArisController+Teammate.swift")
    check(app.components(separatedBy: "if await followsAfterLoss(job) { return nil }").count == 3 && app.contains("await deliverJobItem(item)")
          && app.contains("ArisTaskFollowing.split(left, seen: await ArisAgentClient.tasksSoon"),
          "app: a lost stream, a relaunch and the inbox follow a job by its id")
    let build = tasksSource("Tests/build-agent.sh")
    check(build.contains(#""$SRC"/Shared/Core/Tasks/*.swift"#), "build: the core task files are in the helper")
}

// MARK: - Security (coordinator's review): the journal and the brain list can't be forged by a brain

private func taskSecurityTests() {
    let home = tempHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    // A forged record (no seal, or a wrong one) is dropped: a card "answered yes" by anyone but the helper stays open.
    let job = UUID().uuidString
    [created(job), .started(), .card(ArisTaskCard(id: "k/9", title: "메일 보내기", detail: "모두에게", full: nil))].forEach { ArisTaskJournal.append($0, job: job, home: home) }
    let file = ArisTaskJournal.file(job: job, home: home)!
    let handle = try? FileHandle(forWritingTo: file)
    handle?.seekToEndOfFile()
    handle?.write(ArisTaskRecord.answer("k/9", allow: true).line)
    handle?.write(ArisTaskRecord.answer("k/9", allow: true).line(sealedWith: { _ in "AAAAforged" }))
    handle?.write(ArisTaskRecord.ended(.answered).line(sealedWith: { _ in Data(repeating: 7, count: 32).base64EncodedString() }))
    try? handle?.close()
    let state = ArisTaskJournal.state(job: job, home: home)
    check(state?.openCard?.id == "k/9" && state?.isOpen == true && ArisTaskRecord.records(in: (try? Data(contentsOf: file)) ?? Data()).count == 1,
          "security: unsealed or wrongly sealed lines are dropped (a forged yes, a forged end); only the forged plain line would read without the seal")
    check(ArisTaskRecovery.plan(state!, canResume: true, now: Date()) == .waitCard(ArisTaskCard(id: "k/9", title: "메일 보내기", detail: "모두에게", full: nil)),
          "security: a forged yes doesn't skip the gate: the card is asked again")
    // The next record the helper writes cuts the untrusted tail off and follows the last good one.
    ArisTaskJournal.append(.status("다시"), job: job, home: home)
    check(ArisTaskJournal.records(job: job, home: home).map(\.kind) == [.created, .started, .card, .status] && ArisTaskJournal.state(job: job, home: home)?.openCard?.id == "k/9",
          "security: after a forged tail, the helper's next line is trusted again and the forgery is gone")
    // The chain: a sealed line copied from another job, moved, repeated or cut doesn't hold.
    func lines(_ job: String) -> [Data] {
        ((try? Data(contentsOf: ArisTaskJournal.file(job: job, home: home)!)) ?? Data()).split(separator: 0x0A).map { Data($0) + Data([0x0A]) }
    }
    func put(_ job: String, _ parts: [Data]) { try? ArisPrivateFile.write(parts.reduce(Data(), +), to: ArisTaskJournal.file(job: job, home: home)!) }
    let donor = UUID().uuidString, target = UUID().uuidString
    let card = ArisTaskCard(id: "k/1", title: "메시지 보내기", detail: "엄마에게", full: nil)
    [created(donor), .started(), .card(card), .answer("k/1", allow: true), .ended(.answered)].forEach { ArisTaskJournal.append($0, job: donor, home: home) }
    [created(target), .started(), .card(card)].forEach { ArisTaskJournal.append($0, job: target, home: home) }
    let donorLines = lines(donor), targetLines = lines(target)
    put(target, targetLines + [donorLines[3]])
    check(ArisTaskJournal.state(job: target, home: home)?.openCard?.id == "k/1" && ArisTaskJournal.records(job: target, home: home).count == 3,
          "chain: another job's sealed yes, copied in, doesn't count; the card is asked again")
    put(target, [targetLines[0], targetLines[2], targetLines[1]])
    check(ArisTaskJournal.records(job: target, home: home).map(\.kind) == [.created], "chain: reordered lines: nothing after the last line in its place counts")
    put(target, targetLines + [targetLines[2]])
    check(ArisTaskJournal.records(job: target, home: home).count == 3, "chain: a repeated line doesn't count")
    put(donor, Array(donorLines.prefix(3)) + [donorLines[3].prefix(20)])
    let cut = ArisTaskJournal.state(job: donor, home: home)
    check(cut?.cards.first?.allow == nil && cut?.ending == .answered && cut?.isOpen == false,
          "chain: a tail cut by a crash degrades to the last good record (the yes is gone, never assumed) and an ended task stays ended by its end mark")
    put(target, Array(targetLines.prefix(2)))
    try? FileManager.default.removeItem(at: ArisTaskJournal.endFile(ArisTaskJournal.file(job: target, home: home)!))
    check(ArisTaskJournal.state(job: target, home: home)?.isOpen == true && ArisTaskRecovery.plan(ArisTaskJournal.state(job: target, home: home)!, canResume: false, now: Date()) != .none,
          "chain: a journal cut short is still taken back, from its last good record, through the gate")
    let donorEnd = ArisTaskJournal.endFile(ArisTaskJournal.file(job: donor, home: home)!)
    try? FileManager.default.copyItem(at: donorEnd, to: ArisTaskJournal.endFile(ArisTaskJournal.file(job: target, home: home)!))
    check(ArisTaskJournal.state(job: target, home: home)?.isOpen == true, "chain: another job's end mark doesn't end this one")
    // Even the helper's own record of a yes is never permission: taking a task back only starts it with words.
    let takeBack = tasksSource("ArisAgent/ArisTaskTakeBack.swift") + tasksSource("ArisAgent/ArisTaskRecoveryLive.swift")
    check(!takeBack.contains("approveOnce") && !takeBack.contains(".decide(") && !takeBack.contains("permissions.grant") && !takeBack.contains("mint("),
          "security: taking a task back never approves, decides or grants anything; every step goes through the gate again")
    let keyMode = ((try? FileManager.default.attributesOfItem(atPath: ArisTaskSeal.keyFile(home: home).path))?[.posixPermissions] as? Int) ?? 0
    check(keyMode == 0o600 && ArisTaskSeal.keyFile(home: home).lastPathComponent.hasSuffix("-key")
          && ArisRiskPolicy.isSecret(home + "/.config/aris/tasks-key", work: ArisRiskPolicy.workFolder(home: home)),
          "security: the seal's key is a 0600 *-key file in Aris's folder, a secret to the risk gate")
    // Every brain's rules keep it off the journals and the list, as the scheduler's files.
    let claude = ArisClaudeDriver(model: "sonnet", tools: "/x/aris-tools", task: true).arguments.joined(separator: " ")
    let sealed = ArisClaudeDriver(model: "sonnet", tools: "/x/aris-tools", sealed: true).arguments.joined(separator: " ")
    check(["Write(~/.config/aris/aris/tasks/**)", "Edit(~/.config/aris/aris/tasks/**)", "Read(~/.config/aris/aris/tasks/**)", "Write(~/.config/aris/aris/children.json)",
           "Write(~/.config/boring-notch/aris/tasks/**)", "Edit(~/.config/boring-notch/aris/children.json)", "Read(~/.config/aris/*-key)"].allSatisfy { claude.contains($0) && sealed.contains($0) },
          "security: Claude (open and sealed) is denied the journals and the brain list under both folder names, and the key")
    let agy = ArisAgyRules.deny(tools: "/x/aris-tools", folder: home + "/.config/aris/aris", home: home)
    check(["write_file(\(home)/.config/aris/aris/tasks/*)", "read_file(\(home)/.config/aris/aris/tasks/*)", "write_file(\(home)/.config/aris/aris/children.json)",
           "write_file(\(home)/.config/boring-notch/aris/tasks/*)", "read_file(\(home)/.config/aris/*-key)"].allSatisfy(agy.contains),
          "security: Antigravity's rules deny the journals, the brain list and the key")
    let journal = home + "/.config/aris/aris/tasks/\(job.lowercased()).jsonl"
    for action in [ArisAction.shell("echo x >> \(journal)"), .shell("cp /tmp/x \(home)/.config/aris/aris/children.json"), .fileChange([journal]),
                   .shell("echo x >> \(home)/.config/boring-notch/aris/tasks/a.jsonl")] {
        check(ArisRiskPolicy.risk(of: action, tools: "/x/aris-tools", home: home) != .auto,
              "security: Codex's and the API brain's gate never lets a write to the journals or the list through unasked (\(action))")
    }
    // A turn being stopped declines every approval it still asks for, and its audit lines are still written.
    let codexYes = Data(#"{"id":7,"result":{"decision":"accept"}}"#.utf8) + Data([0x0A])
    let toolYes = Data(#"{"id":8,"result":{"action":"accept","content":{}}}"#.utf8) + Data([0x0A])
    let apiYes = Data(#"{"type":"allow","id":"c1","argv":["x"]}"#.utf8) + Data([0x0A])
    let other = Data(#"{"method":"initialized"}"#.utf8) + Data([0x0A])
    let out = ArisTurnDrain.replies([.send(codexYes), .send(toolYes), .send(apiYes), .send(other), .audit("{}")])
        .compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    check(out.count == 4 && (out[0]["result"] as? [String: Any])?["decision"] as? String == "decline" && (out[1]["result"] as? [String: Any])?["action"] as? String == "decline"
          && (out[1]["result"] as? [String: Any])?["content"] == nil && out[2]["type"] as? String == "deny" && out[2]["id"] as? String == "c1" && out[3]["method"] as? String == "initialized",
          "drain: an approval the stopped turn asks for is declined (Codex's command and tool answers, the API helper's allow), never allowed")
    let runner = tasksSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("case .confirm(let ask): write(driver.decide(ask.id, allow: false))") && runner.contains("""
                    case .audit(let line):
                        acted = true
                        Self.writeAudit(line, key: key)
                    case .tools(let calls):
                        if calls.contains(where: { ArisTurnSideEffects.mayChange($0, tools: Self.toolsPath) }) { changed = true }
""") && runner.contains("write(ArisTurnDrain.replies(events))"),
          "drain: a card asked while draining is answered no, audit lines are written and side effects counted")
}
