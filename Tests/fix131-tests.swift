// Tests for jv-fix131: the thirteenth real-screen VM check of 1.3.0 (a11d7666), default configuration (Core 2 off,
// the API brain). The desktop calls are the ones recorded in notes13/actions-full.log (21:49–21:57), run on
// desktop-v2-tests' rig (fake Peekaboo, recorded fixtures) with TextEdit's shape; nothing touches a real app or the
// screen. Called from main.swift; uses its check().
import CoreGraphics
import Foundation

func runFix131Tests() {
    fix131TypeOverSelectionTests()
    fix131ReplaceAllTests()
    fix131EraseTests()
    fix131MissIsStrictTests()
    fix131UndoTests()
    fix131WordsTests()
    fix131ProtectedPlaceTests()
    fix131WindowUndoTests()
    fix131ParkedTimerTests()
    fix131SmallTests()
}

private let f131Edit = ArisDesktopTarget(name: "TextEdit", bundle: "com.apple.TextEdit", pid: 4242, known: true, never: false, browser: false, sending: false,
                                         appleSigned: true)
private let f131Window = ArisDesktopWindow(id: 9189, frame: CGRect(x: 80, y: 329, width: 1040, height: 720), title: "Untitled")
private let f131Doc = "Apple banana grape cherry.\nSecond line stays here."

private func f131Rig() -> V2Rig {
    let rig = V2Rig()
    rig.apps.apps["textedit"] = f131Edit
    rig.apps.apps["com.apple.textedit"] = f131Edit
    rig.windows.byPid[4242] = [f131Window]
    return rig
}

/// see-chat as TextEdit's Untitled: its text view (elem_59) holds `value`, with `selection` (UTF-16 location, length)
/// selected (nil: the field doesn't say), the keyboard focus on it.
private func f131Look(_ value: String, selection: (Int, Int)?) -> Data {
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

/// A live turn: clean or careful (a screen turn, as the VM's), critical or not; cards answered yes.
private final class F131Turn: ArisDesktopTurn {
    let brain: ArisBrain = .api
    let ledger = ArisComputerUseLedger()
    var brainName: String { "api" }
    var handsFree = false
    var isTask = false
    var screen = false
    var relayed = false
    var request = ""
    var isCritical = false
    var critical: Bool { isCritical }
    var live: Bool { true }
    private let lock = NSLock()
    private var read: Set<String> = []
    private var _cards: [ArisMCPCard] = []
    private var steps = 0
    var cards: [ArisMCPCard] { lock.withLock { _cards } }
    var taint: ArisTaint { lock.withLock { read.isEmpty ? .none : .outsideText } }
    func taint(forApp app: String) -> ArisTaint { lock.withLock { read.subtracting([app]).isEmpty ? .none : .outsideText } }
    func markAppRead(_ app: String) { lock.withLock { _ = read.insert(app) } }
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

private func f131Turn(_ request: String, screen: Bool = true, critical: Bool = false) -> F131Turn {
    let turn = F131Turn()
    turn.request = request
    turn.screen = screen
    turn.isCritical = critical
    return turn
}

private func f131Run(_ rig: V2Rig, _ words: [String], text: String? = nil, turn: ArisDesktopTurn) -> ArisMCPOutcome {
    let box = V2Box()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { rig.engine.handle(words, text: text, turn: turn) { box.set($0); done.signal() } }
    _ = done.wait(timeout: .now() + 60)
    return box.value ?? .failed("no answer")
}

/// `aris-tools type '<text>' --app TextEdit --title Untitled`, as the VM's brain called it.
private func f131Type(_ rig: V2Rig, _ text: String, turn: ArisDesktopTurn) -> ArisMCPOutcome {
    guard case .success(let call) = ArisTypeRequest.call([text, "--app", "TextEdit", "--title", "Untitled"], keyboardApp: nil) else { return .failed("the call") }
    return f131Run(rig, call.words, text: call.text, turn: turn)
}

private func f131Card(_ card: ArisMCPCard) -> String { card.title + "\n" + (card.full ?? card.detail) }

// MARK: - 1. Typing over a selection is one replace card that shows the selected text (Q2a, Q2d1b)

private func fix131TypeOverSelectionTests() {
    // Q2a: "선택한 부분에 '바뀐 글'이라고 입력해 줘" with "banana" selected; the VM's card said only "Text to type: 바뀐 글".
    let rig = f131Rig()
    let turn = f131Turn("선택한 부분에 '바뀐 글'이라고 입력해 줘")
    let replaced = "Apple 바뀐 글 grape cherry.\nSecond line stays here."
    rig.queueData([("see", f131Look(f131Doc, selection: (6, 6))), ("see", f131Look(f131Doc, selection: (6, 6))), ("type", v2pb("type-unverified")),
                   ("see", f131Look(replaced, selection: (10, 0)))])
    let done = f131Type(rig, "바뀐 글", turn: turn)
    let shown = turn.cards.map(f131Card)
    check(done.status == 0 && turn.cards.count == 1 && rig.calls.filter { $0.hasPrefix("type") }.count == 1,
          "fix131 type-over: the VM's call types once on one card (\(turn.cards.count) cards, \(done.output.prefix(160)))")
    check(shown.first.map { $0.hasPrefix("TextEdit에서 글 바꾸기") && $0.contains("지워지는 글:\nbanana") && $0.contains("바뀐 글") } == true,
          "fix131 type-over: its card is a replace that shows the selected “banana” it erases and the text typed (\(shown))")
    // English (Q2d1b): "In TextEdit, replace the selected word with 'changed text'".
    let english = f131Rig()
    let said = f131Turn("In TextEdit, replace the selected word with 'changed text'")
    english.queueData([("see", f131Look(f131Doc, selection: (6, 6))), ("see", f131Look(f131Doc, selection: (6, 6))), ("type", v2pb("type-unverified")),
                       ("see", f131Look("Apple changed text grape cherry.\nSecond line stays here.", selection: (18, 0)))])
    _ = f131Type(english, "changed text", turn: said)
    let card = said.cards.first.map(f131Card) ?? ""
    check(card.hasPrefix("Replace text in TextEdit") && card.contains("Text that is erased:\nbanana") && card.contains("changed text"),
          "fix131 type-over: in English too (\(card))")
    // A plain type of the user's words on a clean turn ran at once over the selection (no card at all): now its card.
    let clean = f131Rig()
    let quiet = f131Turn("선택한 부분에 '바뀐 글'이라고 입력해 줘", screen: false)
    clean.queueData([("see", f131Look(f131Doc, selection: (6, 6))), ("see", f131Look(f131Doc, selection: (6, 6))), ("type", v2pb("type-unverified")),
                     ("see", f131Look(replaced, selection: (10, 0)))])
    _ = f131Type(clean, "바뀐 글", turn: quiet)
    check(quiet.cards.count == 1 && f131Card(quiet.cards[0]).contains("banana"),
          "fix131 type-over: a clean turn's type of the user's words over a selection asks too, with the text (\(quiet.cards.map(f131Card)))")
    // At a bare caret nothing changes: the same clean type runs at once, as before.
    let caret = f131Rig()
    let plain = f131Turn("여기에 '바뀐 글' 써 줘", screen: false)
    caret.queueData([("see", f131Look(f131Doc, selection: (26, 0))), ("see", f131Look(f131Doc, selection: (26, 0))), ("type", v2pb("type-unverified")),
                     ("see", f131Look("Apple banana grape cherry.바뀐 글\nSecond line stays here.", selection: (30, 0)))])
    let ran = f131Type(caret, "바뀐 글", turn: plain)
    check(ran.status == 0 && plain.cards.isEmpty, "fix131 type-over: at a caret a clean type still runs with no card (\(plain.cards.count), \(ran.output.prefix(120)))")
    // Bound to what the card showed: the selection changed before the typing (now "grape"), so nothing is typed.
    let moved = f131Rig()
    let held = f131Turn("선택한 부분에 '바뀐 글'이라고 입력해 줘")
    moved.queueData([("see", f131Look(f131Doc, selection: (6, 6))), ("see", f131Look(f131Doc, selection: (13, 5))), ("type", v2pb("type-unverified")),
                     ("see", f131Look(replaced, selection: (10, 0)))])
    let stopped = f131Type(moved, "바뀐 글", turn: held)
    check(stopped.status != 0 && !moved.calls.contains { $0.hasPrefix("type") } && stopped.output.contains("NOT DONE"),
          "fix131 type-over: a selection that changed since the card stops the typing (\(moved.calls), \(stopped.output.prefix(160)))")
}

// MARK: - 2. Select all, then type or delete: one replace card (Q2b, Q2d2)

private func fix131ReplaceAllTests() {
    // Q2b: `desktop press cmd+a --app TextEdit --title Untitled`, then `aris-tools type '교체된 내용' --app TextEdit --title Untitled`.
    let rig = f131Rig()
    let turn = f131Turn("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘", critical: true)
    rig.queueData([("see", f131Look(f131Doc, selection: (0, 0)))])
    let first = f131Run(rig, ["press", "cmd+a", "--app", "TextEdit", "--title", "Untitled"], turn: turn)
    check(first.status == 0 && turn.cards.isEmpty && !rig.calls.contains { $0.hasPrefix("press") } && first.output.contains("Nothing was pressed yet"),
          "fix131 replace-all: the lone select-all goes up with what replaces it, not as a card of its own (\(turn.cards.map(f131Card)), \(rig.calls))")
    let all = f131Doc.utf16.count
    rig.queueData([("see", f131Look(f131Doc, selection: (0, 0))), ("see", f131Look(f131Doc, selection: (0, 0))), ("press", v2pb("press-return")),
                   ("see", f131Look(f131Doc, selection: (0, all))), ("type", v2pb("type-unverified")), ("see", f131Look("교체된 내용", selection: (6, 0)))])
    let second = f131Type(rig, "교체된 내용", turn: turn)
    let shown = turn.cards.map(f131Card)
    check(second.status == 0 && turn.cards.count == 1 && rig.calls.contains { $0.hasPrefix("press cmd+a") } && rig.calls.filter { $0.hasPrefix("type") }.count == 1,
          "fix131 replace-all: one card in all, then everything is selected and typed over (\(shown.count) cards, \(rig.calls), \(second.output.prefix(160)))")
    check(shown.first.map { $0.hasPrefix("TextEdit에서 글 바꾸기") && $0.contains("이 창의 글을 모두 지우고") && $0.contains("지워지는 글:\n" + f131Doc) && $0.contains("교체된 내용") } == true,
          "fix131 replace-all: the card shows the whole text it erases and what replaces it (\(shown))")
    // Q2d2: `desktop press cmd+a delete --app TextEdit` then `desktop type <ref> --stdin`, in English.
    let en = f131Rig()
    let said = f131Turn("Delete all the text in this document and write 'replaced content'", critical: true)
    en.queueData([("see", f131Look(f131Doc, selection: (0, 0))), ("see", f131Look(f131Doc, selection: (0, 0))), ("press", v2pb("press-return")),
                  ("see", f131Look("", selection: (0, 0)))])
    let held = f131Run(en, ["press", "cmd+a", "delete", "--app", "TextEdit"], turn: said)
    // fix132 (R1e2): `cmd+a delete` in a turn whose words also give the new text is held back like a lone select-all, so
    // the type that follows is the one replace card (it was an erase card, then the type's card: two). Erasing only, it is
    // still one erase card with the whole text (fix132-tests).
    check(held.status == 0 && said.cards.isEmpty && !en.calls.contains { $0.hasPrefix("press") } && held.output.contains(ArisDesktopErase.heldLead),
          "fix131 replace-all: `press cmd+a delete` with new text to write is held for the replace card (\(said.cards.map(f131Card)), \(en.calls))")
    // As one replace: a select-all held back, then the type (the English of Q2b).
    let one = f131Rig()
    let both = f131Turn("Delete all the text in this document and write 'replaced content'", critical: true)
    one.queueData([("see", f131Look(f131Doc, selection: (0, 0)))])
    _ = f131Run(one, ["press", "cmd+a", "--app", "TextEdit"], turn: both)
    one.queueData([("see", f131Look(f131Doc, selection: (0, 0))), ("see", f131Look(f131Doc, selection: (0, 0))), ("press", v2pb("press-return")),
                   ("see", f131Look(f131Doc, selection: (0, all))), ("type", v2pb("type-unverified")), ("see", f131Look("replaced content", selection: (16, 0)))])
    _ = f131Type(one, "replaced content", turn: both)
    let card = both.cards.first.map(f131Card) ?? ""
    check(both.cards.count == 1 && card.hasPrefix("Replace text in TextEdit") && card.contains("Text that is erased:\n" + f131Doc) && card.contains("replaced content"),
          "fix131 replace-all: in English, one replace card (\(both.cards.map(f131Card)))")
    // Only erasing: the held select-all and a delete are one erase card with the text, and its keys select first.
    let erase = f131Rig()
    let wipe = f131Turn("이 문서 글 전부 지워 줘", critical: true)
    erase.queueData([("see", f131Look(f131Doc, selection: (0, 0)))])
    _ = f131Run(erase, ["press", "cmd+a", "--app", "TextEdit"], turn: wipe)
    // fix132d: the select-all is pressed on its own and read back (all of it selected) before the delete goes.
    erase.queueData([("see", f131Look(f131Doc, selection: (0, 0))), ("see", f131Look(f131Doc, selection: (0, 0))), ("press", v2pb("press-return")),
                     ("see", f131Look(f131Doc, selection: (0, f131Doc.utf16.count))), ("press", v2pb("press-return")), ("see", f131Look("", selection: (0, 0)))])
    let gone = f131Run(erase, ["press", "delete", "--app", "TextEdit"], turn: wipe)
    let wiped = wipe.cards.first.map(f131Card) ?? ""
    check(wipe.cards.count == 1 && wiped.hasPrefix("TextEdit에서 글 지우기") && wiped.contains("지워지는 글:\n" + f131Doc) && gone.status == 0
          && erase.calls.contains { $0.hasPrefix("press cmd+a --snapshot") } && erase.calls.contains { $0.hasPrefix("press delete --snapshot") },
          "fix131 replace-all: erasing everything is one erase card with the text, its keys selecting first (\(wipe.cards.map(f131Card)), \(erase.calls), \(gone.output.prefix(120)))")
    // His words don't ask to replace: a lone select-all is pressed on its card as before (nothing held back).
    let plain = f131Rig()
    let select = f131Turn("전체 선택해 줘", critical: true)
    plain.queueData([("see", f131Look(f131Doc, selection: (0, 0))), ("see", f131Look(f131Doc, selection: (0, 0))), ("press", v2pb("press-return")),
                     ("see", f131Look(f131Doc, selection: (0, all)))])
    _ = f131Run(plain, ["press", "cmd+a", "--app", "TextEdit"], turn: select)
    check(plain.calls.contains { $0.hasPrefix("press cmd+a") } && select.cards.count == 1,
          "fix131 replace-all: \"전체 선택해 줘\" still selects, on its card (\(plain.calls), \(select.cards.count))")
}

// MARK: - 3. A delete over a selection shows what it erases

private func fix131EraseTests() {
    let rig = f131Rig()
    let turn = f131Turn("선택한 거 지워 줘", critical: true)
    rig.queueData([("see", f131Look(f131Doc, selection: (6, 6))), ("see", f131Look(f131Doc, selection: (6, 6))), ("press", v2pb("press-return")),
                   ("see", f131Look("Apple  grape cherry.\nSecond line stays here.", selection: (6, 0)))])
    _ = f131Run(rig, ["press", "delete", "--app", "TextEdit"], turn: turn)
    let card = turn.cards.first.map(f131Card) ?? ""
    check(turn.cards.count == 1 && card.hasPrefix("TextEdit에서 글 지우기") && card.contains("지워지는 글:\nbanana") && rig.calls.contains { $0.hasPrefix("press delete") },
          "fix131 erase: a delete over “banana” is an erase card that shows it, and only delete is pressed (\(card), \(rig.calls))")
}

// MARK: - 4. A selection that can't be read is a replace too

private func fix131MissIsStrictTests() {
    let rig = f131Rig()
    let turn = f131Turn("여기에 '바뀐 글' 써 줘", screen: false)
    rig.queueData([("see", f131Look(f131Doc, selection: nil)), ("see", f131Look(f131Doc, selection: nil)), ("type", v2pb("type-unverified")),
                   ("see", f131Look("Apple banana grape cherry.바뀐 글\nSecond line stays here.", selection: nil))])
    _ = f131Type(rig, "바뀐 글", turn: turn)
    let card = turn.cards.first.map(f131Card) ?? ""
    check(turn.cards.count == 1 && card.contains("지워질 글을 미리 읽지 못했어요"),
          "fix131 miss: a field that doesn't tell its selection asks on a card that says so, where a caret ran at once (\(turn.cards.map(f131Card)))")
    let pure = ArisDesktopErase.self
    check(!pure.holds(card: .unread, now: .text("x")) && pure.holds(card: .unread, now: .nothing) && !pure.holds(card: .nothing, now: .text("x"))
          && !pure.holds(card: .nothing, now: .unread) && pure.holds(card: .text("a"), now: .text("a")) && !pure.holds(card: .text("a"), now: .text("b")),
          "fix131 miss: the binding is never looser on a miss than on a hit")
}

// MARK: - 5. "방금 거 되돌려" takes exactly that text back, as the newest change

private func fix131UndoTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix131-undo-\(UUID().uuidString)")
    let before = ArisDesktopUndoLog.folder, performer = ArisDesktopUndoLog.perform
    ArisDesktopUndoLog.folder = folder
    defer {
        ArisDesktopUndoLog.folder = before
        ArisDesktopUndoLog.perform = performer
        try? FileManager.default.removeItem(at: folder)
    }
    let rig = f131Rig()
    let turn = f131Turn("선택한 부분에 '바뀐 글'이라고 입력해 줘")
    let replaced = "Apple 바뀐 글 grape cherry.\nSecond line stays here."
    rig.queueData([("see", f131Look(f131Doc, selection: (6, 6))), ("see", f131Look(f131Doc, selection: (6, 6))), ("type", v2pb("type-unverified")),
                   ("see", f131Look(replaced, selection: (10, 0)))])
    _ = f131Type(rig, "바뀐 글", turn: turn)
    let rows = ArisDesktopUndoLog.rows(today: false)
    check(rows.count == 1 && rows[0]["summary"] as? String == "글 바꿈: TextEdit" && rows[0]["undoable"] as? Bool == true && !(rows.first?.description.contains("banana") ?? true),
          "fix131 undo: the replace is kept as a change that can be undone, with no text of the document in its row (\(rows))")
    // The VM's log had a trash from a minute before (21:48): the typing is newer, so a bare "되돌려" picks it.
    let formatter = ISO8601DateFormatter()
    let older: [[String: Any]] = [["id": UUID().uuidString, "date": formatter.string(from: Date().addingTimeInterval(-90)), "job": "대화", "worker": "api",
                                   "summary": "휴지통으로: 임시폴더13", "undoable": true, "undone": false, "asks": false, "action": "removed"]]
    let body = ArisDesktopUndoLog.merged((try? JSONSerialization.data(withJSONObject: older)) ?? Data(), today: false)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let items = (try? decoder.decode([ArisActivityItem].self, from: body)) ?? []
    let changes = items.map { ArisUndoWords.Change(id: $0.id, date: $0.date, summary: $0.summary, action: $0.action, asks: $0.asks, undoable: $0.undoable, unit: $0.unit,
                                                   passOver: $0.passOver == true) }
    var picked: String?
    if case .undo(let entry, _, _) = ArisUndoWords.reach(changes, since: Date().addingTimeInterval(-900), kind: nil) { picked = entry.id }
    check(items.count == 2 && picked == rows.first?["id"] as? String, "fix131 undo: \"방금 거 되돌려\" offers the typing, not the older trash (\(items.map(\.summary)), \(picked ?? "nil"))")
    // Its undo puts back exactly the text as it was, from the undo store's copy.
    nonisolated(unsafe) var restored: (String, String)?
    ArisDesktopUndoLog.perform = { app, _, text in restored = (app, text) }
    guard let id = rows.first?["id"] as? String, let store = ArisDesktopUndoLog.store else { return check(false, "fix131 undo: an entry and a store") }
    let answer = ArisDesktopUndoLog.undo(id: id, store: store)
    check(answer?.status == 200 && answer?.body.contains("restored\\tTextEdit") == true && restored?.0 == "TextEdit" && restored?.1 == f131Doc,
          "fix131 undo: the undo restores the whole text as it was, said as put back (\(String(describing: answer)), \(String(describing: restored)))")
    check(ArisDesktopUndoLog.rows(today: false).first?["undone"] as? Bool == true && ArisDesktopUndoLog.undo(id: id, store: store)?.status == 500,
          "fix131 undo: once undone it isn't offered or done again")
    check(ArisDesktopUndoLog.undo(id: UUID().uuidString, store: store) == nil, "fix131 undo: an id that isn't the desktop engine's is left to the activity log")
    // A plain insertion at a caret is kept too (its undo takes out only what was typed); nothing at all with no folder.
    let caret = f131Rig()
    let plain = f131Turn("여기에 '추가 문장' 써 줘", screen: false)
    caret.queueData([("see", f131Look(f131Doc, selection: (26, 0))), ("see", f131Look(f131Doc, selection: (26, 0))), ("type", v2pb("type-unverified")),
                     ("see", f131Look("Apple banana grape cherry.추가 문장\nSecond line stays here.", selection: (31, 0)))])
    _ = f131Type(caret, "추가 문장", turn: plain)
    let newest = ArisDesktopUndoLog.rows(today: false).last
    check(newest?["summary"] as? String == "입력: TextEdit" && newest?["undoable"] as? Bool == true, "fix131 undo: text typed at a caret can be undone too (\(String(describing: newest)))")
    check(rows.first?["action"] as? String == "changed" && newest?["action"] as? String == "made" && ArisDesktopUndoLog.action("글 지움: TextEdit") == "removed",
          "fix131 undo: each row says what it did, so \"지운 거 되돌려\" or \"입력한 거\" can name it")
}

// MARK: - 6. The words on the side notch and in an English UI

private func fix131WordsTests() {
    check(ArisActivityWords.english("글 바꿈: TextEdit") == "Text replaced: TextEdit" && ArisActivityWords.english("글 지움: TextEdit") == "Text erased: TextEdit"
          && ArisActivityWords.english("입력: TextEdit") == "Typed: TextEdit", "fix131 words: the new rows' kinds have their English")
    check(ArisCardEnglish.title("TextEdit에서 글 바꾸기") == "Replace text in TextEdit" && ArisCardEnglish.title("TextEdit에서 글 지우기") == "Erase text in TextEdit",
          "fix131 words: an English UI draws a Korean replace card's title in English")
    let detail = ArisCardEnglish.detail("⚠️ 선택한 글을 지우고 그 자리에 입력해요\n지워지는 글:\nbanana", title: "TextEdit에서 글 바꾸기")
    check(detail.hasPrefix("⚠️ This erases the selected text and types in its place\nText that is erased:") && detail.hasSuffix("banana"),
          "fix131 words: and its rows, the erased text as it is (\(detail))")
    for typing in [true, false] {
        for scope in [ArisDesktopErase.Scope.selection, .whole] {
            let korean = ArisDesktopErase(scope: scope, seen: .text("x")).cardLines(typing: typing, english: false)
            let english = ArisDesktopErase(scope: scope, seen: .text("x")).cardLines(typing: typing, english: true)
            check(ArisCardEnglish.detail(korean.joined(separator: "\n"), title: "TextEdit에서 글 바꾸기") == english.joined(separator: "\n"),
                  "fix131 words: the app's English of the card is the helper's own (\(typing), \(scope))")
        }
    }
}

// MARK: - 7. A protected place as a whole: refused in one plain sentence (D1–D5)

private func fix131ProtectedPlaceTests() {
    let asked: [(String, ArisProtectedPlaceAsk.Place, ArisProtectedPlaceAsk.Kind)] = [
        ("도큐멘트 폴더 통째로 지워 줘", .documents, .whole), ("Documents 폴더 휴지통에 넣어", .documents, .whole), ("바탕화면 폴더 지워 줘", .desktop, .whole),
        ("아니, 바탕화면 폴더 자체를 통째로 지워 줘", .desktop, .whole), ("~/Downloads 비워 줘", .downloads, .empty),
        ("다운로드 폴더 안에 있는 거 전부 휴지통에 버려 줘", .downloads, .empty), ("Delete my Documents folder", .documents, .whole),
        ("Empty my Downloads folder", .downloads, .empty), ("move the Desktop folder to the trash", .desktop, .whole),
    ]
    for (said, place, kind) in asked {
        check(ArisProtectedPlaceAsk.parse(said) == ArisProtectedPlaceAsk.Asked(place: place, kind: kind), "fix131 places: \"\(said)\" is a protected place as a whole")
    }
    for said in ["바탕화면에 있는 임시폴더13 폴더 지워 줘", "바탕화면 X13 폴더 안의 sub 폴더에 있는 초안13.txt 휴지통에 버려 줘", "다운로드 폴더 열어 줘", "이 문서 지워 줘",
                 "바탕화면 v13 폴더의 rename-me.txt 이름을 renamed13c.txt로 바꿔 줘", "휴지통 비워 줘", "폴더 자체를 휴지통으로 옮겨", "문서 지워 줘", "다운로드에서 영수증.pdf 지워 줘"] {
        check(ArisProtectedPlaceAsk.parse(said) == nil, "fix131 places: \"\(said)\" goes to the AI as before")
    }
    let korean = ArisProtectedPlaceAsk.reply(ArisProtectedPlaceAsk.Asked(place: .documents, kind: .whole), korean: true)
    let empty = ArisProtectedPlaceAsk.reply(ArisProtectedPlaceAsk.Asked(place: .downloads, kind: .empty), korean: true)
    let english = ArisProtectedPlaceAsk.reply(ArisProtectedPlaceAsk.Asked(place: .documents, kind: .whole), korean: false)
    for line in [korean, empty, english] {
        check(line.filter { $0 == "." }.count == 1 && !line.contains("?") && !line.contains("방법이") && !line.contains("can't list") && !line.contains("휴지통으로 옮겨도"),
              "fix131 places: one plain sentence, no question, no made-up inability (\(line))")
    }
    check(korean.contains("지울 파일을 말씀해") && empty.contains("골라") && english.contains("which files"), "fix131 places: it says what he can do instead")
    check(ArisProtectedPlaceAsk.answer("도큐멘트 폴더 통째로 지워 줘", fromApp: false, handsFree: false, plain: true) == nil
          && ArisProtectedPlaceAsk.answer("도큐멘트 폴더 통째로 지워 줘", fromApp: true, handsFree: true, plain: true) == nil
          && ArisProtectedPlaceAsk.answer("도큐멘트 폴더 통째로 지워 줘", fromApp: true, handsFree: false, plain: true) == korean,
          "fix131 places: answered here only for the app's own plain turn")
    let rule = ArisAgentPrompt.filePlacesRule("aris-tools")
    check(rule.contains("never deleted, moved") && rule.contains("one sentence") && rule.contains("never suggest a wording") && rule.contains("unless `files find` really failed"),
          "fix131 places: the brain's rule says the same")
}

// MARK: - 8. "방금 창 옮긴 거 되돌려 줘" is the recorded undo, never a new move (W3)

private func fix131WindowUndoTests() {
    for said in ["방금 창 옮긴 거 되돌려 줘", "방금 거 되돌려", "방금 만든 거 되돌려 줘", "undo the window move", "put the window back"] {
        check(ArisIntent.parse(said) == .undo, "fix131 window undo: \"\(said)\" is Aris's own undo")
    }
    check(ArisUndoWords.kind(in: "방금 창 옮긴 거 되돌려 줘") == "moved", "fix131 window undo: it takes the newest move")
    for said in ["이 문장 원래대로 되돌려 써 줘", "방금 보낸 메일 취소해", "방금 창 옮긴 거 되돌리지 마"] {
        check(ArisIntent.parse(said) != .undo, "fix131 window undo: \"\(said)\" is not")
    }
    check(ArisWindowMoveReport.undoNote.contains("`undo`") && ArisWindowMoveReport.undoNote.contains("never call a layout its old place"),
          "fix131 window undo: a move's answer says a layout is not its old place and how to put it back")
}

// MARK: - 9. The finished timer's parked answer goes with its card (T1)

private func fix131ParkedTimerTests() {
    let parked = ArisSession.parked(heard: "Timer", reply: "1 minute is up.")
    check(ArisParkedNotice.step(session: parked, heard: "Timer", reply: "1 minute is up.", noticeUp: true, notchOpen: false) == .wait,
          "fix131 timer: while its card is up the parked line stays")
    check(ArisParkedNotice.step(session: parked, heard: "Timer", reply: "1 minute is up.", noticeUp: false, notchOpen: true) == .wait,
          "fix131 timer: and while the notch is open on it")
    check(ArisParkedNotice.step(session: parked, heard: "Timer", reply: "1 minute is up.", noticeUp: false, notchOpen: false) == .clear,
          "fix131 timer: once the card went (a minute after it was seen) the parked line goes too, so reopening the notch doesn't show it")
    check(ArisParkedNotice.step(session: .parked(heard: "날씨", reply: "맑아요."), heard: "Timer", reply: "1 minute is up.", noticeUp: false, notchOpen: false) == .stop
          && ArisParkedNotice.step(session: ArisSession().listening(), heard: "Timer", reply: "1 minute is up.", noticeUp: false, notchOpen: false) == .stop,
          "fix131 timer: anything else the notch holds by then is left alone")
}

// MARK: - 10. The small ones (K1 header, wrong-key path, type over a selection by words)

private func fix131SmallTests() {
    check(ArisCardEnglish.detail("3개를 한 번에 물어봐요:\n1. 우유 사기\n2. 은행 가기", title: "할 일 · 추가") == "3 items, asked about together:\n1. 우유 사기\n2. 은행 가기",
          "fix131 small: a grouped card's header is drawn in the UI's English, the items as said")
    let wrongKey = ArisAPIFailureWords.line(.key, title: "DeepSeek", english: false)
    let shown = ArisSettingsNames.inUILanguage(wrongKey, english: true)
    check(shown.contains("Settings › Talking to Aris › AI · Model") && !shown.contains("설정 ›") && shown.hasPrefix("DeepSeek API 키가"),
          "fix131 small: a Korean request's wrong-key line names the settings path in an English UI's words (\(shown))")
    check(ArisSettingsNames.inUILanguage(wrongKey, english: false) == wrongKey, "fix131 small: in a Korean UI it stays as it was")
    check(ArisLookContext.asksToType("Type 'changed text' where I selected") && ArisLookContext.asksToType("선택한 부분에 '바뀐 글'이라고 입력해 줘")
          && !ArisLookContext.asksToType("이거 뭐야"), "fix131 small: words that ask to type are told")
    let told = ArisLookContext.words(context: "Selected text:\nbanana", unread: nil, unselected: nil, pictured: false, rewrite: false, typesOver: true)
    check(told.contains("aris-tools type") && told.contains("Don't answer with only the text")
          && !ArisLookContext.words(context: "x", unread: nil, unselected: nil, pictured: false, rewrite: false).contains("aris-tools type"),
          "fix131 small: a type over the selection tells the AI to type it in, not to answer with the text")
}
