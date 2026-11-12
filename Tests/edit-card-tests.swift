// Tests for the owner's ②A (mockups/new-features.html, section 2): the confirm card whose values the user can change before they says
// yes. Which fields an action has is the agent's code (ArisEditableAction), the change is re-checked and re-judged by the
// risk gate, the yes echoes the edited card as shown (ArisShownCard), and "내일로 바꿔" changes the card without sending.
// Called from main.swift; uses its check().
import Foundation

func runEditCardTests() {
    editSchemaTests()
    editDiffTests()
    editValidationTests()
    editVerdictTests()
    editEchoTests()
    editReviseTests()
    editListeningTests()
    editLedgerTests()
    editCodexCardTests()
    editDetailTests()
    editDeclineTests()
}

private let editTools = "/Users/p/.config/aris/aris-tools"
private let editHome = "/Users/p"

private func editable(_ command: String) -> ArisEditableAction? {
    ArisEditableAction.parse(.shell(command), tools: editTools)
}

private func editRisk(_ action: ArisEditableAction) -> ArisRisk {
    ArisRiskPolicy.risk(of: .shell(action.command), tools: editTools, home: editHome)
}

// MARK: - Which fields each action has (code, never the model)

private func editSchemaTests() {
    let message = editable("\(editTools) message 엄마 '잘 도착했어요! 저녁 맛있게 드세요'")
    check(message?.kind == .message && message?.fields.map(\.key) == ["to", "text"]
          && message?.fields.map(\.label) == ["받는 사람", "내용"] && message?.fields.map(\.role) == [.recipient, .text],
          "edit card: a message has 받는 사람 and 내용")
    check(message?.fields.map(\.value) == ["엄마", "잘 도착했어요! 저녁 맛있게 드세요"] && message?.fields.allSatisfy { $0.original == nil } == true,
          "edit card: a message's fields are the command's own words")
    check(editable("\(editTools) message 엄마 곧 갈게")?.fields.last?.value == "곧 갈게", "edit card: an unquoted message is its words joined")

    let remind = editable("\(editTools) remind '우유 사기' --at '2026-11-05 18:00'")
    check(remind?.kind == .remind && remind?.fields.map(\.key) == ["text", "at"] && remind?.fields.last?.role == .time
          && remind?.fields.last?.value == "2026-11-05 18:00", "edit card: a reminder has 내용 and 때")
    check(editable("\(editTools) remind 우유 사기")?.fields.map(\.key) == ["text"], "edit card: a reminder with no time has only 내용")

    let event = editable("\(editTools) event '치과' --start '2026-11-06 15:00' --minutes 30 --calendar 집")
    check(event?.kind == .event && event?.fields.map(\.key) == ["title", "start", "minutes", "calendar"] && event?.fields.first?.value == "치과"
          && event?.fields.map(\.fixed) == [false, false, true, true], "edit card: an event has 제목 and 시작, and shows its length and calendar fixed")
    check(event?.applying(["minutes": "90"]) == nil && event?.applying(["calendar": "회사"]) == nil, "edit card: a fixed field can't be changed")
    check(event.map { ArisCardEdit.shown($0.fields, ArisCardEdit.values($0.fields).merging(["minutes": "90"]) { $1 }) }?.contains("길이 (분): 30") == true,
          "edit card: a fixed field shows as it was, whatever the card's values say")
    check(event.map { [editTools] + $0.arguments } == ArisCommandPolicy.words("\(editTools) event 치과 --start '2026-11-06 15:00' --minutes 30 --calendar 집"),
          "edit card: an event keeps its length and calendar as they were")

    for command in ["\(editTools) trash ~/a.txt", "\(editTools) message 엄마", "\(editTools) message 엄마 hi && \(editTools) message 아빠 hi",
                    "osascript -e 'tell application \"Messages\" to send'", "/bin/echo message 엄마 hi", "\(editTools) mail a@b.c hi",
                    "\(editTools) event 치과", "\(editTools) remind --at '2026-11-05 18:00'"] {
        check(editable(command) == nil, "edit card: nothing to edit on \(command)")
    }
    check(ArisEditableAction.parse(.mcp(server: "gmail", tool: "send"), tools: editTools) == nil
          && ArisEditableAction.parse(.computerUse(app: "Messages"), tools: editTools) == nil,
          "edit card: tools and computer use have no editable fields")
}

// MARK: - What changed, and the text the card finally shows

private func editDiffTests() {
    let fields = editable("\(editTools) message 엄마 '잘 도착했어요'")!.fields
    let start = ArisCardEdit.values(fields)
    check(start == ["to": "엄마", "text": "잘 도착했어요"], "edit diff: the card starts with the AI's values")
    check(ArisCardEdit.edits(fields, start).isEmpty, "edit diff: nothing changed, nothing to send back")
    let changed = start.merging(["text": "잘 도착했어요!!"]) { $1 }
    check(ArisCardEdit.edits(fields, changed) == ["text": "잘 도착했어요!!"], "edit diff: only the changed field goes back")
    check(ArisCardEdit.isMarked(fields[1], changed) && !ArisCardEdit.isMarked(fields[0], changed),
          "edit diff: only the changed field is highlighted")
    check(!ArisCardEdit.isMarked(fields[1], start), "edit diff: changing it back takes the highlight away")
    check(ArisCardEdit.shown(fields, changed) == "받는 사람: 엄마\n내용: 잘 도착했어요!!", "edit diff: the card's text is each label and its value")

    // A card that asks again about values the user changed: highlighted against what the AI first wrote.
    let again = [ArisCardField(key: "to", label: "받는 사람", role: .recipient, value: "아빠", original: "엄마")]
    check(ArisCardEdit.isMarked(again[0], ArisCardEdit.values(again)) && ArisCardEdit.edits(again, ArisCardEdit.values(again)).isEmpty,
          "edit diff: a re-asked card shows the change, but nothing new goes back")

    let line = ArisAgentReply.confirm(ArisConfirmation(id: "c1", title: "메시지 보내기", detail: "d", fields: again)).line
    check(ArisAgentReply.parse(String(decoding: line.dropLast(), as: UTF8.self)) == .confirm(ArisConfirmation(id: "c1", title: "메시지 보내기", detail: "d", fields: again)),
          "edit diff: a card's fields survive the stream")
    check(ArisCardEdit.parse([["key": "to", "label": "받는 사람", "role": "boss", "value": "x"]]).isEmpty
          && ArisCardEdit.parse([["key": "to", "label": "a", "role": "text", "value": "x"], ["key": "to", "label": "b", "role": "text", "value": "y"]]).count == 1
          && ArisCardEdit.parse("nope").isEmpty, "edit diff: unknown roles, repeated keys and junk are dropped")
    check(ArisCardEdit.edits(from: ["to": "아빠"]) == ["to": "아빠"] && ArisCardEdit.edits(from: ["to": 3]) == nil
          && ArisCardEdit.edits(from: ["to": String(repeating: "a", count: ArisCardEdit.maxLength + 1)]) == nil
          && ArisCardEdit.edits(from: nil) == [:], "edit diff: /confirm takes edits only as short strings")
}

// MARK: - The agent checks the change again

private func editValidationTests() {
    let base = editable("\(editTools) message 엄마 '잘 도착했어요'")!
    check(base.applying(["nick": "x"]) == nil, "edit check: a field the action doesn't have is refused")
    check(base.applying(["to": "  "]) == nil && base.applying(["text": ""]) == nil, "edit check: an empty value is refused")
    check(base.applying(["to": "-v"]) == nil && base.applying(["text": "--at"]) == nil, "edit check: a value that reads as an option is refused")
    check(base.applying(["to": "엄마\n아빠"]) == nil, "edit check: a recipient is one line")
    check(base.applying(["text": "a\u{0}b"]) == nil && base.applying(["text": "a\u{1B}[2Jb"]) == nil, "edit check: control characters are refused")
    check(base.applying(["text": "첫 줄\n둘째 줄"]) != nil, "edit check: a message may have lines")
    check(base.applying(["to": "엄마\u{2028}아빠"]) == nil && base.applying(["to": "엄마\u{2029}"]) == nil,
          "edit check: no line or paragraph separator outside a message's words")
    check(base.applying(["text": "가족 👨\u{200D}👩\u{200D}👧 사랑해"]) != nil && base.applying(["text": "❤️\u{200D}🔥"]) != nil,
          "edit check: a ZWJ inside an emoji sequence is fine")
    check(base.applying(["text": "a\u{200D}b"]) == nil && base.applying(["text": "abc\u{202E}def"]) == nil && base.applying(["to": "👨\u{200D}👩"]) == nil,
          "edit check: a ZWJ elsewhere, a bidi override, or a ZWJ in a recipient is refused")
    let remindCard = editable("\(editTools) remind 'x' --at '2026-11-05 18:00'")!.fields
    check(!ArisCardEdit.allAccepted(remindCard, ["text": "x", "at": "내일 6시"]) && ArisCardEdit.allAccepted(remindCard, ["text": "x", "at": "2026-11-06 18:00"]),
          "edit check: the app holds 보내기 until a time reads as YYYY-MM-DD HH:MM")

    let edited = base.applying(["text": "it's \"fine\" $HOME `x` (ok)"])!
    check(ArisCommandPolicy.words(edited.command) == [editTools, "message", "엄마", "it's \"fine\" $HOME `x` (ok)"],
          "edit check: the changed command reads back as exactly its words (quotes, $ and backticks are just text)")
    check(edited.fields[1].original == "잘 도착했어요" && edited.fields[0].original == nil, "edit check: the AI's first value is kept for 원래")
    check(edited.applying(["text": "잘 도착했어요"])?.fields[1].original == nil, "edit check: changed back, nothing is marked")

    let remind = editable("\(editTools) remind '우유 사기' --at '2026-11-05 18:00'")!
    check(remind.applying(["at": "2026-11-06 18:00"])?.arguments == ["remind", "우유 사기", "--at", "2026-11-06 18:00"],
          "edit check: a reminder's new time goes into --at")
    check(remind.applying(["at": "내일 6시"]) == nil && remind.applying(["at": "2026-02-30 10:00"]) == nil
          && remind.applying(["at": "2026-11-06 25:00"]) == nil, "edit check: a time must be a real YYYY-MM-DD HH:MM")
}

// MARK: - Risk again: an edit that raises it needs a fresh yes

private func editVerdictTests() {
    let base = editable("\(editTools) message 엄마 '잘 도착했어요'")!
    let text = base.applying(["text": "잘 도착했어요!!"])!
    let to = base.applying(["to": "아빠"])!
    let link = base.applying(["text": "여기 봐 https://example.com/x"])!
    let bareLink = base.applying(["text": "여기 봐 evil.co/x"])!
    check(ArisEditableAction.raise(from: base, to: text) == nil, "edit verdict: fixing the words is covered by the yes")
    check(ArisEditableAction.raise(from: base, to: to) != nil, "edit verdict: a new recipient asks again")
    check(ArisEditableAction.raise(from: base, to: link) != nil && ArisEditableAction.raise(from: base, to: bareLink) != nil,
          "edit verdict: a link added asks again")
    for added in ["192.168.0.1:8080/x 봐", "10.0.0.7", "www.example.org", "mail me at a@b.com"] {
        check(ArisEditableAction.raise(from: base, to: base.applying(["text": added])!) != nil, "edit verdict: \(added) is a link")
    }
    check(ArisEditableAction.links(in: "버전 1.2.3 이에요, 3.5시간 걸려요").isEmpty, "edit verdict: numbers with dots aren't links")
    let hasLink = editable("\(editTools) message 엄마 'https://example.com/x 봐'")!
    check(ArisEditableAction.raise(from: hasLink, to: hasLink.applying(["text": "https://example.com/x 봐 줘"])!) == nil,
          "edit verdict: the link that was already there doesn't")

    check(ArisEditableAction.verdict(base: base, edited: text, risk: editRisk(text), baseRisk: editRisk(base), hardLine: false) == .run,
          "edit verdict: a plain fix runs")
    if case .reask = ArisEditableAction.verdict(base: base, edited: to, risk: editRisk(to), baseRisk: editRisk(base), hardLine: false) {} else {
        check(false, "edit verdict: a new recipient is a fresh card")
    }
    let sneaky = base.applying(["text": "hi; sudo rm -rf ~"])!
    // Audit gate-7: what the user types into a message is only text (the agent runs the changed command word by word, with
    // no shell), so the never-list no longer reads it as a command; a rating of never is still refused.
    check(editRisk(sneaky) == editRisk(base) && editRisk(sneaky) != .never, "edit verdict: the risk gate judges the changed command itself (a message's words are text)")
    if case .refuse = ArisEditableAction.verdict(base: base, edited: sneaky, risk: .never, baseRisk: editRisk(base), hardLine: false) {} else {
        check(false, "edit verdict: what the gate never allows is refused")
    }
    if case .refuse = ArisEditableAction.verdict(base: base, edited: text, risk: .confirm, baseRisk: .confirm, hardLine: true) {} else {
        check(false, "edit verdict: a hard line is refused")
    }
    if case .reask = ArisEditableAction.verdict(base: base, edited: text, risk: .confirm, baseRisk: .auto, hardLine: false) {} else {
        check(false, "edit verdict: an edit the gate rates riskier asks again")
    }
    check(ArisEditableAction.verdict(base: base, edited: text, risk: .confirm, baseRisk: .countdown, hardLine: false) == .run,
          "edit verdict: a countdown shown as a card is already a question")
    check(ArisEditableAction.verdict(base: to, edited: to, risk: editRisk(to), baseRisk: editRisk(to), hardLine: false) == .run,
          "edit verdict: the fresh card's own yes runs it")
    check(to.outcome(status: 0, error: "").contains("아빠") && to.outcome(status: 1, error: "no contact").contains("no contact"),
          "edit verdict: what Aris says after it ran, with the real error")
    check(to.outcome(status: nil, error: "").contains("보냈는지 확인해 주세요"), "edit verdict: stopped at the time limit, the user is asked to check")
    check(ArisEditableAction.answer("날씨는 맑아요.", outcomes: ["아빠한테 보냈어요.", "알림을 넣었어요."])
          == "아빠한테 보냈어요.\n\n알림을 넣었어요.\n\n날씨는 맑아요." && ArisEditableAction.answer("답", outcomes: []) == "답"
          && ArisEditableAction.answer("  ", outcomes: ["o"]) == "o", "edit verdict: the outcomes come first, the AI's answer stays")
    check(ArisEditableAction.steer(outcome: "아빠한테 보냈어요.").contains("not a refusal"), "edit verdict: the AI is told the decline was the user's change")
}

// MARK: - The yes echoes the card as finally shown

private func editEchoTests() {
    let fields = editable("\(editTools) message 엄마 '잘 도착했어요'")!.fields
    let edits = ["text": "잘 도착했어요!!"]
    let shown = ArisCardEdit.shown(fields, ArisCardEdit.values(fields).merging(edits) { $1 })
    func matches(allow: Bool = true, detail: String? = "d", fields: [ArisCardField], edits: [String: String], shown: String?) -> Bool {
        ArisShownCard.matches(allow: allow, detail: detail, full: nil, expectedDetail: "d", expectedFull: nil, fields: fields, edits: edits, shown: shown)
    }
    check(matches(fields: fields, edits: edits, shown: shown), "edit echo: the edited card as shown is the yes")
    check(!matches(fields: fields, edits: edits, shown: ArisCardEdit.shown(fields, ArisCardEdit.values(fields))),
          "edit echo: showing the old text while sending a change is refused")
    check(!matches(fields: fields, edits: edits, shown: nil), "edit echo: a change without its shown text is refused")
    check(!matches(fields: fields, edits: ["nick": "x"], shown: shown), "edit echo: a change to a field the card hasn't is refused")
    check(!matches(fields: [], edits: edits, shown: shown), "edit echo: a card with no fields takes no changes")
    check(!matches(detail: "other", fields: fields, edits: edits, shown: shown), "edit echo: the card it came from must still match")
    check(matches(fields: fields, edits: [:], shown: nil) && matches(fields: [], edits: [:], shown: nil),
          "edit echo: an unchanged yes is as before")
    check(matches(allow: false, detail: nil, fields: fields, edits: ["nick": "x"], shown: "anything"), "edit echo: a no needs no match")
}

// MARK: - "내일로 바꿔": the card changes, nothing is sent

private func editReviseTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 14, minute: 41))!
    let remind = editable("\(editTools) remind '엄마한테 전화' --at '2026-11-05 18:00'")!.fields
    let message = editable("\(editTools) message 엄마 '잘 도착했어요'")!.fields
    func revise(_ said: String, _ fields: [ArisCardField]) -> [String: String]? {
        ArisCardRevise.parse(said, fields: fields, values: ArisCardEdit.values(fields), now: now, calendar: calendar)
    }
    check(revise("내일로 바꿔", remind) == ["at": "2026-11-06 18:00"], "revise: 내일로 바꿔 moves the day, keeps the time")
    check(revise("모레로 해 줘", remind) == ["at": "2026-11-07 18:00"], "revise: 모레로")
    check(revise("7시로 바꿔", remind) == ["at": "2026-11-05 19:00"], "revise: 7시 on an evening time stays evening")
    check(revise("오전 9시 반으로", remind) == ["at": "2026-11-05 09:30"], "revise: 오전 9시 반")
    check(revise("내일 오후 3시로", remind) == ["at": "2026-11-06 15:00"], "revise: a day and a time together")
    check(revise("18:30으로 바꿔", remind) == ["at": "2026-11-05 18:30"], "revise: a clock time")
    check(revise("내용은 아빠한테 전화로 바꿔", remind) == ["text": "아빠한테 전화"], "revise: the words, by their label")
    check(revise("아빠한테 보내", message) == ["to": "아빠"], "revise: a new recipient")
    check(revise("받는 사람 민지로 바꿔", message) == ["to": "민지"], "revise: a recipient by its label")
    check(revise("내용은 곧 갈게로 바꿔", message) == ["text": "곧 갈게"], "revise: a message's words")
    check(revise("엄마한테 보내", message) == nil, "revise: the same recipient changes nothing")
    check(revise("내일로 바꿔", message) == nil, "revise: a message has no time to move")
    check(revise("응, 보내", message) == nil && revise("날씨 어때", message) == nil && revise("", message) == nil,
          "revise: a yes or another question isn't a change")
    // Security review I2 stands: only a short yes form is a yes ("응"), never "보내"; the card's change never is.
    check(ArisConfirmReply.parse("응") == true && ArisConfirmReply.parse("응, 보내") == nil && ArisConfirmReply.parse("내일로 바꿔") == nil,
          "revise: 응 is the yes, 응 보내 and a change are not")
    check(ArisCardTime.friendly("2026-11-05 18:00", now: now, calendar: calendar) == "오늘 오후 6:00"
          && ArisCardTime.friendly("2026-11-06 09:30", now: now, calendar: calendar) == "내일 오전 9:30"
          && ArisCardTime.friendly("2026-11-20 12:00", now: now, calendar: calendar) == "11월 20일 오후 12:00"
          && ArisCardTime.friendly("soon", now: now, calendar: calendar) == nil, "revise: a time also reads as words")
}

private func editListeningTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 14, minute: 41))!
    let fields = editable("\(editTools) remind '엄마한테 전화' --at '2026-11-05 18:00'")!.fields
    let values = ArisCardEdit.values(fields)
    func revision(_ listening: ArisCardListening, at time: Double) -> [String: String]? {
        listening.revision(at: time, fields: fields, values: values, now: now, calendar: calendar)
    }
    var listening = ArisCardListening().heard("내일로", at: 0)
    check(revision(listening, at: 0.3) == nil, "revise voice: a change waits until the words hold still")
    listening = listening.heard("내일로 바꿔", at: 0.4)
    check(revision(listening, at: 0.8) == nil && revision(listening, at: 1.1) == ["at": "2026-11-06 18:00"],
          "revise voice: held still, the change shows")
    check(listening.answer(at: 5, voiceYes: true) == nil, "revise voice: a change is never a yes")
    listening = listening.consumed(at: 1.1)
    check(revision(listening, at: 5) == nil && listening.rest == "", "revise voice: a change is used once")
    // I1: the yes that goes on from the change, or comes right after it, doesn't count.
    let goesOn = ArisCardListening().heard("7시로", at: 0).consumed(at: 0.7).heard("7시로… 해 줘", at: 1.0)
    check(goesOn.rest == "" && goesOn.answer(at: 3, voiceYes: true) == nil && goesOn.final("7시로… 해 줘", at: 3, voiceYes: true) == nil,
          "revise voice: \"7시로… 해 줘\" is the change asked for, not a yes")
    let stop = ArisCardListening().heard("7시로", at: 0).consumed(at: 0.7).heard("7시로 그만 해 줘", at: 1.0)
    check(stop.rest == "그만 해 줘" && stop.answer(at: 1.0, voiceYes: true) == false, "revise voice: \"그만 해 줘\" after a change is still a no, at once")
    let soon = listening.heard("내일로 바꿔 응", at: 2.0)
    check(soon.rest == "응" && soon.answer(at: 2.7, voiceYes: true) == nil && soon.answer(at: 9, voiceYes: true) == nil
          && soon.final("내일로 바꿔 응", at: 9, voiceYes: true) == nil, "revise voice: a yes begun within 2 s of a change never counts")
    let later = listening.heard("내일로 바꿔 응", at: 3.2)
    check(later.answer(at: 3.5, voiceYes: true) == nil && later.answer(at: 3.9, voiceYes: true) == true,
          "revise voice: a yes begun 2 s after the change counts, once it held still")
    check(later.answer(at: 9, voiceYes: false) == nil, "revise voice: in a conversation or hands-free a spoken yes still isn't taken")
    let no = ArisCardListening().heard("내일로 바꿔", at: 0).consumed(at: 0.7).heard("내일로 바꿔 아니 취소", at: 1)
    check(no.answer(at: 1, voiceYes: false) == false, "revise voice: a no counts at once")
    check(ArisCardListening().heard("abc", at: 0).consumed(at: 0).heard("a", at: 1).rest == "", "revise voice: a shorter transcript is nothing new")
    check(ArisCardListening().heard("응", at: 0).answer(at: 0.7, voiceYes: true) == true, "revise voice: with no change, a yes is as before")

    // I2 and I5: typing keeps the card waiting; a click right after a change is ignored.
    check(ArisCardTiming.keepsWaiting(typing: true, changedAt: nil, now: 100) && ArisCardTiming.keepsWaiting(typing: false, changedAt: 96, now: 100)
          && !ArisCardTiming.keepsWaiting(typing: false, changedAt: 94, now: 100) && !ArisCardTiming.keepsWaiting(typing: false, changedAt: nil, now: 100),
          "edit timing: typing, or a change in the last 5 s, keeps the card waiting")
    check(!ArisCardTiming.clickCounts(changedAt: 99.5, now: 100) && ArisCardTiming.clickCounts(changedAt: 99, now: 100)
          && ArisCardTiming.clickCounts(changedAt: nil, now: 100), "edit timing: a click within 1 s of a change is ignored")
    check(ArisCardTiming.longestWait < ArisCardEdit.questionTimeout && ArisCardEdit.questionTimeout < 130,
          "edit timing: the app stops waiting before the agent, which stops before the stream's idle limit")
}

private func editLedgerTests() {
    let fields = editable("\(editTools) message 엄마 '잘 도착했어요'")!.fields
    ArisCardEditLedger.record(id: "c9", fields: fields, values: ArisCardEdit.values(fields))
    check(ArisCardEditLedger.take("c9") == nil, "edit ledger: an unchanged card sends nothing extra")
    let values = ArisCardEdit.values(fields).merging(["to": "아빠"]) { $1 }
    ArisCardEditLedger.record(id: "c9", fields: fields, values: values)
    let taken = ArisCardEditLedger.take("c9")
    check(taken?.edits == ["to": "아빠"] && taken?.shown == ArisCardEdit.shown(fields, values), "edit ledger: the change and the card as shown")
    check(ArisCardEditLedger.take("c9") == nil, "edit ledger: taken once")
}

// The gate's own card for a message the AI wrote: the action behind it is what the fields come from.
func editCodexCardTests() {
    let codex = ArisCodexDriver(model: "m", tools: policyTools, instructions: "i", home: "/Users/me")
    let events = codex.read(String(decoding: try! JSONSerialization.data(withJSONObject: ["id": 1, "method": "item/commandExecution/requestApproval",
        "params": ["command": "/bin/zsh -lc '\(policyTools) message 엄마 \"잘 도착했어요\"'"]]), as: UTF8.self))
    guard case .confirm(let ask)? = events.first, !ask.countdown, let pending = codex.escalation(for: ask.id) else {
        return check(false, "edit card: the AI's message should come to the user as a card")
    }
    let fields = ArisEditableAction.parse(pending.action, tools: policyTools)?.fields
    check(fields?.map(\.value) == ["엄마", "잘 도착했어요"], "edit card: the card's fields come from the command the gate judged")
}

func editDetailTests() {
    let fields = editable("\(editTools) message 엄마 '잘 도착했어요'")!.fields
    let shown = "받는 사람: 엄마\n내용: 잘 도착했어요"
    check(ArisEditableAction.detail("엄마 잘 도착했어요", described: "엄마 잘 도착했어요", fields: fields) == shown,
          "edit card: its details are the fields' text")
    check(ArisEditableAction.detail("방금 읽은 글 때문에 다시 물어요\n엄마 잘 도착했어요", described: "엄마 잘 도착했어요", fields: fields)
          == "방금 읽은 글 때문에 다시 물어요\n" + shown, "edit card: why it asks stays above the fields")
    check(ArisEditableAction.detail("something else", described: "엄마 잘 도착했어요", fields: fields) == "something else\n" + shown,
          "edit card: details that don't end in the command's words stay whole above")
    let card = ArisConfirmation(id: "c", title: "t", detail: "방금 읽은 글 때문에 다시 물어요\n" + shown, fields: fields)
    check(ArisCardEdit.note(card) == "방금 읽은 글 때문에 다시 물어요"
          && ArisCardEdit.note(ArisConfirmation(id: "c", title: "t", detail: shown, fields: fields)) == nil,
          "edit card: the app shows the lines above the fields as a note")
}

// I4: an edit-decline tells the AI, isn't a no for the rest of the turn, and the same action again is refused.
func editDeclineTests() {
    let codex = ArisCodexDriver(model: "m", tools: policyTools, instructions: "i", home: "/Users/me")
    func approval(_ id: Int, _ command: String) -> [ArisBrainEvent] {
        codex.read(String(decoding: try! JSONSerialization.data(withJSONObject: ["id": id, "method": "item/commandExecution/requestApproval",
            "params": ["threadId": "T1", "command": command]]), as: UTF8.self))
    }
    let opening = codex.opening().compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let threadStart = opening.last?["id"] as? Int ?? -1
    _ = codex.read(#"{"id":\#(threadStart),"result":{"thread":{"id":"T1"}}}"#)
    _ = codex.ask("엄마한테 보내 줘")
    _ = codex.read(#"{"method":"turn/started","params":{"turn":{"id":"t1"}}}"#)
    guard case .confirm(let ask)? = approval(1, "\(policyTools) message 엄마 '잘 도착했어요'").first else { return check(false, "edit decline: a card") }
    let lines = codex.declineEdited(ask.id, arguments: ["message", "아빠", "잘 도착했어요"], note: "note")
        .map { String(decoding: $0, as: UTF8.self) }
    let steer = (try? JSONSerialization.jsonObject(with: Data((lines.last ?? "").utf8)) as? [String: Any]) ?? [:]
    let steerParams = steer["params"] as? [String: Any] ?? [:]
    check(lines.count == 2 && lines.first?.contains("decline") == true && steer["method"] as? String == "turn/steer"
          && steerParams["expectedTurnId"] as? String == "t1" && steerParams["threadId"] as? String == "T1",
          "edit decline: the call is declined and the turn is told why (turn/steer)")
    let steerId = (try? JSONSerialization.jsonObject(with: Data((lines.last ?? "").utf8)) as? [String: Any])?["id"] as? Int ?? -1
    check(codex.read(#"{"id":\#(steerId),"error":{"message":"no active turn to steer"}}"#).isEmpty, "edit decline: a late steer is no failure")
    if case .confirm? = approval(2, "\(policyTools) trash ~/a.txt").first {} else {
        check(false, "edit decline: the rest of the turn still asks as usual (not a no)")
    }
    for again in ["\(policyTools) message 엄마 '잘 도착했어요'", "\(policyTools) message 아빠 '잘 도착했어요'"] {
        let events = approval(3, again)
        check(!events.contains { if case .confirm = $0 { return true } else { return false } }, "edit decline: the same send again is refused (\(again))")
    }
    if case .confirm? = approval(4, "\(policyTools) message 민지 '안녕'").first {} else { check(false, "edit decline: another message still asks") }
}
