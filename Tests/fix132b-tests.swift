// Tests for jv-fix132b: the fifteenth real-screen VM check of 1.3.2 (0a62cb69). The desktop calls are the ones
// recorded in notes15 (R1c, R1c2, R1f: "erase all and write X" with only a caret; R1e: "command+A로 전체 선택한 다음 …"),
// run on desktop-v2-tests' rig (fake Peekaboo, recorded fixtures) with TextEdit's shape; nothing touches a real app or
// the screen. Called from main.swift; uses its check().
import CoreGraphics
import Foundation

func runFix132bTests() {
    fix132bCaretReplaceTests()
    fix132bCaretReplaceGuardTests()
    fix132bPartialAtCaretTests()
    fix132bSelectAllWordsTests()
    fix132bTypedAnswerTests()
    fix132bOwnWordsRowTests()
}

private let f132bEdit = ArisDesktopTarget(name: "TextEdit", bundle: "com.apple.TextEdit", pid: 4242, known: true, never: false, browser: false, sending: false,
                                          appleSigned: true)
private let f132bWindow = ArisDesktopWindow(id: 9189, frame: CGRect(x: 80, y: 329, width: 1040, height: 720), title: "Untitled")
private let f132bDoc = "Apple banana grape cherry.\nSecond line stays here."

private func f132bRig() -> V2Rig {
    let rig = V2Rig()
    rig.apps.apps["textedit"] = f132bEdit
    rig.apps.apps["com.apple.textedit"] = f132bEdit
    rig.windows.byPid[4242] = [f132bWindow]
    return rig
}

/// see-chat as TextEdit's Untitled: its text view (elem_59) holds `value`, with `selection` (UTF-16 location, length).
private func f132bLook(_ value: String, selection: (Int, Int)) -> Data {
    guard var object = (try? JSONSerialization.jsonObject(with: v2pb("see-chat"))) as? [String: Any], var data = object["data"] as? [String: Any] else { return Data() }
    data["application_name"] = "TextEdit"
    data["window_title"] = "Untitled"
    data["focused_element"] = ["frame": [[461, 1015], [586, 24]], "processIdentifier": 4242, "role": "AXTextField", "windowID": 9189]
    var list = data["ui_elements"] as? [[String: Any]] ?? []
    for index in list.indices where list[index]["id"] as? String == "elem_59" {
        list[index]["value"] = value
        list[index]["label"] = "Untitled text"
        list[index]["description"] = "Untitled text"
        list[index]["selected_text_range"] = ["location": selection.0, "length": selection.1]
    }
    data["ui_elements"] = list
    object["data"] = data
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
}

/// A live screen turn (as the VM's), cards answered yes.
private final class F132bTurn: ArisDesktopTurn {
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
    private let lock = NSLock()
    private var _cards: [ArisMCPCard] = []
    private var steps = 0
    var cards: [ArisMCPCard] { lock.withLock { _cards } }
    var taint: ArisTaint { .none }
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

private func f132bTurn(_ request: String) -> F132bTurn {
    let turn = F132bTurn()
    turn.request = request
    turn.ledger.startTurn()
    return turn
}

/// One desktop call, with the ledger kept as ArisDesktopRoutes keeps it for an action (started, then ended or held).
private func f132bRun(_ rig: V2Rig, _ words: [String], text: String? = nil, turn: F132bTurn) -> ArisMCPOutcome {
    let action = ArisDesktopHonesty.isAction(words) || words.first == "type"
    if action { turn.ledger.noteActionStarted() }
    let box = V2Box()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { rig.engine.handle(words, text: text, turn: turn) { box.set($0); done.signal() } }
    _ = done.wait(timeout: .now() + 60)
    let outcome = box.value ?? .failed("no answer")
    if action, outcome.status == 0, outcome.output.contains(ArisDesktopErase.heldLead) { turn.ledger.noteActionHeld() }
    else if action { turn.ledger.noteActionEnded(ok: outcome.status == 0) }
    return outcome
}

/// `aris-tools type '<text>' --app TextEdit --title Untitled`, as the VM's brain called it (R1f; R1c without --title).
private func f132bType(_ rig: V2Rig, _ text: String, turn: F132bTurn) -> ArisMCPOutcome {
    guard case .success(let call) = ArisTypeRequest.call([text, "--app", "TextEdit", "--title", "Untitled"], keyboardApp: nil) else { return .failed("the call") }
    return f132bRun(rig, call.words, text: call.text, turn: turn)
}

private func f132bCard(_ card: ArisMCPCard) -> String { card.title + "\n" + (card.full ?? card.detail) }

// MARK: - 1. "Erase all and write X" with only a caret is one replace card, and replaces

private func fix132bCaretReplaceTests() {
    let end = f132bDoc.utf16.count
    for (request, text, korean) in [("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘", "교체된 내용", true),
                                    ("Delete all the text in this document and write 'replaced content'", "replaced content", false)] {
        // R1c / R1c2 / R1f: the caret at the end of the text, nothing selected, a plain `aris-tools type`.
        let rig = f132bRig()
        let turn = f132bTurn(request)
        rig.queueData([("see", f132bLook(f132bDoc, selection: (end, 0))), ("see", f132bLook(f132bDoc, selection: (end, 0))), ("press", v2pb("press-return")),
                       ("see", f132bLook(f132bDoc, selection: (0, end))), ("type", v2pb("type-unverified")), ("see", f132bLook(text, selection: (text.utf16.count, 0)))])
        let typed = f132bType(rig, text, turn: turn)
        let shown = turn.cards.map(f132bCard)
        let lead = korean ? "TextEdit에서 글 바꾸기" : "Replace text in TextEdit"
        let warning = korean ? "⚠️ 이 창의 글을 모두 지우고 그 자리에 입력해요" : "⚠️ This erases all the text in this window and types in its place"
        let erased = korean ? "지워지는 글:\n" : "Text that is erased:\n"
        check(turn.cards.count == 1 && shown[0].hasPrefix(lead) && shown[0].contains(warning) && shown[0].contains(erased + f132bDoc) && shown[0].contains(text),
              "fix132b caret: a replace with only a caret is one replace card that shows the whole text it erases (\(korean), \(shown))")
        check(typed.status == 0 && rig.calls.contains { $0.hasPrefix("press cmd+a") } && rig.calls.filter { $0.hasPrefix("type") }.count == 1
              && rig.calls.firstIndex { $0.hasPrefix("press cmd+a") }! < rig.calls.firstIndex { $0.hasPrefix("type") }!,
              "fix132b caret: on its yes everything is selected, then typed over (never appended) (\(korean), \(rig.calls), \(typed.output.prefix(160)))")
    }
    // The erase preview is the field's text as it is now, read fresh (not an older look of the turn).
    let rig = f132bRig()
    let turn = f132bTurn("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘")
    let now = "Only this line is here now."
    rig.queueData([("see", f132bLook(now, selection: (now.utf16.count, 0))), ("see", f132bLook(now, selection: (now.utf16.count, 0))), ("press", v2pb("press-return")),
                   ("see", f132bLook(now, selection: (0, now.utf16.count))), ("type", v2pb("type-unverified")), ("see", f132bLook("교체된 내용", selection: (6, 0)))])
    _ = f132bType(rig, "교체된 내용", turn: turn)
    let card = turn.cards.first.map(f132bCard) ?? ""
    check(card.contains("지워지는 글:\n" + now) && !card.contains("Apple banana"), "fix132b caret: the card's erase preview is the field's current text (\(card))")
}

// MARK: - 1. What stays: an empty field is a plain type, a changed field stops the turn, words that don't replace append

private func fix132bCaretReplaceGuardTests() {
    // An empty field: nothing is erased, so a plain type card and no select-all.
    do {
        let rig = f132bRig()
        let turn = f132bTurn("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘")
        rig.queueData([("see", f132bLook("", selection: (0, 0))), ("see", f132bLook("", selection: (0, 0))), ("type", v2pb("type-unverified")),
                       ("see", f132bLook("교체된 내용", selection: (6, 0)))])
        _ = f132bType(rig, "교체된 내용", turn: turn)
        let shown = turn.cards.map(f132bCard)
        check(turn.cards.count == 1 && shown[0].hasPrefix("TextEdit에서 입력하기") && !shown[0].contains("지워지는 글") && !rig.calls.contains { $0.hasPrefix("press cmd+a") },
              "fix132b guard: an empty field is a plain type (\(shown), \(rig.calls))")
    }
    // The field changed after the card (the select-all reads other text): nothing typed, the turn records it.
    do {
        let rig = f132bRig()
        let turn = f132bTurn("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘")
        let end = f132bDoc.utf16.count
        let changed = "Changed after the card appeared."
        rig.queueData([("see", f132bLook(f132bDoc, selection: (end, 0))), ("see", f132bLook(f132bDoc, selection: (end, 0))), ("press", v2pb("press-return")),
                       ("see", f132bLook(changed, selection: (0, changed.utf16.count))), ("type", v2pb("type-unverified")), ("see", f132bLook("교체된 내용", selection: (6, 0)))])
        let stopped = f132bType(rig, "교체된 내용", turn: turn)
        check(stopped.status != 0 && stopped.output.contains("NOT DONE") && !rig.calls.contains { $0.hasPrefix("type") } && turn.ledger.fieldChangedThisTurn,
              "fix132b guard: a field that changed after the replace card types nothing and stops the turn (\(stopped.output.prefix(200)), \(rig.calls))")
    }
    // Words that only write (no erase or replace): the caret's type adds, as before, with no erase on the card.
    do {
        let rig = f132bRig()
        let turn = f132bTurn("이 문서에 '새 줄'이라고 써 줘")
        let end = f132bDoc.utf16.count
        rig.queueData([("see", f132bLook(f132bDoc, selection: (end, 0))), ("see", f132bLook(f132bDoc, selection: (end, 0))), ("type", v2pb("type-unverified")),
                       ("see", f132bLook(f132bDoc + "새 줄", selection: (end + 3, 0)))])
        _ = f132bType(rig, "새 줄", turn: turn)
        let shown = turn.cards.map(f132bCard)
        check(turn.cards.count <= 1 && !(shown.first ?? "").contains("지워지는 글") && !rig.calls.contains { $0.hasPrefix("press cmd+a") },
              "fix132b guard: writing without erase words still adds at the caret (\(shown), \(rig.calls))")
    }
    // A selection is still the selection's replace (not everything).
    do {
        let rig = f132bRig()
        let turn = f132bTurn("이거 '체리'로 바꿔 줘")
        rig.queueData([("see", f132bLook(f132bDoc, selection: (6, 6))), ("see", f132bLook(f132bDoc, selection: (6, 6))), ("type", v2pb("type-unverified")),
                       ("see", f132bLook("Apple 체리 grape cherry.\nSecond line stays here.", selection: (8, 0)))])
        _ = f132bType(rig, "체리", turn: turn)
        let shown = turn.cards.map(f132bCard)
        check(turn.cards.count == 1 && shown[0].contains("⚠️ 선택한 글을 지우고") && shown[0].contains("지워지는 글:\nbanana") && !shown[0].contains("모두 지우고"),
              "fix132b guard: a selection is replaced alone, as before (\(shown))")
    }
}

// MARK: - 1. Only words that ask for all of it replace everything; a part to replace on a bare caret types nothing

private func fix132bPartialAtCaretTests() {
    let all = ["이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘", "다 지우고 '새 글' 입력해 줘", "싹 지우고 안녕이라고 써 줘", "내용을 전부 '새 글'로 바꿔 줘",
               "모두 삭제하고 '새 글'이라고 써 줘", "전체 지우고 써 줘", "Delete all the text in this document and write 'replaced content'",
               "replace everything with hello", "clear the whole document and type hi", "erase the entire text and write hi",
               "TextEdit에서 command+A로 전체 선택한 다음 '새 글 15'라고 입력해 줘", "select all and type hello"]
    let part = ["이거 '체리'로 바꿔 줘", "banana를 cherry로 바꿔 줘", "제목을 '새 제목'으로 바꿔 줘", "Replace banana with cherry", "replace all occurrences of cat with dog",
                "이 단어 지우고 '사과'라고 써 줘", "delete the last word and type hi"]
    check(all.allSatisfy(ArisDesktopBatch.asksToReplaceAll), "fix132b all: words that ask for all of it are told (\(all.filter { !ArisDesktopBatch.asksToReplaceAll($0) }))")
    check(!part.contains(where: ArisDesktopBatch.asksToReplaceAll), "fix132b all: words that replace a part are not (\(part.filter(ArisDesktopBatch.asksToReplaceAll)))")
    let end = f132bDoc.utf16.count
    for (request, text) in [("이거 '체리'로 바꿔 줘", "체리"), ("Replace banana with cherry", "cherry")] {
        // A part to replace, and only a caret: refused before any card, nothing typed or pressed, never widened to everything.
        let rig = f132bRig()
        let turn = f132bTurn(request)
        rig.queueData([("see", f132bLook(f132bDoc, selection: (end, 0))), ("see", f132bLook(f132bDoc, selection: (end, 0))), ("type", v2pb("type-unverified")),
                       ("see", f132bLook(f132bDoc + text, selection: (end + text.utf16.count, 0)))])
        let refused = f132bType(rig, text, turn: turn)
        check(refused.status != 0 && refused.output.contains(ArisDesktopErase.partialAtCaretLine) && turn.cards.isEmpty
              && !rig.calls.contains { $0.hasPrefix("type") || $0.hasPrefix("press") } && turn.ledger.actionsThisTurn.notDone == 1 && !turn.ledger.actionsThisTurn.done,
              "fix132b part: “\(request)” on a bare caret is refused with no card and nothing typed (\(refused.output.prefix(160)), \(turn.cards.map(f132bCard)), \(rig.calls))")
    }
    check(ArisDesktopErase.partialAtCaretLine.contains("Nothing was typed") && ArisDesktopErase.partialAtCaretLine.contains("Select exactly the text to replace first")
          && ArisDesktopErase.partialAtCaretLine.contains("ask the user"), "fix132b part: the brain is told to select the text first, or ask")
    // The same words on an empty field: nothing to replace, a plain type.
    let rig = f132bRig()
    let turn = f132bTurn("이거 '체리'로 바꿔 줘")
    rig.queueData([("see", f132bLook("", selection: (0, 0))), ("see", f132bLook("", selection: (0, 0))), ("type", v2pb("type-unverified")),
                   ("see", f132bLook("체리", selection: (2, 0)))])
    let typed = f132bType(rig, "체리", turn: turn)
    check(typed.status == 0 && turn.cards.count == 1 && !f132bCard(turn.cards[0]).contains("지워지는 글") && rig.calls.contains { $0.hasPrefix("type") },
          "fix132b part: on an empty field it is a plain type (\(typed.output.prefix(120)), \(turn.cards.map(f132bCard)))")
}

// MARK: - 2. "command+A로 전체 선택한 다음 …라고 입력해 줘" is one replace card

private func fix132bSelectAllWordsTests() {
    let replaces = ["TextEdit에서 command+A로 전체 선택한 다음 '새 글 15'라고 입력해 줘", "전체선택하고 안녕이라고 써 줘", "모두 선택해서 '새 글' 입력해 줘",
                    "select all and type hello", "Select everything, then write 'new text'", "press cmd+a and type hello"]
    let not = ["전체 선택해서 복사해 줘", "select all and copy it", "이 문서 전부 선택해 줘", "cmd+a 눌러 줘", "이 문서에 '새 줄'이라고 써 줘", "type hello at the end"]
    check(replaces.allSatisfy(ArisDesktopBatch.asksToReplace), "fix132b select-all: “select all, then write X” asks to replace (\(replaces.filter { !ArisDesktopBatch.asksToReplace($0) }))")
    check(!not.contains(where: ArisDesktopBatch.asksToReplace), "fix132b select-all: a select-all to copy, or writing alone, does not (\(not.filter(ArisDesktopBatch.asksToReplace)))")
    // R1e: `press cmd+a` then `aris-tools type '새 글 15'`: the select-all is held back, then one replace card.
    let rig = f132bRig()
    let turn = f132bTurn("TextEdit에서 command+A로 전체 선택한 다음 '새 글 15'라고 입력해 줘")
    let end = f132bDoc.utf16.count
    rig.queueData([("see", f132bLook(f132bDoc, selection: (end, 0)))])
    let first = f132bRun(rig, ["press", "cmd+a", "--app", "TextEdit"], turn: turn)
    check(first.status == 0 && first.output.contains(ArisDesktopErase.heldLead) && turn.cards.isEmpty && !rig.calls.contains { $0.hasPrefix("press") },
          "fix132b select-all: R1e's lone ⌘A is held back, not a key card of its own (\(first.output.prefix(120)), \(turn.cards.map(f132bCard)))")
    rig.queueData([("see", f132bLook(f132bDoc, selection: (end, 0))), ("see", f132bLook(f132bDoc, selection: (end, 0))), ("press", v2pb("press-return")),
                   ("see", f132bLook(f132bDoc, selection: (0, end))), ("type", v2pb("type-unverified")), ("see", f132bLook("새 글 15", selection: (6, 0)))])
    let typed = f132bType(rig, "새 글 15", turn: turn)
    let shown = turn.cards.map(f132bCard)
    check(typed.status == 0 && turn.cards.count == 1 && shown[0].hasPrefix("TextEdit에서 글 바꾸기") && shown[0].contains("지워지는 글:\n" + f132bDoc)
          && rig.calls.contains { $0.hasPrefix("press cmd+a") } && rig.calls.filter { $0.hasPrefix("type") }.count == 1,
          "fix132b select-all: then one replace card, and the text is typed over, never refused (\(shown), \(typed.output.prefix(160)), \(rig.calls))")
}

// MARK: - 3. A typed 허용 answers a card, as a spoken one does

private func fix132bTypedAnswerTests() {
    for yes in ["허용", "허용해", "허용해 줘", "허용이요", "진행해", "진행해 주세요", "실행해", "그렇게 해", "해도 돼", "run it", "allow it", "Allow", "proceed", "go for it"] {
        check(ArisCardWait.typedAnswer(yes, cardUp: true) == true, "fix132b typed: “\(yes)” answers the card yes")
    }
    for no in ["그만", "그만해", "멈춰", "멈추기", "안 돼", "stop", "nah", "never mind", "not now"] {
        check(ArisCardWait.typedAnswer(no, cardUp: true) == false, "fix132b typed: “\(no)” answers the card no, as it does spoken")
    }
    for turn in ["허용?", "허용 안 해", "허용하지 마", "허용해 주고 메일도 확인해 줘", "진행 상황 알려 줘", "run it later today", "allow notifications for Slack",
                 "허용 범위가 뭐야", "stop the music"] {
        check(ArisCardWait.typedAnswer(turn, cardUp: true) != true, "fix132b typed: “\(turn)” never answers the card yes")
    }
    check(ArisCardWait.typedAnswer("허용", cardUp: false) == nil, "fix132b typed: with no card up, “허용” is an ordinary turn")
}

// MARK: - 4. A to-do's or a note's own words are one line on its card, colon or not

private func fix132bOwnWordsRowTests() {
    let title = "서울 날씨: 지금 화씨 52도 대체로 맑음, 오늘 42~58도 흐림, 내일 비 올 확률 57퍼센트"
    check(ArisCardEnglish.keepsLineWhole(title, title: "할 일에 넣기") && ArisCardEnglish.keepsLineWhole(title, title: "Add to-do")
          && ArisCardEnglish.keepsLineWhole("1. " + title, title: "할 일에 넣기") && ArisCardEnglish.keepsLineWhole("시간: 3시", title: "메모 만들기"),
          "fix132b rows: a to-do's (or a note's) own words with a colon stay one line (K1t2)")
    check(!ArisCardEnglish.keepsLineWhole("목록: 집", title: "할 일에 넣기") && !ArisCardEnglish.keepsLineWhole("기한: 내일", title: "할 일에 넣기")
          && !ArisCardEnglish.keepsLineWhole("List: Home", title: "Add to-do") && !ArisCardEnglish.keepsLineWhole("제목: " + title, title: "메모 만들기")
          && !ArisCardEnglish.keepsLineWhole("--priority: high", title: "할 일에 넣기"),
          "fix132b rows: the card's own labels (list, due, a note's title, a flag) stay label / value rows")
    check(!ArisCardEnglish.keepsLineWhole("받는 사람: 엄마", title: "메시지 보내기") && !ArisCardEnglish.keepsLineWhole(title, title: "명령 실행"),
          "fix132b rows: every other card's rows are as before")
    let card = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private/Aris/Home/ArisConfirmCard.swift").standardized, encoding: .utf8)) ?? ""
    check(card.contains("Self.rows(english ? ArisCardEnglish.detail(text, title: question.title) : text, title: question.title)")
          && card.contains("if ArisCardEnglish.keepsLineWhole(String(line), title: title) { return (nil, String(line)) }"),
          "fix132b rows: the confirm card cuts its rows with the card's title")
}
