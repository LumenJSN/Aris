import XCTest
@testable import ArisCore

/// The day in review (F5): the record read back by query and as a digest, and the recap's sentences from fake facts.
final class ArisRecapTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func call(_ capability: String, _ effect: ArisEffectClass, at: Date, ok: Bool = true, decision: ArisDecision = .run,
                      answer: String? = nil, task: String? = nil, arguments: [ArisKeyArgument] = []) -> ArisRecordEntry {
        ArisRecordEntry.call(at: at, session: "s", task: task, capability: capability, effect: effect, provenance: .ownerSaid, decision: decision,
                             answer: answer, arguments: arguments, result: nil, ok: ok, undo: nil)
    }

    private var day: [ArisRecordEntry] {
        [
            call("aris.file_move", .changeReversible, at: at(18, 9), arguments: [.init(kind: .path, value: "/Users/x/a.pdf")]),
            call("aris.file_convert", .changeReversible, at: at(18, 10)),
            call("file.write", .changeReversible, at: at(18, 11)),
            call("aris.add_event", .changeReversible, at: at(18, 12)),
            call("aris.send_message", .outward, at: at(18, 13), answer: "yes", arguments: [.init(kind: .recipient, value: "엄마")]),
            call("aris.weather", .observe, at: at(18, 14)),
            call("aris.volume", .changeReversible, at: at(18, 15), arguments: [.init(kind: .app, value: "Music")]),
            call("shell.run", .changePermanent, at: at(18, 16), ok: false, decision: .refuse(reason: "no")),
            call("aris.timer", .changeReversible, at: at(17, 9)),
        ]
    }

    // MARK: - The record

    func testFamiliesByCapability() {
        XCTAssertEqual(ArisRecordFamily.of(call("aris.file_move", .changeReversible, at: at(18, 9))), .files)
        XCTAssertEqual(ArisRecordFamily.of(call("aris.send_message", .outward, at: at(18, 9))), .sent)
        XCTAssertEqual(ArisRecordFamily.of(call("fleet.say", .changeReversible, at: at(18, 9))), .sessions)
        XCTAssertEqual(ArisRecordFamily.of(call("aris.add_event", .changeReversible, at: at(18, 9))), .calendar)
        XCTAssertEqual(ArisRecordFamily.of(call("app.do", .changeReversible, at: at(18, 9))), .apps)
        XCTAssertNil(ArisRecordFamily.of(call("aris.weather", .observe, at: at(18, 9))), "a look is no work done")
        XCTAssertNil(ArisRecordFamily.of(call("record.undo_last", .changeReversible, at: at(18, 9))), "an undo is no work done")
    }

    func testTheDigestCountsTheDaysChangesNotWhatWasUndone() {
        let entries = day
        let undone = ArisRecordEntry.undone(entries[1].id, at: at(18, 10, 5))
        let digest = ArisRecordDigest.make(ArisRecordState(entries + [undone]), from: at(18, 5), to: at(18, 23))
        XCTAssertEqual(digest.total, 5)
        XCTAssertEqual(digest.count(.files), 2)
        XCTAssertEqual(digest.count(.calendar), 1)
        XCTAssertEqual(digest.count(.sent), 1)
        XCTAssertEqual(digest.count(.controls), 1)
        XCTAssertEqual(digest.undone, 1)
        XCTAssertEqual(digest.refused, 1)
        XCTAssertEqual(digest.asked, 1)
        XCTAssertEqual(ArisRecordDigest.from(digest.json), digest, "the digest survives the route")
        XCTAssertNil(ArisRecordDigest.from(["families": [:]]))
    }

    func testTheQueryByTimeKindAppAndCapability() {
        let state = ArisRecordState(day)
        let today = ArisRecordQuery(from: at(18, 0), to: at(18, 23))
        XCTAssertEqual(today.rows(state).count, 8, "yesterday's timer is not today's")
        var changes = today
        changes.kind = .changes
        XCTAssertEqual(changes.rows(state).map(\.entry.capability), ["aris.file_move", "aris.file_convert", "file.write", "aris.add_event", "aris.send_message", "aris.volume"])
        var sent = today
        sent.kind = .sent
        XCTAssertEqual(sent.rows(state).map(\.entry.capability), ["aris.send_message"])
        var music = today
        music.app = "music"
        XCTAssertEqual(music.rows(state).map(\.entry.capability), ["aris.volume"])
        var files = today
        files.capability = "aris.file"
        files.limit = 1
        XCTAssertEqual(files.rows(state).map(\.entry.capability), ["aris.file_convert"], "the newest within the limit")
        var refused = today
        refused.kind = .refused
        XCTAssertEqual(refused.rows(state).map(\.entry.capability), ["shell.run"])
    }

    func testTheQuerysArgumentsAndLines() {
        let now = at(18, 20)
        let yesterday = ArisRecordQuery.parse(["from": "yesterday", "to": "yesterday"], now: now, calendar: calendar)
        XCTAssertEqual(yesterday?.from, at(17, 0))
        XCTAssertEqual(yesterday?.to, at(18, 0))
        XCTAssertEqual(ArisRecordQuery.parse([:], now: now, calendar: calendar)?.from, at(18, 0), "today by default")
        XCTAssertEqual(ArisRecordQuery.parse(["from": "2026-11-17"], now: now, calendar: calendar)?.from, at(17, 0))
        XCTAssertNil(ArisRecordQuery.parse(["from": "last spring"], now: now, calendar: calendar))
        XCTAssertNil(ArisRecordQuery.parse(["kind": "everything"], now: now, calendar: calendar))
        let query = ArisRecordQuery.parse(["kind": "sent"], now: now, calendar: calendar)!
        let text = ArisRecordQuery.text(query.rows(ArisRecordState(day)), query: query, calendar: calendar)
        XCTAssertEqual(text, "13:00 aris.send_message · 보내기 · 엄마 — run, owner: yes")
        XCTAssertEqual(ArisRecordQuery.text([], query: query), "(nothing in the record for that)")
    }

    // MARK: - The words

    func testNumbersAndParticles() {
        XCTAssertEqual(ArisRecapWords.things(5), "다섯 가지")
        XCTAssertEqual(ArisRecapWords.things(20), "스무 가지")
        XCTAssertEqual(ArisRecapWords.alone(12), "열둘")
        XCTAssertEqual(ArisRecapWords.josa("둘", "을", "를"), "둘을")
        XCTAssertEqual(ArisRecapWords.josa("하나", "을", "를"), "하나를")
        XCTAssertEqual(ArisRecapWords.ro("팀 회의"), "팀 회의로")
        XCTAssertEqual(ArisRecapWords.ro("수업"), "수업으로")
        XCTAssertEqual(ArisRecapWords.ro("저녁 식사 약속 잡기 놀"), "저녁 식사 약속 잡기 놀로", "ㄹ takes 로")
        XCTAssertEqual(ArisRecapWords.ieyo("PS3"), "PS3이에요")
        XCTAssertEqual(ArisRecapWords.ieyo("하나"), "하나예요")
        XCTAssertEqual(ArisRecapWords.time(at(19, 9), english: false, calendar: calendar), "오전 9시")
        XCTAssertEqual(ArisRecapWords.time(at(19, 14, 30), english: true, calendar: calendar), "2:30 PM")
        XCTAssertEqual(ArisRecapWords.day(at(20, 9), today: at(18, 0), english: false, calendar: calendar), "모레")
        XCTAssertEqual(ArisRecapWords.day(at(21, 9), today: at(18, 0), english: false, calendar: calendar), "토요일")
        XCTAssertEqual(ArisRecapWords.day(at(19, 9), today: at(18, 0), english: true, calendar: calendar), "tomorrow")
        XCTAssertEqual(ArisRecapWords.day(at(30, 9), today: at(18, 0), english: false, calendar: calendar), "11월 30일")
    }

    // MARK: - The recap

    private func session(_ number: Int, _ state: ArisFleetState, asked: Bool = true, active: Date) -> ArisFleetSession {
        ArisFleetSession(id: "s\(number)", tool: .claudeCode, number: number, folder: "/Users/x/p\(number)", firstRequest: asked ? "fix it" : nil,
                         state: state, startedAt: active, lastActive: active, starter: .user, reach: .init(kind: .tmux), heard: true)
    }

    private var busyDay: ArisRecapFacts {
        var facts = ArisRecapFacts()
        facts.plan = .init(planned: 5, done: 3, left: 2, moved: 0, leftTitles: ["보고서 쓰기", "운동"])
        facts.record = ArisRecordDigest.make(ArisRecordState(day), from: at(18, 5), to: at(18, 23))
        // The card's 그 밖 rows: the record's six changes.
        facts.extra = 6
        facts.tasks = .init(done: 2, failed: 0, running: 1)
        facts.fleet = [session(1, .idle, active: at(18, 15)), session(2, .waitingPermission, active: at(18, 16)), session(3, .working, active: at(18, 17)),
                       session(4, .idle, asked: false, active: at(18, 17))]
        facts.waiting = 1
        facts.tomorrowFirst = .init(title: "팀 회의", at: at(19, 9))
        facts.tomorrowCount = 3
        facts.deadline = .init(title: "CSC263 PS3", at: at(20, 23, 59))
        return facts
    }

    func testTheDayInFiveSentences() {
        let recap = ArisRecap.make(busyDay, focus: .day, today: at(18, 0), now: at(18, 21), english: false, calendar: calendar)
        XCTAssertEqual(recap.sentences, [
            "오늘 하려던 다섯 가지 중 세 가지를 끝냈고, 두 가지가 남았어요.",
            "제가 오늘 파일 작업 셋, 일정 하나 등 여섯 가지를 처리했어요.",
            "맡기신 일 둘이 끝났고, 코딩 세션 하나가 일을 마쳤어요.",
            "지금 기다리는 건 확인하실 것 하나, 답을 기다리는 코딩 세션 하나예요.",
            "내일은 오전 9시 팀 회의로 시작하고, 가장 가까운 마감은 모레 CSC263 PS3이에요.",
        ])
        XCTAssertLessThanOrEqual(recap.sentences.count, ArisRecap.longest)
    }

    func testTheDayInEnglish() {
        let recap = ArisRecap.make(busyDay, focus: .day, today: at(18, 0), now: at(18, 21), english: true, calendar: calendar)
        XCTAssertEqual(recap.sentences, [
            "You finished three of the five things you planned for today; two are left.",
            "Today I took care of six things, including three file changes and one calendar item.",
            "Two jobs you handed over finished and one coding session wrapped up its work.",
            "Waiting on you: one thing to OK and one coding session with a question.",
            "Tomorrow starts with 팀 회의 at 9 AM, and the nearest deadline is CSC263 PS3 on Friday.",
        ])
    }

    func testWhatIsLeft() {
        let recap = ArisRecap.make(busyDay, focus: .left, today: at(18, 0), now: at(18, 21), english: false, calendar: calendar)
        XCTAssertEqual(recap.sentences, [
            "오늘 남은 일은 보고서 쓰기, 운동, 이렇게 두 가지예요.",
            "맡기신 일 하나가 아직 하는 중이고, 코딩 세션 하나가 일하는 중이에요.",
            "지금 기다리는 건 확인하실 것 하나, 답을 기다리는 코딩 세션 하나예요.",
            "내일은 오전 9시 팀 회의로 시작하고, 가장 가까운 마감은 모레 CSC263 PS3이에요.",
        ])
        var done = ArisRecapFacts()
        done.plan = .init(planned: 2, done: 2)
        XCTAssertEqual(ArisRecap.make(done, focus: .left, today: at(18, 0), now: at(18, 21), english: false, calendar: calendar).sentences,
                       ["오늘 하려던 일은 다 끝냈어요.", "확인을 기다리는 건 없어요."])
    }

    /// A light day still has its parts, each said even when it is nothing (VM run 2026-11-19: one sentence).
    func testAQuietDay() {
        XCTAssertEqual(ArisRecap.make(ArisRecapFacts(), focus: .day, today: at(18, 0), now: at(18, 21), english: false, calendar: calendar).sentences,
                       ["오늘은 정한 일도 한 일도 없었어요.", "확인을 기다리는 건 없어요.", "내일은 아직 잡힌 일이 없어요."])
        var unplanned = ArisRecapFacts()
        unplanned.extra = 2
        XCTAssertEqual(ArisRecap.make(unplanned, focus: .day, today: at(18, 0), now: at(18, 21), english: false, calendar: calendar).sentences,
                       ["오늘 따로 정해 둔 일은 없었어요.", "오늘 한 일은 두 가지예요.", "확인을 기다리는 건 없어요.", "내일은 아직 잡힌 일이 없어요."])
        var oneFamily = ArisRecapFacts()
        oneFamily.record = ArisRecordDigest(total: 2, families: ["sent": 2])
        oneFamily.extra = 2
        XCTAssertEqual(ArisRecap.make(oneFamily, focus: .day, today: at(18, 0), now: at(18, 21), english: false, calendar: calendar).sentences[1],
                       "제가 오늘 메시지 전송 둘을 처리했어요.")
        XCTAssertEqual(ArisRecap.make(ArisRecapFacts(), focus: .day, today: at(18, 0), now: at(18, 21), english: true, calendar: calendar).sentences,
                       ["Nothing was planned or done today.", "Nothing is waiting for your OK.", "Nothing is set for tomorrow yet."])
    }

    /// A call whose aris-tools run wrote activity-log lines is undone when those lines were undone (the old path's
    /// "되돌려"): it no longer counts as done (VM run 2026-11-19: an event and a rename undone there stayed "done").
    func testUndoneThroughTheLogIsUndone() {
        var linked = call("aris.file_rename", .changeReversible, at: at(18, 9), arguments: [.init(kind: .path, value: "/Users/x/a.txt")])
        linked.logged = ["9b2c1a3e-0000-4000-8000-000000000001"]
        let state = ArisRecordState([linked, call("aris.add_event", .changeReversible, at: at(18, 10))])
        XCTAssertEqual(ArisRecordDigest.make(state, from: at(18, 5), to: at(18, 23)).total, 2)
        let undone = ArisRecordDigest.make(state, from: at(18, 5), to: at(18, 23), loggedUndone: ["9b2c1a3e-0000-4000-8000-000000000001"])
        XCTAssertEqual(undone.total, 1)
        XCTAssertEqual(undone.undone, 1)
    }

    /// The owner reads a call by its name, never its capability id.
    func testTheOwnerReadsNamesNotIds() {
        let batch = call("aris.desktop_batch", .changePermanent, at: at(18, 9), arguments: [.init(kind: .app, value: "TextEdit")])
        XCTAssertEqual(ArisRecordQuery.ownerSummary(batch), "앱에서 여러 단계: TextEdit")
        XCTAssertFalse(ArisRecordQuery.ownerSummary(call("aris.unknown_new", .changeReversible, at: at(18, 9))).contains("aris."))
        XCTAssertEqual(ArisCapabilityNames.english("앱에서 여러 단계: TextEdit"), "Steps in an app: TextEdit")
        XCTAssertEqual(ArisCapabilityNames.english("앱 열기"), "App opened")
        XCTAssertNil(ArisCapabilityNames.english("볼륨 올림"))
    }

    /// The number said is the number of rows the card lists (VM run 2026-11-19: "다섯 가지" beside six rows).
    func testTheCountSaidIsTheCountShown() {
        var facts = ArisRecapFacts()
        facts.record = ArisRecordDigest(total: 5, families: ["apps": 3, "files": 1, "calendar": 1])
        facts.extra = 6
        let did = ArisRecap.make(facts, focus: .day, today: at(18, 0), now: at(18, 21), english: false, calendar: calendar).sentences[1]
        XCTAssertEqual(did, "제가 오늘 앱 작업 셋, 파일 작업 하나 등 여섯 가지를 처리했어요.")
        facts.extra = 2
        XCTAssertEqual(ArisRecap.make(facts, focus: .day, today: at(18, 0), now: at(18, 21), english: false, calendar: calendar).sentences[1],
                       "제가 오늘 파일 작업 하나, 일정 하나를 처리했어요.", "a kind is named only while it fits in what is shown")
        facts.extra = 0
        XCTAssertFalse(ArisRecap.make(facts, focus: .day, today: at(18, 0), now: at(18, 21), english: false, calendar: calendar).spoken.contains("처리했어요"),
                       "nothing listed, nothing said as done")
        for day in [ArisRecapFacts(), facts] {
            XCTAssertTrue((3...5).contains(ArisRecap.make(day, focus: .day, today: at(18, 0), now: at(18, 21), english: false, calendar: calendar).sentences.count))
        }
    }

    func testTheFleetCounted() {
        let fleet = ArisRecapFleet([session(1, .idle, active: at(18, 15)), session(2, .idle, active: at(17, 15)), session(3, .failed, active: at(18, 1)),
                                    session(4, .waitingInput, active: at(18, 2)), session(5, .gone, active: at(18, 3))], since: at(18, 5))
        XCTAssertEqual(fleet, { var f = ArisRecapFleet([], since: at(18, 5)); f.finished = 1; f.failed = 1; f.asking = 1; return f }(),
                       "yesterday's and one gone before the day began don't count as finished today")
    }

    // MARK: - Asking and offering

    func testWhatIsLeftIsAsked() {
        for phrase in ["뭐 남았어", "오늘 뭐 남았지", "남은 일 뭐야", "아직 못 끝낸 일 있어", "what's left", "what do i have left today", "anything left"] {
            XCTAssertTrue(ArisRecapAsk.asksLeft(phrase), phrase)
        }
        for phrase in ["타이머 얼마 남았어", "마감 뭐 남았어", "배터리 몇 퍼센트 남았어", "할 일 뭐 남았어", "what's left on the timer", "오늘 정리해 줘"] {
            XCTAssertFalse(ArisRecapAsk.asksLeft(phrase), phrase)
        }
        XCTAssertEqual(ArisRecapAsk.focus("오늘 뭐 했어"), .day)
        XCTAssertEqual(ArisRecapAsk.focus("뭐 남았어"), .left)
    }

    func testTheEveningChipAsksThePolicy() {
        typealias I = ArisInterruption
        XCTAssertTrue(ArisRecapOffer.mayOffer(hasNews: true, I.Moment()))
        XCTAssertFalse(ArisRecapOffer.mayOffer(hasNews: false, I.Moment()), "nothing to tell: dropped")
        XCTAssertFalse(ArisRecapOffer.mayOffer(hasNews: true, I.Moment(inCall: true)), "it waits for the call to end")
        XCTAssertFalse(ArisRecapOffer.mayOffer(hasNews: true, I.Moment(userSpeaking: true)))
        XCTAssertFalse(ArisRecapOffer.mayOffer(hasNews: true, I.Moment(screenAway: true)))
        XCTAssertEqual(I.decide(ArisRecapOffer.want(hasNews: true), I.Moment(mayMakeSound: true)), .show, "never said aloud")
    }
}
