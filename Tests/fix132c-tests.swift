// Tests for jv-fix132c: the sixteenth real-screen VM check of 1.3.2 (3eaabff7). The desktop calls are the ones
// recorded in notes16 (R1k, R1e2: "erase all and write X" done as `desktop set-value`; R2k: "이거 '체리'로 바꿔 줘" as a
// set-value of the whole document, on a ref from the turn before), run on desktop-v2-tests' rig (fake Peekaboo, recorded
// fixtures) with TextEdit's shape; the timer's and the board's hand-over (M1: "타이머를 걸지 못했어요" while it ran), and
// the context's latest turn (E7). Nothing touches a real app, the screen or ~/.config/aris. Called from main.swift.
import CoreGraphics
import Foundation

func runFix132cTests() {
    fix132cSetValueReplaceTests()
    fix132cSetValueGuardTests()
    fix132cSetValuePartialTests()
    fix132cSetValueOtherControlsTests()
    fix132cSetValueBatchTests()
    fix132cDropsMostTests()
    fix132cEarlierTurnRefTests()
    fix132cAckTests()
    fix132cLatestTurnTests()
}

private let f132cEdit = ArisDesktopTarget(name: "TextEdit", bundle: "com.apple.TextEdit", pid: 4242, known: true, never: false, browser: false, sending: false,
                                          appleSigned: true)
private let f132cWindow = ArisDesktopWindow(id: 9189, frame: CGRect(x: 80, y: 329, width: 1040, height: 720), title: "Untitled")
private let f132cDoc = "apple banana grape\nsecond line of text."

private func f132cRig() -> V2Rig {
    let rig = V2Rig()
    rig.apps.apps["textedit"] = f132cEdit
    rig.apps.apps["com.apple.textedit"] = f132cEdit
    rig.windows.byPid[4242] = [f132cWindow]
    return rig
}

/// see-chat as TextEdit's Untitled: its text view (elem_59, a text area as TextEdit's is) holds `value`, the caret at the end.
private func f132cLook(_ value: String, snapshot: String? = nil) -> Data {
    guard var object = (try? JSONSerialization.jsonObject(with: v2pb("see-chat"))) as? [String: Any], var data = object["data"] as? [String: Any] else { return Data() }
    data["application_name"] = "TextEdit"
    data["window_title"] = "Untitled"
    if let snapshot { data["snapshot_id"] = snapshot }
    data["focused_element"] = ["frame": [[461, 1015], [586, 24]], "processIdentifier": 4242, "role": "AXTextArea", "windowID": 9189]
    var list = data["ui_elements"] as? [[String: Any]] ?? []
    for index in list.indices where list[index]["id"] as? String == "elem_59" {
        list[index]["value"] = value
        list[index]["role"] = "textArea"
        list[index]["role_description"] = "text entry area"
        list[index]["label"] = "Untitled text"
        list[index]["description"] = "Untitled text"
        list[index]["selected_text_range"] = ["location": value.utf16.count, "length": 0]
    }
    data["ui_elements"] = list
    object["data"] = data
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
}

/// A live screen turn (as the VM's), cards answered yes (or `answer`); its ledger may be the conversation's from before.
private final class F132cTurn: ArisDesktopTurn {
    let brain: ArisBrain = .api
    let ledger: ArisComputerUseLedger
    var brainName: String { "api" }
    var handsFree = false
    var isTask = false
    var screen = true
    var relayed = false
    var request = ""
    var critical: Bool { true }
    var live: Bool { true }
    private let lock = NSLock()
    private var _cards: [ArisMCPCard] = []
    private var steps = 0
    var cards: [ArisMCPCard] { lock.withLock { _cards } }
    var taint: ArisTaint { .none }
    init(ledger: ArisComputerUseLedger) { self.ledger = ledger }
    func taint(forApp app: String) -> ArisTaint { .none }
    func markAppRead(_ app: String) {}
    func takeOutsideText() {}
    func ask(_ card: ArisMCPCard, answer done: @escaping (ArisMCPAnswer) -> Void) {
        lock.withLock { _cards.append(card) }
        done(.yes([:]))
    }
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { done(.ok) }
    func quiet(_ status: String) {}
    func audit(_ fields: [String: String]) {}
    func operating(_ target: ArisOperatingTarget) {}
    func desktopStep() -> Int { lock.withLock { steps += 1; return steps } }
    func noteDesktopAction(_ note: Result<ArisSavedStep, ArisSavedStepsRefusal>) {}
}

private func f132cTurn(_ request: String, ledger: ArisComputerUseLedger = ArisComputerUseLedger()) -> F132cTurn {
    let turn = F132cTurn(ledger: ledger)
    turn.request = request
    turn.ledger.startTurn()
    return turn
}

/// One desktop call, with the ledger kept as ArisDesktopRoutes keeps it for an action.
private func f132cRun(_ rig: V2Rig, _ words: [String], text: String? = nil, turn: F132cTurn) -> ArisMCPOutcome {
    let action = ArisDesktopHonesty.isAction(words)
    if action { turn.ledger.noteActionStarted() }
    let box = V2Box()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { rig.engine.handle(words, text: text, turn: turn) { box.set($0); done.signal() } }
    _ = done.wait(timeout: .now() + 60)
    let outcome = box.value ?? .failed("no answer")
    if action { turn.ledger.noteActionEnded(ok: outcome.status == 0) }
    return outcome
}

/// `desktop see --app TextEdit` on `look`: the text view's ref, as the VM's brain read it.
private func f132cSee(_ rig: V2Rig, _ look: Data, turn: F132cTurn) -> String {
    rig.queueData([("see", look)])
    let seen = f132cRun(rig, ["see", "--app", "TextEdit"], turn: turn)
    return rig.ref("Untitled text", in: seen.output) ?? "@none:e1"
}

private func f132cSet(_ rig: V2Rig, ref: String, _ text: String, turn: F132cTurn) -> ArisMCPOutcome {
    f132cRun(rig, ["set-value", ref, "--stdin"], text: text, turn: turn)
}

private func f132cCard(_ card: ArisMCPCard) -> String { card.title + "\n" + (card.full ?? card.detail) }

/// The undo folder for one test, put back after.
private func f132cWithUndo(_ body: () -> Void) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix132c-undo-\(UUID().uuidString)")
    let before = ArisDesktopUndoLog.folder, performer = ArisDesktopUndoLog.perform
    ArisDesktopUndoLog.folder = folder
    defer {
        ArisDesktopUndoLog.folder = before
        ArisDesktopUndoLog.perform = performer
        try? FileManager.default.removeItem(at: folder)
    }
    body()
}

// MARK: - A. "Erase all and write X" done as set-value is the replace card, held to the text, and undone by Aris

private func fix132cSetValueReplaceTests() {
    for (request, text, korean) in [("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘", "교체된 내용", true),
                                    ("Delete all the text in this document and write 'replaced content'", "replaced content", false)] {
        f132cWithUndo {
            let rig = f132cRig()
            let turn = f132cTurn(request)
            let ref = f132cSee(rig, f132cLook(f132cDoc), turn: turn)
            rig.queueData([("see", f132cLook(f132cDoc)), ("set-value", v2pb("setvalue")), ("see", f132cLook(text))])
            let set = f132cSet(rig, ref: ref, text, turn: turn)
            let shown = turn.cards.map(f132cCard)
            let lead = korean ? "TextEdit에서 글 바꾸기" : "Replace text in TextEdit"
            let warning = korean ? "⚠️ 이 창의 글을 모두 지우고 그 자리에 입력해요" : "⚠️ This erases all the text in this window and types in its place"
            let erased = korean ? "지워지는 글:\n" : "Text that is erased:\n"
            check(turn.cards.count == 1 && shown[0].hasPrefix(lead) && shown[0].contains(warning) && shown[0].contains(erased + f132cDoc) && shown[0].contains(text),
                  "fix132c A: a set-value over a field with text is the replace card with the ⚠️ warning and the text it erases (R1k/R1e2, \(korean): \(shown))")
            check(set.status == 0 && rig.calls.contains { $0.hasPrefix("set-value") }, "fix132c A: on its yes the value is set (\(set.output.prefix(160)), \(rig.calls))")
            let rows = ArisDesktopUndoLog.rows(today: false)
            check(rows.count == 1 && rows.first?["summary"] as? String == "글 바꿈: TextEdit" && rows.first?["undoable"] as? Bool == true,
                  "fix132c A: the set-value is kept for Aris's undo as a replace (R1ku: \"nothing to undo\"; \(rows))")
            nonisolated(unsafe) var restored: String?
            ArisDesktopUndoLog.perform = { _, _, text in restored = text }
            if let id = rows.first?["id"] as? String, let store = ArisDesktopUndoLog.store {
                let answer = ArisDesktopUndoLog.undo(id: id, store: store)
                check(answer?.status == 200 && restored == f132cDoc, "fix132c A: Aris's undo puts the old text back, whole (\(String(describing: answer)), \(restored ?? "nil"))")
            } else {
                check(false, "fix132c A: an undo entry and a store")
            }
        }
    }
}

// MARK: - A. What holds: a field that changed after the card stops the turn; an empty field is a plain set-value

private func fix132cSetValueGuardTests() {
    do {
        let rig = f132cRig()
        let turn = f132cTurn("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘")
        let ref = f132cSee(rig, f132cLook(f132cDoc), turn: turn)
        let changed = "Changed after the card appeared."
        rig.queueData([("see", f132cLook(changed)), ("set-value", v2pb("setvalue")), ("see", f132cLook("교체된 내용"))])
        let stopped = f132cSet(rig, ref: ref, "교체된 내용", turn: turn)
        check(stopped.status != 0 && stopped.output.contains("NOT DONE") && !rig.calls.contains { $0.hasPrefix("set-value") } && turn.ledger.fieldChangedThisTurn,
              "fix132c guard: a field that changed after the replace card sets nothing and stops the turn (\(stopped.output.prefix(200)), \(rig.calls))")
        rig.queueData([("see", f132cLook(changed))])
        let again = f132cSet(rig, ref: ref, "교체된 내용", turn: turn)
        check(again.status != 0 && turn.cards.count == 1 && !rig.calls.contains { $0.hasPrefix("set-value") },
              "fix132c guard: and nothing more is put on a card in that turn (\(again.output.prefix(160)))")
    }
    do {
        let rig = f132cRig()
        let turn = f132cTurn("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘")
        let ref = f132cSee(rig, f132cLook(""), turn: turn)
        rig.queueData([("see", f132cLook("")), ("set-value", v2pb("setvalue")), ("see", f132cLook("교체된 내용"))])
        let set = f132cSet(rig, ref: ref, "교체된 내용", turn: turn)
        let shown = turn.cards.map(f132cCard)
        check(set.status == 0 && turn.cards.count == 1 && shown[0].hasPrefix("TextEdit에서 값 넣기") && !shown[0].contains("지워지는 글") && !shown[0].contains("⚠️")
              && rig.calls.contains { $0.hasPrefix("set-value") },
              "fix132c guard: an empty field is a plain set-value, as before (\(shown), \(set.output.prefix(120)))")
    }
}

// MARK: - A/B. A part to change never becomes a whole-field set-value that drops most of the text

private func fix132cSetValuePartialTests() {
    for (request, text) in [("이거 '체리'로 바꿔 줘", "체리"), ("replace banana with cherry", "cherry"), ("이 문서에 '안녕'이라고 써 줘", "안녕")] {
        // R2k: the whole document set to "체리". Refused before any card, nothing set.
        let rig = f132cRig()
        let turn = f132cTurn(request)
        let ref = f132cSee(rig, f132cLook(f132cDoc), turn: turn)
        rig.queueData([("see", f132cLook(f132cDoc)), ("set-value", v2pb("setvalue")), ("see", f132cLook(text))])
        let refused = f132cSet(rig, ref: ref, text, turn: turn)
        check(refused.status != 0 && refused.output.contains("Select exactly the text to replace first") && refused.output.contains("ask the user")
              && turn.cards.isEmpty && !rig.calls.contains { $0.hasPrefix("set-value") },
              "fix132c part: “\(request)” as a set-value that drops most of the text is refused with no card (R2k: \(refused.output.prefix(200)), \(turn.cards.map(f132cCard)))")
    }
    // R2e: the whole document with only "banana" changed keeps most of it: the replace card, with the text it erases.
    let rig = f132cRig()
    let turn = f132cTurn("replace banana with cherry")
    let ref = f132cSee(rig, f132cLook(f132cDoc), turn: turn)
    let edited = "apple cherry grape\nsecond line of text."
    rig.queueData([("see", f132cLook(f132cDoc)), ("set-value", v2pb("setvalue")), ("see", f132cLook(edited))])
    let set = f132cSet(rig, ref: ref, edited, turn: turn)
    let shown = turn.cards.map(f132cCard)
    check(set.status == 0 && turn.cards.count == 1 && shown[0].hasPrefix("Replace text in TextEdit") && shown[0].contains("Text that is erased:\n" + f132cDoc)
          && shown[0].contains(edited),
          "fix132c part: a set-value that keeps most of the text is the replace card that shows both (R2e: \(shown), \(set.output.prefix(120)))")
    // An explicit erase-all may drop all of it (R1k), on that card.
    check(ArisDesktopBatch.asksToReplaceAll("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘") && !ArisDesktopBatch.asksToReplaceAll("이거 '체리'로 바꿔 줘"),
          "fix132c part: only erase-all words may drop the text (asksToReplaceAll)")
}

// MARK: - A. Other controls as today; a one-line field shows what it holds

private func fix132cSetValueOtherControlsTests() {
    // A checkbox (not text): its set-value card is as before, no erase lines.
    do {
        let rig = V2Rig()
        let turn = f132cTurn("Subscribe to newsletter 체크해 줘")
        rig.queue([("see", "see-form")])
        let seen = f132cRun(rig, ["see", "--app", "Aris Testbench"], turn: turn)
        let ref = rig.ref("Subscribe to newsletter", in: seen.output) ?? "@none:e1"
        rig.queue([("see", "see-form"), ("set-value", "setvalue"), ("see", "see-form")])
        _ = f132cSet(rig, ref: ref, "1", turn: turn)
        let shown = turn.cards.map(f132cCard)
        check(turn.cards.count == 1 && !shown[0].contains("⚠️") && !shown[0].contains("지워지는 글") && rig.calls.contains { $0.hasPrefix("set-value") },
              "fix132c other: a checkbox's set-value is as before (\(shown))")
    }
    // A one-line text field that holds a name: the replace card shows it, and the set-value is not refused.
    do {
        guard var object = (try? JSONSerialization.jsonObject(with: v2pb("see-form"))) as? [String: Any], var data = object["data"] as? [String: Any] else {
            return check(false, "fix132c other: the form fixture")
        }
        var list = data["ui_elements"] as? [[String: Any]] ?? []
        for index in list.indices where list[index]["id"] as? String == "elem_31" {
            list[index]["value"] = "John"
            list[index]["label"] = "Name"
        }
        data["ui_elements"] = list
        object["data"] = data
        let form = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        let rig = V2Rig()
        let turn = f132cTurn("change the name to the user")
        rig.queueData([("see", form)])
        let seen = f132cRun(rig, ["see", "--app", "Aris Testbench"], turn: turn)
        let ref = rig.ref("Name", in: seen.output) ?? "@none:e1"
        rig.queueData([("see", form), ("set-value", v2pb("setvalue")), ("see", form)])
        _ = f132cSet(rig, ref: ref, "Alex", turn: turn)
        let shown = turn.cards.map(f132cCard)
        check(turn.cards.count == 1 && shown[0].hasPrefix("Replace text in Aris Testbench") && shown[0].contains("Text that is erased:\nJohn")
              && rig.calls.contains { $0.hasPrefix("set-value") },
              "fix132c other: a one-line field's set-value shows what it erases, and goes on its yes (\(shown), \(rig.calls))")
    }
}

// MARK: - A. A batch's set-value over text goes as its own call

private func fix132cSetValueBatchTests() {
    let rig = f132cRig()
    let turn = f132cTurn("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘")
    let ref = f132cSee(rig, f132cLook(f132cDoc), turn: turn)
    rig.queueData([("see", f132cLook(f132cDoc)), ("set-value", v2pb("setvalue")), ("see", f132cLook("교체된 내용"))])
    let batch = f132cRun(rig, ["batch", "--app", "TextEdit", "--stdin"], text: "set-value \(ref) 교체된 내용", turn: turn)
    check(batch.status != 0 && batch.output.contains(ArisDesktopBatch.setValueOverTextLine) && turn.cards.isEmpty && !rig.calls.contains { $0.hasPrefix("set-value") },
          "fix132c batch: a batch's set-value over a field with text is refused, to go as its own call (\(batch.output.prefix(160)), \(turn.cards.map(f132cCard)))")
}

// MARK: - A. How much of the text a set-value keeps

private func fix132cDropsMostTests() {
    let doc = f132cDoc
    check(ArisDesktopErase.dropsMost(was: doc, now: "체리") && ArisDesktopErase.dropsMost(was: doc, now: "cherry") && ArisDesktopErase.dropsMost(was: doc, now: ""),
          "fix132c drops: a value that keeps none of the text drops most of it")
    check(!ArisDesktopErase.dropsMost(was: doc, now: "apple cherry grape\nsecond line of text.") && !ArisDesktopErase.dropsMost(was: doc, now: doc + " more")
          && !ArisDesktopErase.dropsMost(was: doc, now: "second line of text.\napple banana grape"),
          "fix132c drops: an edit of a word, an addition, or lines moved keep most of it")
    check(ArisDesktopErase.dropsMost(was: "첫 줄 원래 글\n둘째 줄 원래 글", now: "새 글 16") && !ArisDesktopErase.dropsMost(was: "회의록초안입니다", now: "회의록초안입니다요"),
          "fix132c drops: Korean, and text with no spaces, by what stays")
}

// MARK: - B. A ref from a look in an earlier turn: looked at again first

private func fix132cEarlierTurnRefTests() {
    let rig = f132cRig()
    let ledger = ArisComputerUseLedger()
    let first = f132cTurn("replace banana with cherry", ledger: ledger)
    let old = f132cSee(rig, f132cLook(f132cDoc, snapshot: "ps1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1"), turn: first)
    // R2k: the next turn's set-value on that ref, with no look of its own.
    let second = f132cTurn("이 문서 글 전부 지우고 '체리'라고 써 줘", ledger: ledger)
    let refused = f132cSet(rig, ref: old, "체리", turn: second)
    check(refused.status != 0 && refused.output.contains(ArisDesktopEngine.earlierTurnLine) && second.cards.isEmpty && !rig.calls.contains { $0.hasPrefix("set-value") },
          "fix132c ref: a ref from a look in an earlier turn does nothing and asks for a new look (R2k: \(refused.output.prefix(160)), \(second.cards.map(f132cCard)))")
    check(rig.engine.refusesBeforeCard(["set-value", old, "--stdin"], text: "체리", turn: second) == ArisDesktopEngine.earlierTurnLine,
          "fix132c ref: Core 2's trust gate hears the same refusal first, so it puts up no card for it")
    // After a look in this turn, its own ref works.
    let fresh = f132cSee(rig, f132cLook(f132cDoc, snapshot: "ps1_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2"), turn: second)
    rig.queueData([("see", f132cLook(f132cDoc)), ("set-value", v2pb("setvalue")), ("see", f132cLook("체리"))])
    let set = f132cSet(rig, ref: fresh, "체리", turn: second)
    check(fresh != old && set.status == 0 && second.cards.count == 1, "fix132c ref: a ref from this turn's look acts as before (\(set.output.prefix(160)))")
}

// MARK: - C. The timer and the board: taken by the app's answer, never by a file it can't remove

/// The app as a sandbox lets it be: it reads the file, can't remove it, and answers on the channel.
private final class F132cChannel: @unchecked Sendable {
    let lock = NSLock()
    var heard: [(name: String, object: String, run: () -> Void)] = []
    var posted: [String] = []
    var answers = true
    let file: URL
    init(file: URL) { self.file = file }

    var channel: ArisAppAck.Channel {
        ArisAppAck.Channel(listen: { [self] name, object, run in
            lock.withLock { heard.append((name, object, run)) }
            return NSObject()
        }, stop: { _ in }, post: { [self] name in
            lock.withLock { posted.append(name) }
            guard answers, let data = try? Data(contentsOf: file), let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = entry["id"] as? String else { return }
            let waiting = lock.withLock { heard.filter { $0.name == ArisAppAck.takenName(name) && $0.object == id } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { waiting.forEach { $0.run() } }
        })
    }
}

private func fix132cAckTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix132c-ack-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("timer.json")
    // M1: the app took it (the timer ran) but couldn't remove the file: it is taken, by the app's answer for that id.
    let app = F132cChannel(file: file)
    let taken = (try? ArisAppAck.handOver(["action": "start", "seconds": 300], to: file, nudge: "com.lumenjsn.aris.timer", timeout: 2, channel: app.channel)) ?? false
    check(taken && app.posted == ["com.lumenjsn.aris.timer"], "fix132c ack: a request the app answered is taken, though the file stayed (M1: \(app.posted))")
    check(!FileManager.default.fileExists(atPath: file.path), "fix132c ack: aris-tools removes the request itself once answered")
    // No app answers: not taken, within the wait, and the file is removed so it never starts later.
    let none = F132cChannel(file: file)
    none.answers = false
    let started = Date()
    let missed = (try? ArisAppAck.handOver(["action": "start", "seconds": 300], to: file, nudge: "com.lumenjsn.aris.timer", timeout: 0.3, channel: none.channel)) ?? true
    check(!missed && Date().timeIntervalSince(started) < 1.5 && !FileManager.default.fileExists(atPath: file.path),
          "fix132c ack: with no answer it is not taken, and the request doesn't stay behind")
    // The app's side: one answer per request id, on the name aris-tools listens for; a repeat or a bad id gets none.
    var said: [(String, String)] = []
    var timer = ArisAppTaken(nudge: "com.lumenjsn.aris.timer")
    let id = UUID().uuidString
    check(timer.take(["action": "stop", "id": id], post: { said.append(($0, $1)) }) && said.count == 1 && said[0].0 == ArisAppAck.takenName("com.lumenjsn.aris.timer") && said[0].1 == id,
          "fix132c ack: the app answers the request's id on <nudge>.taken (\(said))")
    check(!timer.take(["action": "stop", "id": id], post: { said.append(($0, $1)) }) && said.count == 1, "fix132c ack: the same request again is not acted on twice")
    check(timer.take(["action": "stop", "id": "not an id\n"], post: { said.append(($0, $1)) }) && said.count == 1, "fix132c ack: an id that isn't one gets no answer")
    // Every request that waited on the app removing its file uses the answer now; the app no longer tries to remove it.
    let source = { (path: String) in (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../" + path).standardized, encoding: .utf8)) ?? "" }
    let tools = source("ArisTools/ArisTimerCommand.swift") + source("ArisTools/ArisBoardCommand.swift") + source("ArisTools/ArisActivityCommand.swift")
    check(!tools.contains("ArisAppAck.taken(") && tools.contains("ArisAppAck.handOver(") && source("ArisTools/ArisBoardCommand.swift").contains("ArisAppAck.handOver("),
          "fix132c ack: the timer, its undo and the board are handed over and answered")
    let appSide = source("Aris/private/Aris/ArisTimerModel.swift") + source("Aris/private/Aris/ArisBoard.swift")
    check(!appSide.contains("removeItem") && appSide.components(separatedBy: ".take(").count == 3,
          "fix132c ack: the timer and the board answer each request, never removing a file the sandbox keeps read-only")
    let entitlements = source("Aris/Aris.entitlements")
    check(entitlements.contains("home-relative-path.read-only") && !entitlements.contains("home-relative-path.read-write"),
          "fix132c ack: the sandbox stays as it was (~/.config/aris read-only)")
}

// MARK: - D. "that" is the latest turn

private func fix132cLatestTurnTests() {
    let now = Date(timeIntervalSince1970: 1_795_670_000)
    let turns = [ArisContext.Turn(heard: "오늘 서울 날씨 어때?", reply: "서울은 지금 화씨 57도로 대체로 맑아요."),
                 ArisContext.Turn(heard: "방금 알려준 날씨를 '서울 날씨: 맑음'이라는 제목으로 할 일에 넣어 줘", reply: "할 일 목록에 '서울 날씨: 맑음'으로 넣어 뒀어요."),
                 ArisContext.Turn(heard: "What's the weather in Orlando right now?", reply: "Orlando is 31°F right now and overcast.")]
    let context = ArisContext.make(now: now, timeZone: TimeZone(identifier: "America/New_York")!, frontApp: nil, music: nil, events: [], recent: turns)
    check(context.contains("recent:\n- user: 오늘 서울 날씨 어때?") && context.contains("- user: What's the weather in Orlando right now?\n  you: Orlando is 31°F right now and overcast.\n" + ArisContext.latestNote),
          "fix132c latest: the recent turns say which is the latest, right under it (E7: \(context))")
    check(ArisContext.latestNote.contains("latest") && ArisContext.latestNote.contains("that"), "fix132c latest: “that” means the latest turn's answer unless an earlier one is named")
    check(ArisWhyMatch.lastHeard(in: context) == "What's the weather in Orlando right now?", "fix132c latest: the agent still reads the turn before from the context")
    let one = ArisContext.make(now: now, timeZone: .current, frontApp: nil, music: nil, events: [], recent: [])
    check(!one.contains(ArisContext.latestNote), "fix132c latest: no note with no turns")
}
