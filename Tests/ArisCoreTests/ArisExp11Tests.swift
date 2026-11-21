import XCTest
@testable import ArisCore

/// The eleventh VM run, Experimental mode (aris-vmcheck notes11: record-full.jsonl, turns.jsonl, D2-taught.json,
/// L2-taught.json; cap11 T2/T3/C3/C5 cards). The pure rules behind what failed on a real screen with a real model.
final class ArisExp11Tests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_800_000_000)
    private let seen = ArisContentSource(kind: "app", source: "TextEdit")
    private let textEdit = ArisTeachApp(bundle: "com.apple.TextEdit", name: "TextEdit")

    /// notes11/D2-taught.json as the VM's recorder saved it on 7f3fb14e: the line break inside the example, no startsLine.
    private static let savedD2 = """
    [{"changed":"2026-11-20T10:06:53Z","created":"2026-11-20T10:06:53Z","id":"C5BB0FBB-2B41-4DCA-93AE-5D3494A5745F","name":"줄 추가",
      "parameters":[{"app":"TextEdit","example":"\\nAdded line","fromApp":false,"key":"p1","label":"본문"}],"skipped":0,
      "steps":[{"action":"open","app":"TextEdit","bundle":"com.apple.TextEdit"},
               {"action":"type","app":"TextEdit","bundle":"com.apple.TextEdit","fromApp":false,"label":"본문","parameter":"p1","place":"end",
                "role":"textArea","seen":{"kind":"app","source":"TextEdit"},"target":"First Text View 칸"}]},
     {"changed":"2026-11-20T10:07:43Z","created":"2026-11-20T10:07:43Z","id":"3FB3D2C9-1992-488B-8F8B-8F2A9C8747D2","name":"메모 쓰기",
      "parameters":[{"app":"TextEdit","example":"\\nMemo buy bread","fromApp":false,"key":"p1","label":"본문"}],"skipped":0,
      "steps":[{"action":"open","app":"TextEdit","bundle":"com.apple.TextEdit"},
               {"action":"type","app":"TextEdit","bundle":"com.apple.TextEdit","fromApp":false,"label":"본문","parameter":"p1","place":"end",
                "role":"textArea","seen":{"kind":"app","source":"TextEdit"},"target":"First Text View 칸"}]}]
    """

    private func saved() throws -> [ArisTeachProcedure] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ArisTeachProcedure].self, from: Data(Self.savedD2.utf8))
    }

    private func lesson(_ name: String, example: String, startsLine: Bool = true, fromApp: Bool = false) -> ArisTeachProcedure {
        var type = ArisTeachStep(action: .type, app: "TextEdit", bundle: "com.apple.TextEdit", target: "First Text View 칸", role: "textArea",
                                 label: "본문", parameter: "p1", seen: seen)
        type.place = .end
        if startsLine { type.startsLine = true }
        return ArisTeachProcedure(id: UUID(), name: name, steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit"), type],
                                  parameters: [ArisTeachParameter(key: "p1", label: "본문", example: example, app: "TextEdit", fromApp: fromApp)],
                                  skipped: 0, created: when, changed: when)
    }

    // MARK: - Item 2: the line a lesson begins

    /// The VM's lesson: "첫 줄" in the document, he pressed Return and typed "Added line".
    func testHisOwnReturnBeforeTheTextIsTheStepsLineStartNotPartOfTheValue() throws {
        let field = ArisTeachElement(role: "textArea", label: "", identifier: "First Text View")
        let events = [ArisTeachEvent(.appActivated, at: when.addingTimeInterval(0.1), app: textEdit),
                      ArisTeachEvent(.input, at: when.addingTimeInterval(1), app: textEdit, element: field, input: .click),
                      ArisTeachEvent(.input, at: when.addingTimeInterval(2), app: textEdit, element: field, input: .key),
                      ArisTeachEvent(.valueChanged, at: when.addingTimeInterval(2.01), app: textEdit, element: field, value: "첫 줄\nAdded line", before: "첫 줄")]
        var recorder = ArisTeachRecorder()
        recorder.start(name: "줄 추가", at: when)
        for event in events { recorder.feed(event) }
        let made = try ArisTeachGeneralise.procedure(try XCTUnwrap(recorder.stop(at: when.addingTimeInterval(30)))).get()
        let step = try XCTUnwrap(made.steps.first { $0.action == .type })
        XCTAssertEqual(step.startsLine, true, "his Return is where the text begins, kept on the step")
        XCTAssertEqual(made.parameters.first?.example, "Added line", "and never inside the value")
        XCTAssertTrue(step.newLine)
    }

    func testAnOldLessonsLeadingBreakBecomesItsLineStartWhenItIsRead() throws {
        let stored = try saved()
        for procedure in stored {
            let step = try XCTUnwrap(procedure.steps.first { $0.action == .type })
            XCTAssertEqual(step.startsLine, true, procedure.name)
            XCTAssertFalse(procedure.parameters[0].example.hasPrefix("\n"), procedure.name)
        }
        XCTAssertEqual(stored[0].parameters[0].example, "Added line")
        XCTAssertEqual(stored[1].parameters[0].example, "Memo buy bread")
    }

    /// T1: "줄 추가, 우유" typed "첫 줄우유". With a new value the call still begins a line.
    func testAReplayWithANewValueKeepsTheLineBreak() throws {
        let addLine = try saved()[0]
        let given = ArisTeachMatch.values(addLine, words: ", 우유")
        XCTAssertEqual(given, ["p1": "우유"])
        let plan = ArisTeachReplay.plan(addLine, given: given, words: "줄 추가, 우유", run: "t1")
        let call = try XCTUnwrap(plan.calls[1]?.object)
        XCTAssertEqual(call["text"] as? String, "\n우유")
        XCTAssertEqual(call[ArisApps.NewLine.argument] as? String, ArisApps.NewLine.mark)
        // And app.type keeps the break after "첫 줄" (the document T1 ran on).
        let field = ArisApps.ReadElement(id: "elem_1", role: "textArea", label: "", value: "첫 줄")
        let arguments = ArisApps.JSON.object(["text": .string("\n우유"), "at": .string("end"), ArisApps.NewLine.argument: .string(ArisApps.NewLine.mark)])
        XCTAssertEqual(ArisApps.NewLine.typed(arguments, field: field), "\n우유")
    }

    /// T1's reply was "‘줄 추가’ 다 했어요. (2단계)" over a result that said it went on the same line.
    func testTheAccountSaysWhenALineStartingStepLandedOnTheSameLine() {
        let addLine = lesson("줄 추가", example: "Added line")
        let placed = ArisTeachRunEnd.Placed()
        let recorded = "{\"channel\":\"engine\",\"did\":\"typed 2 characters in TextEdit (textArea)\",\"effect\":\"change-reversible\",\"now\":\"the field holds the text; it went on the same line, right after “첫 줄” (no new line was started)\",\"ok\":true,\"verified\":true}"
        placed.note(call: "app_type", beginsLine: true, result: ArisMindResult(text: recorded, isError: false))
        XCTAssertTrue(placed.sameLine)
        let account = ArisTeachRunEnd.withPlace(ArisTeachCopy.account(addLine, outcome: .done(steps: 2), english: false), procedure: addLine,
                                                outcome: .done(steps: 2), sameLine: placed.sameLine, english: false)
        XCTAssertFalse(account.contains("다 했어요"), account)
        XCTAssertTrue(account.contains("새 줄"), account)
        XCTAssertTrue(ArisTeachRunEnd.withPlace("x", procedure: addLine, outcome: .done(steps: 2), sameLine: placed.sameLine, english: true).contains("same line"))
        // A step that begins no line, or a result on its own line, changes nothing.
        let fine = ArisTeachRunEnd.Placed()
        fine.note(call: "app_type", beginsLine: false, result: ArisMindResult(text: recorded, isError: false))
        fine.note(call: "app_type", beginsLine: true, result: ArisMindResult(text: "{\"now\":\"the field holds the text; it is on a line of its own\"}", isError: false))
        XCTAssertFalse(fine.sameLine)
        XCTAssertEqual(ArisTeachRunEnd.withPlace("그대로", procedure: addLine, outcome: .done(steps: 2), sameLine: false, english: false), "그대로")
    }

    // MARK: - Item 2: the value a model offers

    /// T2 (record-full.jsonl 10:09:27): taught.run came with the value "↵우유", the mark the context showed in "last time
    /// “↵Added line”"; the owner's "‘우유’로" was not bound and the old example was typed. T3: "↵내일 3시 회의".
    func testAModelsValueIsBoundToTheOwnersSpanThroughQuotesMarksAndParticles() throws {
        let addLine = try saved()[0]
        let said = "줄 하나 더 넣어 줘 ‘우유’로"
        for offered in ["↵우유", "우유", "‘우유’", "'우유'", "“우유”", "우유로", "‘우유’로", "\n우유", " ↵ 우유 "] {
            XCTAssertEqual(ArisTaughtOffer.given(addLine, offered: ["value": offered], ownerWords: said), ["p1": "우유"], offered)
        }
        let memo = try saved()[1]
        XCTAssertEqual(ArisTaughtOffer.given(memo, offered: ["value": "↵내일 3시 회의"], ownerWords: "메모 써 줘: 내일 3시 회의"), ["p1": "내일 3시 회의"])
        XCTAssertEqual(ArisTaughtOffer.given(memo, offered: ["본문": "코어2 테스트"], ownerWords: "메모에 '코어2 테스트' 써 줘"), ["p1": "코어2 테스트"])
        for particle in ["을", "를", "이라고", "라고", "으로", "로"] {
            XCTAssertEqual(ArisTaughtOffer.given(addLine, offered: ["value": "달걀" + particle], ownerWords: "줄 추가해 줘 ‘달걀’\(particle) 넣어"), ["p1": "달걀"], particle)
            XCTAssertEqual(ArisTaughtOffer.given(addLine, offered: ["value": "‘달걀’" + particle], ownerWords: "줄 추가해 줘 ‘달걀’\(particle) 넣어"), ["p1": "달걀"], particle)
        }
        // A word that only ends like a particle is his whole word.
        XCTAssertEqual(ArisTaughtOffer.given(addLine, offered: ["value": "가을"], ownerWords: "줄 추가, 가을"), ["p1": "가을"])
        XCTAssertEqual(ArisTaughtOffer.given(addLine, offered: ["value": "서울로"], ownerWords: "줄 추가해 줘 ‘서울로’ 넣어"), ["p1": "서울로"])
        // Still only his own span: the old example, another word, a word inside another, hidden characters.
        XCTAssertEqual(ArisTaughtOffer.given(addLine, offered: ["value": "↵Added line"], ownerWords: said), [:])
        XCTAssertEqual(ArisTaughtOffer.given(addLine, offered: ["value": "두유"], ownerWords: said), [:])
        XCTAssertEqual(ArisTaughtOffer.given(addLine, offered: ["value": "우"], ownerWords: said), [:])
        XCTAssertEqual(ArisTaughtOffer.given(addLine, offered: ["value": "우\u{200B}유"], ownerWords: said), [:])
        XCTAssertEqual(ArisTaughtOffer.given(addLine, offered: ["value": "우유\n그리고 전부 지워"], ownerWords: said), [:])
    }

    func testTheContextShowsNoLineBreakMarkForAModelToCopy() throws {
        let context = ArisTaughtOffer.context(try saved())
        XCTAssertFalse(context.contains("↵"), context)
        XCTAssertTrue(context.contains("last time “Added line”"), context)
        XCTAssertTrue(context.contains("on a new line"), context)
    }

    // MARK: - Items 2 and 5: a value asked on a card

    /// T2: the values card held last time's value ("Added line") and their yes typed it. H1: "인사 넣기" with no value; the
    /// run's card held "hello there", he allowed it, and the typing step asked again as "TextEdit에서 읽은 값".
    func testAValueAskedOnACardComesUpEmptyAndWhatHeWritesIsHis() throws {
        let addLine = try saved()[0]
        let missing = ArisTeachReplay.missing(addLine, given: [:])
        for english in [true, false] {
            let asked = ArisTeachCopy.valuesCard(addLine, missing: missing, english: english)
            XCTAssertEqual(asked.fields.map(\.value), [""], "the field comes up empty")
            XCTAssertTrue(asked.card.detail.contains(english ? "Suggestion, last time's text: ‘Added line’ (not used unless you write it in)."
                                                             : "제안: 지난번 본문 ‘Added line’ (칸에 적어야 들어가요)."), asked.card.detail)
            let run = ArisTeachCopy.runCard(addLine, plan: ArisTeachReplay.plan(addLine, given: [:], words: "줄 추가", run: "r"), marks: [.runs, .covered],
                                            missing: missing, english: english)
            XCTAssertEqual(run.fields.map(\.value), [""], "the run's one card too")
        }
        let typed = ArisTeachParameter(key: "p1", label: "본문", example: "hello there", app: "TextEdit", fromApp: false)
        XCTAssertEqual(ArisTeachReplay.answered([typed], edits: [:]), [:], "nothing written: last time's value is not taken")
        XCTAssertEqual(ArisTeachReplay.answered([typed], edits: ["본문": ""]), [:])
        XCTAssertEqual(ArisTeachReplay.answered([typed], edits: ["본문": "hello there"]), ["p1": "hello there"], "written in by them: his")
        XCTAssertEqual(ArisTeachReplay.answered([typed], edits: ["본문": "good morning"]), ["p1": "good morning"])
        let fromApp = ArisTeachParameter(key: "p1", label: "본문", example: "Untitled 3", app: "TextEdit", fromApp: true)
        XCTAssertEqual(ArisTeachReplay.answered([fromApp], edits: [:]), [:])
        XCTAssertEqual(ArisTeachReplay.answered([fromApp], edits: ["본문": "mine"]), ["p1": "mine"])
    }

    func testHisWrittenValueIsCoveredAndLastTimesIsNeverSaidAsReadFromTheApp() {
        var hello = lesson("인사 넣기", example: "hello there", startsLine: false)
        hello.steps.append(ArisTeachStep(action: .menu, app: "TextEdit", bundle: "com.apple.TextEdit", label: "Save…", menu: ["File", "Save…"], keys: "cmd+s", seen: seen))
        let answered = ArisTeachReplay.answered(ArisTeachReplay.missing(hello, given: [:]), edits: ["본문": "hello there"])
        let plan = ArisTeachReplay.plan(hello, given: answered, words: "인사 넣기", run: "h1")
        XCTAssertEqual(ArisTeachCover.why(at: 1, in: plan.steps, ownerGave: plan.ownerGave), .covered)
        XCTAssertTrue(plan.approved.contains { $0.index == 2 }, "the typing step is approved ahead as his value")
        XCTAssertFalse(ArisTeachCopy.origin(hello, step: hello.steps[1], values: plan.values, ownerGave: plan.ownerGave, english: false).origin.contains("읽은 값"))
        // Not written in: last time's value still asks at its step, said as last time's, never as read from TextEdit.
        let left = ArisTeachReplay.plan(hello, given: [:], words: "인사 넣기", run: "h3")
        XCTAssertEqual(ArisTeachCover.why(at: 1, in: left.steps, ownerGave: left.ownerGave), .recordedValue)
        let said = ArisTeachCopy.origin(hello, step: hello.steps[1], values: left.values, ownerGave: left.ownerGave, english: false).origin
        XCTAssertTrue(said.contains("보여 주실 때의 지난번 값이에요") && !said.contains("TextEdit에서 읽은 값"), said)
        // The recorded value of a lesson where the app put it there.
        let recorded = lesson("제목", example: "Untitled 3", startsLine: false, fromApp: true)
        let kept = ArisTeachReplay.plan(recorded, given: ArisTeachReplay.answered(recorded.parameters, edits: [:]), words: "제목", run: "h2")
        XCTAssertEqual(ArisTeachCover.why(at: 1, in: kept.steps, ownerGave: kept.ownerGave), .recordedValue)
        XCTAssertTrue(ArisTeachCopy.origin(recorded, step: recorded.steps[1], values: kept.values, ownerGave: kept.ownerGave, english: false).origin.contains("TextEdit에서 읽은 값"))
    }

    // MARK: - Item 3: a lesson and a built-in of the same word

    func testAnAppsOwnNounWithAParticleIsTheBuiltInAnExactNameIsTheLessonAnythingBetweenAsks() throws {
        let memo = try saved()[1]
        let notes = try XCTUnwrap(ArisTaughtClash.builtIn(for: "메모 쓰기"))
        let table: [(String, ArisTaughtClash.Decision)] = [
            ("메모 쓰기 해 줘", .run),
            ("메모 쓰기, 내일 3시 회의", .run),
            ("메모 쓰기로 ‘우유’ 넣어 줘", .run),
            ("메모 써 줘: 내일 3시 회의", .ask(clash: notes)),
            ("메모 남겨 줘 우유 사기", .ask(clash: notes)),
            ("내일 3시 회의 메모해 줘", .ask(clash: notes)),
            ("메모로 남겨 줘: 우유", .ask(clash: notes)),
            ("메모장에 우유 써 줘", .ask(clash: notes)),
            ("메모에 ‘코어2 테스트’ 써 줘", .builtIn(notes)),
            ("메모에 '회의 안건 정리' 써 줘", .builtIn(notes)),
            ("메모 앱에 우유 사기 적어 줘", .builtIn(notes)),
            ("메모 앱 열어서 우유 써 줘", .builtIn(notes)),
            ("메모앱에다 우유 적어", .builtIn(notes)),
            ("노트에 우유 사기 써 줘", .builtIn(notes)),
            ("메모에다가 내일 3시 회의 추가해 줘", .builtIn(notes)),
            ("Apple Notes에 우유 써 줘", .builtIn(notes)),
        ]
        for (request, expected) in table {
            XCTAssertEqual(ArisTaughtClash.decide(memo, request: request, tainted: false, remembered: nil), expected, request)
        }
        let english = lesson("take a note", example: "buy bread")
        let englishNotes = try XCTUnwrap(ArisTaughtClash.builtIn(for: "take a note"))
        let englishTable: [(String, ArisTaughtClash.Decision)] = [
            ("take a note: buy milk", .run),
            ("Take a note, call mom", .run),
            ("note this down: buy milk", .ask(clash: englishNotes)),
            ("make a note about the meeting", .ask(clash: englishNotes)),
            ("add buy milk to my notes", .builtIn(englishNotes)),
            ("write buy milk in Notes", .builtIn(englishNotes)),
            ("put this in the Notes app", .builtIn(englishNotes)),
            ("save it to Apple Notes", .builtIn(englishNotes)),
        ]
        for (request, expected) in englishTable {
            XCTAssertEqual(ArisTaughtClash.decide(english, request: request, tainted: false, remembered: nil), expected, request)
        }
    }

    /// T3 and Q6: the conversation had read a document, so the clash was never looked at ("배운 대로 할까요?" with no
    /// way to say Notes) and the lesson took a Notes request.
    func testAfterOutsideTextTheClashIsStillSeen() throws {
        let memo = try saved()[1]
        let notes = try XCTUnwrap(ArisTaughtClash.builtIn(for: "메모 쓰기"))
        XCTAssertEqual(ArisTaughtClash.decide(memo, request: "메모 써 줘: 내일 3시 회의", tainted: true, remembered: nil), .ask(clash: notes))
        XCTAssertEqual(ArisTaughtClash.decide(memo, request: "메모에 ‘코어2 테스트’ 써 줘", tainted: true, remembered: nil), .builtIn(notes))
        XCTAssertEqual(ArisTaughtClash.decide(memo, request: "메모 써 줘: 내일 3시 회의", tainted: true, remembered: .builtIn), .builtIn(notes))
        // Never less strict than before: his naming it, or his earlier choice of the lesson, still asks after outside text.
        XCTAssertEqual(ArisTaughtClash.decide(memo, request: "메모 쓰기 해 줘", tainted: true, remembered: nil), .ask(clash: nil))
        XCTAssertEqual(ArisTaughtClash.decide(memo, request: "메모 써 줘: 내일 3시 회의", tainted: true, remembered: .taught), .ask(clash: nil))
        // A lesson with no clash.
        XCTAssertEqual(ArisTaughtClash.decide(try saved()[0], request: "줄 하나 더 넣어 줘", tainted: true, remembered: nil), .ask(clash: nil))
        XCTAssertEqual(ArisTaughtClash.decide(try saved()[0], request: "줄 하나 더 넣어 줘", tainted: false, remembered: nil), .run)
        // His remembered choice of the lesson doesn't take a request that names the app.
        XCTAssertEqual(ArisTaughtClash.decide(memo, request: "메모에 우유 써 줘", tainted: false, remembered: .taught), .builtIn(notes))
        XCTAssertEqual(ArisTaughtClash.decide(memo, request: "메모 써 줘", tainted: false, remembered: .taught), .run)
    }

    // MARK: - Item 1: a replace's card and its binding

    private func replace(erases: ArisErasedText?, ownerNamed: Set<ArisKeyArgument.Kind> = [.app, .body]) -> ArisAskItem {
        // record-full.jsonl 10:01:39: app.type, app TextEdit, body 교체된 내용, change-permanent, ask, ownerSaid.
        var facts = ArisCallFacts(capability: "app.type", arguments: [.init(kind: .app, value: "TextEdit"), .init(kind: .body, value: "교체된 내용")])
        facts.erases = erases
        return ArisAskItem(call: "c3", facts: facts, effect: .changePermanent, decision: .ask, provenance: .ownerSaid, ownerNamed: ownerNamed)
    }

    func testTheReplaceCardShowsWhatItErasesAndThatTheNewTextIsHisWords() {
        let card = ArisAskPlan.card([replace(erases: ArisErasedText(text: "원래 문장 하나\n원래 문장 둘", keepable: true))], id: "a", intent: "t", countdown: false, home: "/Users/x")
        XCTAssertTrue(card.detail.contains("「원래 문장 하나」"), card.detail)
        XCTAssertTrue(card.detail.contains("「원래 문장 둘」"), card.detail)
        XCTAssertTrue(card.detail.contains(ArisAskPlan.newTextIsOwners), card.detail)
        XCTAssertFalse(card.detail.contains(ArisAskPlan.erasesUnread), card.detail)
        // A text the owner's words didn't give gets no such line.
        let chosen = ArisAskPlan.card([replace(erases: ArisErasedText(text: "원래", keepable: true), ownerNamed: [.app])], id: "a", intent: "t", countdown: false, home: "/Users/x")
        XCTAssertFalse(chosen.detail.contains(ArisAskPlan.newTextIsOwners), chosen.detail)
    }

    func testTheUnreadCardSaysPlainlyWhatAllowWillAndWillNotDo() {
        let card = ArisAskPlan.card([replace(erases: ArisErasedText(text: nil, keepable: false))], id: "a", intent: "t", countdown: false, home: "/Users/x")
        XCTAssertTrue(card.detail.contains(ArisAskPlan.erasesUnread) || (card.full ?? "").contains(ArisAskPlan.erasesUnread), card.detail)
        XCTAssertTrue(ArisAskPlan.erasesUnread.contains("다시 읽"))
        XCTAssertTrue(ArisAskPlan.erasesUnread.contains("보지 못한 채"))
    }

    /// C3/C3c: Allow on a card that couldn't read the field overwrote text the owner never saw.
    func testAllowOnACardThatCouldNotReadNeverOverwritesTextHeHasNotSeen() {
        let any = ArisApps.JSON.object([ArisApps.TypeOver.argument: .string(ArisApps.TypeOver.mark(erases: ArisErasedText(text: nil, keepable: false)))])
        XCTAssertTrue(ArisApps.TypeOver.unseen(any, now: "카드 뒤에 바뀐 글"), "read now, and it holds text his card never showed")
        XCTAssertFalse(ArisApps.TypeOver.unseen(any, now: ""), "an empty field erases nothing")
        XCTAssertFalse(ArisApps.TypeOver.unseen(any, now: nil), "still unread: as the card said")
        let seen = ArisApps.JSON.object([ArisApps.TypeOver.argument: .string(ArisApps.TypeOver.mark(erases: ArisErasedText(text: "원래 문장 하나\n원래 문장 둘", keepable: true)))])
        XCTAssertFalse(ArisApps.TypeOver.unseen(seen, now: "원래 문장 하나\n원래 문장 둘"))
        XCTAssertTrue(ArisApps.TypeOver.refusesReplace(seen, holds: "카드 뒤에 바뀐 글"), "the card showed text, the field holds something else")
        XCTAssertTrue(ArisApps.TypeOver.refusesReplace(seen, holds: nil))
        XCTAssertFalse(ArisApps.TypeOver.refusesReplace(seen, holds: "원래 문장 하나\n원래 문장 둘"))
        XCTAssertFalse(ArisApps.TypeOver.unseen(.object([:]), now: "x"), "an unmarked call is as it was")
    }

    /// TextEdit's rich-text window as the VM's app.read printed it: ruler markers e37–e45 around the one text area.
    private var textEditWindow: [ArisApps.ReadElement] {
        var elements = (37...45).map { ArisApps.ReadElement(id: "elem_\($0)", role: "rulerMarker", label: "", value: String(Double($0 - 29) / 2), frame: (Double($0) * 10, 150, 8, 8)) }
        elements.append(ArisApps.ReadElement(id: "elem_46", role: "textArea", label: "", value: "원래 문장 하나\n원래 문장 둘", frame: (94, 170, 700, 460)))
        elements.append(ArisApps.ReadElement(id: "elem_12", role: "comboBox", label: "", value: "12", frame: (300, 110, 40, 20)))
        return elements
    }

    func testTheFieldAReplaceMeansIsFoundHoweverTheModelNamedIt() {
        let window = textEditWindow
        let read = ArisApps.Grounding.Seen(id: "e46", role: "textArea", label: "")
        // By the id of an earlier read (the model had read the window): found again by what it is, in the look taken now.
        XCTAssertEqual(ArisApps.Read.replaceField("e46", seen: read, in: window)?.value, "원래 문장 하나\n원래 문장 둘")
        // The look taken now numbers its elements anew: still the text area, never whatever has that number now.
        let renumbered = window.map { element -> ArisApps.ReadElement in
            var moved = element
            moved.id = "elem_" + String((Int(element.id.dropFirst(5)) ?? 0) + 3)
            return moved
        }
        XCTAssertEqual(ArisApps.Read.replaceField("e46", seen: read, in: renumbered)?.role, "textArea")
        // An id nothing is known about: not read.
        XCTAssertNil(ArisApps.Read.replaceField("e46", seen: nil, in: window))
        XCTAssertNil(ArisApps.Read.replaceField("e40", seen: ArisApps.Grounding.Seen(id: "e40", role: "rulerMarker", label: ""), in: window))
        // No field named, and a description that matches nothing: the window's one document.
        XCTAssertEqual(ArisApps.Read.replaceField(nil, seen: nil, in: window)?.shortId, "e46")
        for said in ["문서", "document", "text area", "the document's text", "본문"] {
            XCTAssertEqual(ArisApps.Read.replaceField(said, seen: nil, in: window)?.shortId, "e46", said)
        }
        // Two documents and nothing to tell them apart: none is guessed.
        let two = window + [ArisApps.ReadElement(id: "elem_60", role: "textArea", label: "", value: "다른 글", frame: (94, 700, 700, 100))]
        XCTAssertNil(ArisApps.Read.replaceField("문서", seen: nil, in: two))
        XCTAssertNil(ArisApps.Read.replaceField("e46", seen: read, in: two.filter { $0.id != "elem_46" } + [ArisApps.ReadElement(id: "elem_70", role: "textArea", label: "", value: "셋째")]))
        // Never a password field.
        let secret = [ArisApps.ReadElement(id: "elem_1", role: "secureTextField", label: "Password", value: "x")]
        XCTAssertNil(ArisApps.Read.replaceField(nil, seen: nil, in: secret))
        XCTAssertNil(ArisApps.Read.replaceField("e1", seen: ArisApps.Grounding.Seen(id: "e1", role: "secureTextField", label: "Password"), in: secret))
    }

    /// The model's other way to replace: Select All, then type (two calls that each look harmless). The watch is an extra
    /// signal (the gate reads every model typing's selection); it is keyed by the app as resolved ("com.apple.textedit").
    func testSelectAllThenTypeIsAReplace() {
        let edit = "com.apple.textedit"
        var watch = ArisSelectAllWatch()
        XCTAssertFalse(watch.typing(session: "s", app: edit))
        watch.acted(session: "s", capability: "app.press", arguments: ["app": "TextEdit", "keys": "cmd+a"], app: edit)
        XCTAssertTrue(watch.typing(session: "s", app: edit), "the typing after it is a replace")
        XCTAssertFalse(watch.typing(session: "s", app: edit), "once")
        for command in ["Select All", "Edit › Select All", "=Edit › Select All [cmd+a]", "전체 선택", "편집 › 전체 선택", "모두 선택", "Edit > Select All",
                        "Edit>Select All…", "편집 > 모두 선택", "Bearbeiten > Alles auswählen", "編集 > すべてを選択", "Édition > Tout sélectionner",
                        "  select   ALL  ", "[cmd+a]", "⌘A", "Edit › Choose Everything [⌘A]"] {
            watch.acted(session: "s", capability: "app.do", arguments: ["app": "TextEdit", "command": command], app: edit)
            XCTAssertTrue(watch.typing(session: "s", app: edit), command)
        }
        for keys in ["cmd+a", "command+a", "⌘A", "cmd+A", "cmd+a delete", "cmd+a cmd+c", "Cmd + A", "cmd-a", "meta+a", "⌘a"] {
            watch.acted(session: "s", capability: "app.press", arguments: ["app": "TextEdit", "keys": keys], app: edit)
            XCTAssertTrue(watch.typing(session: "s", app: edit), keys)
        }
        for notAll in ["Edit › Select Line", "Edit › Copy", "Format › Font › Show Fonts", "Selection"] {
            watch.acted(session: "s", capability: "app.do", arguments: ["app": "TextEdit", "command": notAll], app: edit)
            XCTAssertFalse(watch.typing(session: "s", app: edit), notAll)
        }
        // Another app, another conversation, another key: nothing.
        watch.acted(session: "s", capability: "app.press", arguments: ["app": "TextEdit", "keys": "cmd+a"], app: edit)
        XCTAssertFalse(watch.typing(session: "s", app: "com.apple.notes"))
        XCTAssertFalse(watch.typing(session: "other", app: edit))
        XCTAssertTrue(watch.typing(session: "s", app: edit))
        for keys in ["cmd+s", "cmd+shift+a", "a", "ctrl+a"] {
            watch.acted(session: "s", capability: "app.press", arguments: ["app": "TextEdit", "keys": keys], app: edit)
            XCTAssertFalse(watch.typing(session: "s", app: edit), keys)
        }
        // Nothing between them takes the note away (a click or a key may or may not drop the selection; the typing's
        // decision reads it): a miss is never less strict than a hit.
        watch.acted(session: "s", capability: "app.press", arguments: ["app": "TextEdit", "keys": "cmd+a"], app: edit)
        watch.acted(session: "s", capability: "app.click", arguments: ["app": "TextEdit", "target": "e3"], app: edit)
        watch.acted(session: "s", capability: "app.press", arguments: ["app": "TextEdit", "keys": "cmd+c"], app: edit)
        watch.acted(session: "s", capability: "app.read", arguments: ["app": "TextEdit"], app: edit)
        XCTAssertTrue(watch.typing(session: "s", app: edit))
        watch.acted(session: "s", capability: "app.press", arguments: ["app": "TextEdit", "keys": "cmd+a"], app: edit)
        watch.newTurn(session: "s")
        XCTAssertFalse(watch.typing(session: "s", app: edit))
    }

    /// Security review of exp11, 2: a Select All that names no app is in whichever app is in front, so it counts for
    /// typing into any app; typing that names no app counts any noted app.
    func testASelectAllThatNamesNoAppIsNeverLessStrict() {
        var watch = ArisSelectAllWatch()
        watch.acted(session: "s", capability: "app.press", arguments: ["keys": "cmd+a"], app: nil)
        XCTAssertTrue(watch.typing(session: "s", app: "com.apple.textedit"))
        watch.acted(session: "s", capability: "app.do", arguments: ["command": "Edit › Select All", "app": ""], app: "")
        XCTAssertTrue(watch.typing(session: "s", app: "com.apple.notes"))
        watch.acted(session: "s", capability: "app.press", arguments: ["app": "TextEdit", "keys": "cmd+a"], app: "com.apple.textedit")
        XCTAssertTrue(watch.typing(session: "s", app: nil), "typing into the app in front")
        XCTAssertFalse(watch.typing(session: "s", app: nil))
    }

    /// A Select All the app layer found by itself (pick/discover): its result says what it pressed.
    func testASelectAllIsSeenInWhatTheCallSaysItPressed() {
        func result(_ did: String, ok: Bool = true) -> String { "{\"did\":\"\(did)\",\"ok\":\(ok)}" }
        XCTAssertEqual(ArisSelectAllWatch.selectedAll(capability: "app.do", result: result("pressed Edit › Select All in TextEdit")), "TextEdit")
        XCTAssertEqual(ArisSelectAllWatch.selectedAll(capability: "app.do", result: result("pressed 편집 › 전체 선택 in 텍스트 편집기")), "텍스트 편집기")
        XCTAssertEqual(ArisSelectAllWatch.selectedAll(capability: "app.press", result: result("pressed cmd+a in TextEdit")), "TextEdit")
        XCTAssertNil(ArisSelectAllWatch.selectedAll(capability: "app.do", result: result("pressed Edit › Copy in TextEdit")))
        XCTAssertNil(ArisSelectAllWatch.selectedAll(capability: "app.do", result: result("pressed Edit › Select All in TextEdit", ok: false)))
        XCTAssertNil(ArisSelectAllWatch.selectedAll(capability: "app.type", result: result("pressed Edit › Select All in TextEdit")))
    }

    // MARK: - Item 6: what a card calls the element

    /// C5 (record-full.jsonl 10:04:54, 10:05:06): the read showed `[e188] link “고양이의 지능”`, the card said "대상: e188".
    func testACardNamesTheElementNeverItsId() {
        let seen = ArisApps.Grounding.lines("[e188] link “고양이의 지능”\n[e406] staticText “고양이의 지능”\n[e7] button\n[e9] textField “검색” = “고양이”")
        XCTAssertEqual(ArisApps.Grounding.shown(target: "e188", seen: seen)?.words, "링크 “고양이의 지능”")
        XCTAssertEqual(ArisApps.Grounding.shown(target: "[e188] link “고양이의 지능”", seen: seen)?.words, "링크 “고양이의 지능”")
        XCTAssertEqual(ArisApps.Grounding.shown(target: "e9", seen: seen)?.words, "입력칸 “검색”")
        let unnamed = ArisApps.Grounding.shown(target: "e7", seen: seen)
        XCTAssertEqual(unnamed?.words, "이름 없는 버튼")
        XCTAssertEqual(unnamed?.named, false)
        // An id nothing was read for is never shown as a name.
        XCTAssertEqual(ArisApps.Grounding.shown(target: "e999", seen: seen)?.words, ArisApps.Grounding.unread)
        XCTAssertEqual(ArisApps.Grounding.shown(target: "e999", seen: seen)?.named, false)
        XCTAssertEqual(ArisApps.Grounding.shown(target: "e188", seen: nil)?.words, ArisApps.Grounding.unread)
        // A name is a name already.
        XCTAssertNil(ArisApps.Grounding.shown(target: "고양이의 지능", seen: seen))
    }

    // MARK: - Item 10: what the chip calls an opened folder

    private func opened(_ arguments: [ArisKeyArgument], did: String) -> ArisRecordEntry {
        ArisRecordEntry.call(session: "claude-80199e23588695ff", task: nil, capability: "app.open", effect: .changeReversible, provenance: .ownerSaid,
                             decision: .runWithUndo(announce: false), arguments: arguments,
                             result: "{\"channel\":\"workspace\",\"did\":\"\(did)\",\"effect\":\"change-reversible\",\"ok\":true,\"verified\":false}", ok: true, undo: nil)
    }

    /// record-full.jsonl 09:58:41 ("다운로드 폴더 열어 줘"): app.open with no key argument, "opened /Users/admin/Downloads"; the chip said "앱 열기".
    func testAnOpenedFolderIsCalledAFolder() {
        XCTAssertEqual(ArisRecordQuery.ownerSummary(opened([], did: "opened /Users/admin/Downloads")), "폴더 열기: Downloads")
        XCTAssertEqual(ArisCapabilityNames.english("폴더 열기: Downloads"), "Folder opened: Downloads")
        XCTAssertEqual(ArisRecordQuery.ownerSummary(opened([.init(kind: .path, value: "~/Desktop/v11")], did: "opened /Users/admin/Desktop/v11")), "폴더 열기: v11")
        XCTAssertEqual(ArisRecordQuery.ownerSummary(opened([.init(kind: .path, value: "~/Desktop/a.txt")], did: "opened /Users/admin/Desktop/a.txt")), "파일 열기: a.txt")
        XCTAssertEqual(ArisRecordQuery.ownerSummary(opened([], did: "showed /Users/admin/Desktop/a.txt in Finder")), "앱 열기")
        // 10:31:04 and 10:08:21 of the same record: a page and an app stay what they are.
        XCTAssertEqual(ArisRecordQuery.ownerSummary(opened([.init(kind: .url, value: "https://example.com")], did: "opened https://example.com")), "웹 페이지 열기: https://example.com")
        XCTAssertEqual(ArisRecordQuery.ownerSummary(opened([.init(kind: .app, value: "TextEdit")], did: "opened TextEdit (in the background)")), "앱 열기: TextEdit")
    }

    // MARK: - Item 7: what ran with an undo is said as that

    /// record-full.jsonl 09:59:08 (aris.file_trash, runWithUndo, ownerSaid): the reply said only that it was moved.
    func testAReversibleFileOrCalendarChangeTellsTheModelItCanBeUndone() {
        let said = ArisUndoSaid.text("moved to the Trash: 초안.txt", capability: "aris.file_trash", canUndo: true)
        XCTAssertTrue(said.hasPrefix("moved to the Trash: 초안.txt"), said)
        XCTAssertTrue(said.contains("되돌릴 수 있어요"), said)
        for capability in ["aris.file_rename", "aris.file_move", "aris.add_event"] {
            XCTAssertTrue(ArisUndoSaid.text("x", capability: capability, canUndo: true).contains("되돌릴 수 있어요"), capability)
        }
        // Nothing is promised that isn't there, and other calls say nothing more.
        XCTAssertEqual(ArisUndoSaid.text("moved to the Trash: 초안.txt", capability: "aris.file_trash", canUndo: false), "moved to the Trash: 초안.txt")
        XCTAssertEqual(ArisUndoSaid.text("opened", capability: "app.open", canUndo: true), "opened")
        XCTAssertEqual(ArisUndoSaid.text("typed", capability: "app.type", canUndo: true), "typed")
    }
}
