// Tests for jv-vmfix6, the fourth VM run (aris-vmcheck notes4/*, cap4/*): the parts of defects 1-9 that live in
// the helper and the app (the pure ones are in Tests/ArisCoreTests/ArisTeachVM4Tests).
// D1  a replace's card shows what it erases and its undo puts that text back (the erased text kept in the undo store);
// D2  the live observer reads a text's value before his keys (the app attached, a focus, his click), never walks a
//     menu bar on the main thread at a key, and tells a selection he typed over;
// D5  a taught menu step or press finds its item or control exactly, never a near match (app.do, app.click);
// D7  app.type's undo is made from what the field reads back (an empty field reads as none), Core 2's live parts start
//     when the switch is heard on (the undo had no performer), a run undone in part says what stays, and every reason
//     reaches the user in words;
// D8  the trust gate's replace card in English has no Korean of Aris's and no capability id;
// D9  a teach account's reason is never reworded as his own no ("찾지 않을게요").
// Called from main.swift; uses its check().
import Foundation

private let vmfix6Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func vmfix6Source(_ path: String) -> String { (try? String(contentsOf: vmfix6Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runVmfix6TeachTests() {
    vmfix6ObserverSourceTests()
    vmfix6AppTypeUndoTests()
    vmfix6ExactTests()
    vmfix6UndoRouteTests()
    vmfix6UndoWordsTests()
    vmfix6Core2StartTests()
    vmfix6ReplaceCardTests()
    vmfix6CancelLineTests()
}

// MARK: - D2: the observer

private func vmfix6ObserverSourceTests() {
    let live = vmfix6Source("ArisAgent/Teach/ArisTeachLiveObserver.swift")
    check(live.contains("if let focused = Self.element(Self.attribute(element, kAXFocusedUIElementAttribute)) { baseline(focused) }"),
          "vmfix6 D2: an app's focused text is read when it is attached, before any key of his")
    check(live.contains("baseline(clicked)") && live.contains("            baseline(element)\n            emit(ArisTeachEvent(.focused"),
          "vmfix6 D2: a text element's value is read at his click into it and at its focus")
    check(!live.contains("DispatchQueue.main.async { [weak self] in\n            guard let self, self.sink != nil else { return }\n            if let path = ArisTeachMenuKeys.command(for: keys, in: Self.menuItems(pid))")
          && live.contains("guard let items = menus.withLock({ $0[pid] }) else {") && live.contains("Self.menuQueue.async"),
          "vmfix6 D2: a shortcut is told from menus read off the main thread; no menu walk holds the main thread at his key")
    check(live.contains("kAXSelectedTextChangedNotification]") && live.contains("if over { changed.overSelection = true }"),
          "vmfix6 D1: a selection he types over is told with the change")
}

// MARK: - Fakes: TextEdit with one document and a Format menu

private final class V6System: ArisAppsSystem {
    let editor = ArisAppsRunning(bundle: "com.apple.TextEdit", name: "TextEdit", pid: 701)
    func installedApps() -> [ArisApps.AppRecord] { [.init(bundle: "com.apple.TextEdit", names: ["TextEdit"], path: "/System/Applications/TextEdit.app")] }
    func runningApps() -> [ArisAppsRunning] { [editor] }
    func frontmost() -> ArisAppsRunning? { nil }
    func defaultBrowser() -> String? { "com.apple.Safari" }
    func open(_ request: ArisAppsOpenRequest) -> (ok: Bool, message: String) { (true, "opened") }
    func quit(pid: Int32) -> Bool { true }
    func hide(pid: Int32) -> Bool { true }
    func activate(pid: Int32) -> Bool { true }
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

private final class V6AX: ArisAppsAccessibility {
    var pressed: [[String]] = []
    let bar = ArisApps.MenuBar(menus: [ArisApps.MenuItem(title: "Format", items: [ArisApps.MenuItem(title: "Wrap to Window"), ArisApps.MenuItem(title: "Make Plain Text", key: "T", modifiers: 1)])])
    func menuBar(pid: Int32) -> ArisApps.MenuBar? { bar }
    func pressMenu(pid: Int32, path: [String]) -> (ok: Bool, message: String) { pressed.append(path); return (true, "pressed") }
    func setFullScreen(pid: Int32, window: Int, on: Bool) -> Bool { true }
    func focusedRole(pid: Int32) -> String? { "textArea" }
    func caretToEnd(pid: Int32, at point: (x: Double, y: Double)?) -> ArisApps.CaretEnd { .moved }
}

/// The document's text as the engine reads it; `correct` is what TextEdit does to typed text (its capitals).
private final class V6Engine: ArisAppsEngine {
    var calls: [[String]] = []
    var text: String?
    var correct: (String) -> String = { $0 }
    var buttons = ["Wrap to Window"]
    func run(_ arguments: [String], background: Bool) -> ArisApps.JSON {
        calls.append(arguments)
        switch (arguments.first ?? "", arguments.dropFirst().first ?? "") {
        case ("window", "list"):
            return .object(["success": .bool(true), "data": .object(["windows": .array([.object([
                "window_id": .number(60), "window_title": .string("Untitled"), "is_frontmost": .bool(true),
                "bounds": .object(["x": .number(100), "y": .number(100), "width": .number(800), "height": .number(600)])])])])])
        case ("see", _):
            var area: [String: ArisApps.JSON] = ["id": .string("elem_1"), "role": .string("textArea"), "label": .string("First Text View"),
                                                 "bounds": .object(["x": .number(100), "y": .number(150), "width": .number(800), "height": .number(400)])]
            if let text, !text.isEmpty { area["value"] = .string(text) }
            let pressable = buttons.enumerated().map { index, label -> ArisApps.JSON in
                .object(["id": .string("elem_\(index + 2)"), "role": .string("button"), "label": .string(label), "is_actionable": .bool(true)])
            }
            return .object(["success": .bool(true), "data": .object(["snapshot_id": .string("ps_v6"), "window_title": .string("Untitled"),
                                                                     "ui_elements": .array([.object(area)] + pressable)])])
        case ("type", _):
            text = (text ?? "") + correct(arguments[2])
            return .object(["success": .bool(true), "data": .object(["delivery": .string("typed")])])
        case ("set-value", _):
            text = arguments[6]
            return .object(["success": .bool(true), "data": .object([:])])
        default:
            return .object(["success": .bool(true), "data": .object([:])])
        }
    }
}

private func v6Hands(text: String?) -> (ArisAppsHands, V6AX, V6Engine) {
    let ax = V6AX(), engine = V6Engine()
    engine.text = text
    let hands = ArisAppsHands(system: V6System(), ax: ax, engine: engine, store: ArisAppsMemoryStore())
    hands.pollSeconds = 0
    return (hands, ax, engine)
}

private func v6Mark(_ outcome: ArisApps.Outcome) -> ArisApps.TextUndo.Mark? {
    guard case .textInserted(_, let element, _)? = outcome.undo else { return nil }
    return ArisApps.TextUndo.mark(element)
}

// MARK: - D7 (and D1's undo): app.type's undo from what the field reads back

private func vmfix6AppTypeUndoTests() {
    // "메모 쓰기" into a new, empty document: TextEdit capitalised what was typed. The undo was never made.
    do {
        let (hands, _, engine) = v6Hands(text: nil)
        engine.correct = { $0.prefix(1).uppercased() + $0.dropFirst() }
        let done = hands.call("app.type", .object(["app": .string("TextEdit"), "text": .string("added line"), "target": .string("First Text View 칸"), "at": .string("end")]))
        let mark = v6Mark(done)
        check(done.ok && done.verified && mark?.inserted == "Added line" && mark?.location == 0,
              "vmfix6 D7: typing into an empty document has an undo, made from what it reads back (\(String(describing: mark)))")
        check(mark.map { ArisApps.TextUndo.find(in: "Added line", mark: $0) } == .range(NSRange(location: 0, length: 10)),
              "vmfix6 D7: the undo finds exactly what was typed")
    }
    // "줄 덧붙이기": Return then the line, after what was there.
    do {
        let (hands, _, _) = v6Hands(text: "Existing line keep")
        let done = hands.call("app.type", .object(["app": .string("TextEdit"), "text": .string("\nSecond line"), "target": .string("First Text View 칸"), "at": .string("end")]))
        let mark = v6Mark(done)
        check(mark?.inserted == "\nSecond line" && mark?.location == 18 && mark?.beforeLength == 18,
              "vmfix6 D7: text added after what was there keeps its place and the field's value after")
    }
    // A replace keeps what it erases; without a place to keep it, it says so.
    do {
        let (hands, _, _) = v6Hands(text: "Existing line keep")
        var kept: [String] = []
        hands.keepText = { text in kept.append(text); return "11111111-2222-3333-4444-555555555555" }
        let done = hands.call("app.type", .object(["app": .string("TextEdit"), "text": .string("Added line"), "target": .string("First Text View 칸"), "replace": .bool(true)]))
        check(kept == ["Existing line keep"] && v6Mark(done)?.erased == "11111111-2222-3333-4444-555555555555",
              "vmfix6 D1: a replace keeps what it erased, and its undo names that copy")
        let (bare, _, _) = v6Hands(text: "Existing line keep")
        let lost = bare.call("app.type", .object(["app": .string("TextEdit"), "text": .string("Added line"), "target": .string("First Text View 칸"), "replace": .bool(true)]))
        check(lost.undo == nil && lost.now.contains("couldn't be kept"), "vmfix6 D1: a replace whose erased text couldn't be kept says it can't be undone")
    }
    // The card's read of what a replace would erase opens, clicks and types nothing.
    do {
        let (hands, _, engine) = v6Hands(text: "Existing line keep")
        check(hands.peekField(app: "TextEdit", target: "First Text View 칸") == "Existing line keep"
              && !engine.calls.contains { ["click", "type", "set-value", "press"].contains($0.first ?? "") },
              "vmfix6 D1: what a replace would erase is read for its card, nothing else is done")
    }
    // The undo store keeps a text verified, and the performer puts it back.
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-vmfix6-store-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ArisUndoStore(folder: folder)
        guard let copy = store.keep(data: Data("Existing line keep".utf8)),
              let recipe = ArisApps.TextUndo.replaced(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "", before: "Existing line keep",
                                                      after: "Added line", copy: copy) else {
            return check(false, "vmfix6 D1: the erased text is kept")
        }
        var restored: [String] = []
        var hands = ArisUndoHands()
        hands.setText = { _, _, value in restored.append(value) }
        let line = try? ArisUndoRecipes.perform(recipe, home: "/Users/nobody", store: store, hands: hands)
        check(restored == ["Existing line keep"] && store.copy(copy) == nil && line?.contains("되살렸어요") == true,
              "vmfix6 D1: \"되돌려\" puts the erased text back from its kept copy")
    }
}

// MARK: - D5: exact items and controls

private func vmfix6ExactTests() {
    let (hands, ax, engine) = v6Hands(text: "Lesson line one")
    let menu = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Format › Wrap to Page")]))
    check(!menu.ok && ax.pressed.isEmpty && menu.did.contains("isn't there now") && menu.did.contains("‘Wrap to Window’ instead"),
          "vmfix6 D5: a taught menu step whose item is gone presses nothing and says what is there instead (\(menu.did))")
    ax.pressed = []
    let wrongKey = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Format › Make Plain Text [cmd+t]")]))
    check(!wrongKey.ok && ax.pressed.isEmpty, "vmfix6 D5: an item whose key equivalent changed isn't pressed")
    let exact = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Format › Make Plain Text [cmd+shift+t]")]))
    check(exact.ok && ax.pressed == [["Format", "Make Plain Text"]], "vmfix6 D5: the exact item with its key is pressed")
    let button = hands.call("app.click", .object(["app": .string("TextEdit"), "target": .string("=Wrap to Page")]))
    check(!button.ok && !engine.calls.contains { $0.first == "click" } && button.did.contains("‘Wrap to Window’ instead"),
          "vmfix6 D5: a taught press whose control's words changed presses nothing (\(button.did))")
    let english = ArisTeachCopy.reason(button.did, english: true) ?? ""
    check(english.contains("Wrap to Window") && !english.contains("TextEdit shows"), "vmfix6 D5: the account says it in its own words (\(english))")
    // Security review: an `exact` or `key` beside the rated value (a model's call, an MCP call) is refused, nothing pressed.
    ax.pressed = []
    let calls = engine.calls.count
    let smuggled = hands.call("app.click", .object(["app": .string("TextEdit"), "target": .string("Wrap to Window"), "exact": .string("Pay now")]))
    let smuggledSelect = hands.call("app.select", .object(["app": .string("TextEdit"), "target": .string("Wrap to Window"), "exact": .string("Pay now")]))
    let smuggledMenu = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("Format › Wrap to Window"), "exact": .bool(true),
                                                     "key": .string("cmd+t")]))
    check(!smuggled.ok && !smuggledSelect.ok && !smuggledMenu.ok && ax.pressed.isEmpty && !engine.calls.dropFirst(calls).contains { $0.first == "click" },
          "vmfix6 D5 security: a call carrying exact or key beside its target is refused and presses nothing")
    // The mark names what is pressed: the target the gate rated, exactly.
    engine.buttons = ["Cancel", "Pay now"]
    let marked = hands.call("app.click", .object(["app": .string("TextEdit"), "target": .string("=Cancel")]))
    check(marked.ok && marked.did.contains("Cancel") && !marked.did.contains("Pay now"), "vmfix6 D5 security: a marked target presses exactly that control (\(marked.did))")
}

// MARK: - D7: the run undone in part, through the record

private func vmfix6UndoRouteTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-vmfix6-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let home = folder.resolvingSymlinksInPath().path
    defer { try? FileManager.default.removeItem(atPath: home) }
    let session = "teach-b2c3d4e5", now = Date()
    func step(_ capability: String, _ seconds: Double, result: String, undo: ArisUndoRecipe?) -> ArisRecordEntry {
        ArisRecordEntry.call(at: now.addingTimeInterval(seconds), session: session, task: nil, capability: capability, effect: .changeReversible,
                             provenance: .ownStep, decision: .runWithUndo(announce: false), arguments: [.init(kind: .app, value: "TextEdit")],
                             result: result, ok: true, undo: undo)
    }
    // "메모 쓰기" replayed: TextEdit opened, File › New, the line typed.
    let typed = ArisApps.TextUndo.recipe(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "", before: "", after: "Lesson line one")
    let entries = [step("app.open", -3, result: #"{"did":"opened TextEdit (in the background)"}"#, undo: nil),
                   step("app.do", -2, result: #"{"channel":"menu","did":"pressed File › New in TextEdit","now":"a new window “Untitled 13” opened"}"#, undo: nil),
                   step("app.type", -1, result: #"{"did":"typed 15 characters"}"#, undo: typed)]
    for entry in entries { _ = ArisRecordJournal.append(entry, home: home) }
    var hands = ArisUndoHands()
    hands.setText = { _, _, _ in }
    let answer = ArisRecordRoutes.undo(id: entries[2].id, unit: true, home: home, logLatest: nil, hands: hands)
    let reply = answer.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.body.utf8))) as? [String: Any] } ?? [:]
    check(answer?.status == 200 && reply["kept"] as? String == "window", "vmfix6 D7: a run with a new document is undone in part, and the reply says the document stays")
    let outcome = ArisUndoSteps.outcome(status: 200, reply: reply)
    guard case .done(let note) = outcome else { return check(false, "vmfix6 D7: the app reads it as done") }
    check(ArisUndoWords.keptLine(note, korean: true) == "입력한 글은 지웠어요. 새 문서는 그대로 있어요."
          && ArisUndoWords.keptLine(note, korean: false) == "I removed the text I typed. The new document stays open.",
          "vmfix6 D7: what was undone and what stays, in the UI's language")
    check(ArisUndoWords.keptLine("할 일 추가: 우유", korean: true) == nil, "vmfix6 D7: any other undo keeps its own line")
    check(ArisRecordRoutes.kept([entries[0]]) == nil, "vmfix6 D7: opening an app is nothing that stays")
}

// MARK: - D7: every reason in words

private func vmfix6UndoWordsTests() {
    let reasons = [
        "couldn't undo \"앱에 입력: TextEdit\": undoing TextEdit isn't available in this helper yet",
        "couldn't undo \"앱에 입력: TextEdit\": TextEdit's text was edited after Aris typed into it (or its window is closed), so it was left as it is",
        "couldn't undo \"앱에 입력: TextEdit\": the text Aris typed is already gone from TextEdit",
        "couldn't undo \"앱에 입력: TextEdit\": TextEdit isn't open any more, so its text was left as it is",
        "couldn't undo \"앱에 입력: TextEdit\": TextEdit didn't let Aris remove the text it typed",
        "couldn't undo \"앱에 입력: TextEdit\": the kept copy of what TextEdit's text held is gone",
    ]
    let generic = ArisUndoWords.failure("", korean: true)
    for reason in reasons {
        let korean = ArisUndoWords.failure(reason, korean: true), english = ArisUndoWords.failure(reason, korean: false)
        check(korean != generic && korean.replacingOccurrences(of: "Aris", with: "").range(of: "[A-Za-z]{3,}", options: .regularExpression) == nil,
              "vmfix6 D7: the reason reaches the user in Korean words (\(korean))")
        check(english != ArisUndoWords.failure("", korean: false) && !ArisCardEnglish.hasHangul(english), "vmfix6 D7: and in English (\(english))")
    }
}

// MARK: - D7: Core 2's live parts start when the switch is heard

private func vmfix6Core2StartTests() {
    var started = 0
    let saved = ArisSwitchEffects.core2On
    defer { ArisSwitchEffects.core2On = saved }
    ArisSwitchEffects.core2On = { started += 1 }
    let switches = ArisHelperSwitches()
    ArisSwitchEffects.take([ArisSwitchSet.field: [ArisExperimentSwitch.core2.rawValue: true]], fromApp: true, switches: switches, retire: { _ in })
    check(started == 1 && switches.isOn(.core2), "vmfix6 D7: Core 2's live parts start when the app turns its switch on")
    ArisSwitchEffects.take([ArisSwitchSet.field: [ArisExperimentSwitch.core2.rawValue: true, ArisExperimentSwitch.teach.rawValue: true]], fromApp: true,
                           switches: switches, retire: { _ in })
    check(started == 1, "vmfix6 D7: and only when it turns on")
    let trust = vmfix6Source("ArisAgent/Trust/ArisCore2Trust.swift")
    check(trust.contains("ArisSwitchEffects.core2On = { startLive(home: home) }") && trust.contains("ArisMindLive.start()"),
          "vmfix6 D7: the undo performers are installed when Core 2 is turned on, not only at launch")
    check(vmfix6Source("ArisAgent/Mind/ArisMindLive.swift").contains("ArisTrustGate.peekReplaced = { app, target in"),
          "vmfix6 D1: the replace card reads what it would erase")
}

// MARK: - D1, D8: the replace card in English

private func vmfix6ReplaceCardTests() {
    var facts = ArisCallFacts(capability: "app.type", arguments: [.init(kind: .app, value: "TextEdit"), .init(kind: .body, value: "Added line")])
    facts.erases = ArisErasedText(text: "Existing line keep", keepable: true)
    let item = ArisAskItem(call: "c1", facts: facts, effect: .changePermanent, decision: .ask,
                           provenance: .content(ArisContentSource(kind: "app", source: "TextEdit · 배운 단계")))
    let card = ArisAskPlan.card([item], id: "t1", intent: "i", countdown: false, home: "/Users/user")
    let title = ArisCardEnglish.title(card.title)
    let detail = ArisCardEnglish.detail(card.detail, title: card.title), full = ArisCardEnglish.detail(card.full ?? "", title: card.title)
    // The user's own words (the text typed, the text erased) stay as they are; nothing else of Aris's is Korean.
    let ours = [title, detail, full].joined(separator: "\n").replacingOccurrences(of: "「Existing line keep」", with: "")
    check(title == "Replace text · TextEdit" && !ArisCardEnglish.hasHangul(ours), "vmfix6 D8: the replace card in English is English (\(title) / \(detail) / \(full))")
    check(!full.contains("[app.type]") && full.contains("App: TextEdit") && full.contains("Text: Added line"),
          "vmfix6 D8: the card's rows are labelled, never a capability's id (\(full))")
    check(detail.contains("Erases (18 characters, 1 line):") && detail.contains("say “undo” and I'll put it back"),
          "vmfix6 D1: the card says what it erases and that it can be put back (\(detail))")
}

// MARK: - D9: the cancel line after a failed step

private func vmfix6CancelLineTests() {
    let procedure = ArisTeachProcedure(name: "자 숨기기", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit"),
                                                             ArisTeachStep(action: .click, app: "TextEdit", bundle: "com.apple.TextEdit", target: "Format", label: "Format")],
                                       parameters: [], created: Date())
    let account = ArisTeachCopy.account(procedure, outcome: .stopped(at: 1, end: .failed("nothing called ‘Format’ in TextEdit’s window"), done: 1), english: false)
    let said = ArisCardWait.usersNoWording(account, korean: true)
    check(said == account && account.contains("찾을 수 없었어요") && !said.contains("않을게요"),
          "vmfix6 D9: a step that couldn't be found is said as such, even after his no on the go-on card (\(said))")
}
