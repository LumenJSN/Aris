// Tests for jv-vmfix10, the seventh VM run (aris-vmcheck notes7/*, cap7/*): the parts of its defects that live in
// the helper and the app (the pure ones are in Tests/ArisCoreTests/ArisTeachVM7Tests; the drawn cards in
// card-text-render/check.sh). Each fake does what the VM did, as its records and screenshots show it.
// 1  the values card's text ends with its fields' lines, so the app draws its note (new line, ↵) above them;
// 2  a replay's failed step marks its tag before the sentence that says so: no tick, ever, for that run;
// 3  the card's click hold (still the security review's second) is drawn unlike a disabled button;
// 4  after a replay's undo, a step that changed nothing (Select All, opening the app) doesn't make the reply partial;
// 5  the undo's reply names what was undone ("Removed the text I typed in TextEdit for “줄 추가”.");
// 8  while a replay waits on a card, the app he had is back in front; a later step brings its app forward again.
// Called from main.swift; uses its check().
import Foundation

private let vmfix10Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func vmfix10Source(_ path: String) -> String { (try? String(contentsOf: vmfix10Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runVmfix10Tests() {
    vmfix10ValuesCardTests()
    vmfix10FailedTagTests()
    vmfix10CardHoldTests()
    vmfix10KeptTests()
    vmfix10UndoReplyTests()
    vmfix10FrontWhileAskedTests()
}

// MARK: - 1: the values card's note is drawn

private func vmfix10ValuesCardTests() {
    var typed = ArisTeachStep(action: .type, app: "TextEdit", bundle: "com.apple.TextEdit", target: "First Text View 칸", role: "textArea",
                              label: ArisTeachGeneralise.bodyLabel)
    typed.parameter = "p1"
    typed.place = .end
    typed.startsLine = true
    let made = ArisTeachProcedure(name: "줄 추가", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit"), typed],
                                  parameters: [ArisTeachParameter(key: "p1", label: ArisTeachGeneralise.bodyLabel, example: "Added line", app: "TextEdit", fromApp: false)],
                                  created: Date())
    for english in [true, false] {
        let asked = ArisTeachCopy.valuesCard(made, missing: ArisTeachReplay.missing(made, given: [:]), english: english)
        // As ArisMCPCards.put shapes it for the app: each field's label is its key.
        let fields = asked.fields.map { ArisCardField(key: $0.key, label: $0.key, role: .text, value: $0.value) }
        let card = ArisConfirmation(id: "v", title: asked.card.title, detail: asked.card.detail, fields: fields)
        let note = ArisCardEdit.note(card) ?? ""
        // The field comes up empty (exp11, T2): last time's value is in the note only as a marked suggestion.
        check(note.contains("↵") && note.contains(english ? "on a new line" : "새 줄") && note.contains(english ? "Suggestion, last time's text: ‘Added line’" : "제안: 지난번 본문 ‘Added line’"),
              "vmfix10 1: the values card (\(english ? "English" : "Korean")) draws its note, new line and ↵, above its field (\(note))")
        // The yes still goes back with exactly the card's text (ArisShownCard): unchanged values, no edits.
        check(ArisShownCard.matches(allow: true, detail: card.detail, full: nil, expectedDetail: asked.card.detail, expectedFull: nil, fields: fields),
              "vmfix10 1: the card's yes is bound to the text it was drawn from")
    }
    // Any editable card whose text doesn't end with its fields' own lines is drawn whole, never dropped.
    let odd = ArisConfirmation(id: "o", title: "t", detail: "이 줄은 필드 줄로 끝나지 않아요", fields: [ArisCardField(key: "text", label: "text", role: .text, value: "x")])
    check(ArisCardEdit.note(odd) == "이 줄은 필드 줄로 끝나지 않아요", "vmfix10 1: an editable card's text that doesn't end with its fields is still drawn")
}

// MARK: - 2: the failed step's tag is never ticked

private func vmfix10FailedTagTests() {
    // cap7/W1-result.jpg: "Doing “랩 메모” ✓" under "Step 2 didn't work …" for 3–5 s, until Stop or Continue.
    let made = ArisTeachProcedure(name: "랩 메모", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit"),
                                                          ArisTeachStep(action: .menu, app: "TextEdit", bundle: "com.apple.TextEdit", label: "Wrap to Page",
                                                                        menu: ["Format", "Wrap to Page"])],
                                  parameters: [], created: Date())
    let replies = ArisTeachTurnReplies.failed(made, at: 1, why: "that menu item isn't there now (TextEdit shows ‘Wrap to Window’ instead)", english: true)
    guard case .stepFailed(nil)? = replies.first, case .delta(let said)? = replies.last, replies.count == 2 else {
        return check(false, "vmfix10 2: the step's tag is marked failed first, then the sentence (\(replies))")
    }
    check(said.contains("Step 2 didn't work"), "vmfix10 2: the sentence is the failure line")
    // The app, fed what the run streams: its step running, then the failure (as the app takes each reply).
    var session = ArisSession().listening().hearing("랩 메모 해 줘").thinking()
    session = session.working("Doing “랩 메모” (2/2)")
    for reply in replies {
        switch reply {
        case .stepFailed(let label): session = session.stepFailed(label)
        case .delta(let piece): session = session.answering(piece)
        default: break
        }
    }
    check(!session.tags.isEmpty && session.tags.allSatisfy(\.failed), "vmfix10 2: from the moment the failure is said, the tag shows it failed, never a tick (\(session.tags))")
    // The go-on card that follows keeps it so (asking keeps the steps as they are).
    let asked = session.asking(ArisConfirmation(id: "g", title: "Step 2 didn't work. Go on with the 0 steps left?", detail: "x"))
    check(asked.steps.allSatisfy(\.failed), "vmfix10 2: the go-on card's wait keeps the failed mark")
    // Before: the sentence alone, and the app ticked the tag.
    var before = ArisSession().listening().hearing("랩 메모 해 줘").thinking().working("Doing “랩 메모” (2/2)")
    before = before.answering(said)
    check(before.tags.contains { $0.done && !$0.failed }, "vmfix10 2: (the sentence alone ticks the tag, which is what the VM showed)")
    // Wiring: the run's go-on question streams these, before its card.
    let turn = vmfix10Source("ArisAgent/Teach/ArisTeachTurn.swift")
    let marked = turn.range(of: "for reply in ArisTeachTurnReplies.failed(procedure, at: index, why: why, english: english) { stream(reply, on: connection) }")
    let card = turn.range(of: "let asked = ArisTeachCopy.goOnCard(")
    check(marked != nil && card != nil && marked!.upperBound < card!.lowerBound && !turn.contains("stream(.delta(ArisTeachCopy.failedLine("),
          "vmfix10 2: the go-on question marks the tag and says the failure before its card, and nothing says it unmarked")
}

// MARK: - 3: the card's click hold

private func vmfix10CardHoldTests() {
    typealias H = ArisCardHold
    // The length stays the security review's (one second), set in one place.
    check(H.hold == 0.5, "vmfix10 3: the hold is half a second (the owner's say of 2026-11-19; it was the security review's second) (\(H.hold))")
    let hold = vmfix10Source("Aris/private/Aris/ArisCardHold.swift")
    check(hold.components(separatedBy: "static let hold: Double").count == 2 && !hold.contains("ArisCardTiming.clickHold"),
          "vmfix10 3: the hold's length is one named constant, the only one the hold reads")
    let up = H().shown("step3", at: 10)
    check(!up.clickCounts(card: "step3", at: 10.25) && !up.clickCounts(card: "step3", at: 10 + H.hold - 0.01) && up.clickCounts(card: "step3", at: 10 + H.hold),
          "vmfix10 3: a click on yes within the hold of the card being put up is ignored; after it, it counts")
    // cap7/F4-card3.jpg: the card came up while the notch was still resizing. Each move of the card (and so of its
    // footer's buttons) starts the hold again; it counts once the card has been still for the hold.
    var moving = up
    for frame in 0..<12 { moving = moving.framed(card: "step3", CGRect(x: 4, y: 60, width: 432, height: 140 + Double(frame) * 6), at: 10 + Double(frame) * 0.03) }
    check(!moving.clickCounts(card: "step3", at: 10.33 + H.hold - 0.01) && moving.clickCounts(card: "step3", at: 10.33 + H.hold),
          "vmfix10 3: a card that moved while it came up takes a press once it has been still for the hold (\(moving.readyAt ?? 0))")
    check(abs(up.remaining(at: 10.2) - (H.hold - 0.2)) < 0.0001 && up.remaining(at: 10 + H.hold + 1) == 0, "vmfix10 3: what is left of the hold, for its line")
    let card = vmfix10Source("Aris/private/Aris/Home/ArisConfirmCard.swift"), still = vmfix10Source("Aris/private/Aris/Home/ArisCardStill.swift")
    check(card.contains(".opacity(!ready ? Self.restOpacity : held ? Self.heldOpacity : 1)") && card.contains("static let heldOpacity: Double = 0.5")
          && card.contains("static let restOpacity: Double = 0.4") && card.contains(".overlay { if ready && held { ArisHoldSweep(duration: holdLeft) } }"),
          "vmfix10 3: a held yes is drawn unlike a disabled one, with its line (eighth VM run: at half strength, without its glass); a disabled one stays at rest")
    check(still.contains("struct ArisHoldSweep") && !still.contains("repeatForever") && !still.contains("autoreverses") && !still.contains("TimelineView"),
          "vmfix10 3: the hold's line fills once; nothing blinks or pulses")
}

// MARK: - 4: what stays after a replay's undo

private func vmfix10KeptTests() {
    let now = Date()
    func step(_ capability: String, _ arguments: [ArisKeyArgument], effect: ArisEffectClass? = .changeReversible, result: String = "{}", undo: ArisUndoRecipe? = nil) -> ArisRecordEntry {
        var entry = ArisRecordEntry.call(at: now, session: "teach-r2ko", task: nil, capability: capability, effect: effect ?? .changeReversible, provenance: .ownStep,
                                         decision: .ask, arguments: arguments, result: result, ok: true, undo: undo)
        if effect == nil { entry.effect = nil }
        return entry
    }
    let app = ArisKeyArgument(kind: .app, value: "TextEdit")
    let typed = ArisApps.TextUndo.replaced(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "", before: "Korean keep text", after: "바꾼 글", copy: "k1")
    // cap7/R2ko-undo-done.jpg: "전체 바꾸기" = TextEdit opened, Edit › Select All, the text replaced (undone).
    let replaceRun = [step("app.open", [app]), step("app.do", [app, ArisKeyArgument(kind: .command, value: "=Edit › Select All [cmd+a]")]),
                      step("app.type", [app, ArisKeyArgument(kind: .body, value: "바꾼 글")], effect: .changePermanent, undo: typed)]
    check(ArisRecordRoutes.kept(replaceRun) == nil, "vmfix10 4: opening the app and Select All change nothing that stays: the undo is whole")
    check(ArisRecordRoutes.kept([step("app.do", [app, ArisKeyArgument(kind: .command, value: "전체 선택")])]) == nil, "vmfix10 4: Korean 전체 선택 too")
    check(ArisRecordRoutes.kept([step("app.do", [app, ArisKeyArgument(kind: .command, value: "=File › New [cmd+n]")], result: #"{"now":"a new window “Untitled 2” opened"}"#)]) == "window",
          "vmfix10 4: a new document stays, and is said")
    check(ArisRecordRoutes.kept([step("app.click", [app, ArisKeyArgument(kind: .path, value: "/x")])]) == "other"
          && ArisRecordRoutes.kept([step("app.press", [app])]) == "other" && ArisRecordRoutes.kept([step("mail.send", [], effect: .outward)]) == "other",
          "vmfix10 4: a click, a key press, a sent message: each stays (anything not on the list of no-change steps)")
    check(ArisRecordRoutes.kept([step("app.do", [app, ArisKeyArgument(kind: .command, value: "Select All")], effect: .changePermanent)]) == "other"
          && ArisRecordRoutes.kept([step("app.do", [app, ArisKeyArgument(kind: .command, value: "Select All")], effect: nil)]) == "other",
          "vmfix10 4: the allowlist holds only for a step the gate rated a reversible change; a permanent one, or one with no class, stays")
    check(ArisRecordRoutes.kept([step("app.read", [app], effect: .observe)]) == nil, "vmfix10 4: a look changes nothing")
}

// MARK: - 5: the undo names what was undone

private func vmfix10UndoReplyTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-vmfix10-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let home = folder.resolvingSymlinksInPath().path
    defer { try? FileManager.default.removeItem(atPath: home) }
    let session = "teach-c3d4e5f6", now = Date()
    // cap7/J1-undo-done.jpg: "줄 추가" replayed (TextEdit opened, a line typed), then "되돌려": "Undid “TextEdit” (Typed into an app)."
    let typed = ArisApps.TextUndo.recipe(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "", before: "Existing line keep", after: "Existing line keep\nAdded line")
    let entries = [ArisRecordEntry.call(at: now.addingTimeInterval(-2), session: session, task: nil, capability: "app.open", effect: .changeReversible, provenance: .ownStep,
                                        decision: .runWithUndo(announce: false), arguments: [.init(kind: .app, value: "TextEdit")], result: "{}", ok: true, undo: nil),
                   ArisRecordEntry.call(at: now.addingTimeInterval(-1), session: session, task: nil, capability: "app.type", effect: .changeReversible, provenance: .content(ArisContentSource(kind: "app", source: "TextEdit")),
                                        decision: .runWithUndo(announce: false), arguments: [.init(kind: .app, value: "TextEdit")], result: "{}", ok: true, undo: typed)]
    for entry in entries { _ = ArisRecordJournal.append(entry, home: home) }
    ArisTeachRunNames.shared.note(session: session, name: "줄 추가")
    var hands = ArisUndoHands()
    hands.setText = { _, _, _ in }
    let answer = ArisRecordRoutes.undo(id: entries[1].id, unit: true, home: home, logLatest: nil, hands: hands)
    let reply = answer.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.body.utf8))) as? [String: Any] } ?? [:]
    check(answer?.status == 200 && reply["undid"] as? String == "typed\tTextEdit" && reply["lesson"] as? String == "줄 추가" && reply["kept"] == nil,
          "vmfix10 5: the helper says what came back and the lesson (\(reply))")
    guard case .done(let note) = ArisUndoSteps.outcome(status: 200, reply: reply) else { return check(false, "vmfix10 5: the app reads it as done") }
    let entrySummary = "앱에 입력: TextEdit"
    check(ArisUndoWords.doneReply(note, summary: entrySummary, korean: false) == "Removed the text I typed in TextEdit for “줄 추가”."
          && ArisUndoWords.doneReply(note, summary: entrySummary, korean: true) == "‘줄 추가’에서 TextEdit에 입력한 글을 지웠어요.",
          "vmfix10 5: the reply names what was undone and the lesson (\(ArisUndoWords.doneReply(note, summary: entrySummary, korean: false)))")
    // A replace's undo puts the erased text back; with a new document that stays, that is said too.
    let replaced = ArisUndoWords.note(reply: ["undid": "restored\tTextEdit", "kept": "window"]) ?? ""
    check(ArisUndoWords.doneReply(replaced, summary: entrySummary, korean: false) == "Put back the text I replaced in TextEdit. The new document stays open."
          && ArisUndoWords.doneReply(replaced, summary: entrySummary, korean: true) == "TextEdit에 바꿔 넣은 글을 원래 글로 되돌렸어요. 새 문서는 그대로 있어요.",
          "vmfix10 5: a replace's undo says the text that was there is back")
    // The older replies stand where nothing more is known: the kept lines, any other kind's own line.
    check(ArisUndoWords.doneReply("kept:window", summary: entrySummary, korean: true) == "입력한 글은 지웠어요. 새 문서는 그대로 있어요."
          && ArisUndoWords.doneReply("할 일 추가: 우유 — x", summary: "할 일 추가: 우유", korean: true) == "‘우유’ 할 일을 되돌렸어요."
          && ArisUndoWords.keptLine(ArisUndoWords.note(reply: ["undid": "typed\tTextEdit", "kept": "other"]) ?? "", korean: false) == "I undid what can be undone. The other steps stay as they are.",
          "vmfix10 5: a reply that names nothing is said as before")
    // What comes from outside is cleaned: an unknown kind is dropped, control characters go.
    let odd = ArisUndoWords.parse(ArisUndoWords.note(reply: ["undid": "launched\tRockets\ntyped\tText\u{202E}Edit"]) ?? "")
    check(odd?.undid == [ArisUndoWords.Undid(kind: "typed", app: "TextEdit")], "vmfix10 5: only the known kinds, cleaned (\(String(describing: odd)))")
    check(vmfix10Source("Aris/private/Aris/ArisController+Undo.swift").contains("reply = ArisUndoWords.doneReply(note, summary: entry.summary, korean: korean)"),
          "vmfix10 5: wiring: the undo's reply is made from the note")
    check(vmfix10Source("ArisAgent/Teach/ArisTeachTurn.swift").contains("ArisTeachRunNames.shared.note(session: \"teach-\" + run, name: procedure.name)")
          && vmfix10Source("ArisAgent/Teach/ArisTeachTurn.swift").contains("answered: answered, run: run, card: card"),
          "vmfix10 5: wiring: each replay's record session is named by its lesson")
}

// MARK: - 8: his app is back while a replay waits on a card

final class V10System: ArisAppsSystem {
    let editor = ArisAppsRunning(bundle: "com.apple.TextEdit", name: "TextEdit", pid: 701)
    let finder = ArisAppsRunning(bundle: "com.apple.finder", name: "Finder", pid: 501)
    let safari = ArisAppsRunning(bundle: "com.apple.Safari", name: "Safari", pid: 601)
    let aris = ArisAppsRunning(bundle: "com.lumenjsn.aris", name: "Aris", pid: 900)
    var front: Int32 = 501
    var lastOwner: Int32? = 501
    var activated: [Int32] = []
    /// The apps whose main window was raised, in order (vmfix11-tests).
    var raised: [Int32] = []
    func raiseMainWindow(pid: Int32) { raised.append(pid) }
    /// The windows on screen, front to back, and each batch of windows raised (vmfix12-tests).
    var order: [ArisAppsWindowPlace] = []
    var raisedWindows: [[ArisAppsWindowPlace]] = []
    /// What was activated or raised, in the order it happened.
    var moves: [String] = []
    func windowOrder() -> [ArisAppsWindowPlace] { order }
    func raise(_ windows: [ArisAppsWindowPlace]) { raisedWindows.append(windows); moves.append("raise") }
    var all: [ArisAppsRunning] { [editor, finder, safari, aris] }
    func installedApps() -> [ArisApps.AppRecord] { [.init(bundle: "com.apple.TextEdit", names: ["TextEdit"], path: "/System/Applications/TextEdit.app")] }
    func runningApps() -> [ArisAppsRunning] { all }
    func frontmost() -> ArisAppsRunning? { all.first { $0.pid == front } }
    func ownerFront() -> ArisAppsRunning? {
        if let now = frontmost(), now.pid != aris.pid { return now }
        return lastOwner.flatMap { pid in all.first { $0.pid == pid } }
    }
    func switchTo(_ pid: Int32) {
        front = pid
        if pid != aris.pid { lastOwner = pid }
    }
    func defaultBrowser() -> String? { "com.apple.Safari" }
    func open(_ request: ArisAppsOpenRequest) -> (ok: Bool, message: String) { (true, "opened") }
    func quit(pid: Int32) -> Bool { true }
    func hide(pid: Int32) -> Bool { true }
    func activate(pid: Int32) -> Bool { activated.append(pid); moves.append("activate \(pid)"); switchTo(pid); return true }
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

/// TextEdit's menus: Select All and Make Plain Text are enabled only while TextEdit is active (in front).
private final class V10AX: ArisAppsAccessibility {
    let system: V10System
    var pressed: [[String]] = []
    init(system: V10System) { self.system = system }
    private var active: Bool { system.front == system.editor.pid }
    func menuBar(pid: Int32) -> ArisApps.MenuBar? {
        ArisApps.MenuBar(menus: [
            ArisApps.MenuItem(title: "Edit", items: [ArisApps.MenuItem(title: "Select All", enabled: active, key: "A", modifiers: 0)]),
            ArisApps.MenuItem(title: "Format", items: [ArisApps.MenuItem(title: "Make Plain Text", enabled: active, key: "T", modifiers: 1)]),
        ])
    }
    func pressMenu(pid: Int32, path: [String]) -> (ok: Bool, message: String) {
        guard let item = menuBar(pid: pid)?.item(at: path) else { return (false, "no menu item") }
        guard item.enabled else { return (false, "“\(item.title)” is greyed out right now") }
        pressed.append(path)
        return (true, "pressed")
    }
    func setFullScreen(pid: Int32, window: Int, on: Bool) -> Bool { true }
    func focusedRole(pid: Int32) -> String? { "textArea" }
    func caretToEnd(pid: Int32, at point: (x: Double, y: Double)?) -> ArisApps.CaretEnd { .moved }
}

private final class V10Engine: ArisAppsEngine {
    func run(_ arguments: [String], background: Bool) -> ArisApps.JSON {
        guard arguments.prefix(2) == ["window", "list"] else { return .object(["success": .bool(true), "data": .object([:])]) }
        let window: ArisApps.JSON = .object(["window_id": .number(60), "window_title": .string("Untitled"), "is_frontmost": .bool(true),
                                             "bounds": .object(["x": .number(100), "y": .number(100), "width": .number(800), "height": .number(600)])])
        return .object(["success": .bool(true), "data": .object(["windows": .array([window])])])
    }
}

func v10Hands() -> (ArisAppsHands, V10System) {
    let system = V10System()
    let hands = ArisAppsHands(system: system, ax: V10AX(system: system), engine: V10Engine(), store: ArisAppsMemoryStore())
    hands.pollSeconds = 0.3
    hands.settleSeconds = 0.1
    return (hands, system)
}

private func vmfix10FrontWhileAskedTests() {
    let selectAll: ArisApps.JSON = .object(["app": .string("TextEdit"), "command": .string("=Edit › Select All [cmd+a]")])
    // notes7/W3-front-poll.txt: Finder in front, TextEdit brought forward for a step, then a step failed: TextEdit stayed
    // in front through the failure sentence and the whole go-on card (14 s or more).
    do {
        let (hands, system) = v10Hands()
        hands.beginFrontHold()
        _ = hands.call("app.do", selectAll)
        check(system.front == system.editor.pid, "vmfix10 8: (TextEdit came forward for the step that needed it)")
        system.switchTo(system.aris.pid)   // his click on the step's card
        hands.yieldFront()                 // the next card (a step's, or the go-on question) is up
        check(system.front == system.finder.pid && system.activated == [system.editor.pid, system.finder.pid],
              "vmfix10 8: while the replay waits on a card, Finder (his app) is back in front (\(system.activated))")
        // A later step that needs TextEdit in front brings it forward again; the run's end puts Finder back.
        _ = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Format › Make Plain Text")]))
        check(system.front == system.editor.pid, "vmfix10 8: a later step that needs its app in front brings it forward again")
        hands.endFrontHold()
        check(system.front == system.finder.pid && !system.activated.contains(system.aris.pid),
              "vmfix10 8: the run over, Finder is back, and Aris was never put in front (\(system.activated))")
    }
    // Nothing brought forward: a card's wait activates nothing.
    do {
        let (hands, system) = v10Hands()
        hands.beginFrontHold()
        hands.yieldFront()
        hands.endFrontHold()
        check(system.activated.isEmpty, "vmfix10 8: with no app brought forward, waiting on a card activates nothing")
    }
    // He switched apps himself: his choice stands, now and when the run ends.
    do {
        let (hands, system) = v10Hands()
        hands.beginFrontHold()
        _ = hands.call("app.do", selectAll)
        system.switchTo(system.safari.pid)
        hands.yieldFront()
        hands.endFrontHold()
        check(system.front == system.safari.pid && system.activated == [system.editor.pid], "vmfix10 8: an app he went to himself is left in front")
    }
    // Only Aris was ever in front before: nothing of his to put back, and never Aris.
    do {
        let (hands, system) = v10Hands()
        system.front = system.aris.pid
        system.lastOwner = nil
        hands.beginFrontHold()
        _ = hands.call("app.do", selectAll)
        hands.yieldFront()
        hands.endFrontHold()
        check(system.activated == [system.editor.pid], "vmfix10 8: with no app of his known, nothing is put back, and never Aris (\(system.activated))")
    }
    // Wiring: both kinds of card a replay waits on give the front back first.
    let turn = vmfix10Source("ArisAgent/Teach/ArisTeachTurn.swift")
    let stepCard = turn.range(of: "let card: ArisMindJudge.Card = { gateCard, answer in"), stepYield = turn.range(of: "hands.yieldFront()\n                let shown = ArisMCPCards.shared.put(ArisMCPCard(title: gateCard.title")
    // Ninth VM run, item 6: the front goes back before the failure is said, so the card follows the sentence at once.
    let goOnYield = turn.range(of: "hands.yieldFront()\n                // The step's tag is marked failed before the sentence")
    check(stepCard != nil && stepYield != nil && goOnYield != nil && stepCard!.upperBound < stepYield!.lowerBound,
          "vmfix10 8: wiring: a step's card and the go-on card each put his app back before they go up")
}
