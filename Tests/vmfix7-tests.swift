// Tests for jv-vmfix7, the fifth VM run (aris-vmcheck notes5/*, cap5/*): the parts of its defects that live in the
// helper and the app (the pure ones are in Tests/ArisCoreTests/ArisTeachVM5Tests).
// D1  a menu item enabled only while its app is active is pressed with the app brought forward for that press, the same
//     path, and the app that was in front goes back; one greyed out for real presses nothing and says so;
// D2  the English card's gate verb, and the replay's card wording reaching the gate;
// D3  the chips and lines on a replay's path follow the UI language;
// D4  the no-AI reply names Settings › Talking to Aris › AI · Model, from the names the settings window draws;
// D5  a new document's window, there a moment after File › New, is the one the next typing reads and undoes;
// D6  a bare "되돌려" walks past what changed nothing of his to the change before it;
// D7  the go-on card's buttons (계속 / 멈추기) and the turn that says the failure first;
// D8  Settings search finds the saved steps by "saved", "steps", "lesson", "저장", "단계", "수업";
// M1  Saved steps' 지우기 asks before it forgets; M2 a renamed lesson keeps its place; M4 English cards quote with “”;
// M5  "우유 사기" carries no date of its own (the alert was a reminder left from an earlier run).
// Called from main.swift; uses its check().
import Foundation

private let vmfix7Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func vmfix7Source(_ path: String) -> String { (try? String(contentsOf: vmfix7Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runVmfix7Tests() {
    vmfix7MenuPressTests()
    vmfix7NewWindowTypingTests()
    vmfix7LanguageTests()
    vmfix7NoAITests()
    vmfix7UndoWalkTests()
    vmfix7GoOnTests()
    vmfix7SearchTests()
    vmfix7SavedStepsTests()
    vmfix7TodoDateTests()
}

// MARK: - Fakes: Finder in front, TextEdit behind with one document

private final class V7System: ArisAppsSystem {
    let editor = ArisAppsRunning(bundle: "com.apple.TextEdit", name: "TextEdit", pid: 701)
    let finder = ArisAppsRunning(bundle: "com.apple.finder", name: "Finder", pid: 501)
    var front: Int32 = 501
    var activated: [Int32] = []
    func installedApps() -> [ArisApps.AppRecord] { [.init(bundle: "com.apple.TextEdit", names: ["TextEdit"], path: "/System/Applications/TextEdit.app")] }
    func runningApps() -> [ArisAppsRunning] { [editor, finder] }
    func frontmost() -> ArisAppsRunning? { front == editor.pid ? editor : finder }
    func defaultBrowser() -> String? { "com.apple.Safari" }
    func open(_ request: ArisAppsOpenRequest) -> (ok: Bool, message: String) { (true, "opened") }
    func quit(pid: Int32) -> Bool { true }
    func hide(pid: Int32) -> Bool { true }
    func activate(pid: Int32) -> Bool { activated.append(pid); front = pid; return true }
    func bundleInfo(path: String) -> ArisApps.BundleInfo? { nil }
    func scriptingDictionary(path: String) -> Data? { nil }
    func includedDictionary(path: String) -> Data? { nil }
    func intentsMetadata(path: String) -> Data? { nil }
    func shortcuts() -> [String] { [] }
    func runShortcut(_ name: String, input: String?) -> (ok: Bool, output: String) { (true, "") }
    func automation(bundle: String) -> ArisApps.Grant { .notAsked }
    func runScript(_ source: String, timeout: TimeInterval) -> (ok: Bool, output: String, code: Int?) { (false, "", nil) }
    func pathKind(_ path: String) -> ArisApps.PathKind { .document }
    func displays() -> [ArisApps.Rect] { [ArisApps.Rect(x: 0, y: 25, width: 1440, height: 875)] }
}

/// TextEdit's menus as Cocoa validates them: Select All needs the key window, which only an active app has; Paste is
/// greyed out with nothing to paste. File › New makes a window (`onNew`).
private final class V7AX: ArisAppsAccessibility {
    let system: V7System
    var pressed: [[String]] = []
    var onNew: () -> Void = {}
    init(system: V7System) { self.system = system }
    func menuBar(pid: Int32) -> ArisApps.MenuBar? {
        let active = system.front == pid
        return ArisApps.MenuBar(menus: [
            ArisApps.MenuItem(title: "File", items: [ArisApps.MenuItem(title: "New", key: "N", modifiers: 0)]),
            ArisApps.MenuItem(title: "Edit", items: [ArisApps.MenuItem(title: "Select All", enabled: active, key: "A", modifiers: 0),
                                                     ArisApps.MenuItem(title: "Paste", enabled: false, key: "V", modifiers: 0)]),
        ])
    }
    func pressMenu(pid: Int32, path: [String]) -> (ok: Bool, message: String) {
        guard let item = menuBar(pid: pid)?.item(at: path) else { return (false, "no menu item “\(path.last ?? "")”") }
        guard item.enabled else { return (false, "“\(item.title)” is greyed out right now") }
        pressed.append(path)
        if path == ["File", "New"] { onNew() }
        return (true, "pressed")
    }
    func setFullScreen(pid: Int32, window: Int, on: Bool) -> Bool { true }
    func focusedRole(pid: Int32) -> String? { "textArea" }
    func caretToEnd(pid: Int32, at point: (x: Double, y: Double)?) -> ArisApps.CaretEnd { .moved }
}

/// TextEdit's windows as the engine sees them. A new window has the keyboard (typing goes into it) at once, but the
/// window list shows it only `lag` seconds later, as the VM's did.
private final class V7Engine: ArisAppsEngine {
    var texts: [Int: String] = [60: "Base doc"]
    var newAt: Date?
    var lag: TimeInterval = 0.3
    var typedInto: [Int] = []
    var listed: [Int] {
        var ids = [60]
        if let newAt, Date().timeIntervalSince(newAt) >= lag { ids.append(61) }
        return ids
    }
    var focused: Int { newAt == nil ? 60 : 61 }
    func run(_ arguments: [String], background: Bool) -> ArisApps.JSON {
        switch (arguments.first ?? "", arguments.dropFirst().first ?? "") {
        case ("window", "list"):
            let windows = listed.map { id -> ArisApps.JSON in
                .object(["window_id": .number(Double(id)), "window_title": .string(id == 60 ? "Untitled" : "Untitled 2"), "is_frontmost": .bool(id == focused),
                         "bounds": .object(["x": .number(100), "y": .number(100), "width": .number(800), "height": .number(600)])])
            }
            return .object(["success": .bool(true), "data": .object(["windows": .array(windows)])])
        case ("see", _):
            let id = Int(arguments[2]) ?? 60
            var area: [String: ArisApps.JSON] = ["id": .string("elem_\(id)"), "role": .string("textArea"), "label": .string("First Text View"),
                                                 "bounds": .object(["x": .number(100), "y": .number(150), "width": .number(800), "height": .number(400)])]
            if let text = texts[id], !text.isEmpty { area["value"] = .string(text) }
            return .object(["success": .bool(true), "data": .object(["snapshot_id": .string("ps_\(id)"), "window_title": .string("Untitled"),
                                                                     "ui_elements": .array([.object(area)])])])
        case ("type", _):
            // Keys go to the window with the keyboard, whatever window id the call named.
            typedInto.append(focused)
            texts[focused] = (texts[focused] ?? "") + arguments[2]
            return .object(["success": .bool(true), "data": .object(["delivery": .string("typed")])])
        default:
            return .object(["success": .bool(true), "data": .object([:])])
        }
    }
}

private func v7Hands(settle: TimeInterval = 0) -> (ArisAppsHands, V7System, V7AX, V7Engine) {
    let system = V7System()
    let ax = V7AX(system: system), engine = V7Engine()
    ax.onNew = { engine.newAt = Date() }
    let hands = ArisAppsHands(system: system, ax: ax, engine: engine, store: ArisAppsMemoryStore())
    hands.pollSeconds = 0.3
    hands.settleSeconds = settle
    return (hands, system, ax, engine)
}

// MARK: - D1: a menu item enabled only while its app is active

private func vmfix7MenuPressTests() {
    do {
        let (hands, system, ax, _) = v7Hands()
        let done = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Edit › Select All [cmd+a]")]))
        check(done.ok && ax.pressed == [["Edit", "Select All"]], "vmfix7 D1: Select All, greyed out with TextEdit behind Finder, is pressed (\(done.did))")
        check(system.activated == [701, 501] && system.front == 501, "vmfix7 D1: TextEdit came forward for the press only, and Finder went back in front (\(system.activated))")
    }
    do {
        // Greyed out for real (nothing to paste): nothing pressed, the reason said, Finder back in front.
        let (hands, system, ax, _) = v7Hands()
        let done = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Edit › Paste [cmd+v]")]))
        check(!done.ok && done.did.contains("“Paste” is greyed out right now") && ax.pressed.isEmpty && system.front == 501,
              "vmfix7 D1: an item greyed out in front too presses nothing and says why (\(done.did))")
        check(ArisTeachCopy.reason(done.did, english: false) == "‘Paste’ 메뉴가 지금은 비활성화되어 있어요", "vmfix7 D1: the reason reaches a Korean UI's message")
    }
    do {
        // Already in front and greyed out: no bringing forward, no second try.
        let (hands, system, _, _) = v7Hands()
        system.front = 701
        let done = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Edit › Paste [cmd+v]")]))
        check(!done.ok && system.activated.isEmpty, "vmfix7 D1: an app already in front isn't brought forward again")
    }
    do {
        // Enabled in the background: pressed there, nothing brought forward.
        let (hands, system, ax, _) = v7Hands()
        let done = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=File › New [cmd+n]")]))
        check(done.ok && system.activated.isEmpty && ax.pressed == [["File", "New"]], "vmfix7 D1: an item enabled in the background is pressed in the background")
    }
    do {
        // Security: the name judged is the name pressed. A near name is never pressed, in front or not.
        let (hands, system, ax, _) = v7Hands()
        let near = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Edit › Select all of it [cmd+a]")]))
        check(!near.ok && ax.pressed.isEmpty && system.activated.isEmpty, "vmfix7 D1 security: no near match is pressed, and nothing is brought forward for one")
    }
    let source = vmfix7Source("ArisAgent/Apps/ArisAppsHands+MenuPress.swift")
    check(source.contains("let pressed = ready ? ax.pressMenu(pid: pid, path: path) : first"), "vmfix7 D1: the second press is the same path, only once it is enabled")
}

// MARK: - D5: the new document's window is the one typed into, read and undone

private func vmfix7NewWindowTypingTests() {
    // As the replay did it: File › New, then the line typed at the end of the document's text.
    let (hands, _, _, engine) = v7Hands(settle: 1.0)
    let new = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=File › New [cmd+n]")]))
    check(new.ok && new.now.contains("a new window “Untitled 2” opened"), "vmfix7 D5: the press waits for the window it opens, and says it opened (\(new.now))")
    let typed = hands.call("app.type", .object(["app": .string("TextEdit"), "text": .string("Memo line"), "target": .string("First Text View 칸"), "at": .string("end")]))
    var inserted: String?
    if case .textInserted(_, let element, _)? = typed.undo { inserted = ArisApps.TextUndo.mark(element)?.inserted }
    check(typed.ok && engine.typedInto == [61] && inserted == "Memo line" && engine.texts[60] == "Base doc",
          "vmfix7 D5: the typing in the new document has its undo, made from that document (\(String(describing: inserted)), \(engine.typedInto))")
    // A field read earlier and changed since: the undo is made against what it holds now, never the old read.
    let (again, _, _, other) = v7Hands()
    _ = again.call("app.read", .object(["app": .string("TextEdit")]))
    other.texts[60] = "Base doc, edited since"
    let more = again.call("app.type", .object(["app": .string("TextEdit"), "text": .string(" more"), "target": .string("First Text View 칸"), "at": .string("end")]))
    var mark: ArisApps.TextUndo.Mark?
    if case .textInserted(_, let element, _)? = more.undo { mark = ArisApps.TextUndo.mark(element) }
    check(mark?.inserted == " more" && mark?.location == "Base doc, edited since".utf16.count,
          "vmfix7 D5: the field is read afresh before typing, so its undo holds (\(String(describing: mark)))")
}

// MARK: - D2, D3, M4: the UI's language on the replay's path

private func vmfix7LanguageTests() {
    check(ArisCardEnglish.title("바꾸기 · TextEdit") == "Change · TextEdit" && ArisCardEnglish.title("지우기 · TextEdit") == "Delete · TextEdit",
          "vmfix7 D3: the gate's verb in a card's title is English in an English UI")
    check(ArisReceiptWords.line("앱 열기: TextEdit", english: true) == "App opened: TextEdit" && ArisReceiptWords.line("앱 열기: TextEdit", english: false) == "앱 열기: TextEdit",
          "vmfix7 D3: the chip after a replay reads in the UI's language")
    let receipt = ArisReceipt([ArisReceiptAct(id: "a", summary: "앱 열기: TextEdit", undoable: false, asks: false),
                               ArisReceiptAct(id: "b", summary: "앱에 입력: TextEdit", undoable: true, asks: false)])
    check(receipt?.detail(english: true).contains("App opened: TextEdit") == true && receipt?.detail(english: true).contains("앱") == false,
          "vmfix7 D3: the receipt's tooltip too")
    let stopped = ArisStopLine.line(record: ["앱 열기: TextEdit"], cut: ArisStopLine.Cut(finished: [], cutOff: nil), english: true)
    check(stopped.contains("App opened: TextEdit") && !stopped.contains("앱 열기"), "vmfix7 D3: the stop line names what was done in English (\(stopped))")
    // M4: the gate's 「…」 in an English card.
    let replace = ArisCardEnglish.detail("글 바꾸기 TextEdit 「New text」\n지워지는 글 (9자, 1줄):\n「Base text」", title: "글 바꾸기 · TextEdit")
    check(!replace.contains("「") && !replace.contains("」") && replace.contains("“Base text”") && replace.contains("Replace text TextEdit “New text”"),
          "vmfix7 M4: an English card quotes with “” (\(replace))")
    // D2: a replay step's card (its own title) keeps the gate's own sentences, in English.
    let step = ArisCardEnglish.detail("TextEdit의 ‘본문’ 내용을 지우고 ‘x’ 넣기\n읽은 내용(앱 화면 TextEdit · 배운 단계)이 제안한 일이에요.\n지워지는 글 (4자, 1줄):\n「Base」",
                                      title: "“전체 바꾸기”, step 3 of 3")
    check(step.contains("Suggested by what was read (app window TextEdit · a taught step).") && step.contains("Erases (4 characters, 1 line):") && step.contains("“Base”"),
          "vmfix7 D2: the gate's sentences under a replay's own title are English too (\(step))")
    // Not a gate card: a message's own line that starts like a gate verb stays as he wrote it.
    check(ArisCardEnglish.detail("보기 좋다", title: "메시지 보내기") == "보기 좋다", "vmfix7 D2: no one's own words are taken for the gate's")
    // The replay's card wording reaches the gate's cards.
    let desk = vmfix7Source("ArisAgent/Teach/ArisTeachDesk.swift")
    check(desk.contains("gate.describe(session: session, calls: ArisTeachReplay.described(procedure, plan: plan, english: english))"),
          "vmfix7 D2: a replay words its steps' cards in the UI's language")
    let gate = vmfix7Source("ArisAgent/Trust/ArisTrustGate.swift")
    check(gate.contains("let planned = asks.plan(items, intent: intent, home: home, described: described[session] ?? [:])"), "vmfix7 D2: the gate's cards take that wording")
    check(vmfix7Source("ArisAgent/Teach/ArisTeachTurn.swift").contains("}, goOn: goOn, english: english, pass: pass, carryingAll: true)"), "vmfix7 D2: the turn passes the UI's language on")
}

// MARK: - D4: the real place in Settings

private func vmfix7NoAITests() {
    let english = ArisBrainTrouble(brain: nil, missing: .any).line(korean: false)
    let korean = ArisBrainTrouble(brain: nil, missing: .any).line(korean: true)
    check(english == "No AI is ready on this Mac. Connect one in Settings › Talking to Aris › AI · Model.", "vmfix7 D4: the English line names the real path (\(english))")
    check(korean == "지금 쓸 수 있는 AI가 없어요. 설정 › Aris와 말하기 › AI · 모델에서 AI를 하나 연결해 주세요.", "vmfix7 D4: the Korean line too (\(korean))")
    check(ArisBrainTrouble.all.allSatisfy { !$0.line(korean: true).contains("AI 서비스") && !$0.line(korean: false).contains("AI services") },
          "vmfix7 D4: no line names the page that is gone")
    check(ArisBrainTrouble.settingsButton(english: true) == "Open Settings › AI · Model" && ArisBrainTrouble.settingsButton(english: false) == "설정 › AI · 모델 열기",
          "vmfix7 D4: the button under it names it too")
    // The same names the window draws: its page and part, and the English its catalog gives them.
    let part = ArisSettingsParts.part("talk.ai")
    check(ArisSettingsPage.talk.title == ArisSettingsNames.talkPage.korean && part?.title == ArisSettingsNames.aiPart.korean && part?.page == .talk,
          "vmfix7 D4: the line's page and part are the settings window's own")
    check(ArisSettingsPath.formerName(page: .ai, part: "talk.ai", english: false) == "Aris와 말하기 › AI · 모델"
          && ArisSettingsNames.aiPlace(english: false) == "설정 › " + ArisSettingsPath.formerName(page: .ai, part: "talk.ai", english: false),
          "vmfix7 D4: the path is the one the settings links use")
    let catalog = ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: vmfix7Root.appendingPathComponent("Aris/components/Settings/Settings.xcstrings"))) ?? Data())
    check(catalog[ArisSettingsNames.talkPage.korean] == ArisSettingsNames.talkPage.english && catalog[ArisSettingsNames.aiPart.korean] == ArisSettingsNames.aiPart.english,
          "vmfix7 D4: the English line's names are the English window's (\(String(describing: catalog[ArisSettingsNames.talkPage.korean])))")
}

// MARK: - D6: walking past what changed nothing

private func vmfix7UndoWalkTests() {
    let now = Date()
    // A to-do added, then a replay that opened TextEdit and typed (its typing already undone: filtered out by the app).
    let todo = ArisUndoWords.Change(id: "todo", date: now.addingTimeInterval(-60), summary: "할 일 추가: 우유 사기", action: "made", asks: false, undoable: true)
    let opened = ArisUndoWords.Change(id: "open", date: now.addingTimeInterval(-10), summary: "앱 열기: TextEdit", action: nil, asks: false, undoable: false,
                                      unit: "teach-a", passOver: true)
    switch ArisUndoWords.reach([todo, opened], since: now.addingTimeInterval(-900), kind: nil) {
    case .undo(let entry, _, _): check(entry.id == "todo", "vmfix7 D6: the second 되돌려 reaches the to-do past the app that was opened")
    default: check(false, "vmfix7 D6: the second 되돌려 reaches the to-do past the app that was opened")
    }
    // A change of his that can't be undone still stops it, as before (QA BUG-18).
    let sent = ArisUndoWords.Change(id: "sent", date: now.addingTimeInterval(-5), summary: "메시지 보냄: 엄마", action: nil, asks: false, undoable: false)
    check(ArisUndoWords.reach([todo, opened, sent], since: now.addingTimeInterval(-900), kind: nil) == .cannot("메시지 보냄: 엄마"),
          "vmfix7 D6: a real change that can't be undone is still said, never reached past")
    // The record marks what changes nothing of his.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-vmfix7-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let home = folder.resolvingSymlinksInPath().path
    defer { try? FileManager.default.removeItem(atPath: home) }
    func step(_ capability: String, _ seconds: Double, session: String?, undo: ArisUndoRecipe?, result: String = "{}") -> ArisRecordEntry {
        ArisRecordEntry.call(at: now.addingTimeInterval(seconds), session: session, task: nil, capability: capability, effect: .changeReversible,
                             provenance: .ownStep, decision: .runWithUndo(announce: false), arguments: [.init(kind: .app, value: "TextEdit")],
                             result: result, ok: true, undo: undo)
    }
    let typedUndo = ArisApps.TextUndo.recipe(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "", before: "Doc", after: "DocAdded line")
    let run = [step("app.open", -30, session: "teach-x1", undo: nil),
               step("app.do", -29, session: "teach-x1", undo: nil, result: #"{"now":"a new window “Untitled 2” opened"}"#),
               step("app.type", -28, session: "teach-x1", undo: typedUndo)]
    let elsewhere = step("app.do", -20, session: nil, undo: nil)
    for entry in run + [elsewhere] { _ = ArisRecordJournal.append(entry, home: home) }
    var rows = ArisRecord.activityRows(ArisRecordJournal.state(home: home))
    check(rows.filter { $0["passOver"] as? Bool == true }.map { $0["id"] as? String } == [run[0].id], "vmfix7 D6: before any undo, only opening the app is passed over")
    _ = ArisRecordJournal.append(.undone(run[2].id, at: now, result: "removed"), home: home)
    rows = ArisRecord.activityRows(ArisRecordJournal.state(home: home))
    let passed = Set(rows.filter { $0["passOver"] as? Bool == true }.compactMap { $0["id"] as? String })
    check(passed == [run[0].id, run[1].id], "vmfix7 D6: once the run's typing is undone, what is left of the run is passed over; another change isn't")
    let controller = vmfix7Source("Aris/private/Aris/ArisController+Undo.swift")
    check(controller.contains("passOver: $0.passOver == true)"), "vmfix7 D6: the app reads the mark")
}

// MARK: - D7: the go-on card

private func vmfix7GoOnTests() {
    let card = ArisConfirmation(id: "mcp-1", title: "t", detail: "d", allow: "Continue")
    check(card.allow == "Continue" && ArisConfirmation(id: "x", title: "t", detail: "d", allow: "Pay now").allow == nil,
          "vmfix7 D7: 계속/Continue is an allowed yes word; anything else still isn't")
    check(ArisConfirmWords.allow("계속", sends: false, english: true) == "Continue" && ArisConfirmWords.cancel("계속", english: true) == "Stop"
          && ArisConfirmWords.allow("Continue", sends: false, english: false) == "계속" && ArisConfirmWords.cancel("Continue", english: false) == "멈추기"
          && ArisConfirmWords.cancel(nil, english: true) == "Cancel",
          "vmfix7 D7: the go-on card's buttons are Continue and Stop in the UI's language")
    let turn = vmfix7Source("ArisAgent/Teach/ArisTeachTurn.swift")
    // (Seventh VM run, item 2: the sentence goes out through ArisTeachTurnReplies.failed, after the tag is marked.)
    let said = turn.range(of: "ArisTeachTurnReplies.failed(procedure, at: index, why: why, english: english)")?.lowerBound, asked = turn.range(of: "let asked = ArisTeachCopy.goOnCard(")?.lowerBound
    check(said != nil && asked != nil && said! < asked!, "vmfix7 D7: the failure is said first, then the card asks")
    check(turn.contains("allow: ArisTeachCopy.goOnAllow(english: english))"), "vmfix7 D7: the card carries 계속 / Continue")
    let desk = vmfix7Source("ArisAgent/Teach/ArisTeachDesk.swift")
    check(desk.contains("judge.nextIntent(session: session, intent: next)") && desk.contains("goOn: goOn, afresh: afresh,"),
          "vmfix7 D7 security: the steps after his go-on are decided under an intent of their own")
}

// MARK: - D8: the search finds the saved steps

private func vmfix7SearchTests() {
    let catalog = ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: vmfix7Root.appendingPathComponent("Aris/components/Settings/Settings.xcstrings"))) ?? Data())
    ArisSettingsCopy.install(catalog)
    defer { ArisSettingsCopy.install([:]) }
    let english = ArisSettingsWording.make(page: .able, english: true)
    let alias: (ArisSettingsEntry) -> ArisSettingsIndex.Alias = { .init(title: english.of($0.page, $0.title), page: english.frame($0.page.title)) }
    var s = ArisSettingsSnapshot()
    s.savedSteps = [ArisSavedStepsItem(key: " taught:x", request: "전체 바꾸기", steps: ["a"], stepsEn: ["a"], apps: "TextEdit", saved: "", taught: true)]
    let shown = ArisSettingsBuilder.searchable(s)
    for word in ["saved", "steps", "lesson", "저장", "단계", "수업"] {
        let found = ArisSettingsIndex.search(word, among: shown, alias: alias).map(\.id)
        check(found.contains("memory.saved"), "vmfix7 D8: “\(word)” finds the saved steps (\(found.prefix(4)))")
    }
    check(ArisSettingsIndex.entry("memory.saved")?.page == .able && ArisSettingsParts.holding("memory.saved")?.id == "able.memory",
          "vmfix7 D8: indexed where it is drawn, as the other rows are")
}

// MARK: - M1, M2: Saved steps

private func vmfix7SavedStepsTests() {
    typealias R = ArisSavedStepsSettingsRows
    let item = ArisSavedStepsItem(key: "plain", request: "정리", steps: ["a"], stepsEn: ["a"], apps: "Finder", saved: "")
    var s = ArisSettingsSnapshot()
    s.savedSteps = [item]
    check(R.sections(s, english: false).first?.rows.first?.control == .buttons([ArisSettingButton(title: R.forget, action: .forgetSavedSteps("plain"))]),
          "vmfix7 M1: 지우기 as before, until it is pressed")
    s.savedStepsConfirming = "plain"
    let row = R.sections(s, english: false).first?.rows.first
    check(row?.control == .buttons([ArisSettingButton(title: R.cancel, action: .keepSavedSteps),
                                    ArisSettingButton(title: R.really, action: .forgetSavedSteps("plain"), kind: .danger)])
          && row?.desc == R.forgetAsk,
          "vmfix7 M1: pressed once, it asks: 취소 and 정말 지우기, and says it can't be undone")
    check(R.sections(s, english: true).first?.rows.first?.desc == "This can't be undone. Delete it?", "vmfix7 M1: in English too")
    let model = vmfix7Source("Aris/private/Aris/ArisMemorySettingsModel.swift")
    check(model.contains("guard confirmingForget == key else {") && vmfix7Source("Aris/components/Settings/ArisLiveSettings.swift").contains("memory.forgetSavedStepsPressed(key: key)"),
          "vmfix7 M1: the first press only asks; the second forgets")
    // M2: renamed, it stays where it was.
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let older = ArisTeachProcedure(name: "줄 추가", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit")], parameters: [], created: start)
    let newer = ArisTeachProcedure(name: "메모 쓰기", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit")], parameters: [],
                                   created: start.addingTimeInterval(60))
    let renamed = older.renamed("줄 하나 추가", at: start.addingTimeInterval(600))
    let order = ArisTaughtRoute.rows([renamed, newer]).compactMap { $0["request"] as? String }
    check(order == ["메모 쓰기", "줄 하나 추가"], "vmfix7 M2: a renamed lesson keeps its place (\(order))")
}

// MARK: - M5: "우유 사기" has no date of its own

private func vmfix7TodoDateTests() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let read = ArisTodoDate.titled("우유 사기", now: now)
    check(read.text == "우유 사기" && read.due == nil, "vmfix7 M5: “우유 사기” is added with no due date (the alert was another reminder's)")
}
