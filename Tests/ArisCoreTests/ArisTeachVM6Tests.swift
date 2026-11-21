import XCTest
@testable import ArisCore

/// The sixth VM run's pure parts (aris-vmcheck notes6/*, cap6/*). The app layer's and the app's parts are in
/// tests/vmfix9-tests.swift.
final class ArisTeachVM6Tests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let textEdit = ArisTeachApp(bundle: "com.apple.TextEdit", name: "TextEdit")
    private let aris = ArisTeachApp(bundle: "com.lumenjsn.aris", name: "Aris")
    private var textView: ArisTeachElement { ArisTeachElement(role: "textArea", label: "", identifier: "First Text View") }
    private var composer: ArisTeachElement { ArisTeachElement(role: "textField", label: "Type or hold") }

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func lesson(_ events: [ArisTeachEvent], name: String) -> Result<ArisTeachProcedure, ArisTeachGeneralise.Problem>? {
        var recorder = ArisTeachRecorder()
        recorder.start(name: name, at: start)
        for event in events { recorder.feed(event) }
        return recorder.stop(at: at(30)).map { ArisTeachGeneralise.procedure($0) }
    }

    /// A shortcut the observer told as its menu command (the app had the keyboard, and its menus were read).
    private func chosen(_ time: Double, _ menu: [String], keys: String) -> ArisTeachEvent {
        var event = ArisTeachEvent(.menuChosen, at: at(time), app: textEdit, element: textView, menu: menu)
        event.keys = keys
        return event
    }

    // MARK: - Item 7c (and 7a): the lesson started in Aris's composer, then a shortcut in TextEdit

    /// cap6/LF-after-copy.jpg: "지금부터 하는 거 복사라고 해" typed in Aris (its composer had the keyboard), then ⌘C in
    /// TextEdit with "Copy me" selected; the card said "I didn't see anything I can do again".
    func testACopyOnlyLessonAfterTheComposerIsSaved() throws {
        let events = [ArisTeachEvent(.focused, at: at(0.2), app: aris, element: composer),
                      chosen(3, ["Edit", "Copy"], keys: "cmd+c")]
        let made = try XCTUnwrap(lesson(events, name: "복사")).get()
        XCTAssertEqual(made.steps.map(\.action), [.open, .menu])
        XCTAssertEqual(made.steps.last?.menu, ["Edit", "Copy"])
        XCTAssertEqual(made.steps.last?.keys, "cmd+c")
    }

    /// Item 7a: ⌘A (told as Edit › Select All) right after the composer, then the typing over it: 3 steps, as when the
    /// lesson started with a click in TextEdit.
    func testASelectAllShortcutRightAfterTheComposerIsAStep() throws {
        var typed = ArisTeachEvent(.valueChanged, at: at(4.1), app: textEdit, element: textView, value: "Replaced all", before: "Base doc")
        typed.overSelection = true
        let events = [ArisTeachEvent(.focused, at: at(0.2), app: aris, element: composer),
                      chosen(3, ["Edit", "Select All"], keys: "cmd+a"),
                      ArisTeachEvent(.input, at: at(4), app: textEdit, element: textView, input: .key), typed]
        let made = try XCTUnwrap(lesson(events, name: "전체 바꾸기")).get()
        XCTAssertEqual(made.steps.map(\.action), [.open, .menu, .type])
    }

    /// What is chosen by mouse in a menu while Aris still had the keyboard is not taken as his hand back (unchanged).
    func testAMenuChoiceWithNoKeysAfterTheComposerIsStillLeftOut() {
        let events = [ArisTeachEvent(.focused, at: at(0.2), app: aris, element: composer),
                      ArisTeachEvent(.menuChosen, at: at(3), app: textEdit, menu: ["Edit", "Copy"])]
        guard case .failure(.nothing)? = lesson(events, name: "x") else { return XCTFail("a menu choice with no hand of his seen is not a step") }
    }

    // MARK: - Item 7b: a shortcut of a submenu item greyed out when the menus were read

    /// cap6/LF2-teach-done-8s.jpg: ⌘E (Edit › Find › Use Selection for Find) was saved as "press ⌘E": the menus were read
    /// once as TextEdit was attached, with nothing selected, and that item was greyed out then.
    func testASubmenuShortcutGreyedOutAtTheReadIsItsCommand() {
        let items = [ArisTeachMenuKeys.Item(path: ["Edit", "Select All"], character: "A", modifiers: 0),
                     ArisTeachMenuKeys.Item(path: ["Edit", "Find", "Find…"], character: "F", modifiers: 0),
                     ArisTeachMenuKeys.Item(path: ["Edit", "Find", "Use Selection for Find"], character: "E", modifiers: 0, enabled: false)]
        XCTAssertEqual(ArisTeachMenuKeys.command(for: "cmd+e", in: items), ["Edit", "Find", "Use Selection for Find"])
        XCTAssertEqual(ArisTeachMenuKeys.command(for: "cmd+f", in: items), ["Edit", "Find", "Find…"])
        // Two items with the same keys, both greyed out: no telling which, the key stays.
        let twice = items + [ArisTeachMenuKeys.Item(path: ["View", "Use Selection"], character: "E", modifiers: 0, enabled: false)]
        XCTAssertNil(ArisTeachMenuKeys.command(for: "cmd+e", in: twice))
        // One enabled among them: that one.
        let one = items + [ArisTeachMenuKeys.Item(path: ["View", "Use Selection"], character: "E", modifiers: 0)]
        XCTAssertEqual(ArisTeachMenuKeys.command(for: "cmd+e", in: one), ["View", "Use Selection"])
    }

    // MARK: - Item 5: a card line made shorter ends at a word, with "…"

    /// cap6/M4-card3.jpg: "In TextEdit, replace everything in the document's text with ‘Replaced all’ (what was there".
    func testAShortenedCardLineEndsAtAWordWithAnEllipsis() {
        let line = "In TextEdit, replace everything in the document's text with ‘Replaced all’ (what was there is erased; asks each time)"
        let shown = ArisTextClip.clip(line, ArisAskPlan.lineLength)
        XCTAssertTrue(shown.hasSuffix("…"), shown)
        XCTAssertLessThanOrEqual(shown.count, ArisAskPlan.lineLength)
        XCTAssertTrue(line.hasPrefix(String(shown.dropLast())), shown)
        // It ends at a whole word of the line.
        let kept = String(shown.dropLast())
        XCTAssertTrue(line.dropFirst(kept.count).first.map { $0 == " " } ?? false, shown)
        XCTAssertEqual(ArisTextClip.clip("short", 90), "short")
        // No spaces (a long Korean run, a path): cut at the limit, still marked.
        let solid = String(repeating: "가", count: 120)
        XCTAssertEqual(ArisTextClip.clip(solid, 90), String(repeating: "가", count: 89) + "…")
        // An opening bracket is never left hanging before the mark.
        XCTAssertEqual(ArisTextClip.clip("aaaa bbbb (cccc dddd", 13), "aaaa bbbb…")
    }

    /// The gate's card: each line of the collapsed details that was shortened says so, at a word.
    func testTheCollapsedCardMarksEveryShortenedLine() {
        let long = "In TextEdit, replace everything in the document's text with ‘Replaced all’ (what was there is erased; asks each time)"
        let item = ArisAskItem(call: "call-1", facts: ArisCallFacts(capability: "app.type", arguments: [.init(kind: .app, value: "TextEdit"), .init(kind: .body, value: "Replaced all")]),
                               effect: .changePermanent, decision: .ask, provenance: .ownStep)
        let shown = ArisAskPlan.card([item], id: "c", intent: "i", countdown: false, home: "/Users/x",
                                     described: ["call-1": ArisAskDescription(title: "“전체 바꾸기”, step 3 of 3", line: long, spoken: "x")])
        let first = shown.detail.split(separator: "\n").map(String.init).first { $0.hasPrefix("In TextEdit") }
        XCTAssertEqual(first.map { $0.hasSuffix("…") }, true, shown.detail)
        XCTAssertTrue(shown.full?.contains(long) == true)
    }

    // MARK: - Item 6a / item 1: what a replay's end says

    func testOnlyARunThatDidEveryStepIsDone() {
        XCTAssertTrue(ArisTeachRunEnd.completed(.done(steps: 3)))
        XCTAssertFalse(ArisTeachRunEnd.completed(.partly(done: 2, skipped: [1])))
        XCTAssertFalse(ArisTeachRunEnd.completed(.stopped(at: 1, end: .failed("that menu item isn't there now"), done: 1)))
        XCTAssertFalse(ArisTeachRunEnd.completed(.stopped(at: 2, end: .declined, done: 2)))
        // cap6/D7en-card2.jpg: the failed run's tag is marked; a no on a card already takes the running tag away.
        XCTAssertTrue(ArisTeachRunEnd.marksTagFailed(.stopped(at: 1, end: .failed("that menu item isn't there now"), done: 1)))
        XCTAssertTrue(ArisTeachRunEnd.marksTagFailed(.partly(done: 2, skipped: [1])))
        XCTAssertTrue(ArisTeachRunEnd.marksTagFailed(.stopped(at: 0, end: .unmade, done: 0)))
        XCTAssertFalse(ArisTeachRunEnd.marksTagFailed(.stopped(at: 2, end: .declined, done: 2)))
        XCTAssertFalse(ArisTeachRunEnd.marksTagFailed(.stopped(at: 2, end: .stale, done: 2)))
        XCTAssertFalse(ArisTeachRunEnd.marksTagFailed(.done(steps: 3)))
    }

    /// notes6/R5en-record-tail.jsonl: the typing step's result, ok, with no undo.
    func testTypingWithNoUndoIsSaidAtTheEnd() {
        let unchecked = ArisTeachRunEnd.Unchecked()
        let typed = #"{"channel":"engine","did":"typed 9 characters in TextEdit (textArea)","effect":"change-reversible","ok":true,"verified":false}"#
        unchecked.note(call: "app_do", result: ArisMindResult(text: #"{"ok":true}"#, content: ArisContentSource(kind: "app", source: "TextEdit")))
        XCTAssertTrue(unchecked.apps.isEmpty)
        unchecked.note(call: "app_type", result: ArisMindResult(text: typed, content: ArisContentSource(kind: "app", source: "TextEdit")))
        XCTAssertEqual(unchecked.apps, ["TextEdit"])
        XCTAssertEqual(ArisTeachRunEnd.withUnchecked("Done: “메모 쓰기” (3 steps).", apps: unchecked.apps, english: true),
                       "Done: “메모 쓰기” (3 steps).\nWhat was typed into TextEdit couldn't be checked, so it can't be undone.")
        XCTAssertEqual(ArisTeachRunEnd.withUnchecked("끝", apps: ["TextEdit"], english: false), "끝\nTextEdit에 입력한 글은 확인하지 못해서 되돌릴 수 없어요.")
        // With its undo: nothing more is said.
        let undone = ArisTeachRunEnd.Unchecked()
        var withUndo = ArisMindResult(text: typed, content: ArisContentSource(kind: "app", source: "TextEdit"))
        withUndo.undo = ArisApps.TextUndo.recipe(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "", before: "", after: "Memo line")
        undone.note(call: "app_type", result: withUndo)
        XCTAssertEqual(ArisTeachRunEnd.withUnchecked("Done.", apps: undone.apps, english: true), "Done.")
    }
}
