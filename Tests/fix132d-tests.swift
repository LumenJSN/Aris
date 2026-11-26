// Tests for jv-fix132d: the seventeenth real-screen VM check of 1.3.2 (70b725d5). R1k: "이 문서 글 전부 지우고
// '교체된 내용'이라고 써 줘" was approved, the step paused 142 s on macOS's "Keystroke Receiving" prompt (asked by Aris
// itself at launch, behind the resumed guide), resumed with System Settings in front, the background cmd+a didn't take,
// and the new text went in after the old, told as done and kept as an insertion. Also M2u (the timer's undo said "Timer:
// 5"), R1s (`aris-tools set-value` without `desktop` became a "Mac action" card) and M2 (a timer reply promised a label).
// The same rule for an erase of everything in one keypress (`cmd+a delete`): the delete only over all of it selected,
// the field empty after it, else put back and NOT ERASED.
// The desktop calls run on desktop-v2-tests' rig (fake Peekaboo, recorded fixtures) with TextEdit's shape; nothing touches
// a real app, the screen or ~/.config/aris. Called from main.swift; uses its check().
import CoreGraphics
import Foundation

func runFix132dTests() {
    fix132dPureTests()
    fix132dSelectAllMissedTests()
    fix132dSelectAllNeverTests()
    fix132dAppendTakenBackTests()
    fix132dAppendLeftTests()
    fix132dPauseResumeTests()
    fix132dEraseTests()
    fix132dErasePauseTests()
    fix132dForwardCardTests()
    fix132dPauseLineTests()
    fix132dListenAskTests()
    fix132dTimerWordsTests()
    fix132dDesktopVerbTests()
    fix132dTimerLabelTests()
}

private let f132dEdit = ArisDesktopTarget(name: "TextEdit", bundle: "com.apple.TextEdit", pid: 4242, known: true, never: false, browser: false, sending: false,
                                          appleSigned: true)
private let f132dWindow = ArisDesktopWindow(id: 9189, frame: CGRect(x: 80, y: 329, width: 1040, height: 720), title: "Untitled")
/// R1k's document (24 UTF-16 units) and the text that was to replace it.
private let f132dDoc = "사과 바나나 포도\n두 번째 줄 텍스트입니다."
private let f132dNew = "교체된 내용"
private let f132dRequest = "이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘"

private func f132dRig(lock: ArisDesktopLock? = nil, pause: ArisDesktopPause.Policy? = nil) -> V2Rig {
    let rig = V2Rig(lock: lock, pause: pause)
    rig.apps.apps["textedit"] = f132dEdit
    rig.apps.apps["com.apple.textedit"] = f132dEdit
    rig.windows.byPid[4242] = [f132dWindow]
    return rig
}

/// see-chat as TextEdit's Untitled: its text view (elem_59) holds `value` with `selection` (UTF-16 location, length)
/// selected (nil: the field doesn't tell its selection), the keyboard focus on it.
private func f132dLook(_ value: String, selection: (Int, Int)?) -> Data {
    guard var object = (try? JSONSerialization.jsonObject(with: v2pb("see-chat"))) as? [String: Any], var data = object["data"] as? [String: Any] else { return Data() }
    data["application_name"] = "TextEdit"
    data["window_title"] = "Untitled"
    data["focused_element"] = ["frame": [[461, 1015], [586, 24]], "processIdentifier": 4242, "role": "AXTextField", "windowID": 9189]
    var list = data["ui_elements"] as? [[String: Any]] ?? []
    for index in list.indices where list[index]["id"] as? String == "elem_59" {
        list[index]["value"] = value
        list[index]["label"] = "Untitled text"
        list[index]["description"] = "Untitled text"
        if let selection { list[index]["selected_text_range"] = ["location": selection.0, "length": selection.1] } else { list[index]["selected_text_range"] = nil }
    }
    data["ui_elements"] = list
    object["data"] = data
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
}

private let f132dAll = f132dDoc.utf16.count
/// The document with the caret at its end (no selection), as R1k's was after the background cmd+a.
private var f132dCaretEnd: Data { f132dLook(f132dDoc, selection: (f132dAll, 0)) }
/// All of it selected.
private var f132dSelected: Data { f132dLook(f132dDoc, selection: (0, f132dAll)) }

/// A live screen turn as the VM's, cards answered yes; the notch's lines kept.
private final class F132dTurn: ArisDesktopTurn {
    let brain: ArisBrain = .api
    let ledger = ArisComputerUseLedger()
    var brainName: String { "api" }
    var handsFree = false
    var isTask = false
    var screen = true
    var relayed = false
    var request = ""
    var critical: Bool { true }
    var live: Bool { true }
    /// How every card is answered (yes unless a test says otherwise).
    var answer: ArisMCPAnswer = .yes([:])
    private let lock = NSLock()
    private var _cards: [ArisMCPCard] = []
    private var _quiet: [String] = []
    private var steps = 0
    var cards: [ArisMCPCard] { lock.withLock { _cards } }
    var quiet: [String] { lock.withLock { _quiet } }
    var taint: ArisTaint { .none }
    func taint(forApp app: String) -> ArisTaint { .none }
    func markAppRead(_ app: String) {}
    func takeOutsideText() {}
    func ask(_ card: ArisMCPCard, answer done: @escaping (ArisMCPAnswer) -> Void) {
        lock.withLock { _cards.append(card) }
        done(answer)
    }
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { done(.ok) }
    func quiet(_ status: String) { lock.withLock { _quiet.append(status) } }
    func audit(_ fields: [String: String]) {}
    func operating(_ target: ArisOperatingTarget) {}
    func desktopStep() -> Int { lock.withLock { steps += 1; return steps } }
    func noteDesktopAction(_ note: Result<ArisSavedStep, ArisSavedStepsRefusal>) {}
}

private func f132dTurn(_ request: String = f132dRequest) -> F132dTurn {
    let turn = F132dTurn()
    turn.request = request
    turn.ledger.startTurn()
    return turn
}

private func f132dRun(_ rig: V2Rig, _ words: [String], text: String? = nil, turn: ArisDesktopTurn) -> ArisMCPOutcome {
    let box = V2Box()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { rig.engine.handle(words, text: text, turn: turn) { box.set($0); done.signal() } }
    _ = done.wait(timeout: .now() + 60)
    return box.value ?? .failed("no answer")
}

/// R1k's two calls: `desktop press cmd+a --app TextEdit` (held back for the replace card), then `aris-tools type
/// '교체된 내용' --app TextEdit --title Untitled`, with `queue` for the type (after its two looks).
private func f132dReplace(_ rig: V2Rig, turn: F132dTurn, then queue: [(String, Data)]) -> ArisMCPOutcome {
    rig.queueData([("see", f132dLook(f132dDoc, selection: (0, 0)))])
    _ = f132dRun(rig, ["press", "cmd+a", "--app", "TextEdit", "--title", "Untitled"], turn: turn)
    rig.queueData([("see", f132dCaretEnd), ("see", f132dCaretEnd)] + queue)
    guard case .success(let call) = ArisTypeRequest.call([f132dNew, "--app", "TextEdit", "--title", "Untitled"], keyboardApp: nil) else { return .failed("the call") }
    return f132dRun(rig, call.words, text: call.text, turn: turn)
}

/// The undo folder for one test, with Aris's undo performer stubbed; both put back after.
private func f132dWithUndo(perform: @escaping (String, String, String) throws -> Void, _ body: () -> Void) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix132d-undo-\(UUID().uuidString)")
    let before = ArisDesktopUndoLog.folder, performer = ArisDesktopUndoLog.perform
    ArisDesktopUndoLog.folder = folder
    ArisDesktopUndoLog.perform = perform
    defer {
        ArisDesktopUndoLog.folder = before
        ArisDesktopUndoLog.perform = performer
        try? FileManager.default.removeItem(at: folder)
    }
    body()
}

/// What Aris's undo was asked to take out (the mark's inserted text), thread-safe.
private final class F132dTaken: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func add(_ element: String) { lock.withLock { stored.append(ArisApps.TextUndo.mark(element)?.inserted ?? "?") } }
    var all: [String] { lock.withLock { stored } }
}

private func f132dTyped(_ rig: V2Rig) -> [String] { rig.calls.filter { $0.hasPrefix("type") } }
private func f132dSelects(_ rig: V2Rig) -> [String] { rig.calls.filter { $0.hasPrefix("press cmd+a") } }

// MARK: - The pure checks

private func fix132dPureTests() {
    typealias E = ArisDesktopErase
    let field = { (value: String, range: ArisTextRange?, capped: Bool) -> ArisDesktopElement in
        var element = ArisDesktopElement(id: "elem_59", role: "textArea", label: "Untitled text")
        element.rawValue = value
        element.value = value
        element.rawCapped = capped
        element.selectedRange = range
        return element
    }
    check(E.coversAll(field(f132dDoc, ArisTextRange(location: 0, length: f132dAll), false)) == true
          && E.coversAll(field(f132dDoc, ArisTextRange(location: f132dAll, length: 0), false)) == false
          && E.coversAll(field(f132dDoc, ArisTextRange(location: 0, length: 5), false)) == false
          && E.coversAll(field(f132dDoc, ArisTextRange(location: 3, length: f132dAll - 3), false)) == false
          && E.coversAll(field(f132dDoc, nil, false)) == nil && E.coversAll(field(f132dDoc, ArisTextRange(location: 0, length: 9), true)) == nil,
          "fix132d pure: all of it selected is told from Accessibility's range (the caret at the end, a part, or nothing known)")
    check(E.replacedWhole(f132dNew, with: f132dNew) && E.replacedWhole(f132dNew + "\n", with: f132dNew)
          && E.replacedWhole("e\u{301}", with: "\u{e9}") && !E.replacedWhole(f132dDoc + f132dNew, with: f132dNew) && !E.replacedWhole("", with: f132dNew),
          "fix132d pure: replaced means the field holds just the new text (R1k's append is not)")
    let restored = E.notReplacedLine(restored: true, why: nil), left = E.notReplacedLine(restored: false, why: "TextEdit didn't let Aris remove the text it typed")
    check(restored.hasPrefix(E.notReplacedLead) && restored.contains("nothing in it changed") && restored.contains("plainly")
          && left.hasPrefix(E.notReplacedLead) && left.contains("didn't let Aris remove") && left.contains("old text and the new text together") && left.contains("undo"),
          "fix132d pure: the brain's line says it wasn't replaced, plainly, and whether the field is as it was")
    check(ArisDesktopSession.typeOutcome(.failed(restored)).text == restored,
          "fix132d pure: a not-replaced result keeps its own lead (never “NOT TYPED”, which would be untrue when it was taken back)")
    check(E.afterSelectAll(["cmd+a", "delete"]) == ["delete"] && E.afterSelectAll(["cmd+a", "backspace"]) == ["backspace"]
          && E.afterSelectAll(["delete"]) == nil && E.afterSelectAll(["cmd+a"]) == nil && E.afterSelectAll(["delete", "cmd+a"]) == nil
          && E.afterSelectAll(["cmd+a", "delete", "cmd+a"]) == nil,
          "fix132d pure: an erase in one keypress is split at its select-all, only when it selects and then deletes")
    let erasedBack = E.notErasedLine(restored: true, why: nil), erasedLeft = E.notErasedLine(restored: false, why: "TextEdit didn't take it")
    check(erasedBack.hasPrefix(E.notErasedLead) && erasedBack.contains("nothing in it changed") && erasedBack.contains("plainly")
          && erasedLeft.hasPrefix(E.notErasedLead) && erasedLeft.contains("TextEdit didn't take it") && erasedLeft.contains("some of it was deleted") && erasedLeft.contains("undo"),
          "fix132d pure: the erase's line says it wasn't erased, plainly, and whether the field is as it was")
}

// MARK: - 1. The background select-all didn't take: nothing typed in the background; the window brought forward

private func fix132dSelectAllMissedTests() {
    f132dWithUndo(perform: { _, _, _ in }) {
        let rig = f132dRig()
        let turn = f132dTurn()
        let replaced = f132dReplace(rig, turn: turn, then: [
            ("press", v2pb("press-return")), ("see", f132dCaretEnd),            // the background cmd+a: the caret stays at the end
            ("click", v2pb("click-field")), ("see", f132dCaretEnd),             // forward: the click into the field
            ("press", v2pb("press-return")), ("see", f132dSelected),            // cmd+a with the window in front: all selected
            ("type", v2pb("type-unverified")), ("see", f132dLook(f132dNew, selection: (6, 0))),
        ])
        let typed = f132dTyped(rig)
        check(replaced.status == 0 && typed.count == 1 && typed[0].contains("--foreground") && f132dSelects(rig).count == 2,
              "fix132d select-all: a background cmd+a that didn't take types nothing there; with the window in front it is selected again and typed once (\(rig.calls), \(replaced.output.prefix(200)))")
        let rows = ArisDesktopUndoLog.rows(today: false)
        check(rows.count == 1 && rows.first?["summary"] as? String == "글 바꿈: TextEdit",
              "fix132d select-all: it is kept for undo as a replace, never as an insertion (\(rows))")
    }
}

// MARK: - 1. The select-all never takes: nothing is typed at all

private func fix132dSelectAllNeverTests() {
    f132dWithUndo(perform: { _, _, _ in }) {
        let rig = f132dRig()
        let turn = f132dTurn()
        let stopped = f132dReplace(rig, turn: turn, then: [
            ("press", v2pb("press-return")), ("see", f132dCaretEnd),
            ("click", v2pb("click-field")), ("see", f132dCaretEnd),
            ("press", v2pb("press-return")), ("see", f132dCaretEnd),            // in front too, only the caret
            ("type", v2pb("type-unverified")), ("see", f132dLook(f132dDoc + f132dNew, selection: (f132dAll + 6, 0))),
        ])
        check(stopped.status != 0 && f132dTyped(rig).isEmpty, "fix132d select-all: when all of it never reads as selected, nothing is typed (\(rig.calls))")
        check(stopped.output.contains(ArisDesktopSession.notTypedLead) && stopped.output.contains("didn't take") && !stopped.output.contains("Done ("),
              "fix132d select-all: and the brain is told it wasn't typed (\(stopped.output))")
        check(ArisDesktopUndoLog.rows(today: false).isEmpty, "fix132d select-all: nothing typed, nothing kept for undo")
    }
    // A background job never brings the window forward: the missed select-all stops it there, nothing typed.
    f132dWithUndo(perform: { _, _, _ in }) {
        let rig = f132dRig()
        let turn = f132dTurn()
        turn.isTask = true
        let stopped = f132dReplace(rig, turn: turn, then: [("press", v2pb("press-return")), ("see", f132dCaretEnd),
                                                           ("type", v2pb("type-unverified")), ("see", f132dLook(f132dDoc + f132dNew, selection: nil))])
        check(stopped.status != 0 && f132dTyped(rig).isEmpty && !rig.calls.contains { $0.hasPrefix("click") },
              "fix132d select-all: in a background job a missed select-all types nothing and brings nothing forward (\(rig.calls), \(stopped.output.prefix(160)))")
    }
}

// MARK: - 1. Typed beside the old text all the same: taken out again, the step failed, said plainly

private func fix132dAppendTakenBackTests() {
    let taken = F132dTaken()
    f132dWithUndo(perform: { _, element, restoring in
        guard restoring.isEmpty else { throw ArisUndoError(message: "not an insertion") }
        taken.add(element)
    }) {
        // A field that doesn't tell its selection: the select-all can't be checked before, so the typing is checked after.
        let rig = f132dRig()
        let turn = f132dTurn()
        let unknown = f132dLook(f132dDoc, selection: nil)
        rig.queueData([("see", f132dLook(f132dDoc, selection: (0, 0)))])
        _ = f132dRun(rig, ["press", "cmd+a", "--app", "TextEdit", "--title", "Untitled"], turn: turn)
        rig.queueData([("see", unknown), ("see", unknown), ("press", v2pb("press-return")), ("see", unknown),
                       ("type", v2pb("type-unverified")), ("see", f132dLook(f132dDoc + f132dNew, selection: nil)),
                       ("see", unknown)])                                                    // read back after it was taken out
        guard case .success(let call) = ArisTypeRequest.call([f132dNew, "--app", "TextEdit", "--title", "Untitled"], keyboardApp: nil) else {
            return check(false, "fix132d append: the call")
        }
        let outcome = f132dRun(rig, call.words, text: call.text, turn: turn)
        check(outcome.status != 0 && !outcome.output.contains("Done ("), "fix132d append: R1k's append is never told as done (\(outcome.status))")
        check(outcome.output.contains(ArisDesktopErase.notReplacedLead) && outcome.output.contains("nothing in it changed") && !outcome.output.contains("NOT TYPED"),
              "fix132d append: it fails, saying plainly it wasn't replaced and nothing changed (\(outcome.output))")
        check(taken.all == [f132dNew], "fix132d append: exactly the text typed is taken out again, as Aris's undo does it (\(taken.all))")
        check(ArisDesktopUndoLog.rows(today: false).isEmpty, "fix132d append: put back, so no insertion is kept for undo (R1k-desktop-undo.json had one)")
    }
}

private func fix132dAppendLeftTests() {
    f132dWithUndo(perform: { _, _, _ in throw ArisUndoError(message: "TextEdit didn't let Aris remove the text it typed") }) {
        let rig = f132dRig()
        let turn = f132dTurn()
        let unknown = f132dLook(f132dDoc, selection: nil), appended = f132dLook(f132dDoc + f132dNew, selection: nil)
        rig.queueData([("see", f132dLook(f132dDoc, selection: (0, 0)))])
        _ = f132dRun(rig, ["press", "cmd+a", "--app", "TextEdit", "--title", "Untitled"], turn: turn)
        rig.queueData([("see", unknown), ("see", unknown), ("press", v2pb("press-return")), ("see", unknown),
                       ("type", v2pb("type-unverified")), ("see", appended), ("see", appended)])
        guard case .success(let call) = ArisTypeRequest.call([f132dNew, "--app", "TextEdit", "--title", "Untitled"], keyboardApp: nil) else {
            return check(false, "fix132d append left: the call")
        }
        let outcome = f132dRun(rig, call.words, text: call.text, turn: turn)
        check(outcome.status != 0 && outcome.output.contains(ArisDesktopErase.notReplacedLead), "fix132d append left: when it can't be taken out, the step still fails")
        check(outcome.output.contains("didn't let Aris remove") && outcome.output.contains("old text and the new text together"),
              "fix132d append left: and says the field holds both (\(outcome.output))")
        let rows = ArisDesktopUndoLog.rows(today: false)
        check(rows.count == 1 && rows.first?["summary"] as? String == "입력: TextEdit" && rows.first?["undoable"] as? Bool == true,
              "fix132d append left: what was left is kept for Aris's undo (\(rows))")
    }
}

// MARK: - 1. R1k itself: a pause on a permission window, then the step from its start, select-all checked again

private func fix132dPauseResumeTests() {
    for (front, title) in [(true, "the select-all redone in front"), (false, "never selected")] {
        f132dWithUndo(perform: { _, _, _ in }) {
            let lock = ArisDesktopLock(waitLimit: 5, idleHold: 30, poll: 0.02)
            let rig = f132dRig(lock: lock, pause: ArisDesktopPause.Policy(limit: 5, poll: 0.05))
            let turn = f132dTurn()
            rig.queueData([("see", f132dLook(f132dDoc, selection: (0, 0)))])
            _ = f132dRun(rig, ["press", "cmd+a", "--app", "TextEdit", "--title", "Untitled"], turn: turn)
            // The prompt is up when the approved step first runs, and gone a few looks later.
            let asked = F132dCount()
            rig.windows.prompt = { _ in asked.next() <= 3 ? "universalAccessAuthWarn" : nil }
            rig.queueData([("see", f132dCaretEnd), ("see", f132dCaretEnd),
                           ("press", v2pb("press-return")), ("see", f132dCaretEnd),
                           ("click", v2pb("click-field")), ("see", f132dCaretEnd),
                           ("press", v2pb("press-return")), ("see", front ? f132dSelected : f132dCaretEnd),
                           ("type", v2pb("type-unverified")), ("see", f132dLook(front ? f132dNew : f132dDoc + f132dNew, selection: nil))])
            guard case .success(let call) = ArisTypeRequest.call([f132dNew, "--app", "TextEdit", "--title", "Untitled"], keyboardApp: nil) else {
                return check(false, "fix132d pause: the call")
            }
            let outcome = f132dRun(rig, call.words, text: call.text, turn: turn)
            let paused = outcome.output.contains("Aris paused")
            if front {
                check(paused && outcome.status == 0 && f132dTyped(rig).count == 1 && f132dSelects(rig).count == 2
                      && ArisDesktopUndoLog.rows(today: false).first?["summary"] as? String == "글 바꿈: TextEdit",
                      "fix132d pause (\(title)): after the pause the select-all is pressed again and checked, and the text replaces it (\(rig.calls), \(outcome.output.prefix(200)))")
            } else {
                check(paused && outcome.status != 0 && f132dTyped(rig).isEmpty && outcome.output.contains("didn't take") && ArisDesktopUndoLog.rows(today: false).isEmpty,
                      "fix132d pause (\(title)): after the pause nothing is typed beside the old text (\(rig.calls), \(outcome.output.prefix(200)))")
            }
        }
    }
}

private final class F132dCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { count += 1; return count } }
}

// MARK: - 1b. An erase of everything in one keypress (`cmd+a delete`): the same rule as the replace

private let f132dWipe = "이 문서 글 전부 지워 줘"

/// `desktop press cmd+a delete --app TextEdit --title Untitled` on an erase card, with `queue` after its two looks.
private func f132dErase(_ rig: V2Rig, turn: F132dTurn, then queue: [(String, Data)]) -> ArisMCPOutcome {
    rig.queueData([("see", f132dLook(f132dDoc, selection: (0, 0))), ("see", f132dCaretEnd)] + queue)
    return f132dRun(rig, ["press", "cmd+a", "delete", "--app", "TextEdit", "--title", "Untitled"], turn: turn)
}

private func f132dDeletes(_ rig: V2Rig) -> [String] { rig.calls.filter { $0.hasPrefix("press delete") || $0.hasPrefix("press cmd+a delete") } }

private func fix132dEraseTests() {
    // Cmd+A didn't take in the background: nothing deleted there; forward, selected again, read back, then the delete.
    f132dWithUndo(perform: { _, _, _ in }) {
        let rig = f132dRig()
        let turn = f132dTurn(f132dWipe)
        let erased = f132dErase(rig, turn: turn, then: [
            ("press", v2pb("press-return")), ("see", f132dCaretEnd),                     // the background cmd+a: only the caret
            ("window-focus", v2pb("window-focus")), ("see", f132dCaretEnd),             // forward: the window, looked at again
            ("press", v2pb("press-return")), ("see", f132dSelected),                     // cmd+a in front: all of it
            ("press", v2pb("press-return")), ("see", f132dLook("", selection: (0, 0))),   // the delete, then empty
        ])
        let deletes = f132dDeletes(rig)
        check(erased.status == 0 && deletes.count == 1 && deletes[0].hasPrefix("press delete --window-id 9189 --foreground") && f132dSelects(rig).count == 2,
              "fix132d erase: a background cmd+a that didn't take deletes nothing there; in front it is selected again and the delete goes once (\(rig.calls), \(erased.output.prefix(200)))")
        check(turn.cards.count == 1 && ArisDesktopUndoLog.rows(today: false).first?["summary"] as? String == "글 지움: TextEdit",
              "fix132d erase: one erase card, and the erase is kept for undo (\(ArisDesktopUndoLog.rows(today: false)))")
    }
    // Cmd+A never takes: no delete at all, NOT ERASED.
    f132dWithUndo(perform: { _, _, _ in }) {
        let rig = f132dRig()
        let turn = f132dTurn(f132dWipe)
        let stopped = f132dErase(rig, turn: turn, then: [
            ("press", v2pb("press-return")), ("see", f132dCaretEnd),
            ("window-focus", v2pb("window-focus")), ("see", f132dCaretEnd),
            ("press", v2pb("press-return")), ("see", f132dCaretEnd),
            ("press", v2pb("press-return")), ("see", f132dLook(String(f132dDoc.dropLast()), selection: nil)),
        ])
        check(stopped.status != 0 && f132dDeletes(rig).isEmpty, "fix132d erase: when all of it never reads as selected, no delete is pressed (\(rig.calls))")
        check(stopped.output.contains(ArisDesktopErase.notErasedLead) && stopped.output.contains("didn't take") && !stopped.output.contains("Done ("),
              "fix132d erase: and the brain is told it wasn't erased (\(stopped.output.prefix(300)))")
        check(ArisDesktopUndoLog.rows(today: false).isEmpty, "fix132d erase: nothing deleted, nothing kept for undo")
    }
    // A field that doesn't tell its selection, and the delete took one character (the caret's): put back, NOT ERASED.
    f132dWithUndo(perform: { _, _, _ in }) {
        let rig = f132dRig()
        let turn = f132dTurn(f132dWipe)
        let unknown = f132dLook(f132dDoc, selection: nil)
        rig.queueData([("see", unknown), ("see", unknown), ("press", v2pb("press-return")), ("see", unknown),
                       ("press", v2pb("press-return")), ("see", f132dLook(String(f132dDoc.dropLast()), selection: nil)),
                       ("set-value", v2pb("setvalue")), ("see", unknown)])
        let outcome = f132dRun(rig, ["press", "cmd+a", "delete", "--app", "TextEdit", "--title", "Untitled"], turn: turn)
        let restore = rig.calls.first { $0.hasPrefix("set-value") } ?? ""
        check(outcome.status != 0 && !outcome.output.contains("Done (") && restore.contains("--value=사과 바나나 포도"),   // (the log line ends at the value's line break)
              "fix132d erase: a delete that left text is never told as done; the old text is set back (\(rig.calls))")
        check(outcome.output.contains(ArisDesktopErase.notErasedLead) && outcome.output.contains("nothing in it changed"),
              "fix132d erase: it fails, saying plainly the text wasn't erased and nothing changed (\(outcome.output.prefix(300)))")
        check(ArisDesktopUndoLog.rows(today: false).isEmpty, "fix132d erase: put back, so nothing is kept for undo")
    }
    // Put back fails: still NOT ERASED, said so, and what's left is kept for Aris's undo.
    f132dWithUndo(perform: { _, _, _ in }) {
        let rig = f132dRig()
        let turn = f132dTurn(f132dWipe)
        let unknown = f132dLook(f132dDoc, selection: nil), cut = f132dLook(String(f132dDoc.dropLast()), selection: nil)
        rig.queueData([("see", unknown), ("see", unknown), ("press", v2pb("press-return")), ("see", unknown),
                       ("press", v2pb("press-return")), ("see", cut), ("set-value", v2pb("setvalue")), ("see", cut)])
        let outcome = f132dRun(rig, ["press", "cmd+a", "delete", "--app", "TextEdit", "--title", "Untitled"], turn: turn)
        let rows = ArisDesktopUndoLog.rows(today: false)
        check(outcome.status != 0 && outcome.output.contains(ArisDesktopErase.notErasedLead) && outcome.output.contains("some of it was deleted")
              && rows.count == 1 && rows.first?["summary"] as? String == "글 지움: TextEdit",
              "fix132d erase: when it can't be put back, it fails, says so, and keeps it for undo (\(outcome.output.prefix(260)), \(rows))")
    }
}

private func fix132dErasePauseTests() {
    for front in [true, false] {
        f132dWithUndo(perform: { _, _, _ in }) {
            let lock = ArisDesktopLock(waitLimit: 5, idleHold: 30, poll: 0.02)
            let rig = f132dRig(lock: lock, pause: ArisDesktopPause.Policy(limit: 5, poll: 0.05))
            let turn = f132dTurn(f132dWipe)
            let asked = F132dCount()
            rig.windows.prompt = { _ in asked.next() <= 3 ? "universalAccessAuthWarn" : nil }
            let outcome = f132dErase(rig, turn: turn, then: [
                ("press", v2pb("press-return")), ("see", f132dCaretEnd),
                ("window-focus", v2pb("window-focus")), ("see", f132dCaretEnd),
                ("press", v2pb("press-return")), ("see", front ? f132dSelected : f132dCaretEnd),
                ("press", v2pb("press-return")), ("see", f132dLook(front ? "" : String(f132dDoc.dropLast()), selection: (0, 0))),
            ])
            let paused = outcome.output.contains("Aris paused")
            if front {
                check(paused && outcome.status == 0 && f132dDeletes(rig).count == 1 && f132dSelects(rig).count == 2
                      && ArisDesktopUndoLog.rows(today: false).first?["summary"] as? String == "글 지움: TextEdit",
                      "fix132d erase pause: after the pause the select-all is pressed again and checked before the one delete (\(rig.calls), \(outcome.output.prefix(200)))")
            } else {
                check(paused && outcome.status != 0 && f132dDeletes(rig).isEmpty && outcome.output.contains(ArisDesktopErase.notErasedLead)
                      && ArisDesktopUndoLog.rows(today: false).isEmpty,
                      "fix132d erase pause: after the pause, never selected, nothing is deleted (\(rig.calls), \(outcome.output.prefix(200)))")
            }
        }
    }
}

// MARK: - 1c. The forward card names every key that goes (security review of ed0d3167)

private func fix132dForwardCardTests() {
    // The erase path's forward card, asked when no card's yes covers it (cardYes false: an app that sends, or no card
    // before): it must name the select-all that goes before the delete, not only "delete".
    let rig = f132dRig()
    let turn = f132dTurn(f132dWipe)
    turn.answer = .no
    guard case .success(let binary) = rig.engine.engineBinary() else { return check(false, "fix132d forward card: the engine's binary") }
    let session = ArisDesktopSession(engine: rig.engine, binary: binary, target: f132dEdit, turn: turn)
    rig.queueData([("see", f132dCaretEnd)])
    guard case .success(let (look, _)) = session.look(f132dWindow), let field = look.focusedElement else { return check(false, "fix132d forward card: a look of the field") }
    check(!session.basis.cardYes, "fix132d forward card: no card's yes covers this session")
    let pressedBefore = rig.calls.filter { $0.hasPrefix("press") }.count
    let erased = session.forward(keys: ["delete"], in: look, window: f132dWindow, selectingAll: field)
    let erasing = turn.cards.last?.detail ?? ""
    let refused: Bool
    if case .failure = erased { refused = true } else { refused = false }
    check(refused && erasing.contains("키: cmd+a delete") && rig.calls.filter { $0.hasPrefix("press") }.count == pressedBefore,
          "fix132d forward card: on the erase path the card names the select-all before the delete, and its no presses nothing (\(erasing))")
    _ = session.forward(keys: ["return"], in: look, window: f132dWindow)
    let plain = turn.cards.last?.detail ?? ""
    check(plain.contains("키: return") && !plain.contains("cmd+a"), "fix132d forward card: any other forward card names just its own keys (\(plain))")
    // The type's forward card: the keys it presses before the text are on it too.
    let typed = ArisDesktopCopy.forwardTypeDetail(title: "Untitled", text: "교체된 내용", english: false, keysFirst: ["cmd+a"])
    let atEnd = ArisDesktopCopy.forwardTypeDetail(title: "Untitled", text: "hi", english: true, keysFirst: ["cmd+down"])
    check(typed.contains("먼저 누르는 키: cmd+a\n입력하는 글:\n교체된 내용") && atEnd.contains("Keys first: cmd+down\nText to type:\nhi")
          && ArisDesktopCopy.forwardTypeDetail(title: "무제", text: "안녕", english: false) == "창: “무제”\n입력하는 글:\n안녕\n백그라운드 입력이 안 돼서 창을 앞으로 가져와 실제로 입력해요",
          "fix132d forward card: the type's card names a replace's select-all or the caret's key before the text, and is as before with none")
    let ladder = fix132dSource("ArisAgent/ArisDesktopTextLadder.swift"), actions = fix132dSource("ArisAgent/ArisDesktopActions.swift")
    check(ladder.contains("let keysFirst = (caretPlace.map { [ArisDesktopCaret.keys($0)] } ?? []) + (selectsAllFirst ? [\"cmd+a\"] : [])")
          && ladder.contains("forwardTypeDetail(title: look.title, text: text, english: english, keysFirst: keysFirst)")
          && actions.contains("let shownKeys = (field != nil ? [\"cmd+a\"] : []) + keys"),
          "fix132d forward card: both foreground cards are built from every key that is sent")
}

// MARK: - 2. The pause names the window and brings a system prompt forward when that is safe

private func fix132dPauseLineTests() {
    typealias P = ArisDesktopPause
    let keystrokes = P.Window(title: "Keystroke Receiving", forApp: "Aris")
    check(P.line(.prompt(owner: "universalAccessAuthWarn", web: false), english: false, window: keystrokes)
          == "macOS “Keystroke Receiving” 창(Aris)을 처리해 주세요 — 끝나면 이어서 할게요"
          && P.line(.prompt(owner: "universalAccessAuthWarn", web: false), english: true, window: keystrokes)
          == "Please answer macOS's “Keystroke Receiving” window for Aris — I'll carry on when it's done",
          "fix132d pause line: the window is named, with the app it asks for (it said only “로그인/권한 창”)")
    check(P.line(.prompt(owner: "SecurityAgent", web: false), english: false, window: P.Window(title: "Keystroke Receiving", forApp: nil))
          == "macOS “Keystroke Receiving” 창을 처리해 주세요 — 끝나면 이어서 할게요"
          && P.line(.prompt(owner: "SecurityAgent", web: false), english: false, window: P.Window(title: nil, forApp: "Aris")) == "macOS 권한 창(Aris)을 처리해 주세요 — 끝나면 이어서 할게요"
          && P.line(.prompt(owner: "SecurityAgent", web: false), english: false, window: nil) == "로그인/권한 창을 처리해 주세요 — 끝나면 이어서 할게요"
          && P.line(.prompt(owner: "SecurityAgent", web: false), english: false, window: P.Window(title: " ", forApp: "")) == "로그인/권한 창을 처리해 주세요 — 끝나면 이어서 할게요"
          && P.line(.prompt(owner: "AuthenticationServicesAgent", web: true), english: false, window: keystrokes).hasPrefix("웹사이트 로그인 창이에요"),
          "fix132d pause line: a title alone, an app alone, nothing readable (the line as before), and a website's sign-in as before")
    let odd = P.named(P.Window(title: "Key\u{202E}stroke \"Receiving\"\n" + String(repeating: "x", count: 60), forApp: nil), english: true) ?? ""
    check(!odd.contains("\u{202E}") && !odd.contains("\n") && odd.contains("…") && odd.count < 80, "fix132d pause line: a title is cleaned and kept short (\(odd))")
    check(P.requester(in: ["“Aris” would like to receive keystrokes from any application."]) == "Aris"
          && P.requester(in: ["Grant access in Privacy & Security", "“Aris”이(가) 모든 응용 프로그램으로부터 키 입력을 수신하려고 합니다."]) == "Aris"
          && P.requester(in: ["no quotes here"]) == nil,
          "fix132d pause line: the app a prompt asks for is the name in quotes in its text")
    check(P.raises(.prompt(owner: "universalAccessAuthWarn", web: false), task: false, secureInput: false, sinceKey: 30)
          && !P.raises(.prompt(owner: "universalAccessAuthWarn", web: false), task: true, secureInput: false, sinceKey: 30)
          && !P.raises(.prompt(owner: "universalAccessAuthWarn", web: false), task: false, secureInput: true, sinceKey: 30)
          && !P.raises(.prompt(owner: "universalAccessAuthWarn", web: false), task: false, secureInput: false, sinceKey: 0.5)
          && !P.raises(.prompt(owner: "AuthenticationServicesAgent", web: true), task: false, secureInput: false, sinceKey: 30)
          && !P.raises(.secureInput, task: false, secureInput: false, sinceKey: 30) && !P.raises(.secretField, task: false, secureInput: false, sinceKey: 30),
          "fix132d pause raise: a system prompt comes forward only in a turn the user is there for, not while they type or a password field is up")
    // The engine: the named line in the notch, the prompt brought forward once, the pause and its resume as before.
    let lock = ArisDesktopLock(waitLimit: 5, idleHold: 30, poll: 0.02)
    let rig = V2Rig(lock: lock, pause: ArisDesktopPause.Policy(limit: 5, poll: 0.05))
    let asked = F132dCount()
    rig.windows.prompt = { _ in asked.next() <= 6 ? "universalAccessAuthWarn" : nil }
    rig.windows.shownPrompt = keystrokes
    rig.queue([("see", "see-before-export"), ("menu-click", "menu-click"), ("see", "see-after-export")])
    let turn = V2Turn()
    turn.request = "Aris Testbench에서 PDF로 내보내 줘"
    let outcome = rig.run(["menu", "click", "--app", "Aris Testbench", "--path", "File > Export > PDF…"], turn: turn)
    check(outcome.status == 0 && outcome.output.contains("Aris paused") && turn.quiet.contains("macOS “Keystroke Receiving” 창(Aris)을 처리해 주세요 — 끝나면 이어서 할게요")
          && rig.windows.raised == 1,
          "fix132d pause (engine): the notch names the window, it is brought forward once, and the step runs after it (\(turn.quiet), raised \(rig.windows.raised))")
    let job = V2Rig(lock: ArisDesktopLock(waitLimit: 5, idleHold: 30, poll: 0.02), pause: ArisDesktopPause.Policy(limit: 5, poll: 0.05))
    let jobAsked = F132dCount()
    job.windows.prompt = { _ in jobAsked.next() <= 6 ? "universalAccessAuthWarn" : nil }
    job.queue([("see", "see-before-export"), ("menu-click", "menu-click"), ("see", "see-after-export")])
    let task = V2Turn()
    task.request = "Aris Testbench에서 PDF로 내보내 줘"
    task.isTask = true
    _ = job.run(["menu", "click", "--app", "Aris Testbench", "--path", "File > Export > PDF…"], turn: task)
    check(job.windows.raised == 0 && task.quiet.contains("로그인/권한 창을 처리해 주세요 — 끝나면 이어서 할게요"),
          "fix132d pause (engine): a background job never brings it forward, and a window that can't be read keeps the line as before (\(task.quiet))")
    let live = fix132dSource("ArisAgent/ArisDesktopLive.swift")
    check(live.contains("func promptWindow() -> ArisDesktopPause.Window?") && live.contains("func raisePrompt() -> Bool")
          && live.contains("return app.activate()") && !live.contains("AXUIElementPerformAction(window, kAXPressAction"),
          "fix132d pause wiring: the live prompt is read by Accessibility and only activated, nothing pressed in it")
}

// MARK: - 2. Input Monitoring isn't asked for at launch while the guide may still come up

private func fix132dListenAskTests() {
    check(ArisOnboarding.guideDue(launchDecided: false, later: true, replay: false) && ArisOnboarding.guideDue(launchDecided: false, later: false, replay: true)
          && !ArisOnboarding.guideDue(launchDecided: true, later: true, replay: false) && !ArisOnboarding.guideDue(launchDecided: false, later: false, replay: false),
          "fix132d listen: the guide is due while its launch decision isn't made and the setup waits to go on (or a replay)")
    let taps = fix132dSource("Aris/private/App/ArisKeyTaps.swift"), guide = fix132dSource("Aris/private/Aris/Onboarding/ArisOnboardingGuide.swift")
    check(taps.contains("pastFirstRun && !granted && !askedBefore && !guideDue") && taps.contains("guideDue: ArisOnboardingGuide.shared.dueAtLaunch) {")
          && taps.components(separatedBy: "CGRequestListenEventAccess()").count == 2,
          "fix132d listen: the one request waits while the guide is due (seventeenth VM run: asked just before the put-off guide resumed)")
    check(guide.contains("func showAtLaunch(loginItem: Bool) {\n        launchDecided = true") && guide.contains("ArisOnboarding.guideDue(launchDecided: launchDecided"),
          "fix132d listen: the guide's launch decision is what ends the wait (then the 5-second look asks, or the guide's own list does)")
}

private func fix132dSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

// MARK: - 3. The timer's undo says the timer by its length

private func fix132dTimerWordsTests() {
    typealias W = ArisUndoWords
    check(W.doneLine("타이머: 5", korean: true) == "5분 타이머를 되돌렸어요." && W.doneLine("타이머: 5분", korean: true) == "5분 타이머를 되돌렸어요."
          && W.doneLine("타이머: 1분 30초", korean: true) == "1분 30초 타이머를 되돌렸어요." && W.doneLine("타이머: 90분", korean: true) == "1시간 30분 타이머를 되돌렸어요.",
          "fix132d timer: the Korean reply names the timer by its length (M2u: “‘5’ 타이머를 되돌렸어요”)")
    check(W.doneLine("타이머: 5", korean: false) == "I took back the 5-minute timer." && W.doneLine("타이머: 1분 30초", korean: false) == "I took back the 1 min 30 s timer.",
          "fix132d timer: in English too")
    let entry = ArisUndoWords.Candidate(id: "t", summary: "타이머: 5", action: "made")
    let korean = W.card(for: entry, newest: nil, doubt: false, korean: true), english = W.card(for: entry, newest: nil, doubt: false, korean: false)
    check(korean.detail == "되돌릴 일: 5분 타이머" && english.detail == "To undo: 5-minute timer",
          "fix132d timer: the undo card says “5분 타이머” (M2u: “Timer: 5”; \(korean.detail) / \(english.detail))")
    check(W.doneLine("타이머: pomodoro", korean: true) == "‘pomodoro’ 타이머를 되돌렸어요." && W.doneLine("할 일 추가: 타이머: 5분", korean: true) == "‘타이머: 5분’ 할 일을 되돌렸어요.",
          "fix132d timer: only a timer's own line with a length is said that way")
    for seconds in [300, 90, 60, 45, 5_400] {
        let logged = "타이머: " + ArisTimerLog.length(seconds: seconds)
        check(ArisActivityWords.timerLength(logged) == TimeInterval(seconds), "fix132d timer: aris-tools logs \(seconds) s as “\(logged)”, read back as its length")
    }
    let command = fix132dSource("ArisTools/ArisTimerCommand.swift")
    check(command.contains("\"타이머: \" + ArisTimerLog.length(seconds: $0)") && !command.contains("logActivity(stopping ? \"타이머 끔\" : \"타이머: \\(words.first"),
          "fix132d timer: `aris-tools timer 5` logs “타이머: 5분”, not the bare number")
}

// MARK: - 3. A desktop verb without `desktop` gets the same "write it again" refusal

private func fix132dDesktopVerbTests() {
    let tools = "/Users/admin/.config/aris/aris-tools"
    let r1s = "\(tools) set-value @sj339k:e14 'value seventeen' --stdin"
    let action = ArisAction.shell(r1s)
    check(ArisRiskPolicy.risk(of: action, tools: tools, home: "/Users/admin") == .never,
          "fix132d desktop verb: `aris-tools set-value …` (R1s) is never a “Mac action” card")
    let why = ArisRiskPolicy.callProblem(r1s, tools: tools) ?? ""
    check(why.hasPrefix("Refused: Aris couldn't read that call") && why.contains("`desktop set-value") && why.contains("Write it again as the usage says; nothing was done."),
          "fix132d desktop verb: the brain gets the same “write it again” refusal other badly-formed desktop calls get (\(why))")
    check(ArisRiskPolicy.neverReason(action, tools: tools, home: "/Users/admin") == why, "fix132d desktop verb: the log's reason is the same line")
    let heredoc = "\(tools) click @s1:e3 --stdin <<'ARIS'\nhello\nARIS"
    check(ArisRiskPolicy.desktopVerbProblem(heredoc, tools: tools) != nil
          && ["see --app TextEdit", "press cmd+a --app TextEdit", "menu click --app Safari --path \"File > New\"", "scroll down"].allSatisfy {
              ArisRiskPolicy.desktopVerbProblem("\(tools) \($0)", tools: tools) != nil },
          "fix132d desktop verb: every desktop-only verb, a heredoc's first line read only")
    check(["type 'hi' --app Notes", "window left", "app \"Figma\"", "timer 5", "keys cmd+t --app Safari", "desktop set-value @s:e1 --stdin"].allSatisfy {
              ArisRiskPolicy.desktopVerbProblem("\(tools) \($0)", tools: tools) == nil }
          && ArisRiskPolicy.desktopVerbProblem("echo set-value", tools: tools) == nil,
          "fix132d desktop verb: aris-tools' own commands (type, window, app, …) and a proper desktop call are untouched")
    check(ArisRiskPolicy.risk(of: .shell("\(tools) timer 5"), tools: tools, home: "/Users/admin") != .never,
          "fix132d desktop verb: a plain timer is rated as before")
}

// MARK: - 3. The timer has no label: no brain is told it has one

private func fix132dTimerLabelTests() {
    let tools = "/tools/aris-tools"
    let system = ArisAgentPrompt.system(tools: tools, gated: true, functions: true), sealed = ArisAgentPrompt.sealed(tools: tools, functions: true)
    check(ArisAgentPrompt.timerRule.contains("no label") && ArisAgentPrompt.timerRule.contains("차 마실 시간")
          && system.contains(ArisAgentPrompt.timerRule) && sealed.contains(ArisAgentPrompt.timerRule),
          "fix132d timer label: the prompts say the timer only rings, so a reply never promises “차 마실 시간” (M2)")
    let timer = ArisAPICatalog.entry("timer")?.function.description ?? ""
    check(timer.contains("no label"), "fix132d timer label: so does the timer function (\(timer))")
}
