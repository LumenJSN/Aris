// Tests for what the third VM run found (2026-11-11: REPORT-v3-upgrade.md, bugs A to D and its smaller list, and
// REPORT-v3-new.md). Each rule is pinned in pure logic on values made here: nothing is asked of macOS or of an agent,
// no window is shown, and nothing of the user's is read or changed.
// - B: a typed "undo that" reaches aris-agent the way the 한 일 tab's Undo does, and the helper's rule still refuses a
//   `confirmed` it never asked for (the whole exchange is run against ArisPendingUndos);
// - A: a thing that only points back ("that", "그거") is never the argument of a local act.
// Called from main.swift; uses its check().
import Foundation

func runV3FixTests() {
    v3UndoTests()
    v3UndoWordsTests()
    v3PointsBackTests()
    v3LookTargetTests()
    v3RemindersAccessTests()
    v3SetupKeysTests()
    v3ListenStartTests()
    v3CardedStepTests()
    v3TagPressTests()
    v3SmallerTests()
    v3SmallerLogicTests()
    v3OpenNotchPointerTests()
    v3HelperAnswersTests()
    v3HelperRestartTests()
}

private let v3Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")

func v3Source(_ path: String) -> String {
    (try? String(contentsOf: v3Root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The lines of a source file that are code (a comment may name what the code no longer does).
func v3Code(_ path: String) -> String {
    v3Source(path).split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}

// MARK: - B: the typed undo and the helper's rule

/// aris-agent's side of POST /undo as ArisAgent/main.swift runs it, with the real rule (ArisPendingUndos) and the real
/// reply (ArisActivityBridge.undoReply); aris-tools is the fake: an entry in `asking` exits 3 unless --confirmed.
private struct V3UndoHelper {
    var pending = ArisPendingUndos()
    /// Entries whose undo deletes an event Aris made or brings a schedule back: their summary and kind.
    var asking: [String: (summary: String, kind: String)] = [:]
    var undone: [String] = []
    var refusals = 0
    var requests: [[String: Any]] = []

    mutating func post(_ body: [String: Any], at now: Date = Date(timeIntervalSince1970: 1_000)) -> ArisUndoOutcome {
        requests.append(body)
        let id = body["id"] as? String, confirmed = body["confirmed"] as? Bool == true
        if confirmed {
            let yes = pending.consuming(id: id, summary: body["summary"] as? String, at: now)
            pending = yes.rest
            guard yes.allowed else {
                refusals += 1
                return ArisUndoSteps.outcome(status: 403, reply: [:])
            }
        }
        guard let arguments = ArisActivityBridge.undoArguments(id: id, confirmed: confirmed), let id else { return ArisUndoSteps.outcome(status: 400, reply: [:]) }
        var status: Int32 = 0, out = "undone: x"
        if let ask = asking[id], !arguments.contains("--confirmed") {
            status = ArisActivityBridge.needsConfirmStatus
            out = String(decoding: (try? JSONSerialization.data(withJSONObject: ["id": id, "summary": ask.summary, "kind": ask.kind])) ?? Data(), as: UTF8.self)
        } else {
            undone.append(id)
        }
        let reply = ArisActivityBridge.undoReply(status: status, out: out, err: "")
        if reply.code == 409 { pending = pending.issuing(replyBody: reply.body, at: now) }
        return ArisUndoSteps.outcome(status: reply.code, reply: ((try? JSONSerialization.jsonObject(with: Data(reply.body.utf8))) as? [String: Any]) ?? [:])
    }
}

/// The typed undo's steps in the order ArisController.undoLast takes them; `yes`: the user's answers to the cards, in order.
/// Returns what ended it and the cards shown.
private func v3TypedUndo(_ entry: ArisUndoWords.Candidate, helper: inout V3UndoHelper, yes: [Bool], newest: ArisUndoWords.Candidate? = nil,
                         doubt: Bool = false, korean: Bool = false) -> (outcome: ArisUndoOutcome?, cards: [String]) {
    var answers = yes, cards: [String] = []
    if ArisUndoSteps.start(asks: entry.asks) == .ownCard {
        let card = ArisUndoWords.card(for: entry, newest: newest, doubt: doubt, korean: korean)
        cards.append(card.title + " / " + card.detail)
        guard !answers.isEmpty, answers.removeFirst() else { return (nil, cards) }
    }
    var outcome = helper.post(ArisUndoSteps.request(id: entry.id, confirmed: false, echo: nil))
    switch ArisUndoSteps.next(after: outcome, entry: entry, newest: newest, doubt: doubt, korean: korean) {
    case .say: break
    case .otherEntry: outcome = .failed("other")
    case .card(let ask, let echo):
        cards.append(ask.title + " / " + ask.detail)
        guard !answers.isEmpty, answers.removeFirst() else { return (nil, cards) }
        outcome = helper.post(ArisUndoSteps.request(id: entry.id, confirmed: true, echo: echo))
    }
    return (outcome, cards)
}

private func v3UndoTests() {
    let todoId = "DEF819FC-0000-4000-8000-000000000001", eventId = "7D220A76-0000-4000-8000-000000000002"
    let todo = ArisUndoWords.Candidate(id: todoId, summary: "할 일 추가: that", action: "made")
    let event = ArisUndoWords.Candidate(id: eventId, summary: "일정 추가: Lunch", action: "made", asks: true)

    // The bug as the tester saw it: Aris's own card, then `confirmed` for an entry the helper never asked about.
    var old = V3UndoHelper()
    check(old.post(["id": todoId, "confirmed": true, "summary": "To undo: 할 일 추가: that"]) == .refused && old.undone.isEmpty && old.refusals == 1,
          "vm3 bug B (the bug): a yes sent with `confirmed` for an entry the helper never asked about is refused, and nothing is undone")

    // Now: an ordinary change is one card of Aris's own, then the plain request, as the 한 일 tab and the receipt send it.
    var helper = V3UndoHelper()
    let plain = v3TypedUndo(todo, helper: &helper, yes: [true])
    check(plain.outcome == .done("undone: x") && helper.undone == [todoId] && helper.refusals == 0,
          "vm3 bug B: a typed “undo that” on a to-do, the volume or the timer is undone after its one card (\(String(describing: plain.outcome)))")
    check(plain.cards == ["Undo / To undo: To-do added: that"] && helper.requests.count == 1 && helper.requests[0]["confirmed"] as? Bool == false
          && helper.requests[0]["summary"] == nil,
          "vm3 bug B: that undo is one card and one request, sent without `confirmed` (\(plain.cards))")
    var declined = V3UndoHelper()
    check(v3TypedUndo(todo, helper: &declined, yes: [false]).outcome == nil && declined.requests.isEmpty && declined.undone.isEmpty,
          "vm3 bug B: a no on the card sends nothing at all")

    // One the helper asks about itself: the helper is asked first, its card is the one card, and the yes echoes its summary.
    check(ArisUndoSteps.start(asks: false) == .ownCard && ArisUndoSteps.start(asks: true) == .helperAsks,
          "vm3 bug B: an undo that deletes an event or revives a schedule goes to the helper before any card")
    var asking = V3UndoHelper(asking: [eventId: ("일정 추가: Lunch", "deleteEvent")])
    let asked = v3TypedUndo(event, helper: &asking, yes: [true])
    check(asked.outcome == .done("undone: x") && asking.undone == [eventId] && asking.refusals == 0 && asked.cards == ["Delete the event / Event added: Lunch\nLogged as: 일정 추가: Lunch"],
          "vm3 bug B: an event Aris made is deleted only after the helper's own card, shown once (\(asked.cards))")
    check(asking.requests.count == 2 && asking.requests[0]["confirmed"] as? Bool == false && asking.requests[1]["confirmed"] as? Bool == true
          && asking.requests[1]["summary"] as? String == "일정 추가: Lunch",
          "vm3 bug B: the yes goes back with `confirmed` and exactly the summary the helper's 409 carried")
    var saidNo = V3UndoHelper(asking: [eventId: ("일정 추가: Lunch", "deleteEvent")])
    check(v3TypedUndo(event, helper: &saidNo, yes: [false]).outcome == nil && saidNo.undone.isEmpty && saidNo.requests.count == 1,
          "vm3 bug B: a no on the helper's card deletes nothing")
    var revive = V3UndoHelper(asking: [eventId: ("예약 취소: 저녁 알림 (매일 20:00)", "restoreSchedule")])
    let revived = v3TypedUndo(ArisUndoWords.Candidate(id: eventId, summary: "예약 취소: 저녁 알림 (매일 20:00)", action: "removed", asks: true),
                              helper: &revive, yes: [true], korean: true)
    check(revived.outcome == .done("undone: x") && revived.cards == ["예약 다시 살리기 / 예약 취소: 저녁 알림 (매일 20:00)"],
          "vm3 bug B: bringing a removed schedule back is asked on its own card, in Korean as it was (\(revived.cards))")
    // The list said it wouldn't ask and the helper asks all the same: its card comes second, and nothing runs without it.
    var surprise = V3UndoHelper(asking: [todoId: ("일정 추가: Lunch", "deleteEvent")])
    let twoCards = v3TypedUndo(todo, helper: &surprise, yes: [true, false])
    check(twoCards.cards.count == 2 && twoCards.outcome == nil && surprise.undone.isEmpty,
          "vm3 bug B: when the helper asks though the list didn't say so, its card is shown too and a no there undoes nothing")

    // The helper's rule is as it was: nothing but its own card's yes counts.
    var forged = V3UndoHelper(asking: [eventId: ("일정 추가: Lunch", "deleteEvent")])
    check(forged.post(ArisUndoSteps.request(id: eventId, confirmed: true, echo: "일정 추가: Lunch")) == .refused && forged.undone.isEmpty,
          "vm3 bug B (the rule): `confirmed` with the right summary but no 409 before it is refused")
    _ = forged.post(ArisUndoSteps.request(id: eventId, confirmed: false, echo: nil))
    check(forged.post(ArisUndoSteps.request(id: eventId, confirmed: true, echo: "Delete the event")) == .refused && forged.undone.isEmpty,
          "vm3 bug B (the rule): `confirmed` that doesn't echo the 409's summary is refused")
    check(forged.post(ArisUndoSteps.request(id: eventId, confirmed: true, echo: "일정 추가: Lunch")) == .refused,
          "vm3 bug B (the rule): and the card is spent by that wrong echo: a second guess is refused too")
    var late = V3UndoHelper(asking: [eventId: ("일정 추가: Lunch", "deleteEvent")])
    _ = late.post(ArisUndoSteps.request(id: eventId, confirmed: false, echo: nil), at: Date(timeIntervalSince1970: 0))
    check(late.post(ArisUndoSteps.request(id: eventId, confirmed: true, echo: "일정 추가: Lunch"), at: Date(timeIntervalSince1970: ArisApprovalQueue.lifetime + 5)) == .refused,
          "vm3 bug B (the rule): a yes after the card's lifetime is refused")
    check(ArisUndoSteps.request(id: eventId, confirmed: true, echo: nil)["confirmed"] as? Bool == false
          && ArisUndoSteps.request(id: nil, confirmed: true, echo: "x")["confirmed"] as? Bool == false,
          "vm3 bug B: the app never sends `confirmed` without the entry and the summary the helper gave")
    check(ArisUndoSteps.next(after: .needsConfirm(id: todoId, summary: "일정 추가: Lunch"), entry: event, newest: nil, doubt: false, korean: false) == .otherEntry
          && ArisUndoSteps.next(after: .needsConfirm(id: "", summary: "x"), entry: event, newest: nil, doubt: false, korean: false) == .otherEntry,
          "vm3 bug B: a 409 about another entry, or about none, is never confirmed")
    check(ArisUndoSteps.next(after: .refused, entry: todo, newest: nil, doubt: false, korean: false) == .say(.refused)
          && ArisUndoSteps.next(after: .failed("no entry"), entry: todo, newest: nil, doubt: false, korean: false) == .say(.failed("no entry")),
          "vm3 bug B: a refusal or a failure is said as it is")
    let stays = ArisUndoWords.Candidate(id: todoId, summary: "볼륨 올림", action: "changed")
    if case .card(let card, let echo) = ArisUndoSteps.next(after: .needsConfirm(id: eventId, summary: "일정 추가: Lunch"), entry: event, newest: stays, doubt: true, korean: false) {
        check(card.detail == "Event added: Lunch\nLogged as: 일정 추가: Lunch\nThe latest one (Volume up) isn't that kind, so it stays" && echo == "일정 추가: Lunch" && card.id == "undo-" + eventId,
              "vm3 bug B: with a kind named, the helper's card also says which newer change stays, and the echo is still the helper's summary")
    } else {
        check(false, "vm3 bug B: with a kind named, the helper's card also says which newer change stays")
    }

    // Wiring: the controller takes these steps, and the tab's and the receipt's path is untouched.
    let controller = v3Code("Aris/private/Aris/ArisController+Undo.swift")
    check(controller.contains("ArisUndoSteps.start(asks: entry.asks) == .ownCard") && controller.contains("var outcome = await undoWaiting(id: entry.id, korean: korean)")
          && controller.contains("ArisUndoSteps.next(after: outcome, entry: entry")
          && controller.contains("outcome = await undoWaiting(id: entry.id, confirmed: true, shown: ask, echo: echo, korean: korean)")
          && controller.components(separatedBy: "confirmed: true").count == 3,
          "vm3 bug B: wiring: the typed undo asks the helper plainly first; `confirmed` is sent only after the helper's card (here and in the tab's undo)")
    check(controller.contains("let outcome = await undoWaiting(id: id, korean: korean)\n        guard case .needsConfirm(let asked, let summary, let revives) = outcome"),
          "vm3 bug B: wiring: the 한 일 tab's and the receipt's undo go as they did")
    check(v3Code("Aris/private/Aris/ArisAgentClient+Undo.swift").contains("ArisUndoSteps.request(id: id, confirmed: confirmed, echo: echo ?? shown?.detail)"),
          "vm3 bug B: wiring: the request's body is the tested one")
    let agent = v3Code("ArisAgent/main.swift")
    check(agent.contains("let yes = pendingUndos.consuming(id: object[\"id\"] as? String, summary: object[\"summary\"] as? String, at: Date())")
          && agent.contains("guard yes.allowed else {") && agent.contains("if reply.code == 409 { pendingUndos = pendingUndos.issuing(replyBody: reply.body, at: Date()) }"),
          "vm3 bug B: wiring: aris-agent's rule for a confirmed undo is unchanged")

    // The second ledger line: the folder is looked up only once the undo has really waited.
    check(!ArisUndoSteps.asksFolder(waited: 0) && !ArisUndoSteps.asksFolder(waited: ArisUndoWords.hintAfter - 0.1) && ArisUndoSteps.asksFolder(waited: ArisUndoWords.hintAfter),
          "vm3 bug B: an undo that comes back at once asks nothing about a folder")
    let sleep = controller.range(of: "try? await Task.sleep(for: .seconds(ArisUndoWords.hintAfter))"), folder = controller.range(of: "await ArisAgentClient.undoFolder(id: id)")
    check(sleep != nil && folder != nil && sleep!.lowerBound < folder!.lowerBound && controller.components(separatedBy: "ArisAgentClient.undoFolder(").count == 2,
          "vm3 bug B: wiring: the folder look-up comes after the wait, so a quick undo leaves no “undo-folder … refused” line")
}

private func v3UndoWordsTests() {
    let todo = ArisUndoWords.Candidate(id: "a", summary: "할 일 추가: that", action: "made")
    let volume = ArisUndoWords.Candidate(id: "b", summary: "볼륨 올림", action: "changed")
    check(ArisUndoWords.card(for: todo, newest: todo, doubt: false, korean: false).detail == "To undo: To-do added: that"
          && ArisUndoWords.card(for: volume, newest: volume, doubt: false, korean: false).detail == "To undo: Volume up",
          "vm3 smaller: the English Undo card says the record in English, by the 한 일 tab's table (it read “To undo 할 일 추가: that”)")
    check(ArisUndoWords.card(for: todo, newest: todo, doubt: false, korean: true).detail == "되돌릴 일: 할 일 추가: that"
          && ArisUndoWords.card(for: volume, newest: volume, doubt: false, korean: true) == ("되돌리기", "되돌릴 일: 볼륨 올림"),
          "vm3 smaller: the Korean Undo card is as it was")
    check(ArisUndoWords.card(for: todo, newest: volume, doubt: true, korean: false).detail == "To undo: To-do added: that\nThe latest one (Volume up) isn't that kind, so it stays",
          "vm3 smaller: the line about the newer change that stays is English too")
    check(ArisUndoWords.doneLine("할 일 추가: that", korean: false) == "Undid “that” (To-do added)." && ArisUndoWords.doneLine("볼륨 올림", korean: false) == "Undid “Volume up”."
          && ArisUndoWords.doneLine("일정 추가: 회의", korean: true) == "‘회의’ 일정을 되돌렸어요.",
          "vm3 smaller: the reply after an undo names the record in the request's language (\(ArisUndoWords.doneLine("할 일 추가: that", korean: false)))")
    check(ArisUndoWords.noneOfKindLine([todo, volume], korean: false) == "Nothing of that kind. The latest are: To-do added: that; Volume up. Which one should I undo?",
          "vm3 smaller: and so does the line that names the latest two")
}

// MARK: - A: a thing that only points back is the AI's

private func v3PointsBackTests() {
    func isAsk(_ said: String) -> Bool {
        if case .ask = ArisIntent.guarded(ArisIntent.parse(said), said: said) { return true }
        return false
    }
    func added(_ said: String) -> String? {
        if case .addTodo(let item) = ArisIntent.guarded(ArisIntent.parse(said), said: said) { return item }
        return nil
    }
    // The tester's words, and the other pointing words.
    for said in ["add that to my to-dos", "Add that to my to-dos.", "add this to my to-do list", "add it to my todos", "put them on my to-do list",
                 "add those to my reminders", "add these to my to-do list", "add the above to my to-dos", "add the same to my to-do list",
                 "add that one to my to-dos", "add this thing to my to-do list", "add all of those to my to-dos", "can you add that to my to-dos please",
                 "add that too to my to-dos", "put that on my reminders", "add what you just said to my to-dos", "add the same thing to my to-do list",
                 "add a to-do: that", "new to-do: it", "to-do: this one"] {
        check(isAsk(said), "vm3 bug A: “\(said)” is the AI's to resolve, never a to-do named by a pointing word")
    }
    for said in ["remind me about that", "remind me to do that", "remind me to do it tomorrow", "remind me about this tomorrow at 5", "add a reminder for that",
                 "set a reminder to do this", "reminder: that"] {
        check(isAsk(said), "vm3 bug A: “\(said)” is the AI's: what to be reminded of is only pointed at")
    }
    for said in ["그거 할 일에 추가해 줘", "이거 할 일에 추가해줘", "저거 할 일에 넣어 줘", "방금 그거 할 일에 추가해 줘", "그것도 할 일에 추가해", "방금 거 할 일에 적어 줘",
                 "할 일에 그거 추가해 줘", "이것들 할 일 목록에 넣어줘", "위에 거 할 일에 추가해 줘", "방금 말한 거 할 일에 추가해 줘", "그 내용 할 일에 추가해 줘",
                 "그걸 미리 알림에 추가해 줘"] {
        check(isAsk(said), "vm3 bug A: “\(said)” is the AI's (the Korean rule had the same hole)")
    }
    // A thing with a name of its own is still Aris's own add, as before.
    check(added("add buy milk to my to-do list") == "buy milk" && added("add call that guy about the fence to my to-dos") == "call that guy about the fence"
          && added("add IT support ticket to my to-dos") == "IT support ticket" && added("remind me to call mom tomorrow at 5") == "call mom tomorrow at 5"
          && added("remind me to send it to Kim") == "send it to Kim" && added("add this week's report to my to-dos") == "this week's report",
          "vm3 bug A: an item with words of its own is added by the app as before (\(String(describing: added("add this week's report to my to-dos"))))")
    check(added("우유 사기 할 일에 추가해 줘") == "우유 사기" && added("그 회의 자료 준비 할 일에 추가해 줘") == "그 회의 자료 준비" && added("이거저거 정리하기 할 일에 넣어 줘") == "이거저거 정리하기",
          "vm3 bug A: a Korean item with words of its own is added as before")
    // The other local acts that take words: an app opened, a to-do ticked off.
    for said in ["open that", "open it", "open this one", "launch that", "그거 열어 줘", "이거 켜 줘", "그거 다 했어", "방금 그거 끝냈어", "mark that as done", "check it off"] {
        check(isAsk(said), "vm3 bug A: “\(said)” names nothing the app could open or tick: the AI's")
    }
    var opens = false, ticks = false
    if case .openApp = ArisIntent.parse("open safari") { opens = true }
    if case .finishTodo("우유 사기") = ArisIntent.parse("우유 사기 다 했어") { ticks = true }
    check(opens && ticks,
          "vm3 bug A: an app or a to-do that is named is the app's own as before")
    // The rule itself.
    for words in ["that", "This", "it", "them", "those", "these", "the above", "the same", "that one", "this thing", "those things", "these ones", "the same thing",
                  "all of them", "both of those", "“that”", "that.", "the last one", "what you said", "그거", "이거", "저거", "그것", "방금 그거", "아까 그거", "그거를",
                  "이것들", "방금 거", "위에 거", "같은 거", "그 내용", "방금 말한 거"] {
        check(ArisPointsBack.only(words), "vm3 bug A: “\(words)” only points back")
    }
    for words in ["", "that report", "it support", "this week's report", "them apples for the pie", "the same day delivery order", "buy that", "call them", "thatcher",
                  "item", "그 회의", "이거저거 정리", "거울 닦기", "그거 사기", "저거 반납하기"] {
        check(!ArisPointsBack.only(words), "vm3 bug A: “\(words)” names something (or nothing at all): not a bare pointer")
    }
    check(ArisPointsBack.onlyAsTask("do that") && ArisPointsBack.onlyAsTask("take care of it") && ArisPointsBack.onlyAsTask("that")
          && !ArisPointsBack.onlyAsTask("call them") && !ArisPointsBack.onlyAsTask("do the dishes") && !ArisPointsBack.onlyAsTask("check the oven"),
          "vm3 bug A: what a reminder is about points back only when nothing in it says what to do")
    // The routine's step by words (aris-agent): "add that to my morning routine" is never a step called "that".
    let morning = ArisRoutine(id: UUID(), name: "morning", steps: ["check the weather in orlando", "tell me the time"], own: true, created: Date(), changed: Date())
    if case .addStep(_, let step)? = ArisRoutineIntent.parse("add open notes to my morning routine", routines: [morning]) {
        check(step == "open notes", "vm3 bug A: a routine step with words of its own is added as before")
    } else {
        check(false, "vm3 bug A: a routine step with words of its own is added as before")
    }
    check(ArisRoutineIntent.parse("add that to my morning routine", routines: [morning]) == nil && ArisRoutineIntent.parse("add it to my morning routine", routines: [morning]) == nil,
          "vm3 bug A: “add that to my morning routine” is left to the AI, never a step called “that”")
    // A routine's step that only points is never done by the app by itself either.
    check(ArisRoutineStepRule.act(for: "add that to my to-dos") == nil && ArisRoutineStepRule.act(for: "open it") == nil && ArisRoutineStepRule.act(for: "add buy milk to my to-do list") != nil,
          "vm3 bug A: a routine step by words follows the same rule")
}

private func v3LookTargetTests() {
    // (fix-6, second upgrade run bug 1: the target is ArisFrontNow's now, from the window server's order and the app's
    // word; these are the same cases on it.)
    typealias F = ArisFrontNow
    let aris: Int32 = 100, agent: Int32 = 50, textEdit: Int32 = 200, finder: Int32 = 300, prompt: Int32 = 400
    let windows = [F.Window(id: 1, pid: aris, layer: 27), F.Window(id: 2, pid: prompt, layer: 8), F.Window(id: 3, pid: aris, layer: 0),
                   F.Window(id: 4, pid: textEdit, layer: 0), F.Window(id: 5, pid: finder, layer: 0)]
    let ordinary: (Int32) -> Bool = { [textEdit, finder, aris].contains($0) }
    let stepped: (Int32) -> Bool = { ArisLookTarget.steppedOver(pid: $0, bundleId: $0 == prompt ? "com.apple.UserNotificationCenter" : "", aris: aris, own: agent) }
    check(F.lookTarget(told: textEdit, windows: windows, steppedOver: stepped, ordinary: ordinary)?.pid == textEdit,
          "vm3n bug 1 (look): with one of the user's apps in front, the look reads it, as before")
    check(F.lookTarget(told: aris, windows: windows, steppedOver: stepped, ordinary: ordinary)?.pid == textEdit,
          "vm3n bug 1 (look): a question typed into the notch puts Aris in front: the look reads the app whose window is under it, not Aris")
    check(F.lookTarget(told: prompt, windows: windows, steppedOver: stepped, ordinary: ordinary)?.pid == textEdit,
          "vm3n bug 1 (look): with a macOS prompt in front, the look reads the app under it, never the prompt")
    check(F.lookTarget(told: aris, windows: [F.Window(id: 3, pid: aris, layer: 0), F.Window(id: 9, pid: 999, layer: 0)], steppedOver: stepped, ordinary: ordinary) == nil
          && F.lookTarget(told: nil, windows: [], steppedOver: stepped, ordinary: ordinary) == nil,
          "vm3n bug 1 (look): with no ordinary app's window on screen nothing is read (and the look says so)")
    check(F.lookTarget(told: aris, windows: [F.Window(id: 6, pid: finder, layer: 3), F.Window(id: 7, pid: finder, layer: 0)], steppedOver: stepped, ordinary: ordinary)?.window == 7
          && F.lookTarget(told: agent, windows: windows, steppedOver: stepped, ordinary: ordinary)?.pid == textEdit,
          "vm3n bug 1 (look): only an app's own windows (layer 0) count, and the helper itself is stepped over too")
    check(ArisLookTarget.screenArguments(pid: 200) == ["screen", "--pid", "200"] && ArisLookTarget.screenArguments(pid: nil) == ["screen"],
          "vm3n bug 1 (look): the tool is told which app's window to read")
    let look = v3Code("ArisAgent/ArisLook.swift"), tool = v3Code("ArisTools/ArisScreen.swift")
    check(look.contains("ArisFrontNow.lookTarget(told: told") && look.contains("ArisLookTarget.screenArguments(pid: pid, window: windowId)") && !look.contains("AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute"),
          "vm3n bug 1 (look): wiring: the look's app, its window's words and its selection are all the target's")
    check(tool.contains("option(\"--pid\", in: &args)") && tool.contains("guard let app = named ?? ArisFrontLive.frontPid()")
          && tool.contains("guard !ArisCaptureRules.isPrivate(app.bundleIdentifier)"),
          "vm3n bug 1 (look): wiring: the tool reads the named app's window, and a private app is still never read")
    check(v3Code("ArisAgent/main.swift").contains("aris: (object[\"pid\"] as? Int).flatMap { Int32(exactly: $0) },"), "vm3n bug 1 (look): wiring: the route says which process is Aris")
}

// MARK: - vm3n bug 2: Reminders access is read from macOS at each request

private func v3RemindersAccessTests() {
    typealias A = ArisRemindersAccess
    check(A.allowed(status: .full, grantedByRequest: false) && !A.allowed(status: .notAsked, grantedByRequest: false) && !A.allowed(status: .writeOnly, grantedByRequest: false),
          "vm3n bug 2: Reminders may be used with full access, as macOS says it now")
    check(A.allowed(status: .notAsked, grantedByRequest: true),
          "vm3n bug 2 (the bug): macOS's own prompt answered with a yes in this run counts, though this process still reads “not asked yet”")
    check(!A.allowed(status: .denied, grantedByRequest: true) && !A.allowed(status: .restricted, grantedByRequest: true),
          "vm3n bug 2: a status that says no is a no, whatever was allowed earlier")
    check(A.seen(known: .notAsked, fresh: .full) == (true, true) && A.seen(known: .denied, fresh: .full) == (true, true),
          "vm3n bug 2: access that has just turned on gets a new event store (one made before the grant may not see the lists) and a fresh read of the lists")
    check(A.seen(known: .full, fresh: .full) == (false, false) && A.seen(known: .full, fresh: .denied) == (false, true) && A.seen(known: .notAsked, fresh: .notAsked) == (false, false),
          "vm3n bug 2: nothing is rebuilt while the answer is the same, and a grant taken away reads the (now empty) lists again")
    check(A.asksAgain(fresh: .notAsked, answeredThisRun: true) && !A.asksAgain(fresh: .notAsked, answeredThisRun: false)
          && !A.asksAgain(fresh: .denied, answeredThisRun: true) && !A.asksAgain(fresh: .full, answeredThisRun: true),
          "vm3n bug 2: a refused request asks macOS again only when its prompt was already answered in this run (nothing is shown twice), never on a plain read and never after a no")
    let reminders = v3Code("Aris/private/Aris/ArisReminders.swift")
    check(reminders.contains("var authorized: Bool { ArisRemindersAccess.allowed(status: Self.plain(status), grantedByRequest: grantedByRequest) }")
          && reminders.contains("let fresh = EKEventStore.authorizationStatus(for: .reminder)\n        let step = ArisRemindersAccess.seen(known: Self.plain(status), fresh: Self.plain(fresh))\n        if step.newStore { replaceStore() }")
          && v3Code("Aris/private/Aris/ArisReminderStore.swift").contains("private var store = EKEventStore()") && reminders.contains("if granted { replaceStore() }"),
          "vm3n bug 2: wiring: the status is read from macOS at each look and the store is replaced after a grant")
    check(v3Code("Aris/private/Aris/ArisTodoModel.swift").components(separatedBy: "reminders.accessForRequest()").count == 3
          && v3Code("Aris/private/Aris/ArisTodoRouteHandler.swift").contains("guard await reminders.accessForRequest() else {")
          && v3Code("Aris/private/Aris/ArisWidgetModel.swift").contains("guard await reminders.accessForRequest() else { return nil }")
          && v3Code("Aris/private/Aris/ArisFixModel.swift").contains("case .reminders: return ArisReminders.shared.accessNow()"),
          "vm3n bug 2: wiring: an add, the list, the to-do card, a tool's call and the re-ask's look each read it then, none from an earlier look")
}

// MARK: - vm3n bug 3: the setup's × and the keyboard; the composer takes a click anywhere

private func v3SetupKeysTests() {
    let window = v3Code("Aris/private/Aris/Onboarding/ArisOnboardingWindow.swift")
    let close = window.range(of: "Button { guide.close(.dismissed) } label: {"), end = window.range(of: ".accessibilityLabel(ArisOnboardingCopy.close)")
    check(close != nil && end != nil && window[close!.lowerBound..<end!.lowerBound].contains(".focusable(false)"),
          "vm3n bug 3: the setup's × never has the keyboard's focus, so a stray Space cannot close the setup")
    check(window.components(separatedBy: ".focusable(false)").count == 2 && window.contains("Button(ArisOnboardingCopy.later) { guide.close(.later) }")
          && window.contains("guide.close(.dismissed)"),
          "vm3n bug 3: only the ×: the page's own buttons and “Finish later” keep the keys, and what × means is unchanged (the owner's choice)")
    let composer = v3Code("Aris/private/Aris/Home/ArisComposer.swift")
    check(composer.contains(".onTapGesture { takeKeyboard(tapped: true) }") && composer.contains("ArisPanelKeys.take(panel)\n        focused = true")
          && composer.contains("if text.isEmpty { hint.allowsHitTesting(false) }"),
          "vm3n bug 3: a click anywhere on the composer's pill, its key caps included, puts the cursor in its field")
}

// MARK: - vm3n bug 4: no microphone is said as that

private func v3ListenStartTests() {
    typealias L = ArisListenStart
    check(L.problem(usesMicrophone: true, hasMicrophone: false, modelMissing: true) == .noMicrophone
          && L.problem(usesMicrophone: true, hasMicrophone: false, modelMissing: false) == .noMicrophone,
          "vm3n bug 4: on a Mac with no input device the failure is “no microphone”, whether or not the speech model is there")
    check(L.problem(usesMicrophone: true, hasMicrophone: true, modelMissing: true) == .modelPreparing
          && L.problem(usesMicrophone: false, hasMicrophone: false, modelMissing: true) == .modelPreparing,
          "vm3n bug 4: a model that is really still loading keeps its own line")
    check(L.problem(usesMicrophone: true, hasMicrophone: true, modelMissing: false) == nil && L.problem(usesMicrophone: false, hasMicrophone: false, modelMissing: false) == nil,
          "vm3n bug 4: with a microphone and the model (or the wake detector's audio in hand) nothing stops the start")
    let en = L.line(.noMicrophone, english: true), ko = L.line(.noMicrophone, english: false)
    check(en.hasPrefix("I can't find a microphone.") && en.contains("System Settings › Sound › Input") && ko.contains("마이크를 찾을 수 없어요") && ko.contains("사운드 › 입력"),
          "vm3n bug 4: the line says there is no microphone and what to do")
    check(ArisListenerWords.modelPreparing(english: true) == "The speech recognition model is still getting ready. Please say it again in a moment."
          && ArisCardListenLog.isModelPreparing(ArisListenerWords.modelPreparing(english: false)),
          "vm3n bug 4: the model's line is word for word as it was")
    check(ArisStartFailure.line(ArisFailure(message: en), timedOut: false, abandoned: false, english: true) == en
          && ArisStartFailure.line(ArisFailure(message: "x"), timedOut: false, abandoned: false, english: true) == "I couldn't start listening: x"
          && ArisStartFailure.line(ArisFailure(message: en), timedOut: false, abandoned: true, english: true) == nil,
          "vm3n bug 4: the notch says the microphone sentence whole, with no “I couldn't start listening:” before it")
    typealias D = ArisMicChoice.Device
    check(!ArisMicChoice.anyInput([]) && !ArisMicChoice.anyInput([D(id: 1, transport: .builtIn, hasInput: false)])
          && ArisMicChoice.anyInput([D(id: 1, transport: .builtIn, hasInput: false), D(id: 2, transport: .other, hasInput: true)]),
          "vm3n bug 4: a Mac has a microphone when any of its audio devices can record")
    check(L.shownOnPage(failed: true, reply: en, listening: false) == en && L.shownOnPage(failed: true, reply: en, listening: true) == nil
          && L.shownOnPage(failed: false, reply: en, listening: false) == nil && L.shownOnPage(failed: true, reply: "", listening: false) == nil,
          "vm3n bug 4: the setup's Dictation page shows the same sentence under its note while the notch says it")
    let listener = v3Code("Aris/private/Aris/ArisListener.swift")
    check(listener.contains("ArisListenStart.problem(usesMicrophone: source == nil, hasMicrophone: ArisMicChoice.hasMicrophone(), modelMissing: modelMissing)")
          && v3Code("Aris/private/Aris/Onboarding/ArisOnboardingTryPages.swift").contains("ArisListenStart.shownOnPage(failed: aris.session.phase == .failed, reply: aris.session.reply, listening: listening)"),
          "vm3n bug 4: wiring: the listener asks the rule before it starts, and the page shows what came of it")
}

// MARK: - C: the step that waited on a card

private func v3CardedStepTests() {
    func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 2_000 + seconds) }
    let card = ArisConfirmation(id: "c1", title: "Convert files", detail: "Desktop › noise-long.wav\n→ M4A")
    let working = ArisSession().listening().hearing("convert noise-long.wav on my Desktop to m4a").thinking()
        .working("Finding files").working("Converting video or sound")
    let asking = working.asking(card)
    let yes = asking.answered(delivered: true, allowed: true)
    check(yes.tags.map(\.label) == ["Finding files", "Converting video or sound"] && yes.tags.map(\.done) == [true, false],
          "vm3 bug C: straight after the yes the carded step is the running tag under its own name, not ticked (\(yes.tags.map { $0.label + ($0.done ? " ✓" : "") }))")
    check(!yes.tags.contains { $0.label == ArisSession.thinkingLabel } && yes.status == "Converting video or sound",
          "vm3 bug C: and no “Thinking” runs beside it")
    var times = ArisTagTimes().seeing(working, at: at(0)).seeing(asking, at: at(5)).seeing(yes, at: at(15))
    check(times.began == [1: at(15)], "vm3 bug C: its clock counts from the yes, not through the wait on the card")
    // A stop in that phase names it and leaves no tick for it.
    let cut = ArisStopLine.cut(yes)
    check(cut == ArisStopLine.Cut(finished: ["Finding files"], cutOff: "Converting video or sound")
          && ArisStopLine.line(record: [], cut: cut, english: true) == "Stopped at ‘Converting video or sound’. The rest wasn't done.",
          "vm3 bug C: a stop after the yes says “Stopped at ‘Converting video or sound’” (it said only “Stopped.”)")
    let stopped = yes.stopped(ArisStopLine.line(record: [], cut: cut, english: true))
    check(stopped.tags.map(\.label) == ["Finding files"] && stopped.tags.allSatisfy(\.done),
          "vm3 bug C: and the stopped step keeps no tick: only what had finished before the card is ticked")
    // Its tick comes when the AI moves on, or answers.
    let relabelled = yes.working("Converting video or sound (1 min)")
    check(relabelled.tags.map(\.done) == [true, false] && relabelled.tags.map(\.id) == [0, 1],
          "vm3 bug C: the conversion's own next status stays in the same running tag")
    times = times.seeing(relabelled, at: at(40))
    check(times.began == [1: at(15)], "vm3 bug C: and keeps its clock")
    let movedOn = yes.working("Checking the weather")
    check(movedOn.tags.map(\.label) == ["Finding files", "Converting video or sound", "Checking the weather"] && movedOn.tags.map(\.done) == [true, true, false],
          "vm3 bug C: the step is ticked once the AI has moved on to the next one")
    let answered = yes.answering("Converted it — noise-long.m4a is on your Desktop.")
    check(answered.tags.map(\.done) == [true, true] && answered.tags.map(\.failed) == [false, false],
          "vm3 bug C: or when the turn ends with its answer")
    let failedStep = yes.stepFailed("Converting video or sound").answering("I couldn't convert it.")
    check(failedStep.tags.map(\.failed) == [false, true], "vm3 bug C: a step the agent says failed is marked failed, never ticked")
    let turnFailed = yes.failing("Aris's helper isn't running. Restart the helper.")
    check(turnFailed.tags.map(\.label) == ["Finding files"] && turnFailed.tags.allSatisfy(\.done),
          "vm3 bug C: a turn that fails while the step runs leaves no tick for it")
    // A no, and a card that no step waited on, are as they were.
    let no = asking.answered(delivered: true, allowed: false)
    check(no.tags.map(\.label) == ["Finding files", ArisSession.thinkingLabel] && no.steps.map(\.label) == ["Finding files"],
          "vm3 bug C: after a no the step that waited is gone, never ticked, as before")
    let between = working.working("Reading the page").answering("…").listening().hearing("x").thinking().working("Finding files")
    let nothingWaiting = ArisSession().listening().hearing("x").thinking().asking(card).answered()
    check(nothingWaiting.tags.map(\.label) == [ArisSession.thinkingLabel] && !between.tags.isEmpty,
          "vm3 bug C: a card that came before any step leaves “Thinking” running after the yes, as before")
    check(v3Code("Aris/private/Aris/ArisSession.swift").contains("steps: allowed ? steps : steps.filter(\\.done)"),
          "vm3 bug C: wiring: a yes no longer finishes the steps")
}

// MARK: - D: a press on the running tag

private func v3TagPressTests() {
    typealias P = ArisTagPress
    let size = CGSize(width: 180, height: 28)
    for point in [CGPoint(x: 90, y: 14), CGPoint(x: 0, y: 0), CGPoint(x: 180, y: 28), CGPoint(x: 1, y: 27), CGPoint(x: 179.5, y: 0.5), CGPoint(x: -2, y: 14), CGPoint(x: 182, y: 30)] {
        check(P.ended(at: point, in: size, pressable: true) == .stop, "vm3 bug D: a press that ends anywhere inside the tag's frame stops (\(point))")
    }
    for point in [CGPoint(x: 90, y: 40), CGPoint(x: -10, y: 14), CGPoint(x: 200, y: 14), CGPoint(x: 90, y: -8)] {
        if case .ignored(let reason) = P.ended(at: point, in: size, pressable: true) {
            check(reason.contains("outside") && reason.contains("180×28"), "vm3 bug D: a press let go away from the tag does nothing, and the log says where it ended (\(reason))")
        } else {
            check(false, "vm3 bug D: a press let go away from the tag does nothing (\(point))")
        }
    }
    check(P.ended(at: CGPoint(x: 90, y: 14), in: size, pressable: false) == .ignored("the tag was no longer running")
          && P.ended(at: CGPoint(x: 1, y: 1), in: .zero, pressable: true) == .ignored("the tag had no frame yet"),
          "vm3 bug D: a press on a tag that stopped running, or that has no frame yet, does nothing and says why")
    // The frame is the one at the press: a tag that grew since its first layout (the clock came in) takes a press on its new part.
    check(P.ended(at: CGPoint(x: 170, y: 14), in: CGSize(width: 180, height: 28), pressable: true) == .stop
          && P.ended(at: CGPoint(x: 170, y: 14), in: CGSize(width: 120, height: 28), pressable: true) != .stop,
          "vm3 bug D: the frame that counts is the tag's own at the press (a size kept from an earlier layout would refuse the wider tag's end)")
    check(P.logLine(P.takenAway) == "a press on the running tag did nothing: it was taken away before it ended",
          "vm3 bug D: a press that was received and not acted on writes one line with its reason")
    let tag = v3Code("Aris/private/Aris/Home/ArisActivityTag.swift")
    check(tag.contains("GeometryReader { geometry in") && tag.contains(".gesture(press(in: geometry.size))")
          && tag.contains("switch ArisTagPress.ended(at: value.location, in: size, pressable: pressable) {") && !tag.contains("@State private var size"),
          "vm3 bug D: wiring: the press is judged against the tag's frame as it is, not a stored size")
    check(tag.components(separatedBy: "log.notice(\"\\(ArisTagPress.logLine(").count == 3,
          "vm3 bug D: wiring: an ignored press and one taken away are both logged")
    let windows = v3Code("Aris/private/Notch/ArisNotchWindows.swift")
    check(windows.contains("panel.contentView = ArisNotchHostingView(rootView:") && windows.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }"),
          "vm3 bug D: wiring: a click on the notch counts even when its panel is not key (the keyboard went back to the app behind after a card)")
}

// MARK: - The smaller things of both reports

private func v3SmallerTests() {
    // The why-not sentence names the AI in the answer's language.
    let lead = ArisWhyDeclined.lead(brain: ArisWhyCopy.englishBrain("API 브레인"), ranNothing: true, rule: nil, korean: false)
    check(lead.contains("API model answered in its own words") && !lead.contains("브레인"), "vm3 smaller: the English why-not sentence says “API model”, not “API 브레인” (\(lead))")
    check(v3Code("ArisAgent/ArisWhyAnswer.swift").contains("ArisWhyDeclined.lead(brain: record.brains.last.map(brain), ranNothing: ranNothing"),
          "vm3 smaller: wiring: the lead gets the AI's name as the answer says it")
    check(ArisWhyDeclined.lead(brain: "API 브레인", ranNothing: true, rule: nil, korean: true).contains("API 브레인"), "vm3 smaller: the Korean sentence is as it was")
    // The power card: the plain words alone, for exactly the four fixed scripts.
    for (verb, title) in [("restart", "Mac 재시동"), ("shut down", "Mac 끄기"), ("log out", "로그아웃"), ("sleep", "Mac 잠자기")] {
        let command = "osascript -e 'tell application \"System Events\" to \(verb)'"
        let card = ArisCodexDriver.describe(command: command, tools: "/t/aris-tools")
        check(card.0 == title && card.1 == ArisCardWords.power(verb).detail && !card.1.contains("osascript") && !card.1.contains("System Events") && !card.1.contains("\n"),
              "vm3 smaller: the \(verb) card shows only the plain words, no raw script under them (\(card.1))")
    }
    let other = ArisCodexDriver.describe(command: "osascript -e 'tell application \"System Events\" to restart' -e 'beep'", tools: "/t/aris-tools")
    check(other.0 != "Mac 재시동" && other.1.contains("beep") && ArisCommandPolicy.powerVerb(script: "tell application \"System Events\" to restart with delay") == nil,
          "vm3 smaller: any other script is no power card and keeps its command on the card")
    // The notch steps aside for System Settings' list and for the reader.
    let aside = v3Code("Aris/private/Notch/ArisStepAside.swift")
    check(aside.contains("static func openedElsewhere() {\n        NotificationCenter.default.post(name: .arisSettingsOpenedByPress, object: nil)")
          && v3Code("Aris/private/Aris/ArisFixModel.swift").contains("open(pane)\n                ArisStepAside.openedElsewhere()"),
          "vm3 smaller: the Reminders fix button (any fix that opens macOS's own list) takes the open notch out of the list's way")
    check(v3Code("Aris/private/Aris/Home/ArisTurnView.swift").contains("ArisBoard.shared.open(answer: shownReply, question: session.heard)\n        ArisStepAside.openedElsewhere()"),
          "vm3 smaller: “Read more ›” takes the notch out of the reader's way, so the two texts never run through each other")
    // The second report's.
    let leave = v3Code("Aris/private/Aris/Onboarding/ArisOnboardingGuide+Leave.swift")
    check(leave.contains("hidden: \\(settings?.isHidden ?? asked, privacy: .public)") && !leave.contains("hidden: \\(hidden, privacy: .public)"),
          "vm3n smaller: the setup's log says whether System Settings is hidden from what the app says after the hide, not from hide()'s early answer")
    check(v3Code("Aris/private/Aris/ArisPermissionGuide.swift").contains("panel.hasShadow = false") && !v3Code("Aris/private/Aris/ArisPermissionGuide.swift").contains("panel.hasShadow = true"),
          "vm3n smaller: the helper panel draws no window shadow (the grey box outline around it)")
    let strings = v3Source("Aris/components/Settings/Settings.xcstrings")
    check(strings.contains("A small model that takes short requests before the AI does (TypeSafe Jev) · optional") && !strings.contains("\"TypeSafe Jev · optional\"")
          && v3Code("Aris/components/Settings/ArisAIServicesPage.swift").contains("짧은 말을 AI보다 먼저 알아듣는 작은 모델(TypeSafe Jev) · 없어도 돼요"),
          "vm3n smaller: the AI services row says in one clause what TypeSafe Jev is")
    check(!strings.contains("Aris is two programs") && strings.contains("drag the Aris icon into the list there")
          && !v3Code("Aris/components/Settings/ArisSettingsBuilder.swift").contains("프로그램이 둘이라"),
          "one row: Settings › Computer control's intro names one program, Aris, to drag into the list")
}

private func v3SmallerLogicTests() {
    // The reason line: a card that is there only because outside content was read says so, on every brain.
    typealias G = ArisGateReason
    check(G.raised(outside: true, hardLine: false, cleanRisk: .auto, asksAfter: true),
          "vm3 smaller: an action that runs by itself and is carded only because outside content was read is known as that (a conversion after the brain's own `files find`)")
    check(!G.raised(outside: false, hardLine: false, cleanRisk: .auto, asksAfter: true) && !G.raised(outside: true, hardLine: true, cleanRisk: .auto, asksAfter: true)
          && !G.raised(outside: true, hardLine: false, cleanRisk: .confirm, asksAfter: true) && !G.raised(outside: true, hardLine: false, cleanRisk: .countdown, asksAfter: true)
          && !G.raised(outside: true, hardLine: false, cleanRisk: .never, asksAfter: true) && !G.raised(outside: true, hardLine: false, cleanRisk: .auto, asksAfter: false),
          "vm3 smaller: never in a clean conversation, across a hard line, for an action that asks anyway, or a kind that isn't asked after outside text")
    let convert = ArisConfirmation(id: "c1", title: "파일 변환", detail: "Desktop › noise-long.wav\n→ M4A", full: "whole", fields: [], allow: nil)
    let said = G.card(for: convert, raised: true)
    check(said.detail == ArisEscalation.taintedReason + "\nDesktop › noise-long.wav\n→ M4A" && said.full == ArisEscalation.taintedReason + "\nwhole" && said.id == "c1" && said.title == convert.title
          && ArisGateWords.detail(said.detail).hasPrefix("Asking once more because outside content was read\n"),
          "vm3 smaller: its card opens with “Asking once more because outside content was read”, as the trash card after the same `files find` does")
    check(G.card(for: said, raised: true) == said && G.card(for: convert, raised: false) == convert
          && G.card(for: ArisConfirmation(id: "m", title: "엄마", detail: "곧 갈게", countdown: true), raised: true).countdown,
          "vm3 smaller: the line is said once, never on a card that is there anyway, and a countdown stays a countdown")
    let h = "/Users/x", t = "/t/aris-tools"
    let conversion = ArisAction.shell("\(t) convert \(h)/Desktop/noise-long.wav --to m4a")
    check(ArisRiskPolicy.bringsInUntrusted(.shell("\(t) files find noise-long.wav --in \(h)/Desktop"), tools: t, home: h),
          "vm3 smaller: a `files find` result is outside text to the gate (file names are whoever's)")
    check(G.raised(outside: true, hardLine: ArisRiskPolicy.hardLine(of: conversion, tools: t) != nil,
                   cleanRisk: ArisRiskPolicy.risk(of: conversion, tools: t, home: h, request: "convert noise-long.wav on my Desktop to m4a"),
                   asksAfter: ArisRiskPolicy.asksAfterOutsideText(conversion, tools: t)),
          "vm3 smaller: by the gate's own rules the tester's conversion is such a card (risk \(ArisRiskPolicy.risk(of: conversion, tools: t, home: h, request: "convert noise-long.wav on my Desktop to m4a")), asked after outside text \(ArisRiskPolicy.asksAfterOutsideText(conversion, tools: t)))")
    let runner = v3Code("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("let escalated = ArisEscalation.card(for: ask, approvable: approvable, hardLine: hardLine, tainted: tainted)")
          && runner.contains("let ask = ArisGateReason.card(for: escalated, raised: raised)")
          && runner.contains("ArisGateReason.raised(outside: driver.taint.blocks(covered: pendingAction.covered), hardLine: hardLine != nil,"),
          "vm3 smaller: wiring: the rule is applied where every brain's card passes, so no brain's card differs")
    // The 한 일 tab: no Undo on a timer that has run out.
    func row(_ summary: String, ago: TimeInterval, undoable: Bool = true, undone: Bool = false) -> ArisActivityItem {
        ArisActivityItem(id: "x", date: Date(timeIntervalSince1970: 10_000 - ago), job: "Aris", worker: "user", summary: summary, undoable: undoable, undone: undone, asks: false)
    }
    let now = Date(timeIntervalSince1970: 10_000)
    check(ArisActivityTab.style(row("타이머: 5분", ago: 301), now: now) == .plain && ArisActivityTab.style(row("타이머: 1분", ago: 3_600), now: now) == .plain,
          "vm3 smaller: a timer that has already ended offers no Undo in the 한 일 tab")
    check(ArisActivityTab.style(row("타이머: 5분", ago: 120), now: now) == .undo && ArisActivityTab.style(row("타이머: 1시간 30분", ago: 3_600), now: now) == .undo,
          "vm3 smaller: a timer still running keeps its Undo")
    check(ArisActivityTab.style(row("할 일 추가: 타이머: 5분 사기", ago: 9_000), now: now) == .undo && ArisActivityTab.style(row("볼륨 올림", ago: 9_000), now: now) == .undo
          && ArisActivityTab.style(row("타이머: 곧", ago: 9_000), now: now) == .undo && ArisActivityTab.style(row("타이머: 5분", ago: 9_000, undone: true), now: now) == .undone,
          "vm3 smaller: every other row is as it was (a line that only mentions a timer, a length that can't be read, an undone row)")
    check(ArisActivityWords.timerLength("타이머: 90초") == 90 && ArisActivityWords.timerLength("타이머: 25") == 1_500 && ArisActivityWords.timerLength("타이머: 1시간 30분") == 5_400
          && ArisActivityWords.timerLength("타이머 끔") == nil, "vm3 smaller: a logged timer's length is read from its line")
    // The ✦ menu's side panel item.
    check(ArisSideMenu.title(.left, open: true, english: true) == "Close the side panel" && ArisSideMenu.title(.right, open: true, english: true) == "Close the right side panel"
          && ArisSideMenu.title(.left, open: true, english: false) == "사이드 패널 닫기" && ArisSideMenu.title(.left, english: true) == "Open the side panel"
          && ArisSideMenu.act(open: true) == .close && ArisSideMenu.act(open: false) == .open,
          "vm3n smaller: the ✦ menu says “Close the side panel” while it is open, and choosing it closes it")
    let status = v3Code("Aris/private/Aris/ArisStatusItem.swift")
    check(status.contains("ArisSideMenu.title(side, open: ArisSidePanels.shared.open.contains(side))") && status.contains("return ArisSidePanels.shared.collapse(.left)")
          && status.contains("return ArisSidePanels.shared.collapse(.right)") && status.contains("ArisSettingsWindow.shared.show()\n        ArisSidePanels.shared.stepAside()"),
          "vm3n smaller: wiring: the menu's item toggles its side, and Settings opened from the menu folds an open side panel out of its way")
}

// MARK: - vm3n: an open notch that was never told of a hover

private func v3OpenNotchPointerTests() {
    typealias P = ArisNotchPointer
    var watch = P.OpenWatch()
    // Opened from the keyboard or by Aris, the pointer never on it: nothing is ever closed by this watch.
    for _ in 0..<10 {
        let step = P.openStep(watch, onNotch: false, buttonDown: false)
        watch = step.next
        check(!step.left, "vm3n pointer: a pointer that was never on the open notch closes nothing")
    }
    // The notch opened under a still pointer (no hover event): found on it, then gone in one jump.
    var seen = P.openStep(P.OpenWatch(), onNotch: true, buttonDown: false)
    check(seen.next == P.OpenWatch(seenOn: true, misses: 0) && !seen.left, "vm3n pointer: with no hover known, the pointer found on the open notch is noted")
    seen = P.openStep(seen.next, onNotch: false, buttonDown: false)
    check(!seen.left && seen.next.misses == 1, "vm3n pointer: one look that finds it gone is not yet a leave (it may be crossing an edge)")
    seen = P.openStep(seen.next, onNotch: false, buttonDown: false)
    check(seen.left, "vm3n pointer: found gone twice in a row, it has left though no hover event ever said so: the notch closes as after a hover")
    // Back on it in between, or a drag that began on it, never counts.
    var back = P.openStep(P.OpenWatch(seenOn: true, misses: 1), onNotch: true, buttonDown: false)
    check(back.next.misses == 0 && !back.left, "vm3n pointer: a pointer found back on the notch starts the count again")
    back = P.openStep(P.OpenWatch(seenOn: true, misses: 1), onNotch: false, buttonDown: true)
    check(back.next.misses == 0 && !back.left, "vm3n pointer: a held mouse button (a drag that began on the notch) is never a leave")
    check(P.trustGained(trusted: false, hovering: true, measured: true, onNotch: true) && P.trustGained(trusted: true, hovering: false, measured: false, onNotch: false)
          && !P.trustGained(trusted: false, hovering: true, measured: true, onNotch: false) && !P.trustGained(trusted: false, hovering: true, measured: false, onNotch: true)
          && !P.trustGained(trusted: false, hovering: false, measured: true, onNotch: true),
          "vm3n pointer: a hover that began while the measurement disagreed is trusted once the events and the measured place agree, and only then")
    let root = v3Code("Aris/private/Notch/ArisNotchRoot+Behaviour.swift")
    check(root.contains("openingUntil = Date().addingTimeInterval(0.28 / speed)\n            watchOpen()") && root.contains("ArisNotchPointer.openStep(watch, onNotch: onNotch, buttonDown: NSEvent.pressedMouseButtons != 0)")
          && root.contains("guard step.left else { continue }\n                if mayCloseAutomatically { vm.close() }"),
          "vm3n pointer: wiring: the watch runs while the notch is open, and closes it only where a hover's end would")
}

// MARK: - The turns aris-agent answers itself are recorded as its own

private func v3HelperAnswersTests() {
    let line = String(decoding: ArisAgentReply.helperAnswers.line, as: UTF8.self)
    check(ArisAgentReply.parse(line) == .helperAnswers && !ArisAgentReply.helperAnswers.isLast && ArisAgentReply.parse("{\"own\":false}") != .helperAnswers,
          "vm3 smaller: aris-agent can say on the turn's stream that it answers this one itself, and the turn goes on to its answer")
    check(ArisTurnPath.answerer(brain: "api", helper: true) == "aris-agent" && ArisTurnPath.answerer(brain: "codex", helper: false) == "codex" && ArisTurnPath.helper == "helper",
          "vm3 smaller: such a turn's log line says “aris-agent answered”, never the name of a brain that was not asked")
    var stats = ArisTurnStats(startedAt: .now)
    stats.heard("why did you do that?", path: "brain:api", tier: "quick", at: .now)
    stats.answered(by: ArisTurnPath.helper)
    check(String(describing: stats).contains("helper") && !String(describing: stats).contains("brain:api"),
          "vm3 smaller: and turns.jsonl records it as the helper's, not as “brain:api”")
    let morning = ArisRoutine(id: UUID(), name: "morning", steps: ["a", "b"], own: true, created: Date(), changed: Date())
    check(ArisRoutineIntent.run(morning).asksAnAI && !ArisRoutineIntent.list.asksAnAI && !ArisRoutineIntent.create(name: "x", steps: ["a"]).asksAnAI
          && !ArisRoutineIntent.delete(morning).asksAnAI && !ArisRoutineIntent.dropStep(morning, words: "a").asksAnAI && !ArisRoutineIntent.show(morning).asksAnAI,
          "vm3 smaller: making, changing, listing, showing and deleting a routine ask no AI; only a run may")
    let agent = v3Code("ArisAgent/main.swift")
    check(agent.contains("stream(.helperAnswers, on: connection)\n                                           stream(.answer(text), on: connection)")
          && v3Code("ArisAgent/ArisRoutineTurn.swift").contains("if !intent.asksAnAI { stream(.helperAnswers, on: connection) }"),
          "vm3 smaller: wiring: the why answer and the routine's own answers are marked as the helper's")
    let controller = v3Code("Aris/private/Aris/ArisController.swift")
    check(controller.contains("stats?.answered(by: ArisTurnPath.helper)") && controller.contains("ArisTurnPath.answerer(brain: brain.rawValue, helper: helperAnswers)"),
          "vm3 smaller: wiring: the app records and logs it")
}

private func v3HelperRestartTests() {
    typealias W = ArisFixWords
    check(W.stillRestarting(answering: false, waited: 0) && W.stillRestarting(answering: false, waited: 20) && W.stillRestarting(answering: false, waited: W.restartLimit - 1),
          "vm3 smaller: the helper's button keeps reading “Restarting the helper…” while the restart is under way (it went back after a few seconds, 15 s early)")
    check(!W.stillRestarting(answering: true, waited: 3) && !W.stillRestarting(answering: false, waited: W.restartLimit) && W.restartLimit >= 30,
          "vm3 smaller: until the helper answers, or a stated limit: then it is the button again")
    let model = v3Code("Aris/private/Aris/ArisFixModel.swift")
    check(model.contains("if !answering { await showRestarting() }") && model.contains("while ArisFixWords.stillRestarting(answering: answering, waited: Date().timeIntervalSince(began)) {")
          && model.contains("if answering { say(ArisFixWords.helperBack(english: ArisUIWords.english)) } else { feedback = nil }"),
          "vm3 smaller: wiring: the button follows that rule and says when the helper is back")
}
