// jv-recap: the day in review (F5). The record read back (record.query and the day's digest on POST /dayend),
// the day-end card's facts said in four or five sentences, "뭐 남았어", the coding sessions that wait as rows of the
// card, the evening chip through the interruption policy, and the one switch in Settings. The controller and the
// model need AppKit: the pure parts run here and their wiring is checked in the sources.
import Foundation

private let recapDays: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}()

/// 2026-11-18 (a Wednesday) at `hour`, `day` days later.
private func recapAt(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    recapDays.date(from: DateComponents(year: 2026, month: 11, day: 18 + day, hour: hour, minute: minute))!
}

private func recapSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func recapSession(_ number: Int, _ state: ArisFleetState, active: Date) -> ArisFleetSession {
    ArisFleetSession(id: "s\(number)", tool: .claudeCode, number: number, folder: "/Users/x/p\(number)", firstRequest: "fix the tests", state: state,
                     startedAt: active, lastActive: active, starter: .user, reach: .init(kind: .tmux), heard: true)
}

private func recapCall(_ capability: String, _ effect: ArisEffectClass, at: Date, arguments: [ArisKeyArgument] = []) -> ArisRecordEntry {
    ArisRecordEntry.call(at: at, session: "s", task: nil, capability: capability, effect: effect, provenance: .ownerSaid, decision: .run,
                         arguments: arguments, result: "읽은 메일 본문 일부", ok: true, undo: nil)
}

/// A day of fake facts: two to-dos (one ticked off), three jobs, a card, a session waiting on a permission, one that
/// finished, tomorrow's meeting and Friday's deadline.
private func recapFacts() -> ArisDayEndFacts {
    var facts = ArisDayEndFacts()
    // The 한 일 list as /activity gives it with Core 2 on: the record's four changes are its rows (what is said is
    // what is listed: jv-vmfix2, D5).
    facts.activity = [("옮김: a.pdf", 9), ("합침: 2개 → b.pdf", 10), ("일정 추가: 치과", 12), ("메시지 보냄: 엄마", 13)].map { summary, hour in
        ArisActivityItem(id: UUID().uuidString, date: recapAt(hour), job: "대화", worker: "Aris", summary: summary, undoable: false, undone: false, asks: false, teammate: nil)
    }
    facts.todos = [
        .init(id: "t1", title: "보고서 쓰기", due: recapAt(0), hasTime: false),
        .init(id: "t2", title: "우유 사기", due: recapAt(0), hasTime: false, completed: recapAt(11)),
    ]
    facts.jobs = [
        .init(id: "j1", title: "영수증 PDF로 합치기", outcome: .done),
        .init(id: "j2", title: "회의록 정리", outcome: .done),
        .init(id: "j3", title: "사진 정리", outcome: .running),
    ]
    facts.cards = [.init(id: "c1", title: "엄마에게 보내기", action: "보내기")]
    facts.events = [.init(start: recapAt(9, day: 1), end: recapAt(10, day: 1), title: "팀 회의")]
    facts.deadlines = [.init(course: "CSC263", title: "PS3", at: recapAt(23, 59, day: 2))]
    facts.sessions = [recapSession(1, .idle, active: recapAt(15)), recapSession(2, .waitingPermission, active: recapAt(16))]
    facts.record = ArisRecordDigest.make(ArisRecordState([
        recapCall("aris.file_move", .changeReversible, at: recapAt(9)),
        recapCall("aris.files_merge", .changeReversible, at: recapAt(10)),
        recapCall("aris.add_event", .changeReversible, at: recapAt(12)),
        recapCall("aris.send_message", .outward, at: recapAt(13), arguments: [.init(kind: .recipient, value: "엄마")]),
    ]), from: recapAt(5), to: recapAt(21))
    return facts
}

private func recapMappingTests() {
    let now = recapAt(21)
    let facts = recapFacts()
    let card = ArisDayEnd.make(facts, now: now, calendar: recapDays)
    let recap = ArisDayEndRecap.facts(card, facts, now: now, calendar: recapDays)
    check(recap.plan.planned == 5 && recap.plan.done == 3 && recap.plan.left == 2 && recap.plan.leftTitles == ["사진 정리", "보고서 쓰기"],
          "recap: the plan is counted as the card counts it (\(recap.plan))")
    check(recap.tasks == .init(done: 2, failed: 0, running: 1) && recap.waiting == 1, "recap: the jobs and the cards, the sessions apart")
    check(recap.tomorrowFirst == .init(title: "팀 회의", at: recapAt(9, day: 1)) && recap.deadline?.title == "CSC263 PS3", "recap: tomorrow's first thing and the nearest deadline")
    let spoken = ArisDayEndRecap.spoken(card, facts, focus: .day, now: now, calendar: recapDays)
    print("recap example (ko): \(spoken)")
    print("recap example (left): \(ArisDayEndRecap.spoken(card, facts, focus: .left, now: now, calendar: recapDays))")
    let english = ArisDayEnd.make(facts, now: now, calendar: recapDays, english: true)
    print("recap example (en): \(ArisDayEndRecap.spoken(english, facts, focus: .day, now: now, calendar: recapDays))")
    check(spoken == "오늘 하려던 다섯 가지 중 세 가지를 끝냈고, 두 가지가 남았어요. 제가 오늘 파일 작업 둘, 일정 하나 등 네 가지를 처리했어요. "
          + "맡기신 일 둘이 끝났고, 코딩 세션 하나가 일을 마쳤어요. 지금 기다리는 건 확인하실 것 하나, 답을 기다리는 코딩 세션 하나예요. "
          + "내일은 오전 9시 팀 회의로 시작하고, 가장 가까운 마감은 모레 CSC263 PS3이에요.", "recap: the day in five sentences")
    check(!spoken.contains("읽은 메일") && !spoken.contains("엄마"), "recap: nothing anyone wrote in a call's result or arguments is said")
}

private func recapCardTests() {
    let now = recapAt(21)
    let card = ArisDayEnd.make(recapFacts(), now: now, calendar: recapDays)
    check(card.waiting.map(\.id) == ["card:c1", "session:s2"] && card.waiting.last?.title == "2번 · p2 · 권한을 기다려요" && card.waiting.last?.card == nil,
          "card: a session that waits for the user is a row of 내 확인 (no 보기: it has no card)")
    check(ArisDayEnd.make(recapFacts(), now: now, calendar: recapDays, english: true).waiting.last?.title == "#2 · p2 · waiting for permission", "card: the same in English")
    var off = recapFacts()
    off.sessions = []
    check(ArisDayEnd.make(off, now: now, calendar: recapDays).counts.waiting == 1, "card: with the recap off no session is read, and the card is as before")
}

private func recapRouteTests() {
    let state = ArisRecordState([recapCall("aris.file_move", .changeReversible, at: recapAt(9)), recapCall("aris.timer", .changeReversible, at: recapAt(9, day: -1))])
    let today = (day: recapAt(5), now: recapAt(21))
    check(ArisDayEndRoute.digest(["record": true], today: today, recordOn: true, state: { state })?.total == 1, "route: the day's digest, yesterday's left out")
    check(ArisDayEndRoute.digest(["record": true], today: today, recordOn: false, state: { state }) == nil, "route: no record without Core 2's record")
    check(ArisDayEndRoute.digest([:], today: today, recordOn: true, state: { state }) == nil, "route: only when the app asks")
    let body = ArisDayEndRoute.body(jobs: [], from: recapAt(0, day: 1), to: recapAt(0, day: 2), calendar: recapDays, today: today,
                                    record: ArisRecordDigest(total: 1, families: ["files": 1]))
    let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    check(ArisRecordDigest.from(object?["record"]) == ArisRecordDigest(total: 1, families: ["files": 1]), "route: the app reads the digest back")
    check(!String(decoding: body, as: UTF8.self).contains("file_move"), "route: counts only, never a line")
}

private func recapCapabilityTests() {
    let entry = ArisCapabilityBook.entry(id: "record.query")
    check(entry?.name == "record_query" && entry?.effect([:]) == .observe, "capability: record.query is in the book, and it only looks")
    let state = ArisRecordState([recapCall("aris.send_message", .outward, at: recapAt(13), arguments: [.init(kind: .recipient, value: "엄마")])])
    let result = ArisRecordCapability.answer(["kind": "sent"], state: state, now: recapAt(21), calendar: recapDays)
    check(result.content == ArisToolResult.Content(kind: "aris", source: "record") && !result.isError && result.text.contains("엄마"),
          "capability: what it reads back is marked as content (a recipient in it can't make an outward call the owner's)")
    check(!result.text.contains("읽은 메일"), "capability: a call's result text never comes back")
    check(ArisRecordCapability.answer(["from": "someday"], state: state, now: recapAt(21)).isError, "capability: a time it can't read says so")
    check(ArisTodayTrust(judge: { _ in .ok }).decide(ArisTrustCall(entry: entry!, arguments: [:], effect: .observe, argv: nil, stdin: nil, environment: [:], tools: "t"))
            == .refuse(ArisTodayTrust.noTool), "capability: the gate is unchanged (until jv-trust's policy decides, a helper capability gets no tool)")
}

private func recapAskTests() {
    let was = ArisRecapSwitch.isOn
    defer { ArisRecapSwitch.isOn = was }
    ArisRecapSwitch.isOn = { false }
    if case .dayEnd = ArisIntent.parse("뭐 남았어") { check(false, "ask: with the recap off \"뭐 남았어\" is not the card's") } else { check(true, "ask: off, as before") }
    ArisRecapSwitch.isOn = { true }
    for spoken in ["뭐 남았어?", "오늘 남은 일 뭐야", "What's left?"] {
        if case .dayEnd = ArisIntent.parse(spoken) { check(true, "ask: \(spoken) opens the card") } else { check(false, "ask: \(spoken) opens the card") }
    }
    if case .dayEnd = ArisIntent.parse("타이머 얼마 남았어") { check(false, "ask: the timer's question is the timer's") } else { check(true, "ask: the timer's question is the timer's") }
    if case .dayEnd = ArisIntent.parse("What did I do today?") { check(true, "ask: what did I do today") } else { check(false, "ask: what did I do today") }
}

private func recapSettingTests() {
    let rows = ArisSettingsBuilder.sections(.aris, ArisSettingsSnapshot()).flatMap(\.rows)
    let row = rows.first { $0.id == ArisRecapSetting.id }
    check(row?.control == .toggle(.recap, false), "setting: the day in review has one row, off until the user has heard it")
    let index = rows.firstIndex { $0.id == ArisRecapSetting.id }, chip = rows.firstIndex { $0.id == ArisDayEndSetting.id }
    check(index != nil && chip != nil && index == chip.map { $0 + 1 }, "setting: it sits under the evening chip's row")
    check(ArisSettingsIndex.entry(ArisRecapSetting.id)?.page == .aris && ArisSettingsIndex.search("남은 일").first?.id == ArisRecapSetting.id
          && ArisSettingsIndex.search("recap").contains { $0.id == ArisRecapSetting.id }, "setting: a search for 남은 일 or recap finds it")
    check(ArisSettingsIndex.search("오늘 정리").first?.id == ArisDayEndSetting.id, "setting: 오늘 정리 still finds the chip first")
    let catalog = recapSource("Aris/components/Settings/Settings.xcstrings")
    check(catalog.contains("\"\(ArisRecapSetting.title)\"") && catalog.contains("\"\(ArisRecapSetting.detail)\""), "setting: its words have English")
}

private func recapWiringTests() {
    let model = recapSource("Aris/private/Aris/DayEnd/ArisDayEndModel.swift")
    check(model.contains("aris.interruption(ArisRecapOffer.want(hasNews: true)).comesUp"), "wiring: the evening chip asks the interruption policy when the recap is on")
    check(model.contains("facts.sessions = ArisFleetStore.shared.fleet.sessions") && model.contains("record: recap"), "wiring: the sessions and the digest are read only with the recap on")
    let controller = recapSource("Aris/private/Aris/DayEnd/ArisController+DayEnd.swift")
    check(controller.contains("recordTurn(heard: heard, reply: remembered)") && controller.contains("model.show(made, line: sentence)"),
          "wiring: what is said stands above the list, and the history keeps the fixed line (no titles reach the AI)")
    check(recapSource("Aris/private/Aris/ArisIntent.swift").contains("ArisRecapAsk.asksLeftWhenOn(phrase)"), "wiring: what is left is asked locally")
}

func runRecapTests() {
    recapMappingTests()
    recapCardTests()
    recapRouteTests()
    recapCapabilityTests()
    recapAskTests()
    recapSettingTests()
    recapWiringTests()
}
