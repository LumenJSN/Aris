import XCTest
@testable import ArisCore

/// "Show it once" against the fourth VM run (aris-vmcheck notes4/I4-taught.json, I4b-taught.json, K6-taught.json,
/// I6-taught.json, I2-taught.json; cap4/I4-teach-done-8s.jpg, I4-delete-card-showall.jpg, K7-ko-failreplay-cancel.jpg).
/// The principle: a lesson's text step is only what the user typed and where it went relative to what was there, and a
/// replay never removes text he did not remove in the lesson.
final class ArisTeachVM4Tests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let textEdit = ArisTeachApp(bundle: "com.apple.TextEdit", name: "TextEdit")
    private var textView: ArisTeachElement { ArisTeachElement(role: "textArea", label: "", identifier: "First Text View") }

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func key(_ time: Double) -> ArisTeachEvent { ArisTeachEvent(.input, at: at(time), app: textEdit, element: textView, input: .key) }

    private func change(_ time: Double, _ value: String, before: String?, over: Bool = false) -> ArisTeachEvent {
        var event = ArisTeachEvent(.valueChanged, at: at(time), app: textEdit, element: textView, value: value, before: before)
        if over { event.overSelection = true }
        return event
    }

    private func procedure(_ events: [ArisTeachEvent], name: String = "lesson") throws -> ArisTeachProcedure {
        var recorder = ArisTeachRecorder()
        recorder.start(name: name, at: start)
        for event in events { recorder.feed(event) }
        let lesson = try XCTUnwrap(recorder.stop(at: at(30)))
        return try ArisTeachGeneralise.procedure(lesson).get()
    }

    private func typeStep(_ made: ArisTeachProcedure) throws -> ArisTeachStep { try XCTUnwrap(made.steps.first { $0.action == .type }) }

    // MARK: - D1: "줄 추가" typed into an empty new document was saved as "replace everything in 본문"

    /// The lesson as the observer reports it now: his click into the empty document (its value read then, ""), his
    /// keys, and the changes, the last one TextEdit's own capital ("added line" → "Added line").
    private var addLine: [ArisTeachEvent] {
        [ArisTeachEvent(.appActivated, at: at(0.1), app: textEdit),
         ArisTeachEvent(.input, at: at(1), app: textEdit, element: textView, input: .click),
         key(2), change(2.01, "a", before: ""), key(2.1), change(2.11, "added", before: "a"), key(2.6), change(2.61, "added line", before: "added"),
         change(2.7, "Added line", before: "added line")]
    }

    func testTypingIntoAnEmptyDocumentIsAnInsertionNotAReplace() throws {
        let made = try procedure(addLine, name: "줄 추가")
        XCTAssertEqual(made.steps.map(\.action), [.open, .type])
        let step = try typeStep(made)
        XCTAssertEqual(step.place, .end)
        XCTAssertFalse(step.replaces)
        XCTAssertEqual(made.parameters.first?.example, "Added line")
        let arguments = try XCTUnwrap(step.arguments(values: made.examples))
        XCTAssertEqual(arguments["at"], .string("end"))
        XCTAssertNil(arguments["replace"])
        // An insertion into a document is a reversible change: the replay doesn't ask, and "되돌려" takes it back. (The text
        // began a line, so its call carries a line break: rated as Return where the focus can't be read, ArisTeachNewLineTests.)
        let document = ArisApps.EffectContext(surface: { _, _ in .plain })
        XCTAssertEqual(ArisApps.Spec.named("app.type")?.effect(.object(arguments), document), .changeReversible)
        XCTAssertFalse(ArisTeachCopy.step(step, in: made, english: false).contains("원래 내용은 지워져요"))
    }

    func testASelectAllInAnEmptyFieldIsNoReplace() throws {
        let events = [ArisTeachEvent(.appActivated, at: at(0.1), app: textEdit), ArisTeachEvent(.focused, at: at(0.5), app: textEdit, element: textView),
                      ArisTeachEvent(.shortcut, at: at(1), app: textEdit, element: textView, keys: "cmd+a"), key(2), change(2.01, "Added line", before: "")]
        XCTAssertEqual(try typeStep(procedure(events)).place, .end)
    }

    func testTextGoneWithNoSelectionSeenIsNeverAReplace() throws {
        // As the run recorded it: the change kept carried a value read late ("added line"), so TextEdit's capital
        // looked like text removed. With no selection of his seen, nothing he didn't remove is removed by a replay.
        let made = try procedure([ArisTeachEvent(.appActivated, at: at(0.1), app: textEdit), key(2), change(2.7, "Added line", before: "added line")])
        XCTAssertNotEqual(try typeStep(made).place, .all)
        XCTAssertEqual(ArisTeachGeneralise.textChange(before: "old text", after: "new"), .init(text: "new", place: .end))
    }

    func testTypingOverASelectionOfWhatWasThereReplaces() throws {
        let events = [ArisTeachEvent(.appActivated, at: at(0.1), app: textEdit), key(2), change(2.01, "N", before: "Existing line keep", over: true),
                      key(2.1), change(2.11, "New", before: "N")]
        let step = try typeStep(procedure(events))
        XCTAssertEqual(step.place, .all)
        XCTAssertEqual(step.arguments(values: [:].merging(["p1": "New"]) { $1 })?["replace"], .bool(true))
        XCTAssertEqual(ArisTeachGeneralise.textChange(before: "old text", after: "new", overSelection: true), .init(text: "new", place: .all))
    }

    // MARK: - D2: "quick note" saved "Lesson line one\nEnglish line" (the document's old line as his) as a replace

    /// ⌘↓, Return and "english line" typed into a document holding "Lesson line one", read against its value from his
    /// click (before any key of his could be in it), as the observer reads it now.
    private var quickNote: [ArisTeachEvent] {
        [ArisTeachEvent(.appActivated, at: at(0.1), app: textEdit),
         ArisTeachEvent(.input, at: at(1), app: textEdit, element: textView, input: .click),
         ArisTeachEvent(.shortcut, at: at(1.5), app: textEdit, element: textView, keys: "cmd+down"),
         ArisTeachEvent(.shortcut, at: at(2), app: textEdit, element: textView, keys: "return"),
         change(2.01, "Lesson line one\n", before: "Lesson line one"),
         key(2.2), change(2.21, "Lesson line one\ne", before: "Lesson line one\n"),
         key(2.9), change(2.91, "Lesson line one\nenglish line", before: "Lesson line one\ne"),
         change(3.0, "Lesson line one\nEnglish line", before: "Lesson line one\nenglish line")]
    }

    func testQuickNoteKeepsOnlyTheLineHeTypedWithItsReturn() throws {
        let made = try procedure(quickNote, name: "quick note")
        // The Return is the step's line start, not part of the value (eleventh VM run, T1).
        XCTAssertEqual(made.parameters.first?.example, "English line")
        let step = try typeStep(made)
        XCTAssertEqual(step.startsLine, true)
        XCTAssertEqual(step.place, .end)
        XCTAssertFalse(step.replaces)
    }

    func testQuickNoteAsRecordedIsNeverTheWholeFieldNorAReplace() throws {
        // The run's own recording: the only change kept was read after his typing ("…\nenglish line" before TextEdit's
        // capital). The document's old line is never taken for his, and nothing is replaced.
        let made = try procedure([ArisTeachEvent(.appActivated, at: at(0.1), app: textEdit),
                                  ArisTeachEvent(.shortcut, at: at(1.5), app: textEdit, element: textView, keys: "cmd+down"),
                                  key(2.9), change(3.0, "Lesson line one\nEnglish line", before: "Lesson line one\nenglish line")])
        let step = try typeStep(made)
        XCTAssertNotEqual(step.place, .all)
        XCTAssertFalse(made.parameters.first?.example.contains("Lesson line one") ?? true)
    }

    // MARK: - D3: "줄 덧붙이기" (⌘↓, Return, "Second line") replayed as "Existing line keepSecond line"

    func testAReturnBeforeTheTextIsKeptAndTheEndKeyIsWhereItGoes() throws {
        let events = [ArisTeachEvent(.appActivated, at: at(0.1), app: textEdit),
                      ArisTeachEvent(.input, at: at(1), app: textEdit, element: textView, input: .click),
                      ArisTeachEvent(.shortcut, at: at(1.5), app: textEdit, element: textView, keys: "cmd+down"),
                      ArisTeachEvent(.shortcut, at: at(2), app: textEdit, element: textView, keys: "return"),
                      change(2.01, "Existing line keep\n", before: "Existing line keep"),
                      key(2.2), change(2.21, "Existing line keep\nSecond line", before: "Existing line keep\n")]
        let made = try procedure(events, name: "줄 덧붙이기")
        // No "⌘↓ 누르기" of its own: the key is where the text goes.
        XCTAssertEqual(made.steps.map(\.action), [.open, .type])
        XCTAssertEqual(made.parameters.first?.example, "Second line")
        XCTAssertEqual(made.steps[1].startsLine, true)
        let arguments = try XCTUnwrap(made.steps[1].arguments(values: made.examples))
        XCTAssertEqual(arguments["text"], .string("\nSecond line"))
        XCTAssertEqual(arguments["at"], .string("end"))
    }

    func testAnEndKeyFollowedByNoTypingStaysAStep() throws {
        let events = [ArisTeachEvent(.appActivated, at: at(0.1), app: textEdit),
                      ArisTeachEvent(.shortcut, at: at(1.5), app: textEdit, element: textView, keys: "cmd+down"),
                      ArisTeachEvent(.menuChosen, at: at(5), app: textEdit, menu: ["File", "Save"])]
        XCTAssertEqual(try procedure(events).steps.map(\.action), [.open, .press, .menu])
    }

    func testTypingInsideTextGoesAtTheCaret() throws {
        XCTAssertEqual(ArisTeachGeneralise.textChange(before: "ab", after: "aXYb"), .init(text: "XY", place: .caret))
        var step = ArisTeachStep(action: .type, app: "TextEdit", bundle: "com.apple.TextEdit", target: "First Text View 칸", text: "XY")
        step.place = .caret
        XCTAssertEqual(step.arguments(values: [:])?["at"], .string("caret"))
    }

    // MARK: - D4: a mouse-chosen menu saved "pick ‘File’" / "pick ‘Format’" before the item, which always failed

    func testAMenuChosenWithTheMouseIsOneMenuStep() throws {
        let bar = ArisTeachElement(role: "menuBarItem", label: "Format")
        let events = [ArisTeachEvent(.appActivated, at: at(0.1), app: textEdit),
                      ArisTeachEvent(.input, at: at(1), app: textEdit, input: .click),
                      ArisTeachEvent(.selected, at: at(1.05), app: textEdit, element: bar),
                      ArisTeachEvent(.menuChosen, at: at(2), app: textEdit, menu: ["Format", "Wrap to Page"])]
        let made = try procedure(events, name: "자 숨기기")
        XCTAssertEqual(made.steps.map(\.action), [.open, .menu])
        XCTAssertEqual(made.steps[1].menuPath, "Format › Wrap to Page")
    }

    func testAMenuOpenedAndClosedIsNothing() {
        var recorder = ArisTeachRecorder()
        recorder.start(name: "x", at: start)
        recorder.feed(ArisTeachEvent(.input, at: at(1), app: textEdit, input: .click))
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.selected, at: at(1.05), app: textEdit, element: ArisTeachElement(role: "menuBarItem", label: "File"))), .nothing)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testALessonSavedWithAMenuOpeningReplaysWithoutIt() throws {
        // notes4/I2-taught.json's "메모 남기기", as saved.
        let saved = #"""
        {"changed":"2026-11-19T12:26:29Z","created":"2026-11-19T12:26:29Z","id":"827EAAE4-135E-4CD3-ACCA-DF7C7DD13E50","name":"메모 남기기",
         "parameters":[{"app":"TextEdit","example":"Milk and bread\n","fromApp":false,"key":"p1","label":"본문"}],"skipped":0,
         "steps":[{"action":"open","app":"TextEdit","bundle":"com.apple.TextEdit"},
                  {"action":"select","app":"TextEdit","bundle":"com.apple.TextEdit","label":"File","role":"menuBarItem","seen":{"kind":"app","source":"TextEdit"},"target":"File"},
                  {"action":"menu","app":"TextEdit","bundle":"com.apple.TextEdit","label":"New","menu":["File","New"],"seen":{"kind":"app","source":"TextEdit"}},
                  {"action":"type","app":"TextEdit","bundle":"com.apple.TextEdit","fromApp":false,"label":"본문","parameter":"p1","place":"end","role":"textArea","seen":{"kind":"app","source":"TextEdit"},"target":"First Text View 칸"}]}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let procedure = try decoder.decode(ArisTeachProcedure.self, from: Data(saved.utf8))
        XCTAssertEqual(procedure.steps.map(\.action), [.open, .menu, .type])
    }

    // MARK: - D5: "Wrap to Page" taught, "Wrap to Window" pressed and reported done

    private let formatMenu = [
        ArisApps.Command(id: "menu:a", title: "Wrap to Window", channel: .menu, path: ["Format", "Wrap to Window"], effect: .changeReversible),
        ArisApps.Command(id: "menu:b", title: "Make Plain Text", channel: .menu, path: ["Format", "Make Plain Text"], keys: "⌘⇧T", effect: .changeReversible),
    ]

    func testATaughtMenuStepFindsOnlyItsExactItem() throws {
        guard case .missing(let why) = ArisApps.Exact.menu("Format › Wrap to Page", key: nil, in: formatMenu, app: "TextEdit") else {
            return XCTFail("a near match was pressed")
        }
        XCTAssertTrue(why.contains("isn't there now") && why.contains("‘Wrap to Window’ instead"), why)
        XCTAssertEqual(ArisApps.Exact.menu("Format › Make Plain Text", key: "cmd+shift+t", in: formatMenu, app: "TextEdit"), .found(formatMenu[1]))
        guard case .missing = ArisApps.Exact.menu("Format › Make Plain Text", key: "cmd+t", in: formatMenu, app: "TextEdit") else {
            return XCTFail("an item with another key was pressed")
        }
        XCTAssertEqual(ArisApps.Exact.keys(shortcut: "⌘⇧T"), "cmd+shift+t")
        let step = ArisTeachStep(action: .menu, app: "TextEdit", bundle: "com.apple.TextEdit", label: "Wrap to Page", menu: ["Format", "Wrap to Page"])
        // Exactness is a mark on the path the gate rates, never an argument beside it.
        XCTAssertEqual(step.arguments(values: [:])?["command"], .string("=Format › Wrap to Page"))
        XCTAssertNil(step.arguments(values: [:])?["exact"])
        var keyed = step
        keyed.keys = "cmd+shift+t"
        XCTAssertEqual(keyed.arguments(values: [:])?["command"], .string("=Format › Wrap to Page [cmd+shift+t]"))
        XCTAssertEqual(ArisApps.Exact.parse("=Format › Wrap to Page [cmd+shift+t]"), .init(text: "Format › Wrap to Page", exact: true, key: "cmd+shift+t"))
        XCTAssertEqual(ArisApps.Exact.parse("Format › Wrap to Page"), .init(text: "Format › Wrap to Page", exact: false, key: nil))
        // Said as a fact in Korean, never in the words of his own no.
        let korean = try XCTUnwrap(ArisTeachCopy.reason(why, english: false))
        XCTAssertTrue(korean.contains("Wrap to Window") && !korean.contains("지 못했어요"), korean)
    }

    func testATaughtPressFindsOnlyItsExactControl() {
        let elements = [ArisApps.ReadElement(id: "e1", role: "button", label: "Wrap to Window"), ArisApps.ReadElement(id: "e2", role: "button", label: "Save")]
        XCTAssertEqual(ArisApps.Exact.controls("Wrap to Page", in: elements), .none)
        XCTAssertEqual(ArisApps.Exact.controls("Save", in: elements), .one(elements[1]))
        XCTAssertEqual(ArisApps.Exact.nearest("Wrap to Page", in: elements)?.label, "Wrap to Window", "what the app shows instead is said")
        let step = ArisTeachStep(action: .click, app: "TextEdit", bundle: "com.apple.TextEdit", target: "Save 버튼", role: "button", label: "Save")
        XCTAssertEqual(step.arguments(values: [:])?["target"], .string("=Save"))
        XCTAssertNil(step.arguments(values: [:])?["exact"])
        // A row is still found by its description.
        XCTAssertEqual(ArisTeachStep(action: .select, app: "Mail", bundle: "com.apple.mail", target: "Inbox 항목", role: "row", label: "Inbox").arguments(values: [:])?["target"],
                       .string("Inbox 항목"))
    }

    /// Security review of the D5 fix: what the gate rates is what is pressed. The mark is on the one value both read,
    /// the schema has no `exact` or `key`, and pay, send and delete words under the mark are rated as without it.
    func testWhatIsRatedIsWhatIsPressed() throws {
        let context = ArisApps.EffectContext()
        for name in ["app.click", "app.select", "app.do"] {
            let spec = try XCTUnwrap(ArisApps.Spec.named(name))
            let properties = (spec.parameters.any as? [String: Any])?["properties"] as? [String: Any] ?? [:]
            XCTAssertNil(properties["exact"], name)
            XCTAssertNil(properties["key"], name)
        }
        let click = try XCTUnwrap(ArisApps.Spec.named("app.click")), select = try XCTUnwrap(ArisApps.Spec.named("app.select"))
        for label in ["보내기", "Send", "Pay now", "결제", "Delete", "삭제", "Cancel"] {
            let plain = click.effect(.object(["app": .string("Mail"), "target": .string(label)]), context)
            XCTAssertEqual(click.effect(.object(["app": .string("Mail"), "target": .string("=" + label)]), context), plain, label)
            XCTAssertEqual(select.effect(.object(["app": .string("Mail"), "target": .string("=" + label)]), context),
                           select.effect(.object(["app": .string("Mail"), "target": .string(label)]), context), label)
        }
        // A replay step pressing "보내기" is rated outward, so it asks.
        let send = ArisTeachStep(action: .click, app: "Messages", bundle: "com.apple.MobileSMS", target: "보내기 버튼", role: "button", label: "보내기")
        XCTAssertEqual(click.effect(.object(try XCTUnwrap(send.arguments(values: [:]))), context), .outward)
        XCTAssertEqual(click.effect(.object(["app": .string("Mail"), "target": .string("=Send")]), context), .outward)
    }

    // MARK: - D6: "Left out: 1 password or secret field" after the Wrap to Page lesson

    func testAScrollBarsNumberIsNoSecretField() throws {
        let scrollBar = ArisTeachElement(role: "scrollBar", label: "")
        var recorder = ArisTeachRecorder()
        recorder.start(name: "자 숨기기", at: start)
        recorder.feed(ArisTeachEvent(.input, at: at(1), app: textEdit, input: .click))
        recorder.feed(ArisTeachEvent(.menuChosen, at: at(2), app: textEdit, menu: ["Format", "Wrap to Page"]))
        // Wrap to Page moves the document's scroll bar: its value is a number that passes the card check.
        XCTAssertTrue(ArisTeachPrivacy.holdsCard("0.4285714285714286"))
        recorder.feed(ArisTeachEvent(.valueChanged, at: at(2.1), app: textEdit, element: scrollBar, value: "0.4285714285714286"))
        XCTAssertEqual(recorder.skipped, 0)
        // A real secret field still counts, once.
        let password = ArisTeachElement(role: "textField", label: "Password")
        recorder.feed(ArisTeachEvent(.valueChanged, at: at(3), app: textEdit, element: password, value: "x"))
        recorder.feed(ArisTeachEvent(.valueChanged, at: at(3.1), app: textEdit, element: password, value: "xy"))
        XCTAssertEqual(recorder.skipped, 1)
        // A card number typed into a field is still left out.
        var other = ArisTeachRecorder()
        other.start(name: "y", at: start)
        other.feed(ArisTeachEvent(.valueChanged, at: at(1), app: textEdit, element: textView, value: "4111 1111 1111 1111"))
        XCTAssertEqual(other.skipped, 1)
    }

    // MARK: - D7: undoing a replay's typing failed on real TextEdit

    func testTextUndoIsMadeFromWhatTheFieldReadsBack() throws {
        // Sent "added line" into an empty document; TextEdit made it "Added line". An empty field reads as "".
        let recipe = try XCTUnwrap(ArisApps.TextUndo.recipe(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "", before: "",
                                                             after: "Added line"))
        guard case .textInserted(_, let element, _) = recipe, let mark = ArisApps.TextUndo.mark(element) else { return XCTFail("no mark") }
        XCTAssertEqual(mark.inserted, "Added line")
        XCTAssertEqual(ArisApps.TextUndo.find(in: "Added line", mark: mark), .range(NSRange(location: 0, length: 10)))
        XCTAssertEqual(ArisApps.TextUndo.find(in: "Added line!", mark: mark), .changed)
        XCTAssertEqual(ArisApps.TextUndo.find(in: "", mark: mark), .gone)
        // Appended after what was there, Return first.
        let appended = try XCTUnwrap(ArisApps.TextUndo.recipe(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "",
                                                               before: "Existing line keep", after: "Existing line keep\nSecond line"))
        guard case .textInserted(_, let kept, _) = appended, let second = ArisApps.TextUndo.mark(kept) else { return XCTFail("no mark") }
        XCTAssertEqual(ArisApps.TextUndo.find(in: "Existing line keep\nSecond line", mark: second), .range(NSRange(location: 18, length: 12)))
        XCTAssertFalse(kept.contains("Existing line keep"), "what was there is kept only as a length and a hash")
        // Inside the text, at the caret.
        let inside = try XCTUnwrap(ArisApps.TextUndo.insertion(before: "ab", after: "aXYb"))
        XCTAssertEqual(inside, .init(location: 1, text: "XY"))
        // Something that was there gone: no insertion, so no undo that could remove his text.
        XCTAssertNil(ArisApps.TextUndo.insertion(before: "abc", after: "aXc"))
        XCTAssertTrue(ArisApps.TextUndo.refusal([.changed], app: "TextEdit", replace: false).contains("was edited after Aris typed"))
    }

    func testAReplaceKeepsWhatItErased() throws {
        let recipe = try XCTUnwrap(ArisApps.TextUndo.replaced(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "",
                                                               before: "Existing line keep", after: "Added line", copy: "11111111-2222-3333-4444-555555555555"))
        guard case .textInserted(_, let element, _) = recipe, let mark = ArisApps.TextUndo.mark(element) else { return XCTFail("no mark") }
        XCTAssertEqual(mark.erased, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(ArisApps.TextUndo.find(in: "Added line", mark: mark), .range(NSRange(location: 0, length: 10)))
        XCTAssertEqual(ArisApps.TextUndo.find(in: "Existing line keep", mark: mark), .gone)
    }

    func testARecipeFromBeforeStillUndoes() throws {
        let old = #"{"bundle":"com.apple.TextEdit","role":"textArea","label":"","inserted":"Second line","beforeLength":18,"beforeHash":"\#(ArisApps.TextUndo.hash("Existing line keep"))"}"#
        let mark = try XCTUnwrap(ArisApps.TextUndo.mark(old))
        XCTAssertEqual(ArisApps.TextUndo.find(in: "Existing line keepSecond line", mark: mark), .range(NSRange(location: 18, length: 11)))
    }

    // MARK: - D1's replay: the replace card shows what it erases

    func testAReplaceCardShowsWhatItErasesAndNoCapabilityId() {
        var facts = ArisCallFacts(capability: "app.type", arguments: [.init(kind: .app, value: "TextEdit"), .init(kind: .body, value: "Added line")])
        facts.erases = ArisErasedText(text: "Existing line keep\nSecond", keepable: true)
        let item = ArisAskItem(call: "c1", facts: facts, effect: .changePermanent, decision: .ask, provenance: .ownStep)
        let card = ArisAskPlan.card([item], id: "t1", intent: "i", countdown: false, home: "/Users/user")
        XCTAssertEqual(card.title, "글 바꾸기 · TextEdit")
        for line in ["지워지는 글 (25자, 2줄):", "「Existing line keep」", "「Second」", ArisAskPlan.erasesKept] { XCTAssertTrue(card.detail.contains(line), card.detail) }
        XCTAssertFalse((card.full ?? "").contains("[app.type]"), card.full ?? "")
        XCTAssertTrue((card.full ?? "").contains("앱: TextEdit") && (card.full ?? "").contains("내용: Added line"), card.full ?? "")
        facts.erases = ArisErasedText(text: "x", keepable: false)
        let lost = ArisAskPlan.card([ArisAskItem(call: "c2", facts: facts, effect: .changePermanent, decision: .ask, provenance: .ownStep)], id: "t2", intent: "i",
                                    countdown: false, home: "/Users/user")
        XCTAssertTrue(lost.detail.contains(ArisAskPlan.erasesLost))
    }

    // MARK: - D8: the English card's word for the document's text

    func testTheEnglishCardCallsTheDocumentsTextText() throws {
        let made = try procedure(quickNote, name: "quick note")
        let english = ArisTeachCopy.saveCard(made, replacing: false, english: true)
        XCTAssertFalse(english.detail.contains("본문"), english.detail)
        XCTAssertTrue(english.detail.contains("[text]") && english.detail.contains("Changes each time: text"), english.detail)
        XCTAssertTrue(ArisTeachCopy.saveCard(made, replacing: false, english: false).detail.contains("[본문]"))
        // He may name it either way.
        XCTAssertEqual(ArisTeachMatch.values(made, words: "text is hello"), ["p1": "hello"])
        XCTAssertEqual(ArisTeachMatch.values(made, words: "본문은 안녕"), ["p1": "안녕"])
        let missing = ArisTeachReplay.missing(made, given: [:])
        XCTAssertEqual(ArisTeachCopy.valuesCard(made, missing: missing, english: true).fields.first?.key, "text")
        XCTAssertEqual(ArisTeachReplay.answered(missing, edits: ["text": "hi"]), ["p1": "hi"])
    }

    // MARK: - D9: the value's newline made a row of its own on the card

    func testANewlineIsShownAsAMark() throws {
        let made = try procedure(quickNote, name: "quick note")
        let line = ArisTeachCopy.step(try typeStep(made), in: made, english: false)
        XCTAssertFalse(line.contains("\n"), line)
        XCTAssertTrue(line.contains("↵"), line)
        XCTAssertTrue(line.contains("English line"), line)
    }
}
