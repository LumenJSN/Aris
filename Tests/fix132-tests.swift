// Tests for jv-fix132: the fourteenth real-screen VM check of 1.3.1 (d3387ee7), default configuration. The desktop
// calls are the ones recorded in notes14 (R1b, R1b2/R1c, R1e2), run on desktop-v2-tests' rig (fake Peekaboo, recorded
// fixtures) with TextEdit's shape; nothing touches a real app or the screen. Called from main.swift; uses its check().
import CoreGraphics
import Foundation

func runFix132Tests() {
    fix132KeysRequestTests()
    fix132KeysGateTests()
    fix132ReplaceOneCardTests()
    fix132FieldChangedTests()
    fix132FieldChangedGateTests()
    fix132BalanceTests()
    fix132UndoKindTests()
    fix132SmallTests()
}

private let f132Edit = ArisDesktopTarget(name: "TextEdit", bundle: "com.apple.TextEdit", pid: 4242, known: true, never: false, browser: false, sending: false,
                                         appleSigned: true)
private let f132Window = ArisDesktopWindow(id: 9189, frame: CGRect(x: 80, y: 329, width: 1040, height: 720), title: "Untitled")
private let f132Doc = "Apple banana grape cherry.\nSecond line stays here."
private let f132Tools = "/Users/admin/.config/aris/aris-tools"

private func f132Rig() -> V2Rig {
    let rig = V2Rig()
    rig.apps.apps["textedit"] = f132Edit
    rig.apps.apps["com.apple.textedit"] = f132Edit
    rig.windows.byPid[4242] = [f132Window]
    return rig
}

/// see-chat as TextEdit's Untitled: its text view (elem_59) holds `value`, with `selection` (UTF-16 location, length).
private func f132Look(_ value: String, selection: (Int, Int)?) -> Data {
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

/// A live screen turn (as the VM's), cards answered yes; the desktop route's ledger bookkeeping done as the route does it.
private final class F132Turn: ArisDesktopTurn {
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

private func f132Turn(_ request: String) -> F132Turn {
    let turn = F132Turn()
    turn.request = request
    turn.ledger.startTurn()
    return turn
}

/// One desktop call, with the ledger kept as ArisDesktopRoutes keeps it for an action (started, then ended or held).
private func f132Run(_ rig: V2Rig, _ words: [String], text: String? = nil, turn: F132Turn) -> ArisMCPOutcome {
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

/// `aris-tools type '<text>' --app TextEdit --title Untitled`, as the VM's brain called it.
private func f132Type(_ rig: V2Rig, _ text: String, turn: F132Turn) -> ArisMCPOutcome {
    guard case .success(let call) = ArisTypeRequest.call([text, "--app", "TextEdit", "--title", "Untitled"], keyboardApp: nil) else { return .failed("the call") }
    return f132Run(rig, call.words, text: call.text, turn: turn)
}

/// `aris-tools keys <chords> --app TextEdit --title Untitled` as aris-tools now hands it to the engine (ArisKeysRequest).
private func f132Keys(_ rig: V2Rig, _ chords: [String], turn: F132Turn) -> ArisMCPOutcome {
    guard case .success(let call) = ArisKeysRequest.parse(chords + ["--app", "TextEdit", "--title", "Untitled"]),
          case .success(let words) = ArisKeysRequest.desktopWords(call, keyboardApp: nil) else { return .failed("the call") }
    return f132Run(rig, words, turn: turn)
}

private func f132Source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func f132Card(_ card: ArisMCPCard) -> String { card.title + "\n" + (card.full ?? card.detail) }

// MARK: - 1. `keys` reads every chord, and only plain erasing keys go to the engine

private func fix132KeysRequestTests() {
    // R1b: aris-tools read only the first chord of `keys cmd+a delete`, so on the card's yes only cmd+a was sent.
    if case .success(let call) = ArisKeysRequest.parse(["cmd+a", "delete", "--app", "TextEdit", "--title", "Untitled"]) {
        check(call.chords == ["cmd+a", "delete"] && call.app == "TextEdit" && call.title == "Untitled" && call.times == 1,
              "fix132 keys: every chord given is read, with the app and the window (\(call))")
        let words = ArisKeysRequest.desktopWords(call, keyboardApp: nil)
        check(words == .success(["press", "cmd+a", "delete", "--app", "TextEdit", "--title", "Untitled"]),
              "fix132 keys: erasing keys become the engine's one `desktop press` with both chords (\(words))")
    } else {
        check(false, "fix132 keys: `cmd+a delete --app TextEdit --title Untitled` parses")
    }
    check(ArisKeysRequest.parse(["cmd+a", "--times", "3", "--app", "Notes"]).map(\.times) == .success(3)
          && ArisKeysRequest.parse(["--app", "Notes"]).map(\.times) == .failure(ArisKeysRequestError(line: ArisKeysRequest.usage))
          && ArisKeysRequest.parse(["cmd+a", "--window-id", "3"]).map(\.times) == .failure(ArisKeysRequestError(line: "keys doesn't take --window-id. " + ArisKeysRequest.usage))
          && ArisKeysRequest.parse(Array(repeating: "a", count: 9)).map(\.times) == .failure(ArisKeysRequestError(line: ArisKeysRequest.usage)),
          "fix132 keys: flags, a missing chord, an unknown flag and too many chords are read as before")
    // An allowlist: only a bare select-all and bare deleting keys; cmd+delete (Finder's move to the Trash) stays the gate's.
    check(ArisKeysRequest.erases(["cmd+a", "delete"]) && ArisKeysRequest.erases(["delete", "delete"]) && ArisKeysRequest.erases(["command+a", "backspace"])
          && ArisKeysRequest.erases(["cmd+a"]), "fix132 keys: a select-all and bare deletes are erasing keys")
    check(!ArisKeysRequest.erases(["cmd+delete"]) && !ArisKeysRequest.erases(["cmd+a", "cmd+delete"]) && !ArisKeysRequest.erases(["option+delete"])
          && !ArisKeysRequest.erases(["shift+delete"]) && !ArisKeysRequest.erases(["cmd+a", "cmd+v"]) && !ArisKeysRequest.erases(["return"]) && !ArisKeysRequest.erases([]),
          "fix132 keys: anything else (cmd+delete, a paste, return) is not")
    if case .success(let call) = ArisKeysRequest.parse(["delete", "--times", "5"]) {
        check(ArisKeysRequest.desktopWords(call, keyboardApp: "com.apple.TextEdit") == .success(["press"] + Array(repeating: "delete", count: 5) + ["--app", "com.apple.TextEdit"])
              && ArisKeysRequest.desktopWords(call, keyboardApp: nil) == .failure(ArisKeysRequestError(line: ArisKeysRequest.noAppLine)),
              "fix132 keys: repeats are pressed as many times, in the app with the keyboard; with none named or found, nothing")
    }
    if case .success(let call) = ArisKeysRequest.parse(["delete", "--times", "20", "--app", "TextEdit"]) {
        check(ArisKeysRequest.desktopWords(call, keyboardApp: nil) == .failure(ArisKeysRequestError(line: ArisKeysRequest.usage))
              && !ArisKeysRequest.fitsEngine(call) && !ArisKeysRequest.handsToEngine(["keys", "delete", "--times", "20", "--app", "TextEdit"]),
              "fix132 keys: more presses than one engine press takes stay the shell gate's (its card), never cut short")
    }
}

// MARK: - 1. The shell gate leaves erasing keys to the engine's one card; other keys keep its card

private func fix132KeysGateTests() {
    let home = FileManager.default.temporaryDirectory.path
    let risk = { (line: String, critical: Bool) in
        ArisRiskPolicy.risk(of: .shell("\(f132Tools) \(line)"), tools: f132Tools, home: home, critical: critical, request: "이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘")
    }
    check(risk("keys cmd+a delete --app TextEdit --title Untitled", true) == .auto,
          "fix132 gate: R1b's `keys cmd+a delete` puts up no raw \"Press keys\" card of its own (the engine's erase card is the one)")
    check(risk("keys cmd+delete --app Finder", true) == .confirm && risk("keys cmd+v --app TextEdit", true) == .confirm
          && risk("keys cmd+delete --app Finder", false) == .confirm && risk("keys return --app Terminal", false) == .confirm,
          "fix132 gate: any other keys keep the shell gate's card as before")
    check(!ArisRiskPolicy.asksAfterOutsideText(.shell("\(f132Tools) keys cmd+a delete --app TextEdit"), tools: f132Tools)
          && ArisRiskPolicy.asksAfterOutsideText(.shell("\(f132Tools) keys cmd+v --app TextEdit"), tools: f132Tools),
          "fix132 gate: after outside text, erasing keys are the engine's card (which shows the erased text); other keys still ask")
    check(ArisKeysRequest.handsToEngine(["keys", "cmd+a", "delete", "--app", "TextEdit"]) && !ArisKeysRequest.handsToEngine(["keys", "cmd+delete", "--app", "Finder"])
          && !ArisKeysRequest.handsToEngine(["type", "cmd+a"]) && !ArisKeysRequest.handsToEngine(["keys", "cmd+a", "--bogus", "x"]),
          "fix132 gate: only a well-formed erasing `keys` call is handed to the engine")
}

// MARK: - 1. "전부 지우고 '…'라고 써 줘" is one replace card, whichever way the brain erases first

private func fix132ReplaceOneCardTests() {
    let all = f132Doc.utf16.count
    for (request, text, korean) in [("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘", "교체된 내용", true),
                                    ("Delete all the text in this document and write 'replaced content'", "replaced content", false)] {
        // R1b / R1e2: `aris-tools keys cmd+a delete --app TextEdit --title Untitled`, then `aris-tools type '<text>' …`.
        let rig = f132Rig()
        let turn = f132Turn(request)
        rig.queueData([("see", f132Look(f132Doc, selection: (0, 0)))])
        let first = f132Keys(rig, ["cmd+a", "delete"], turn: turn)
        check(first.status == 0 && turn.cards.isEmpty && !rig.calls.contains { $0.hasPrefix("press") } && first.output.contains(ArisDesktopErase.heldLead),
              "fix132 replace: `cmd+a delete` with new text to write is held back, not a card of its own (\(korean), \(turn.cards.map(f132Card)), \(rig.calls))")
        check(turn.ledger.actionsThisTurn.notDone == 0 && !turn.ledger.actionsThisTurn.done,
              "fix132 replace: the held keys count as neither done nor not done (\(turn.ledger.actionsThisTurn))")
        rig.queueData([("see", f132Look(f132Doc, selection: (0, 0))), ("see", f132Look(f132Doc, selection: (0, 0))), ("press", v2pb("press-return")),
                       ("see", f132Look(f132Doc, selection: (0, all))), ("type", v2pb("type-unverified")), ("see", f132Look(text, selection: (text.utf16.count, 0)))])
        let second = f132Type(rig, text, turn: turn)
        let shown = turn.cards.map(f132Card)
        let lead = korean ? "TextEdit에서 글 바꾸기" : "Replace text in TextEdit"
        let erased = korean ? "지워지는 글:\n" : "Text that is erased:\n"
        check(second.status == 0 && turn.cards.count == 1 && shown[0].hasPrefix(lead) && shown[0].contains(erased + f132Doc) && shown[0].contains(text)
              && !shown[0].contains("--app") && !shown[0].contains("cmd+a delete"),
              "fix132 replace: exactly one card, the replace with the whole erased text and the new text, no raw arguments (\(korean), \(shown))")
        check(rig.calls.contains { $0.hasPrefix("press cmd+a") } && rig.calls.filter { $0.hasPrefix("type") }.count == 1,
              "fix132 replace: on its yes everything is selected and typed over (\(rig.calls), \(second.output.prefix(120)))")
    }
    // Only erasing ("전부 지워 줘"): `cmd+a delete` is its own erase card with the whole text, at once, as before.
    let rig = f132Rig()
    let turn = f132Turn("이 문서 글 전부 지워 줘")
    // fix132d: the select-all is pressed on its own and read back (all of it selected) before the delete goes.
    rig.queueData([("see", f132Look(f132Doc, selection: (0, 0))), ("see", f132Look(f132Doc, selection: (0, 0))), ("press", v2pb("press-return")),
                   ("see", f132Look(f132Doc, selection: (0, f132Doc.utf16.count))), ("press", v2pb("press-return")), ("see", f132Look("", selection: (0, 0)))])
    let erased = f132Keys(rig, ["cmd+a", "delete"], turn: turn)
    let card = turn.cards.first.map(f132Card) ?? ""
    check(turn.cards.count == 1 && card.hasPrefix("TextEdit에서 글 지우기") && card.contains("지워지는 글:\n" + f132Doc) && erased.status == 0
          && rig.calls.contains { $0.hasPrefix("press cmd+a --snapshot") } && rig.calls.contains { $0.hasPrefix("press delete --snapshot") },
          "fix132 replace: erasing only is one erase card with the whole text (\(turn.cards.map(f132Card)), \(rig.calls))")
    // His words: what goes in its place is given ("…라고 써 줘", "…로 바꿔 줘", "write …", "replace it with …"), or not.
    let writes = ["이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘", "전부 지우고 안녕으로 바꿔 줘", "다 지우고 '새 글' 입력해 줘",
                  "Delete all the text in this document and write 'replaced content'", "clear it and replace it with hello"]
    let erasesOnly = ["이 문서 글 전부 지워 줘", "다 지워", "Delete all the text in this document", "clear everything"]
    check(writes.allSatisfy(ArisDesktopErase.writesNewText) && !erasesOnly.contains(where: ArisDesktopErase.writesNewText),
          "fix132 replace: words that give the new text are told from words that only erase (\(writes.filter { !ArisDesktopErase.writesNewText($0) }), \(erasesOnly.filter(ArisDesktopErase.writesNewText)))")
}

// MARK: - 2. "The field changed": nothing more acts in the turn, and the reply says nothing was changed

private func fix132FieldChangedTests() {
    // R1c: the type's replace card showed the whole text; the text changed before the yes ("Changed after the card appeared.").
    let rig = f132Rig()
    let turn = f132Turn("이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘")
    rig.queueData([("see", f132Look(f132Doc, selection: (0, 0)))])
    _ = f132Keys(rig, ["cmd+a", "delete"], turn: turn)
    let changed = "Changed after the card appeared."
    rig.queueData([("see", f132Look(f132Doc, selection: (0, 0))), ("see", f132Look(changed, selection: (changed.utf16.count, 0))),
                   ("press", v2pb("press-return")), ("type", v2pb("type-unverified")), ("see", f132Look("교체된 내용", selection: (6, 0)))])
    let stopped = f132Type(rig, "교체된 내용", turn: turn)
    check(stopped.status != 0 && stopped.output.contains("NOT DONE") && !stopped.output.contains("Make the same call again")
          && stopped.output.contains("make no other change in this turn") && !rig.calls.contains { $0.hasPrefix("type") },
          "fix132 changed: nothing typed, and the brain is told the request stops here, never to make the same call again (\(stopped.output.prefix(300)))")
    check(turn.ledger.fieldChangedThisTurn && turn.ledger.fieldChangeThisTurn == false,
          "fix132 changed: the turn records that its field changed with nothing done before it")
    // The model re-proposed at once (R1b2: a third card): now refused, with no card and nothing pressed or typed.
    let cards = turn.cards.count
    let calls = rig.calls.count
    rig.queueData([("see", f132Look(changed, selection: (changed.utf16.count, 0))), ("see", f132Look(changed, selection: (changed.utf16.count, 0)))])
    let again = f132Type(rig, "교체된 내용", turn: turn)
    let pressed = f132Run(rig, ["press", "cmd+a", "delete", "--app", "TextEdit"], turn: turn)
    check(again.status != 0 && pressed.status != 0 && again.output.contains(ArisDesktopErase.afterChangedLine) && pressed.output == ArisDesktopErase.afterChangedLine
          && turn.cards.count == cards && !rig.calls.dropFirst(calls).contains { $0.hasPrefix("type") || $0.hasPrefix("press") },
          "fix132 changed: every acting call after it in the turn is refused, with no new card (\(turn.cards.count - cards) new cards, \(again.output.prefix(160)))")
    // A look still runs (the brain may say what the field holds now).
    rig.queueData([("see", f132Look(changed, selection: (0, 0)))])
    let look = f132Run(rig, ["see", "--app", "TextEdit"], turn: turn)
    check(look.status == 0, "fix132 changed: a look still runs after it (\(look.output.prefix(120)))")
    // A new turn starts clean.
    turn.ledger.startTurn()
    check(!turn.ledger.fieldChangedThisTurn && turn.ledger.fieldChangeThisTurn == nil, "fix132 changed: the next turn acts again")
    // The reply is built from what happened (R1c's said "문서는 비웠지만…" when nothing was erased).
    let false1 = "문서는 비웠지만 '교체된 내용'은 입력하지 못했어요."
    let fixed = ArisDesktopHonesty.fieldChanged(false1, changed: false, korean: true)
    check(fixed.contains("아무것도 바꾸지 않았어요") && fixed.contains("다시 할까요") && !fixed.contains("비웠"),
          "fix132 changed: the reply says nothing was changed and asks whether to try again (\(fixed))")
    let english = ArisDesktopHonesty.fieldChanged("I cleared the document but couldn't type the text.", changed: false, korean: false)
    check(english.hasPrefix("Nothing was changed") && !english.contains("cleared"), "fix132 changed: in English too (\(english))")
    let after = ArisDesktopHonesty.fieldChanged("다 바꿨어요.", changed: true, korean: true)
    check(after.contains("그 뒤로는 아무것도 바꾸지 않았어요") && !after.contains("다 바꿨어요"), "fix132 changed: after an earlier step, it says nothing more was changed (\(after))")
    check(ArisDesktopHonesty.fieldChanged("교체된 내용으로 바꿨어요.", changed: nil, korean: true) == "교체된 내용으로 바꿨어요.",
          "fix132 changed: a turn whose field didn't change keeps its reply")
}

/// The shell gates refuse what would ask next, once the field changed (the default path's API gate and Codex's).
private func fix132FieldChangedGateTests() {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix132-gate-\(UUID().uuidString)").path
    let gate = ArisAPIGate(tools: f132Tools, home: home)
    gate.request = "이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘"
    gate.tier = .critical
    let line = "\(f132Tools) keys cmd+v --app TextEdit"
    var asked = false
    if case .ask = gate.judge(line) { asked = true }
    nonisolated(unsafe) var stopped = true
    gate.stopsActing = { stopped }
    var refused = false
    if case .deny(_, let reason) = gate.judge(line) { refused = reason.contains(ArisDesktopErase.gateStopLine) }
    stopped = false
    var askedAgain = false
    if case .ask = gate.judge(line) { askedAgain = true }
    check(asked && refused && askedAgain, "fix132 changed: the API brain's gate refuses a call that would ask, only while the turn's field changed (\(asked), \(refused), \(askedAgain))")
    let source = f132Source("ArisAgent/ArisAgentRunner.swift")
    check(source.contains("gate.stopsActing = { [computerUse] in computerUse.fieldChangedThisTurn }")
          && source.contains("answer = ArisDesktopHonesty.fieldChanged(answer, changed: computerUse.fieldChangeThisTurn, korean: koreanRequest)"),
          "fix132 changed: the runner wires the ledger to the API gate and builds the reply from it")
    let codex = f132Source("ArisAgent/ArisCodexDriver.swift")
    check(codex.contains("computerUse.fieldChangedThisTurn { refuse(ArisDesktopErase.gateStopLine) }"), "fix132 changed: and Codex's gate does the same")
}

// MARK: - 3. An empty account is not a temporary limit

private func fix132BalanceTests() {
    func said(_ event: ArisBrainEvent) -> String {
        switch event {
        case .failure(let text): return "failure:" + text
        case .unavailable(let text): return "unavailable:" + text
        default: return "?"
        }
    }
    func kind(_ status: Int, _ body: String) -> ArisAPIError.Kind { ArisAPIError.http(status: status, body: Data(body.utf8), headers: [:]).kind }
    // Each provider's empty-account answer (X2: DeepSeek's "Insufficient Balance" was shown as a limit to wait out).
    let empty: [(String, Int, String)] = [
        ("DeepSeek", 402, #"{"error":{"message":"Insufficient Balance","type":"unknown_error","param":null,"code":"invalid_request_error"}}"#),
        ("OpenAI", 429, #"{"error":{"message":"You exceeded your current quota, please check your plan and billing details.","type":"insufficient_quota","param":null,"code":"insufficient_quota"}}"#),
        ("Anthropic", 400, #"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."}}"#),
        ("OpenRouter", 402, #"{"error":{"message":"Insufficient credits. Add more using https://openrouter.ai/settings/credits","code":402}}"#),
        ("Gemini", 400, #"{"error":{"code":400,"message":"Gemini API free tier is not available in your country. Please enable billing on your project in Google AI Studio.","status":"FAILED_PRECONDITION"}}"#),
        ("Gemini", 403, #"{"error":{"code":403,"message":"This API method requires billing to be enabled. Please enable billing on project #1234 by visiting the console.","status":"PERMISSION_DENIED"}}"#)]
    for (provider, status, body) in empty {
        check(kind(status, body) == .billing, "fix132 balance: \(provider)'s empty account (\(status)) is read as no balance (\(kind(status, body)))")
    }
    // Waiting helps for these: they stay limits, and a bad key stays a key.
    check(kind(429, #"{"error":{"message":"Rate limit reached for gpt-4o in organization org-x on tokens per min"}}"#) == .rate
          && kind(429, #"{"error":{"code":429,"message":"Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 15","status":"RESOURCE_EXHAUSTED"}}"#) == .quota
          && kind(401, #"{"error":{"message":"Invalid API key"}}"#) == .auth && kind(403, #"{"error":{"message":"Forbidden"}}"#) == .auth,
          "fix132 balance: a rate limit, a per-minute quota and a refused key are not an empty account")
    check(ArisAPIError.streamed(["error": ["type": "insufficient_quota", "message": "You exceeded your current quota, please check your plan and billing details."]]).kind == .billing
          && ArisAPIError.streamed(["error": ["type": "rate_limit_error", "message": "Number of request tokens has exceeded your per-minute rate limit"]]).kind == .rate,
          "fix132 balance: an error inside a stream is told apart the same way")
    // The line: the account is out of credit, never "wait a while"; both languages; none of the provider's words.
    for driverSaid in [said(ArisMindBrainDriver.failure(kind: "billing", message: "Insufficient Balance (key sk-abcdefghij0000, request_id: 218f87a1)", title: "DeepSeek"))] {
        let line = driverSaid.replacingOccurrences(of: "unavailable:", with: "").replacingOccurrences(of: "failure:", with: "")
        check(line == ArisAPIFailureWords.line(.balance, title: "DeepSeek", english: false) && line.contains("잔액") && !line.contains("한도") && !line.contains("잠시 뒤")
              && !line.contains("0000") && !line.contains("218f87a1"),
              "fix132 balance: Core 2's driver says DeepSeek's balance is used up, in Aris's own words (\(driverSaid))")
        let korean = ArisBrainFailure.friendly(line, brain: .api, korean: true)
        let english = ArisBrainFailure.friendly(line, brain: .api, korean: false)
        check(korean == line && english == ArisAPIFailureWords.line(.balance, title: "DeepSeek", english: true) && english.contains("credit") && !english.contains("limit")
              && !english.contains("try again in"),
              "fix132 balance: the notch keeps that line (no limit line), in the request's language (\(korean) / \(english))")
        check(ArisBrainFix.fix(forLine: korean, another: { _ in nil }) == .settings(.brain) && ArisBrainFix.fix(forLine: english, another: { _ in .claude }) == .settings(.brain),
              "fix132 balance: its chip opens the AI settings (topping up or another AI is the fix, not trying again)")
    }
    check(ArisAPIFailureWords.kind(.billing) == .balance && ArisAPIFailureWords.english(ArisAPIFailureWords.line(.balance, title: "Groq", english: false))
          == ArisAPIFailureWords.line(.balance, title: "Groq", english: true), "fix132 balance: the Korean line reads back into English")
    // The default path's API driver (Core 2 off) says the same.
    let source = f132Source("ArisAgent/ArisAPIDriver.swift")
    check(source.contains("case .billing:") && source.contains("ArisAPIFailureWords.line(.balance, title: title, english: false)"),
          "fix132 balance: the API driver words an empty account as such too")
    // Another brain's own words for it (Claude Code with an API key, a CLI's stderr) get the same kind of line.
    let claude = ArisBrainFailure.friendly("Credit balance is too low", brain: .claude, korean: true)
    check(claude.contains("잔액") && !claude.contains("한도"), "fix132 balance: any brain's empty account is said as such (\(claude))")
    check(ArisAPISmoke.message(ArisAPIError(kind: .billing, message: "balance: x")).contains("잔액"), "fix132 balance: the Settings connection test says so too")
}

// MARK: - 6. Undo by kind

private func fix132UndoKindTests() {
    typealias W = ArisUndoWords
    let now = Date()
    func change(_ summary: String, _ action: String, ago: TimeInterval) -> W.Change {
        W.Change(id: UUID().uuidString, date: now.addingTimeInterval(-ago), summary: summary, action: action, asks: false, undoable: true)
    }
    let since = now.addingTimeInterval(-900)
    // X7: the rename was undone already; the newest is the taught run's typing. "방금 이름 바꾼 거 되돌려 줘".
    let typed = change("입력: TextEdit", "made", ago: 30)
    let event = change("일정 추가: 회의", "made", ago: 400)
    let x7 = W.reach([typed, event], since: since, kind: W.kind(in: "방금 이름 바꾼 거 되돌려 줘"), named: W.named(in: "방금 이름 바꾼 거 되돌려 줘"))
    check(x7 == .noneOfKind([W.Candidate(id: typed.id, summary: typed.summary, action: "made"), W.Candidate(id: event.id, summary: event.summary, action: "made")]),
          "fix132 undo: a rename asked for with none left is not taken for the newest typing (\(x7))")
    // X4: "방금 일정 지운 거 되돌려 줘" with a rename and an event added (no event removed, ever).
    let rename = change("이름 바꿈: rename-me.txt → renamed14x.txt", "changed", ago: 60)
    let x4 = W.reach([rename, event], since: since, kind: W.kind(in: "방금 일정 지운 거 되돌려 줘"), named: W.named(in: "방금 일정 지운 거 되돌려 줘"))
    if case .noneOfKind(let others) = x4 { check(others.first?.id == rename.id, "fix132 undo: X4 finds no removed event; the newest is offered next") }
    else { check(false, "fix132 undo: X4 finds no removed event (\(x4))") }
    // A kind that is there is found by its thing too: "이름 바꾼 거" takes the rename under a newer typing; "일정 넣은 거" the event.
    if case .undo(let entry, _, let doubt) = W.reach([typed, rename, event], since: since, kind: W.kind(in: "방금 이름 바꾼 거 되돌려 줘"), named: W.named(in: "방금 이름 바꾼 거 되돌려 줘")) {
        check(entry.id == rename.id && doubt, "fix132 undo: \"이름 바꾼 거\" takes the rename, the newer typing named as staying")
    } else { check(false, "fix132 undo: \"이름 바꾼 거\" takes the rename") }
    if case .undo(let entry, _, _) = W.reach([typed, rename, event], since: since, kind: W.kind(in: "방금 일정 넣은 거 되돌려 줘"), named: W.named(in: "방금 일정 넣은 거 되돌려 줘")) {
        check(entry.id == event.id, "fix132 undo: \"일정 넣은 거\" takes the event, not the newer typing (also made)")
    } else { check(false, "fix132 undo: \"일정 넣은 거\" takes the event") }
    let window = change("창 배치: TextEdit 왼쪽 절반", "moved", ago: 20)
    if case .undo(let entry, _, _) = W.reach([window, typed], since: since, kind: W.kind(in: "방금 창 옮긴 거 되돌려 줘"), named: W.named(in: "방금 창 옮긴 거 되돌려 줘")) {
        check(entry.id == window.id, "fix132 undo: \"창 옮긴 거\" still takes the window move")
    } else { check(false, "fix132 undo: \"창 옮긴 거\" still takes the window move") }
    // A bare "방금 거 되돌려" is unchanged: the newest.
    if case .undo(let entry, _, _) = W.reach([typed, rename], since: since, kind: W.kind(in: "방금 거 되돌려"), named: W.named(in: "방금 거 되돌려")) {
        check(entry.id == typed.id, "fix132 undo: a bare undo takes the newest")
    } else { check(false, "fix132 undo: a bare undo takes the newest") }
    // The card for it: the newest, with a first line that says the kind asked for isn't there (both languages).
    let card = W.card(for: W.Candidate(id: rename.id, summary: rename.summary, action: "changed"), newest: nil, doubt: false, korean: true,
                      missing: W.missingLine(kind: "removed", named: .event, korean: true))
    check(card.title == "되돌리기" && card.detail.hasPrefix("최근 기록에 없어요: 지운 일정") && card.detail.contains("되돌릴 일: 이름 바꿈: rename-me.txt"),
          "fix132 undo: X4's card says no removed event is there, then what the yes would undo (\(card.detail))")
    let english = W.card(for: W.Candidate(id: typed.id, summary: typed.summary, action: "made"), newest: nil, doubt: false, korean: false,
                         missing: W.missingLine(kind: nil, named: .rename, korean: false))
    check(english.detail.hasPrefix("There's no recent rename to undo.") && english.detail.contains("To undo: Typed: TextEdit"),
          "fix132 undo: X7's card in English (\(english.detail))")
    check(W.missingLine(kind: "made", named: nil, korean: true) == "최근 기록에 없어요: 만든 것. 대신 가장 최근 일을 되돌릴까요?",
          "fix132 undo: a kind named by its verb alone is said too")
    let undo = f132Source("Aris/private/Aris/ArisController+Undo.swift")
    check(undo.contains("case .noneOfKind(let others):") && undo.contains("missing = ArisUndoWords.missingLine(kind: kind, named: named, korean: cardKorean)")
          && !undo.contains("return await undoSay(ArisUndoWords.noneOfKindLine(others, korean: korean))"),
          "fix132 undo: nothing of the kind is a card (the newest, saying so), never a text question")
}

// MARK: - 5. Small ones

private func fix132SmallTests() {
    // D3: "~/Downloads 비워 줘" after outside text went to the AI, which opened Finder. A refusal needs no vouch.
    check(ArisProtectedPlaceAsk.answer("~/Downloads 비워 줘", fromApp: true, handsFree: false, plain: true)?.contains("다운로드 폴더를 통째로 비우지는") == true,
          "fix132 small: \"~/Downloads 비워 줘\" is refused here in one sentence")
    let agentMain = f132Source("ArisAgent/main.swift")
    check(agentMain.contains("if let line = ArisProtectedPlaceAsk.answer(request, fromApp: peerFailure == nil, handsFree: handsFree"),
          "fix132 small: that refusal comes after outside text too (no vouch needed to refuse)")
    let prompt = f132Source("ArisAgent/ArisAgentPrompt.swift")
    check(prompt.contains("Open or reveal \" +\n            \"a folder or file only when the user asks to see it") || prompt.contains("Open or reveal a folder or file only when the user asks to see it")
          || (prompt.contains("Open or reveal") && prompt.contains("only when the user asks to see it")),
          "fix132 small: the brain opens a folder only when asked to see it")
    // K1: the to-do items lost their "14": word for word, numbers kept.
    check(prompt.contains("is added word for word as the user or the document has it: numbers, codes and punctuation kept")
          && f132Source("ArisAgent/ArisCapabilityFunctions.swift").contains("word for word as the user or the document has it (numbers included)"),
          "fix132 small: to-do items are added word for word, numbers included")
    // D7: "바탕화면에 있는 임시폴더14 폴더 지워 줘": the new folder isn't indexed; the Desktop's own items find it.
    let listed: [String: [String]] = ["/Users/x/Desktop": ["임시폴더14", "v14", ".hidden임시폴더14"], "/Users/x/Documents": ["notes"], "/Users/x/Downloads": []]
    check(ArisFindQuery.placeMatches("임시폴더14", home: "/Users/x") { listed[$0] ?? [] } == ["/Users/x/Desktop/임시폴더14"]
          && ArisFindQuery.placeMatches("임시폴더14 폴더", home: "/Users/x") { listed[$0] ?? [] } == ["/Users/x/Desktop/임시폴더14"]
          && ArisFindQuery.placeMatches("없는것", home: "/Users/x") { listed[$0] ?? [] }.isEmpty,
          "fix132 small: the Desktop, Documents and Downloads are looked through by their own items when Spotlight has nothing")
    let files = f132Source("ArisTools/ArisFilesCommand.swift"), reads = f132Source("ArisTools/ArisLocalReadCommands.swift")
    check(files.contains("ArisFindQuery.placeMatches(words, home: home)") && reads.contains("ArisFindQuery.placeMatches(words, home: home)"),
          "fix132 small: `find` and `files find` both do")
    // W3u: "‘TextEdit left’ 창 옮김을 되돌렸어요": the layout in Korean, the kind named as Korean.
    check(ArisUndoWords.doneLine("창 옮김: TextEdit left", korean: true) == "‘TextEdit 왼쪽 절반’ 창 옮긴 것을 되돌렸어요."
          && ArisUndoWords.doneLine("창 옮김: TextEdit left", korean: false) == "I took back the window move “TextEdit left”."
          && ArisActivityWords.english("창 옮김: Safari right") == "Window moved: Safari right"
          && ArisUndoWords.card(for: ArisUndoWords.Candidate(id: "w", summary: "창 옮김: TextEdit full", action: "moved"), newest: nil, doubt: false, korean: true).detail
            == "되돌릴 일: 창 옮김: TextEdit 전체 화면",
          "fix132 small: a window move is said in Korean in a Korean reply and card, in English in an English one")
    // R1d: "보내기 전에 확인해 주세요" after typing at TextEdit's caret: only in a chat or mail field.
    check(!ArisTypeHere.insertedLine(korean: true, undoable: true, sends: false).contains("보내기") && !ArisTypeHere.insertedLine(korean: false, undoable: false, sends: false).contains("send")
          && ArisTypeHere.insertedLine(korean: true, undoable: true, sends: true).contains("보내기 전에 확인해 주세요")
          && ArisTypeHere.sends(focusKind: "chat") && ArisTypeHere.sends(focusKind: "mail") && !ArisTypeHere.sends(focusKind: "field") && !ArisTypeHere.sends(focusKind: nil),
          "fix132 small: \"check it before you send it\" only where it could be sent")
    // Notices: the relaunch offer goes by itself; one that goes by itself is gone 5 minutes after it was posted.
    let reopen = ArisPermissionNotice.notice(for: .offerRelaunch(ArisPermissionKey(.inputMonitoring)), english: false)
    check(reopen?.showsFor == ArisPermissionNotice.relaunchShowsFor && reopen?.actions.map(\.role) == [.relaunchApp],
          "fix132 small: \"Reopen Aris\" goes by itself after a while (its button stays in Settings)")
    let now = Date()
    let timer = ArisNotice(kind: .system, title: "Timer", body: "2 minutes is up.", posted: now.addingTimeInterval(-16 * 60), showsFor: 60)
    let fresh = ArisNotice(kind: .system, title: "Timer", body: "1 minute is up.", posted: now.addingTimeInterval(-30), showsFor: 60)
    let card = ArisNotice(kind: .problem, title: "Accessibility is off", body: "x", posted: now.addingTimeInterval(-3_600))
    var queue = ArisNoticeQueue().posting(timer).posting(fresh).posting(card)
    queue = queue.presenting(timer.id).presenting(card.id)
    let retired = queue.retiring(at: now)
    check(!retired.shown.contains { $0.id == timer.id } && retired.shown.contains { $0.id == card.id } && retired.pending.map(\.id) == [fresh.id],
          "fix132 small: a timer's notice is gone once it outlived its time, however often it stepped aside; a card without a clock stays")
    check(f132Source("Aris/private/Aris/Notice/ArisNoticeCenter.swift").contains("let kept = queue.retiring(at: now)"), "fix132 small: the pill's clock retires them")
    // Settings › Permissions "3 file folders": its Allow opens the Files and Folders list when macOS asked nothing.
    let settings = f132Source("Aris/components/Settings/ArisLiveSettings.swift")
    check(settings.contains("if off.contains(where: { known[$0] != true }),"), "fix132 small: the folders row's Allow always does something visible")
}
