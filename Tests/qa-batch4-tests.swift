// Tests for QA batch 4 (session jdoe-62): calendar writes on the Mac calendar, not Notion (BUG-16); the app's undo
// never hangs and never says raw English (BUG-17); undo takes only the latest change, and local changes are logged
// (BUG-18); the brief's deadline tile and its spoken line (BUG-19).
import Foundation

func runQABatch4Tests() {
    qaCalendarIsTheMacsTests()
    qaUndoAnswersTests()
    qaUndoLatestOnlyTests()
    qaBriefWordsTests()
}

// MARK: - BUG-16: the schedule is the Mac's calendar on every brain

private func qaCalendarIsTheMacsTests() {
    let codex = ArisAgentPrompt.system(tools: "/t", notion: true, gated: true)
    check(!codex.contains("notion-calendar") && !codex.contains("Notion Calendar"), "BUG-16: Codex's prompt has no Notion Calendar")
    check(codex.contains("`/t event \"<title>\"") && codex.contains("don't look them up"),
          "BUG-16: Codex adds events with aris-tools event and answers the schedule from the context")
    check(codex.contains(ArisAgentPrompt.cardRule(calendar: true)), "BUG-16: Codex shows the calendar card like every brain")
    check(codex.contains("notion-search"), "BUG-16: Notion pages and notes stay")
    for prompt in [ArisAgentPrompt.system(tools: "/t"), ArisAgentPrompt.system(tools: "/t", reads: true),
                   ArisAgentPrompt.system(tools: "/t", gated: true, functions: true), ArisAgentPrompt.system(tools: "/t", relay: true)] {
        check(!prompt.contains("Notion Calendar") && !prompt.contains("notion-calendar"), "BUG-16: no brain's prompt names Notion Calendar")
    }
    check(!ArisCodexDriver.notionTools.contains { $0.hasPrefix("notion-calendar") } && ArisCodexDriver.notionTools.contains("notion-search"),
          "BUG-16: Codex's Notion has no calendar tools (events go to the Mac calendar)")
    check(ArisActions.calendarApp == "Calendar", "BUG-16: aris-tools calendar opens Apple Calendar")
}

// MARK: - BUG-17: the app's undo answers in time, in words

private func qaUndoAnswersTests() {
    // QA's root cause: aris-agent waited on macOS's "데스크탑 폴더의 파일에 접근하려고 합니다" prompt; the app gave up at
    // 20 s. Now the undo waits a minute (the agent, then the app a little longer), and after a few seconds says why.
    check(ArisActivityBridge.undoTimeout >= 60 && ArisUndoWords.clientTimeout > ArisActivityBridge.undoTimeout + 5
          && ArisActivity.appleScriptLimit < ArisActivityBridge.undoTimeout && ArisUndoWords.hintAfter <= 5,
          "BUG-17: a folder prompt gets a minute; aris-tools ends first, then the agent, then the app")
    check(ArisUndoWords.waitingLine(folder: "Desktop", korean: true) == "Mac이 데스크탑 폴더 접근을 묻고 있어요. 허용하면 이어서 해요."
          && ArisUndoWords.waitingLine(folder: "Downloads", korean: true).contains("다운로드 폴더")
          && ArisUndoWords.waitingLine(folder: nil, korean: true).contains("폴더 접근")
          && ArisUndoWords.waitingLine(folder: "Documents", korean: false).contains("Documents folder"),
          "BUG-17: the notch says Mac is asking for the folder, naming it when known")
    let home = "/Users/me"
    check(ArisFolderAccess.folder(of: "/Users/me/Desktop/qa/a.png", home: home) == "Desktop"
          && ArisFolderAccess.folder(of: "/Users/me/Downloads/x.pdf", home: home) == "Downloads"
          && ArisFolderAccess.folder(of: "/Users/me/Documents", home: home) == "Documents"
          && ArisFolderAccess.folder(of: "/Users/me/Desktops/x", home: home) == nil && ArisFolderAccess.folder(of: "/tmp/x", home: home) == nil,
          "BUG-17: which protected folder a path is in")
    check(ArisFolderAccess.folder(ofUndo: ["trashMade": ["paths": ["/Users/me/Desktop/qa/a.png"]]], home: home) == "Desktop"
          && ArisFolderAccess.folder(ofUndo: ["moveBack": ["from": "/Users/me/Music/x", "to": "/Users/me/Documents/x"]], home: home) == "Documents"
          && ArisFolderAccess.folder(ofUndo: ["deleteEvent": ["id": "E1"]], home: home) == nil,
          "BUG-17: an entry's undo names its folder")
    check(ArisFolderAccess.url(named: "Desktop", home: home)?.path == "/Users/me/Desktop" && ArisFolderAccess.url(named: "Library", home: home) == nil
          && ArisFolderAccess.url(named: "../Desktop", home: home) == nil, "BUG-17: the consent touch only ever reads one of the three folders")
    // 설정 › 컴퓨터 제어: a row per folder, in the existing permission rows' style.
    let rows = ArisSettingsSnapshot.folderPermissions(granted: ["Desktop": true])
    check(rows.map(\.id) == ["folder.Desktop", "folder.Documents", "folder.Downloads"] && rows[0].granted && !rows[1].granted
          && rows[0].title == "데스크탑 폴더", "BUG-17: settings show the Desktop, Documents and Downloads access (one row: macOS asks for Aris)")
    var snapshot = ArisSettingsSnapshot()
    snapshot.permissions = rows
    let section = ArisSettingsBuilder.sections(.control, snapshot).first { $0.id == "control.permissions" }
    check(section?.rows.map(\.id) == ["control.folders"],
          "BUG-17: they are a row of 권한 like the others (one row for the three folders: settings item 11)")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("aris-qa4-lock-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let descriptor = ArisActivity.openLock(root.appendingPathComponent("activity.jsonl"))
    check(descriptor >= 0 && fcntl(descriptor, F_GETFD) & FD_CLOEXEC != 0,
          "BUG-17: the log's lock is never inherited (a stuck osascript can't keep the log locked)")
    if descriptor >= 0 { close(descriptor) }
    let started = Date()
    var said = ""
    do { try ArisActivity.runBounded("/bin/sleep", ["5"], limit: 0.5, app: "Calendar") } catch { said = error.localizedDescription }
    check(Date().timeIntervalSince(started) < 3 && said.contains("Calendar"), "BUG-17: an AppleScript that hangs is stopped: \(said)")

    // What the notch says: never raw English, in either language's own words.
    for raw in ["aris-tools didn't answer", "aris-agent didn't answer", "nothing to undo", "that can't be undone", "that was already undone",
                "no entry with that id", "couldn't undo \"일정 추가: 회의\": Calendar: no such event", "Operation not permitted"] {
        let korean = ArisUndoWords.failure(raw, korean: true)
        check(!korean.isEmpty && korean.replacingOccurrences(of: "Mac", with: "").range(of: "[A-Za-z]{3,}", options: .regularExpression) == nil,
              "BUG-17: \(raw) -> \(korean)")
        check(!ArisUndoWords.failure(raw, korean: false).contains(raw) || raw == "nothing to undo", "BUG-17 (en): \(raw) isn't passed through raw")
    }
    check(ArisUndoWords.failure("that can't be undone", korean: true) == "방금 한 일은 되돌릴 수 없어요.", "BUG-17: not undoable, said plainly")
    check(ArisUndoWords.failure("지금은 대화 중이에요. 끝나고 다시 눌러 주세요.", korean: true) == "지금은 대화 중이에요. 끝나고 다시 눌러 주세요.",
          "BUG-17: the app's own Korean reason stays as it is")
    check(ArisUndoWords.failure("aris-tools didn't answer", korean: true).contains("시간"), "BUG-17: a timeout says it took too long")
    // A card that is needed shows, for voice too: an event Aris made, or a schedule brought back.
    check(ArisUndoWords.asksOnCard(.needsConfirm(id: "x", summary: "일정 추가: 회의"))
          && ArisUndoWords.asksOnCard(.needsConfirm(id: "x", summary: "예약 취소", revivesSchedule: true))
          && !ArisUndoWords.asksOnCard(.done("x")) && !ArisUndoWords.asksOnCard(.needsConfirm(id: "", summary: "x")),
          "BUG-17: every yes the undo needs is asked on a card")
}

// MARK: - BUG-18: "방금 한 거 되돌려" takes only the latest change

private func qaUndoLatestOnlyTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("aris-qa4-undo-\(UUID().uuidString)")
    let home = root.path
    try? FileManager.default.createDirectory(at: root.appendingPathComponent("Desktop"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent(".config/aris/aris/activity.jsonl")
    let made = home + "/Desktop/a.png"
    FileManager.default.createFile(atPath: made, contents: Data("x".utf8))
    func entry(_ summary: String, _ undo: ArisUndo?, ago: TimeInterval) -> ArisActivityEntry {
        ArisActivityEntry(id: UUID(), date: Date().addingTimeInterval(-ago), job: "대화", worker: "Aris", summary: summary, undo: undo, undone: false)
    }
    let older = entry("convert: 1개 만듦", .trashMade(paths: [made]), ago: 600)
    let newer = entry("새 폴더: 과제", nil, ago: 30)
    ArisActivity.append(older, file: file)
    ArisActivity.append(newer, file: file)
    var said = ""
    do { _ = try ArisActivity.undo(id: nil, confirmed: false, file: file, home: home) } catch { said = error.localizedDescription }
    check(said == "that can't be undone" && FileManager.default.fileExists(atPath: made),
          "BUG-18: the latest change can't be undone: said so, and the older one is left alone (\(said))")
    check(ArisActivityBridge.latestUndoable(file: file) == nil, "BUG-18: the gate's mirror takes the latest change too (nothing to undo)")
    // A later undoable change is the one undone.
    let volume = entry("볼륨 30", .setVolume(level: 55), ago: 5)
    ArisActivity.append(volume, file: file)
    check(ArisActivityBridge.latestUndoable(file: file)?.summary == "볼륨 30", "BUG-18: the mirror names the latest change")
    check(ArisActivity.needsYes(.setVolume(level: 55)) == false && ArisActivity.needsYes(.removeTodo(id: "r1")) == false,
          "BUG-18: undoing a local change needs no card")

    // The local changes, logged by kind (the app's request, through the agent).
    check(ArisActivity.localUndo(kind: "todo-add", id: "r1", level: nil) == .some(.removeTodo(id: "r1"))
          && ArisActivity.localUndo(kind: "todo-done", id: "r1", level: nil) == .some(.reopenTodo(id: "r1"))
          && ArisActivity.localUndo(kind: "timer-set", id: nil, level: nil) == .some(.stopTimer)
          && ArisActivity.localUndo(kind: "volume", id: nil, level: 40) == .some(.setVolume(level: 40)),
          "BUG-18: to-do add/done, the timer and the volume are logged with their undo")
    check(ArisActivity.localUndo(kind: "timer-cancel", id: nil, level: nil) == .some(nil) && ArisActivity.localUndo(kind: "arrange", id: nil, level: nil) == .some(nil),
          "BUG-18: a cancelled timer and arranged windows are logged, not undoable")
    check(ArisActivity.localUndo(kind: "todo-add", id: nil, level: nil) == nil && ArisActivity.localUndo(kind: "volume", id: nil, level: 400) == nil
          && ArisActivity.localUndo(kind: "trash", id: nil, level: nil) == nil, "BUG-18: anything else is refused")
    check(ArisActivityBridge.localLogArguments(kind: "volume", summary: "볼륨 30", id: nil, level: 55) == ["activity", "log", "--kind", "volume", "--level", "55", "볼륨 30"]
          && ArisActivityBridge.localLogArguments(kind: "todo-add", summary: "할 일: 우유", id: "x-coredata://A/B", level: nil)
             == ["activity", "log", "--kind", "todo-add", "--id", "x-coredata://A/B", "할 일: 우유"]
          && ArisActivityBridge.localLogArguments(kind: "trash", summary: "x", id: nil, level: nil) == nil
          && ArisActivityBridge.localLogArguments(kind: "volume", summary: "", id: nil, level: 5) == nil,
          "BUG-18: the agent asks aris-tools to log only these kinds")
    // Codable round trip of the new undo kinds.
    for undo in [ArisUndo.removeTodo(id: "r1"), .reopenTodo(id: "r1"), .setVolume(level: 40), .stopTimer] {
        let data = try? JSONEncoder().encode(undo)
        check(data.flatMap { try? JSONDecoder().decode(ArisUndo.self, from: $0) } == undo, "BUG-18: \(undo) is kept in the log")
    }
    // No AI writes these entries: only the agent, for the app.
    let tools = "/Users/me/.config/aris/aris-tools"
    check(ArisRiskPolicy.risk(of: .shell("\(tools) activity log --kind volume --level 0 x"), tools: tools, home: "/Users/me") == .never
          && ArisRiskPolicy.risk(of: .shell("\(tools) activity --today"), tools: tools, home: "/Users/me") == .auto,
          "BUG-18: an AI can't write the log (reading it stays a read)")
    if case .deny = ArisTurnGate.verdict(tool: "Bash", command: "\(tools) activity log --kind arrange x", tools: tools, tainted: false) {} else {
        check(false, "BUG-18: the open Claude can't write the log")
    }
    check(!ArisSealedTools.allows(["activity", "log", "--kind", "arrange", "x"]), "BUG-18: nor the sealed one")
    check(ArisTodoRoute.Request(json: ["op": "reopen", "id": "r1"])?.op == .reopen, "BUG-18: the app can reopen a ticked to-do")
}

// MARK: - BUG-19: the brief's deadline tile and what can be spoken

private func qaBriefWordsTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let now = ISO8601DateFormatter().date(from: "2026-10-31T12:30:00Z")!
    let facts: [String: Any] = ["weather": ["place": "Orlando", "temp": 8, "sky": "흐림", "rain": 70],
                                "due": [["course": "CSC263H1", "title": "Problem Set 3", "at": "2026-11-01T03:59:00Z"]],
                                "dueCount": 7, "dueToday": 2, "announcements": 2]
    let brief = ArisBrief.make(facts: facts, events: [], now: now, calendar: calendar)
    check(brief.tiles.last?.label == "오늘 마감 2 · 이번 주 7", "BUG-19: the tile says today's and this week's counts: \(brief.tiles.last?.label ?? "")")
    let english = ArisBrief.make(facts: facts, events: [], now: now, calendar: calendar, english: true)
    check(english.tiles.last?.label == "2 due today · 7 this week", "BUG-19: and in English: \(english.tiles.last?.label ?? "")")
    let tomorrow: [String: Any] = ["due": [["course": "MAT224", "title": "Quiz", "at": "2026-11-02T03:59:00Z"]], "dueCount": 1, "dueToday": 0]
    let later = ArisBrief.make(facts: tomorrow, events: [], now: now, calendar: calendar)
    check(later.tiles.last?.label == "오늘 마감 0 · 이번 주 1" && later.tiles.last?.detail.hasPrefix("내일") == true && later.tiles.last?.urgent == false,
          "BUG-19: a deadline that isn't today says its day in the detail")
    check(!brief.spoken.contains("·") && !brief.summary.contains("·") && brief.spoken.contains(", ") && !english.spoken.contains("·"),
          "BUG-19: what can be spoken has no separators, only commas and full stops: \(brief.spoken)")
    check(brief.spoken.contains("오늘 마감 2개") && brief.spoken.contains("이번 주 7개"), "BUG-19: the spoken line counts naturally: \(brief.spoken)")
    let items = [ArisCanvas.Item(kind: "assignment", course: "A", title: "a", date: ISO8601DateFormatter().date(from: "2026-11-01T03:59:00Z")!, submitted: false, unread: false),
                 ArisCanvas.Item(kind: "assignment", course: "B", title: "b", date: ISO8601DateFormatter().date(from: "2026-11-01T05:00:00Z")!, submitted: false, unread: false),
                 ArisCanvas.Item(kind: "assignment", course: "C", title: "c", date: ISO8601DateFormatter().date(from: "2026-10-31T20:00:00Z")!, submitted: false, unread: false)]
    check(ArisCanvas.dueToday(items, now: now, calendar: calendar) == 2, "BUG-19: today's deadlines are counted in the brief's own day")
}
