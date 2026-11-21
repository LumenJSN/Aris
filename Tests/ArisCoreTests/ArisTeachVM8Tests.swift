import XCTest
@testable import ArisCore

/// The eighth VM run's pure parts (aris-vmcheck notes8/*, cap8/*). The helper's and the app's parts are in
/// tests/vmfix11-tests.swift.
final class ArisTeachVM8Tests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let textEdit = ArisTeachApp(bundle: "com.apple.TextEdit", name: "TextEdit")
    private var textView: ArisTeachElement { ArisTeachElement(role: "textArea", label: "", identifier: "First Text View") }

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func recorder(_ name: String, keysHeard: Bool = true) -> ArisTeachRecorder {
        var recorder = ArisTeachRecorder()
        recorder.start(name: name, at: start)
        recorder.keysHeard = keysHeard
        recorder.feed(ArisTeachEvent(.appActivated, at: at(0.5), app: textEdit))
        recorder.feed(ArisTeachEvent(.focused, at: at(0.6), app: textEdit, element: textView))
        return recorder
    }

    private func key(_ time: Double) -> ArisTeachEvent { ArisTeachEvent(.input, at: at(time), app: textEdit, element: textView, input: .key) }

    private func change(_ time: Double, _ value: String, before: String) -> ArisTeachEvent {
        ArisTeachEvent(.valueChanged, at: at(time), app: textEdit, element: textView, value: value, before: before)
    }

    private func paste(_ time: Double) -> ArisTeachEvent {
        var paste = ArisTeachEvent(.menuChosen, at: at(time), app: textEdit, element: textView, menu: ["Edit", "Paste"])
        paste.keys = "cmd+v"
        return paste
    }

    private func made(_ recorder: ArisTeachRecorder) -> ArisTeachProcedure? {
        var recorder = recorder
        guard let lesson = recorder.stop(at: at(60)) else { return nil }
        return try? ArisTeachGeneralise.procedure(lesson).get()
    }

    // MARK: - Item 1: a paste is one step

    /// notes8/PT-taught.json, "붙여넣기 시험": "typed words " typed after "Paste base ", ⌘V (the clipboard held the
    /// composer's "지금부터 하는 거 붙여넣기 시험이라고 해"), Delete. Saved: type p1, Edit › Paste, and a second type "taken from
    /// the app" holding what the paste had put there; the replay pasted and then typed the old clipboard too
    /// (notes8/PR-doc.txt).
    func testThePasteLessonOfTheVMIsOnePasteStep() {
        var watched = recorder("붙여넣기 시험")
        watched.feed(key(1))
        XCTAssertNil(watched.feed(change(1.05, "Paste base t", before: "Paste base ")))
        watched.feed(key(2))
        XCTAssertNil(watched.feed(change(2.05, "Paste base typed words ", before: "Paste base t")))
        XCTAssertNil(watched.feed(paste(3)))
        let clip = "지금부터 하는 거 붙여넣기 시험이라고 해"
        XCTAssertNil(watched.feed(change(3.1, "Paste base typed words " + clip, before: "Paste base typed words ")))
        watched.feed(key(4))
        XCTAssertNil(watched.feed(change(4.05, "Paste base typed words " + clip.dropLast(), before: "Paste base typed words " + clip)))
        let procedure = made(watched)
        XCTAssertEqual(procedure?.steps.map(\.action), [.open, .type, .menu])
        XCTAssertEqual(procedure?.steps.last?.menu, ["Edit", "Paste"])
        XCTAssertEqual(procedure?.parameters.map(\.example), ["typed words "], "what the paste put there is no value of the lesson")
    }

    /// Typed text after a paste is still his own step, holding only what he typed.
    func testTypingAfterAPasteIsItsOwnStepWithOnlyHisText() {
        var watched = recorder("붙이고 쓰기")
        watched.feed(paste(1))
        XCTAssertNil(watched.feed(change(1.1, "CLIP", before: "")))
        watched.feed(key(2))
        XCTAssertNil(watched.feed(change(2.05, "CLIPa", before: "CLIP")))
        watched.feed(key(2.3))
        XCTAssertNil(watched.feed(change(2.35, "CLIPab", before: "CLIPa")))
        let procedure = made(watched)
        XCTAssertEqual(procedure?.steps.map(\.action), [.open, .menu, .type])
        XCTAssertEqual(procedure?.parameters.map(\.example), ["ab"])
        XCTAssertEqual(procedure?.parameters.first?.fromApp, false)
    }

    /// ⌘V told as a key (the app's menus weren't read yet), Edit › Paste chosen with the mouse (no key heard at all),
    /// and the Korean menu: each is one step too.
    func testAPasteByKeyOrByMouseIsOneStep() {
        var byKey = recorder("키")
        byKey.feed(ArisTeachEvent(.shortcut, at: at(1), app: textEdit, element: textView, keys: "cmd+v"))
        byKey.feed(change(1.1, "CLIP", before: ""))
        XCTAssertEqual(made(byKey)?.steps.map(\.action), [.open, .press])
        for menu in [["Edit", "Paste"], ["Edit", "Paste and Match Style"], ["편집", "붙여넣기"]] {
            var byMouse = recorder("마우스", keysHeard: false)
            byMouse.feed(ArisTeachEvent(.menuChosen, at: at(1), app: textEdit, menu: menu))
            byMouse.feed(change(1.1, "CLIP", before: ""))
            // Without his keys heard, what he types next is his by his presence alone: only the paste's own change goes.
            byMouse.feed(ArisTeachEvent(.input, at: at(2), app: textEdit, input: .hand))
            byMouse.feed(change(2.1, "CLIPx", before: "CLIP"))
            let procedure = made(byMouse)
            XCTAssertEqual(procedure?.steps.map(\.action), [.open, .menu, .type], "\(menu)")
            XCTAssertEqual(procedure?.parameters.map(\.example), ["x"], "\(menu)")
        }
    }

    /// A paste that put nothing in (an empty clipboard) takes nothing of what he types next.
    func testAPasteThatChangedNothingTakesNoTypedText() {
        var watched = recorder("빈 붙여넣기")
        watched.feed(paste(1))
        watched.feed(key(2))
        watched.feed(change(2.05, "h", before: ""))
        watched.feed(key(2.2))
        watched.feed(change(2.25, "hi", before: "h"))
        XCTAssertEqual(made(watched)?.parameters.map(\.example), ["hi"])
    }

    /// Select All then a paste: the select stays a step (no typed step stands for it), so the replay still replaces.
    func testSelectAllBeforeAPasteStaysAStep() {
        var watched = recorder("전체 붙여넣기")
        watched.feed(ArisTeachEvent(.shortcut, at: at(1), app: textEdit, element: textView, keys: "cmd+a"))
        watched.feed(ArisTeachEvent(.shortcut, at: at(2), app: textEdit, element: textView, keys: "cmd+v"))
        watched.feed(change(2.1, "CLIP", before: "old"))
        XCTAssertEqual(made(watched)?.steps.map(\.keys), [nil, "cmd+a", "cmd+v"])
    }

    // MARK: - Item 4: the new-line note only when a line break is really put in

    /// A lesson as notes8/PT-taught.json holds it: TextEdit opened, `menu` chosen (when given), text put at the end of
    /// the document, its typing marked as beginning a line.
    private func lesson(_ name: String, menu: [String]?, keys: String?) -> ArisTeachProcedure {
        var typed = ArisTeachStep(action: .type, app: "TextEdit", bundle: "com.apple.TextEdit", target: "First Text View 칸", role: "textArea",
                                  label: ArisTeachGeneralise.bodyLabel)
        typed.parameter = "p1"
        typed.place = .end
        typed.startsLine = true
        typed.fromApp = false
        var steps = [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit")]
        if let menu {
            var chosen = ArisTeachStep(action: .menu, app: "TextEdit", bundle: "com.apple.TextEdit", label: menu.last, menu: menu)
            chosen.keys = keys
            steps.append(chosen)
        }
        return ArisTeachProcedure(name: name, steps: steps + [typed],
                                  parameters: [ArisTeachParameter(key: "p1", label: ArisTeachGeneralise.bodyLabel, example: "Memo text", app: "TextEdit", fromApp: false)],
                                  created: start)
    }

    private func valuesNote(_ procedure: ArisTeachProcedure, english: Bool) -> String {
        ArisTeachCopy.valuesCard(procedure, missing: ArisTeachReplay.missing(procedure, given: [:]), english: english).card.detail
    }

    /// cap8/M1-card1.jpg, "메모 쓰기" (File › New, then the text): the card said "It goes on a new line (↵)", and the
    /// replay put "Memo text" at the very start of the new, empty document with no line break (notes8/M1-doc.txt).
    func testAStepIntoABrandNewDocumentHasNoNewLineNote() {
        for (menu, keys) in [(["File", "New"], "cmd+n" as String?), (["File", "New"], nil), (["파일", "신규"], "cmd+n")] {
            let memo = lesson("메모 쓰기", menu: menu, keys: keys)
            for english in [true, false] {
                let note = valuesNote(memo, english: english)
                XCTAssertFalse(note.contains("↵") || note.contains("new line") || note.contains("새 줄"), "\(menu) \(keys ?? "-"): \(note)")
            }
        }
    }

    /// "줄 추가" (no new document) and "랩 메모" (Format › Wrap to Page before the text) still say it: there a line
    /// break is put in after what the document holds.
    func testAStepIntoTheDocumentAsItIsKeepsItsNewLineNote() {
        for made in [lesson("줄 추가", menu: nil, keys: nil), lesson("랩 메모", menu: ["Format", "Wrap to Page"], keys: nil),
                     lesson("새 창", menu: ["Window", "New Tab Group"], keys: nil)] {
            XCTAssertTrue(valuesNote(made, english: true).contains("It goes on a new line (↵)."), made.name)
            XCTAssertTrue(valuesNote(made, english: false).contains("새 줄(↵)에 넣어요."), made.name)
        }
    }

    // MARK: - Item 6: wording

    private func wrapMemo() -> ArisTeachProcedure { lesson("랩 메모", menu: ["Format", "Wrap to Page"], keys: nil) }

    /// cap8/W1-after-Continue.jpg: "Done: “랩 메모” (2 steps), without step 2 (…), which didn't work." for a lesson of
    /// three steps of which two ran.
    func testAPartRunSaysHowManyOfItsStepsRanAndWhichWasSkipped() {
        let english = ArisTeachCopy.account(wrapMemo(), outcome: .partly(done: 2, skipped: [1]), english: true)
        XCTAssertEqual(english, "Did “랩 메모”: 2 of its 3 steps ran. Skipped step 2 (In TextEdit, choose ‘Format › Wrap to Page’), which didn't work.")
        let korean = ArisTeachCopy.account(wrapMemo(), outcome: .partly(done: 2, skipped: [1]), english: false)
        XCTAssertTrue(korean.hasPrefix("‘랩 메모’ 3단계 중 2단계를 했어요. 안 된 2단계 “"), korean)
        XCTAssertTrue(korean.hasSuffix("”는 건너뛰었어요."), korean)
    }

    /// cap8/W5ko-*: "2단계 ‘TextEdit에서 메뉴 ‘Format › Wrap to Page’ 누르기’가 안 됐어요": the same marks inside and out.
    func testAKoreanStepLineIsQuotedInMarksItDoesNotHoldItself() {
        let made = wrapMemo()
        let lines = [ArisTeachCopy.failedLine(made, at: 1, why: "", english: false),
                     ArisTeachCopy.account(made, outcome: .stopped(at: 1, end: .failed(""), done: 1), english: false),
                     ArisTeachCopy.account(made, outcome: .stopped(at: 1, end: .declined, done: 1), english: false),
                     ArisTeachCopy.account(made, outcome: .stopped(at: 1, end: .refused(""), done: 1), english: false),
                     ArisTeachCopy.account(made, outcome: .stopped(at: 1, end: .unmade, done: 1), english: false)]
        for line in lines {
            XCTAssertTrue(line.contains("2단계 “") && line.contains("‘Format › Wrap to Page’"), line)
            XCTAssertNil(line.range(of: "‘[^’]*‘", options: .regularExpression), "a single mark opened inside single marks: \(line)")
        }
    }

    /// cap8/O1-undo-card.jpg: a replace's undo card said "Typed into an app: TextEdit".
    func testAReplaceIsNamedAsAReplaceWhereTheOwnerReadsIt() {
        func typed(erased: String?) -> ArisRecordEntry {
            var mark = ArisApps.TextUndo.Mark(bundle: "com.apple.TextEdit", role: "textArea", label: "", inserted: "All swapped", beforeLength: 10, beforeHash: "x")
            mark.erased = erased
            let element = String(decoding: (try? JSONEncoder().encode(mark)) ?? Data(), as: UTF8.self)
            return ArisRecordEntry.call(at: start, session: "teach-1", task: nil, capability: "app.type", effect: .changePermanent, provenance: .ownStep,
                                        decision: .ask, arguments: [ArisKeyArgument(kind: .app, value: "TextEdit")], result: "{}", ok: true,
                                        undo: .textInserted(app: "TextEdit", element: element, before: ""))
        }
        XCTAssertEqual(ArisRecordQuery.ownerSummary(typed(erased: "copy-1")), "앱의 글 바꿈: TextEdit")
        XCTAssertEqual(ArisCapabilityNames.english("앱의 글 바꿈: TextEdit"), "Replaced text in an app: TextEdit")
        XCTAssertEqual(ArisRecordQuery.ownerSummary(typed(erased: nil)), "앱에 입력: TextEdit")
    }

    /// notes8/record-full.jsonl: "TextEdit에 입력한 글을 지웠어요" and "주인이 거절" in the English UI's journal, the lesson
    /// not named.
    func testTheJournalsWordsFollowTheLanguageAndNameTheLesson() {
        XCTAssertEqual(ArisJournalWords.textUndone(app: "TextEdit", restored: false, lesson: "줄 추가", english: true), "Removed the text I typed in TextEdit for “줄 추가”.")
        XCTAssertEqual(ArisJournalWords.textUndone(app: "TextEdit", restored: false, lesson: "줄 추가", english: false), "‘줄 추가’에서 TextEdit에 입력한 글을 지웠어요.")
        XCTAssertEqual(ArisJournalWords.textUndone(app: "TextEdit", restored: true, lesson: nil, english: true), "Put back the text I replaced in TextEdit.")
        XCTAssertEqual(ArisJournalWords.declined(english: true), "You said no")
        XCTAssertEqual(ArisJournalWords.declined(english: false), "하지 말라고 하셨어요")
    }

    // MARK: - Item 7: a lesson of deleting alone

    /// notes8/DL-teach-done.log: Delete pressed in the document and nothing else; "I didn't see anything I can do again".
    func testALessonOfDeletingAloneSaysDeletingIsNotLearnedYet() {
        var watched = recorder("지우기")
        watched.feed(key(1))
        XCTAssertNil(watched.feed(change(1.05, "Delete bas", before: "Delete base")))
        var lesson = watched
        let events = lesson.stop(at: at(9))?.events ?? []
        XCTAssertEqual(ArisTeachGeneralise.procedure(name: "지우기", events: events, at: at(9)), .failure(.nothing), "deleting is still not replayed")
        XCTAssertTrue(ArisTeachGeneralise.deletedText(events))
        for english in [true, false] {
            let said = ArisTeachCopy.nothingSaved("지우기", deletedText: true, english: english)
            XCTAssertTrue(said.contains(english ? "deleting on its own isn't something I can learn yet" : "지우기만 하는 건 아직 배울 수 없어서"), said)
            XCTAssertEqual(ArisTeachCopy.nothingSaved("지우기", deletedText: false, english: english), ArisTeachCopy.nothingToLearn("지우기", english: english))
        }
        // A lesson with nothing in it at all, or with typing, is not said to be a deletion.
        XCTAssertFalse(ArisTeachGeneralise.deletedText([]))
        XCTAssertFalse(ArisTeachGeneralise.deletedText([change(1, "ab", before: "a")]))
    }

    // MARK: - Item 8: typed text that begins like the text after it

    /// cap8/Wbad-learn-card-memoWrap.jpg: the document held "Wrap seed"; after Format › Wrap to Page the caret was at
    /// its start, "Wrap memo" was typed there ("Wrap memoWrap seed"), and the lesson said he typed "memoWrap ".
    func testTypedTextThatBeginsLikeTheTextAfterItIsNotCutInTheWrongPlace() {
        var watched = recorder("랩 메모")
        watched.feed(ArisTeachEvent(.menuChosen, at: at(1), app: textEdit, menu: ["Format", "Wrap to Page"]))
        var held = "Wrap seed"
        for (index, character) in "Wrap memo".enumerated() {
            let time = 2 + Double(index) * 0.2
            watched.feed(key(time))
            let next = String("Wrap memo".prefix(index + 1)) + "Wrap seed"
            XCTAssertNil(watched.feed(change(time + 0.05, next, before: held)), "\(character)")
            held = next
        }
        let procedure = made(watched)
        XCTAssertEqual(procedure?.parameters.map(\.example), ["Wrap memo"])
        XCTAssertEqual(procedure?.steps.last?.place, .caret)
    }

    /// The values alone (no first character known), and a first change that isn't one character, are told as before;
    /// an unambiguous run is untouched by the hint.
    func testTheHintOnlyDecidesBetweenPlacesTheValuesAllow() {
        typealias G = ArisTeachGeneralise
        XCTAssertEqual(G.textChange(before: "Wrap seed", after: "Wrap memoWrap seed").text, "memoWrap ")
        XCTAssertEqual(G.textChange(before: "Wrap seed", after: "Wrap memoWrap seed", began: "W"), G.TextChange(text: "Wrap memo", place: .caret))
        XCTAssertEqual(G.textChange(before: "Wrap seed", after: "Wrap memoWrap seed", began: "m"), G.TextChange(text: "memoWrap ", place: .caret))
        XCTAssertEqual(G.textChange(before: "Wrap seed", after: "Wrap memoWrap seed", began: "z").text, "memoWrap ", "no place fits: as before")
        XCTAssertEqual(G.textChange(before: "Wrap ", after: "Wrap Wrap memo", began: "W"), G.TextChange(text: "Wrap memo", place: .end))
        XCTAssertEqual(G.textChange(before: "xa", after: "xaba", began: "b"), G.TextChange(text: "ba", place: .end))
        XCTAssertEqual(G.textChange(before: "", after: "hello", began: "h"), G.TextChange(text: "hello", place: .end))
    }
}
