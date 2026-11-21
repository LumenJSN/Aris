import XCTest
@testable import ArisCore

/// The ninth VM run's pure parts (aris-vmcheck notes9/*, cap9/*). The helper's and the app's parts are in
/// tests/vmfix12-tests.swift.
final class ArisTeachVM9Tests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let textEdit = ArisTeachApp(bundle: "com.apple.TextEdit", name: "TextEdit")
    private var textView: ArisTeachElement { ArisTeachElement(role: "textArea", label: "", identifier: "First Text View") }

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func recorder(_ name: String) -> ArisTeachRecorder {
        var recorder = ArisTeachRecorder()
        recorder.start(name: name, at: start)
        recorder.keysHeard = true
        recorder.feed(ArisTeachEvent(.appActivated, at: at(0.5), app: textEdit))
        recorder.feed(ArisTeachEvent(.focused, at: at(0.6), app: textEdit, element: textView))
        return recorder
    }

    private func key(_ time: Double, in element: ArisTeachElement? = nil) -> ArisTeachEvent {
        ArisTeachEvent(.input, at: at(time), app: textEdit, element: element ?? textView, input: .key)
    }

    private func change(_ time: Double, _ value: String, before: String, in element: ArisTeachElement? = nil) -> ArisTeachEvent {
        ArisTeachEvent(.valueChanged, at: at(time), app: textEdit, element: element ?? textView, value: value, before: before)
    }

    private func shortcut(_ time: Double, _ keys: String) -> ArisTeachEvent {
        ArisTeachEvent(.shortcut, at: at(time), app: textEdit, element: textView, keys: keys)
    }

    private func lesson(_ recorder: ArisTeachRecorder, read: [ArisTeachEvent] = []) -> ArisTeachRecorder.Lesson? {
        var recorder = recorder
        recorder.close(read)
        return recorder.stop(at: at(60))
    }

    private func made(_ recorder: ArisTeachRecorder, read: [ArisTeachEvent] = []) -> ArisTeachProcedure? {
        lesson(recorder, read: read).flatMap { try? ArisTeachGeneralise.procedure($0).get() }
    }

    // MARK: - Item 1: text typed at the start of text that begins the same way

    /// The lesson of cap9/S1-card-crop.jpg ("앞에 쓰기": the document held "Wrap seed ", ⌘↓, ⌘↑, "Wrap memo" typed;
    /// notes9/S1-doc-after-teach.txt: "Wrap memoWrap seed "; the card said he typed ‘memoWrap ’), with the text
    /// element's changes reported as `reports` gives them (each the value read when a change notice was handled).
    private func frontLesson(_ reports: [String], carets: [Int?]? = nil) -> ArisTeachRecorder {
        var watched = recorder("앞에 쓰기")
        watched.feed(shortcut(1, "cmd+down"))
        watched.feed(shortcut(1.3, "cmd+up"))
        var held = "Wrap seed "
        for (index, value) in reports.enumerated() {
            let time = 2 + Double(index) * 0.3
            watched.feed(key(time))
            let event = change(time + 0.05, value, before: held)
            XCTAssertNil(watched.feed(event), value)
            held = value
        }
        return watched
    }

    /// The first change notice handled after two keys were already in the field (the eighth run's fix needed the first
    /// change to hold exactly one more character).
    func testAFirstReportOfTwoCharactersStillTellsWhereHeTyped() {
        let reports = ["WrWrap seed "] + (3...9).map { String("Wrap memo".prefix($0)) + "Wrap seed " }
        let procedure = made(frontLesson(reports))
        XCTAssertEqual(procedure?.parameters.map(\.example), ["Wrap memo"])
        XCTAssertEqual(procedure?.steps.map(\.action), [.open, .press, .press, .type])
        XCTAssertEqual(procedure?.steps.last?.place, .caret)
    }

    /// A change notice that came with the value still as it was (nothing in yet), then his keys one by one.
    func testAFirstReportWithNothingChangedStillTellsWhereHeTyped() {
        let reports = ["Wrap seed "] + (1...9).map { String("Wrap memo".prefix($0)) + "Wrap seed " }
        XCTAssertEqual(made(frontLesson(reports))?.parameters.map(\.example), ["Wrap memo"])
    }

    /// The changes reported in two lumps ("Wrap ", then the rest).
    func testReportsInLumpsStillTellWhereHeTyped() {
        XCTAssertEqual(made(frontLesson(["Wrap Wrap seed ", "Wrap memoWrap seed "]))?.parameters.map(\.example), ["Wrap memo"])
    }

    /// One key at a time, as the eighth run's test had it, with the document's real text ("Wrap seed " with its space).
    func testKeyByKeyStaysRight() {
        let reports = (1...9).map { String("Wrap memo".prefix($0)) + "Wrap seed " }
        XCTAssertEqual(made(frontLesson(reports))?.parameters.map(\.example), ["Wrap memo"])
    }

    /// Every change in one notice, or none at all and the value read once when the lesson ended: only the caret the
    /// element reports (after "Wrap memo" it is at 9) tells the place.
    func testTheCaretSettlesWhatTheValuesLeaveOpen() {
        var watched = recorder("앞에 쓰기")
        watched.feed(key(2))
        var whole = change(2.05, "Wrap memoWrap seed ", before: "Wrap seed ")
        whole.caret = 9
        XCTAssertNil(watched.feed(whole))
        XCTAssertEqual(made(watched)?.parameters.map(\.example), ["Wrap memo"])

        var silent = recorder("앞에 쓰기")
        silent.feed(key(2))
        var read = change(2, "Wrap memoWrap seed ", before: "Wrap seed ")
        read.caret = 9
        let procedure = made(silent, read: [read])
        XCTAssertEqual(procedure?.parameters.map(\.example), ["Wrap memo"])
        XCTAssertEqual(procedure?.steps.last?.place, .caret)
        // No caret read: as before (the latest place), never a guess.
        XCTAssertEqual(made(silent, read: [change(2, "Wrap memoWrap seed ", before: "Wrap seed ")])?.parameters.map(\.example), ["memoWrap "])
        // A caret that fits no place the values allow is not believed.
        read.caret = 14
        XCTAssertEqual(made(silent, read: [read])?.parameters.map(\.example), ["memoWrap "])
    }

    func testARunIsFollowedThroughATypoTakenBackAndAComposedSyllable() {
        typealias R = ArisTeachRun
        var run: R? = R.none
        var held = "Wrap seed "
        for value in ["WWrap seed ", "WrWrap seed ", "WrzWrap seed ", "WrWrap seed ", "WraWrap seed "] {
            run = run?.after(old: held, new: value)
            held = value
        }
        XCTAssertEqual(run, R(low: 0, high: 0, length: 3))
        XCTAssertEqual(run?.text(in: held, before: "Wrap seed ")?.text, "Wra")
        // cap9/S7: Korean typed in front of Korean ("안녕 " before "안녕 세상 "), each syllable composed in place.
        run = R.none
        held = "안녕 세상 "
        for value in ["ㅇ안녕 세상 ", "아안녕 세상 ", "안안녕 세상 ", "안ㄴ안녕 세상 ", "안녀안녕 세상 ", "안녕안녕 세상 ", "안녕 안녕 세상 "] {
            run = run?.after(old: held, new: value)
            held = value
        }
        XCTAssertEqual(run?.text(in: held, before: "안녕 세상 ")?.text, "안녕 ")
        // Typed in two places, or text that was there taken out: no one run; told from the two values as before.
        XCTAssertNil(R(low: 0, high: 0, length: 2).after(old: "abXY", new: "abXYc"))
        XCTAssertNil(R.none.after(old: "abc", new: "ab"))
        // The whole run taken back, then typed again elsewhere: a new run.
        XCTAssertEqual(R(low: 2, high: 2, length: 1).after(old: "abXc", new: "abc"), R.none)
        // A caret counted in UTF-16 inside text with a character two units long.
        XCTAssertEqual(R.characters(upTo: 3, in: "a😀b"), 2)
        XCTAssertNil(R.characters(upTo: 2, in: "a😀b"))
        XCTAssertNil(R.characters(upTo: 9, in: "abc"))
    }

    // MARK: - Item 1: a field with no name of its own

    /// cap9/S4-NSfield-card-crop.jpg: typing that landed in a toolbar field was saved as "put [_NS:8] in ‘_NS:8’".
    func testAFieldNamedOnlyByAMachineIdentifierIsNotSavedAndTheCardSaysSo() {
        let field = ArisTeachElement(role: "textField", label: "", identifier: "_NS:8")
        XCTAssertEqual(field.name, "")
        XCTAssertNil(ArisTeachGeneralise.target(field))
        XCTAssertEqual(ArisTeachElement(role: "textArea", label: "", identifier: "First Text View").name, "First Text View")
        XCTAssertEqual(ArisTeachElement(role: "textField", label: "", placeholder: "Search", identifier: "_NS:12").name, "Search")
        for machine in ["_NS:8", "_NS:122", "NSTextField-41", "0x600003a1c", "7", "_field", "a/b"] { XCTAssertFalse(ArisTeachElement.namesIt(machine), machine) }
        for real in ["First Text View", "search-field", "subject", "To.Field"] { XCTAssertTrue(ArisTeachElement.namesIt(real), real) }

        var watched = recorder("가운데 쓰기")
        watched.feed(key(1))
        XCTAssertNil(watched.feed(change(1.05, "Alpha bet beta", before: "Alpha beta")))
        watched.feed(ArisTeachEvent(.focused, at: at(2), app: textEdit, element: field))
        watched.feed(key(2.5, in: field))
        XCTAssertNil(watched.feed(change(2.55, "bet ", before: "", in: field)))
        let kept = lesson(watched)!
        let procedure = try? ArisTeachGeneralise.procedure(kept).get()
        XCTAssertEqual(procedure?.steps.map(\.action), [.open, .type])
        XCTAssertEqual(procedure?.parameters.map(\.label), ["본문"])
        XCTAssertEqual(ArisTeachGeneralise.leftOut(kept.events), [.unnamedField])
        for english in [true, false] {
            let card = ArisTeachCopy.saveCard(procedure!, replacing: false, leftOut: [.unnamedField], english: english)
            XCTAssertFalse(card.detail.contains("_NS"), card.detail)
            XCTAssertTrue(card.detail.contains(english ? "a text field that has no name" : "이름 없는 입력 칸"), card.detail)
            XCTAssertFalse(ArisTeachCopy.saveCard(procedure!, replacing: false, english: english).detail.contains(english ? "no name" : "이름 없는"))
        }
        // Only that field typed into: nothing is saved, and the reply says why.
        var only = recorder("가운데 쓰기")
        only.feed(ArisTeachEvent(.focused, at: at(2), app: textEdit, element: field))
        only.feed(key(2.5, in: field))
        XCTAssertNil(only.feed(change(2.55, "bet ", before: "", in: field)))
        let none = lesson(only)!
        XCTAssertEqual(try? ArisTeachGeneralise.procedure(none).get(), nil)
        XCTAssertEqual(ArisTeachGeneralise.leftOut(none.events), [.unnamedField])
        XCTAssertTrue(ArisTeachCopy.nothingSaved("가운데 쓰기", leftOut: [.unnamedField], english: true).contains("has no name"))
        XCTAssertTrue(ArisTeachCopy.nothingSaved("가운데 쓰기", leftOut: [.unnamedField], english: false).contains("이름 없는 입력 칸"))
        XCTAssertEqual(ArisTeachCopy.nothingSaved("x", leftOut: [.deleting], english: true), ArisTeachCopy.onlyDeleted("x", english: true))
        XCTAssertEqual(ArisTeachCopy.nothingSaved("x", leftOut: [], english: false), ArisTeachCopy.nothingToLearn("x", english: false))
    }

    // MARK: - Item 5: deleting that was left out is said

    /// cap9/P5-card-crop.jpg, "붙여 지우기": "abc " typed, ⌘V, Delete. The card showed the typing and Edit › Paste and
    /// nothing about the Delete.
    func testTheCardSaysThatDeletingWasLeftOut() {
        var watched = recorder("붙여 지우기")
        watched.feed(key(1))
        XCTAssertNil(watched.feed(change(1.05, "abc ", before: "")))
        var paste = ArisTeachEvent(.menuChosen, at: at(2), app: textEdit, element: textView, menu: ["Edit", "Paste"])
        paste.keys = "cmd+v"
        XCTAssertNil(watched.feed(paste))
        let clip = "지금부터 하는 거 붙여 지우기라고 해"
        XCTAssertNil(watched.feed(change(2.1, "abc " + clip, before: "abc ")))
        watched.feed(key(3))
        XCTAssertNil(watched.feed(change(3.05, "abc " + clip.dropLast(), before: "abc " + clip)))
        let kept = lesson(watched)!
        let procedure = try! ArisTeachGeneralise.procedure(kept).get()
        XCTAssertEqual(procedure.steps.map(\.action), [.open, .type, .menu], "no delete step is made")
        XCTAssertEqual(ArisTeachGeneralise.leftOut(kept.events), [.deleting])
        let english = ArisTeachCopy.saveCard(procedure, replacing: false, leftOut: [.deleting], english: true).detail
        XCTAssertTrue(english.contains("Left out: what you deleted") && english.contains("whole clipboard"), english)
        let korean = ArisTeachCopy.saveCard(procedure, replacing: false, leftOut: [.deleting], english: false).detail
        XCTAssertTrue(korean.contains("지우신 건 빼고 배웠어요") && korean.contains("클립보드에 있는 걸 전부"), korean)
        // No paste in the lesson: the note doesn't speak of the clipboard.
        let typedOnly = ArisTeachProcedure(name: "x", steps: Array(procedure.steps.prefix(2)), parameters: procedure.parameters, created: at(0))
        XCTAssertFalse(ArisTeachCopy.saveCard(typedOnly, replacing: false, leftOut: [.deleting], english: true).detail.contains("clipboard"))
        // A typo taken back while typing is no deleting left out.
        var typo = recorder("x")
        typo.feed(key(1))
        XCTAssertNil(typo.feed(change(1.05, "abx", before: "")))
        typo.feed(key(1.2))
        XCTAssertNil(typo.feed(change(1.25, "ab", before: "abx")))
        XCTAssertEqual(ArisTeachGeneralise.leftOut(lesson(typo)!.events), [])
    }

    /// The audit's line about a lesson says how its text changes came (so a VM run can tell), and none of the text.
    func testTheLessonsShapeNamesNoText() {
        let shape = ArisTeachGeneralise.shape(lesson(frontLesson(["WWrap seed ", "WrWrap seed "]))!.events)
        XCTAssertEqual(shape, "appActivated focused shortcut shortcut valueChanged(live run 0-0+2)")
        XCTAssertFalse(shape.contains("Wr"))
    }
}
