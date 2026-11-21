import XCTest
@testable import ArisCore

/// The sixth VM run (aris-vmcheck notes5/I1-taught.json, cap5/I1-replay-allow1.jpg): "줄 추가" was taught by typing
/// "Added line" into an empty document and replayed on one holding "Existing line keep" as "Existing line keepAdded
/// line". A lesson now keeps whether his typing began a line (read only from the field's text before his typing), and
/// its replay puts one line break before the text where the line isn't empty: as part of the text the trust gate rates
/// and the card shows (↵), never added after the decision; app.type types that break only into a text area whose text
/// doesn't already end a line, so a miss types less, never more.
final class ArisTeachNewLineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let bundle = "com.apple.TextEdit"
    private let textEdit = ArisTeachApp(bundle: "com.apple.TextEdit", name: "TextEdit")
    private var textView: ArisTeachElement { ArisTeachElement(role: "textArea", label: "", identifier: "First Text View") }
    private var searchField: ArisTeachElement { ArisTeachElement(role: "textField", label: "Search") }

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    /// He typed `value` into `element`, which held `before` (nil: not read) right before his first key.
    private func lesson(before: String?, value: String, element: ArisTeachElement? = nil) throws -> ArisTeachProcedure {
        let field = element ?? textView
        let events = [ArisTeachEvent(.appActivated, at: at(0.1), app: textEdit),
                      ArisTeachEvent(.input, at: at(1), app: textEdit, element: field, input: .click),
                      ArisTeachEvent(.input, at: at(2), app: textEdit, element: field, input: .key),
                      ArisTeachEvent(.valueChanged, at: at(2.01), app: textEdit, element: field, value: value, before: before)]
        var recorder = ArisTeachRecorder()
        recorder.start(name: "줄 추가", at: start)
        for event in events { recorder.feed(event) }
        let made = try XCTUnwrap(recorder.stop(at: at(30)))
        return try ArisTeachGeneralise.procedure(made).get()
    }

    private func typeStep(_ made: ArisTeachProcedure) throws -> ArisTeachStep { try XCTUnwrap(made.steps.first { $0.action == .type }) }

    /// "줄 추가" as the VM saved it, with the mark a lesson keeps now.
    private func addLine(startsLine: Bool?, place: ArisTeachStep.Place? = .end, role: String = "textArea") -> ArisTeachProcedure {
        var step = ArisTeachStep(action: .type, app: "TextEdit", bundle: bundle, target: "First Text View 칸", role: role, label: "본문", parameter: "p1",
                                 seen: ArisContentSource(kind: "app", source: "TextEdit"))
        step.place = place
        step.startsLine = startsLine
        step.fromApp = false
        return ArisTeachProcedure(name: "줄 추가", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle), step],
                                  parameters: [ArisTeachParameter(key: "p1", label: "본문", example: "Added line", app: "TextEdit", fromApp: false)],
                                  created: start)
    }

    // MARK: - Recording: whether his typing began a line

    func testTypingIntoAnEmptyDocumentBeganALine() throws {
        let step = try typeStep(lesson(before: "", value: "Added line"))
        XCTAssertEqual(step.startsLine, true)
        XCTAssertEqual(step.place, .end)
        XCTAssertEqual(step.text ?? "", "", "the text he typed stays his value, with no line break of its own")
    }

    func testTypingAfterALineBreakBeganALine() throws {
        XCTAssertEqual(try typeStep(lesson(before: "Existing line keep\n", value: "Existing line keep\nAdded line")).startsLine, true)
    }

    func testTypingRightAfterTextDidNotBeginALine() throws {
        let step = try typeStep(lesson(before: "Existing line keep", value: "Existing line keepAdded line"))
        XCTAssertNil(step.startsLine)
        // His own Return before the text is the step's line start, never part of the value (eleventh VM run, T1: kept
        // in the value, a run with another value dropped it).
        let returned = try lesson(before: "Existing line keep", value: "Existing line keep\nSecond line")
        XCTAssertEqual(try typeStep(returned).startsLine, true)
        XCTAssertEqual(returned.parameters.first?.example, "Second line")
    }

    func testTextNotReadBeforeHisTypingIsNoMark() throws {
        XCTAssertNil(try typeStep(lesson(before: nil, value: "Added line")).startsLine, "a field not read before is no evidence: nothing is marked")
    }

    func testASingleLineFieldIsNeverMarked() throws {
        XCTAssertNil(try typeStep(lesson(before: "", value: "weather", element: searchField)).startsLine)
    }

    func testTheRuleReadsOnlyTheTextBeforeAndAfter() {
        XCTAssertTrue(ArisTeachGeneralise.startsLine(before: "", after: "x"))
        XCTAssertTrue(ArisTeachGeneralise.startsLine(before: "a\n", after: "a\nx"))
        XCTAssertTrue(ArisTeachGeneralise.startsLine(before: "a\r\n", after: "a\r\nx"))
        XCTAssertTrue(ArisTeachGeneralise.startsLine(before: "a\nb", after: "a\nxb"), "inside the text, right after a line break")
        XCTAssertFalse(ArisTeachGeneralise.startsLine(before: "a", after: "ax"))
        XCTAssertFalse(ArisTeachGeneralise.startsLine(before: "a", after: "a\nx"))
        XCTAssertFalse(ArisTeachGeneralise.startsLine(before: "ab", after: "xab"), "the start of a field that holds text is not an empty field")
        XCTAssertFalse(ArisTeachGeneralise.startsLine(before: nil, after: "x"))
    }

    // MARK: - Replay: the decision table of the call it makes

    func testAMarkedStepCarriesTheLineBreakInTheTextTheGateRates() throws {
        let arguments = try XCTUnwrap(addLine(startsLine: true).steps[1].arguments(values: ["p1": "Added line"]))
        XCTAssertEqual(arguments["text"], .string("\nAdded line"))
        XCTAssertEqual(arguments["line"], .string("new"))
        XCTAssertEqual(arguments["at"], .string("end"))
        // In a document a line break is a new line: still a reversible change.
        let document = ArisApps.EffectContext(surface: { _, _ in .plain })
        XCTAssertEqual(ArisApps.Spec.named("app.type")?.effect(.object(arguments), document), .changeReversible)
        // Where Return sends, or where the focus can't be read, the break is rated as Return: the gate sees it.
        let form = ArisApps.EffectContext(surface: { _, _ in .form })
        XCTAssertEqual(ArisApps.Spec.named("app.type")?.effect(.object(arguments), form), .outward)
        XCTAssertEqual(ArisApps.Spec.named("app.type")?.effect(.object(arguments), ArisApps.EffectContext()), .outward)
    }

    func testAnUnmarkedStepIsExactlyAsBefore() throws {
        for mark in [nil, false] as [Bool?] {
            let arguments = try XCTUnwrap(addLine(startsLine: mark).steps[1].arguments(values: ["p1": "Added line"]))
            XCTAssertEqual(arguments, ["app": .string("TextEdit"), "target": .string("First Text View 칸"), "text": .string("Added line"), "at": .string("end")])
        }
    }

    func testOnlyAnInsertionAtTheEndOfATextAreaGetsTheBreak() throws {
        // At the caret the text before it can't be told at replay: nothing is added.
        let caret = try XCTUnwrap(addLine(startsLine: true, place: .caret).steps[1].arguments(values: ["p1": "Added line"]))
        XCTAssertEqual(caret["text"], .string("Added line"))
        XCTAssertNil(caret["line"])
        // A replace is untouched.
        let replace = try XCTUnwrap(addLine(startsLine: true, place: .all).steps[1].arguments(values: ["p1": "Added line"]))
        XCTAssertEqual(replace["text"], .string("Added line"))
        XCTAssertEqual(replace["replace"], .bool(true))
        XCTAssertNil(replace["line"])
        // A lesson edited by hand to mark a one-line field: no break.
        let field = try XCTUnwrap(addLine(startsLine: true, role: "textField").steps[1].arguments(values: ["p1": "Added line"]))
        XCTAssertEqual(field["text"], .string("Added line"))
        XCTAssertNil(field["line"])
    }

    func testTheReplayPlanTypesWhatItsCardShows() throws {
        let made = addLine(startsLine: true)
        let plan = ArisTeachReplay.plan(made, given: ["p1": "Second"], words: "줄 추가 해 줘, 본문은 Second", run: "nl")
        let call = try XCTUnwrap(plan.calls[1])
        XCTAssertEqual(call.object?["text"] as? String, "\nSecond")
        let english = ArisTeachReplay.described(made, plan: plan, english: true)[call.id]
        let korean = ArisTeachReplay.described(made, plan: plan, english: false)[call.id]
        XCTAssertEqual(english?.line, "In TextEdit, put ‘↵Second’ in the document's text, on a new line")
        XCTAssertEqual(korean?.line, "TextEdit의 ‘본문’에 새 줄로 ‘↵Second’ 넣기")
    }

    // MARK: - app.type: where the break is typed

    private func field(_ role: String, _ value: String?) -> ArisApps.ReadElement {
        ArisApps.ReadElement(id: "elem_1", role: role, label: "First Text View", value: value)
    }

    private let base: [String: ArisApps.JSON] = ["app": .string("TextEdit"), "text": .string("\nAdded line"), "at": .string("end"), "line": .string("new")]
    private var marked: ArisApps.JSON { .object(base) }
    private func marked(_ change: (inout [String: ArisApps.JSON]) -> Void) -> ArisApps.JSON {
        var object = base
        change(&object)
        return .object(object)
    }

    func testTheBreakIsTypedOnlyAfterTextThatDoesNotEndALine() {
        XCTAssertEqual(ArisApps.NewLine.typed(marked, field: field("textArea", "Existing line keep")), "\nAdded line")
        XCTAssertEqual(ArisApps.NewLine.typed(marked, field: field("textArea", nil)), "Added line", "an empty document")
        XCTAssertEqual(ArisApps.NewLine.typed(marked, field: field("textArea", "")), "Added line")
        XCTAssertEqual(ArisApps.NewLine.typed(marked, field: field("textArea", "Existing line keep\n")), "Added line")
        XCTAssertEqual(ArisApps.NewLine.typed(marked, field: field("textArea", "Existing\r\n")), "Added line")
    }

    func testAOneLineFieldOrAFieldNotKnownNeverGetsTheBreak() {
        for role in ["textField", "searchField", "comboBox", "secureTextField", "staticText", "other"] {
            XCTAssertEqual(ArisApps.NewLine.typed(marked, field: field(role, "Existing")), "Added line", role)
        }
        XCTAssertEqual(ArisApps.NewLine.typed(marked, field: nil), "Added line", "the focused field, not read: nothing added")
        XCTAssertEqual(ArisApps.NewLine.typed(marked { $0["at"] = .string("caret") }, field: field("textArea", "Existing")), "Added line")
        XCTAssertEqual(ArisApps.NewLine.typed(marked { $0["replace"] = .bool(true) }, field: field("textArea", "Existing")), "Added line")
    }

    func testWithoutTheMarkTheTextIsTypedAsGiven() {
        let plain = marked { $0["line"] = nil }
        XCTAssertEqual(ArisApps.NewLine.typed(plain, field: field("textArea", "")), "\nAdded line", "his own Return is his text")
        XCTAssertEqual(ArisApps.NewLine.typed(plain, field: nil), "\nAdded line")
        // The mark only ever takes the one leading break away: a text without one is typed as given.
        XCTAssertEqual(ArisApps.NewLine.typed(marked { $0["text"] = .string("Added line") }, field: field("textArea", "Existing")), "Added line")
        XCTAssertEqual(ArisApps.NewLine.typed(marked { $0["line"] = .string("old") }, field: field("textArea", "")), "\nAdded line", "only the one mark")
    }

    /// Security review: the mark is never a second value beside the rated one. Whatever the call says and whatever the
    /// field holds, what is typed is the rated text or that text without its one leading line break: never more.
    func testWhatIsTypedIsNeverMoreThanWhatWasRated() {
        let texts = ["\nAdded line", "Added line", "\n", "\n\nTwo", "\r\nCR", "send\n", ""]
        let fields: [ArisApps.ReadElement?] = [nil, field("textArea", nil), field("textArea", "x"), field("textArea", "x\n"), field("textField", "x"),
                                               field("button", "x")]
        let lines: [ArisApps.JSON?] = [nil, .string("new"), .string("old"), .bool(true)]
        let places: [ArisApps.JSON?] = [nil, .string("end"), .string("caret")]
        for text in texts {
            for line in lines {
                for place in places {
                    for replace in [nil, ArisApps.JSON.bool(true)] {
                        var object: [String: ArisApps.JSON] = ["app": .string("TextEdit"), "text": .string(text)]
                        object["line"] = line
                        object["at"] = place
                        object["replace"] = replace
                        for field in fields {
                            let typed = ArisApps.NewLine.typed(.object(object), field: field)
                            XCTAssertTrue(typed == text || "\n" + typed == text, "\(text.debugDescription) → \(typed.debugDescription)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Undo takes the break back with the text

    func testTheUndoRemovesTheBreakWithTheText() throws {
        let before = "Existing line keep", after = "Existing line keep\nAdded line"
        let recipe = try XCTUnwrap(ArisApps.TextUndo.recipe(app: "TextEdit", bundle: bundle, role: "textArea", label: "First Text View", before: before, after: after))
        guard case .textInserted(_, let element, _) = recipe, let mark = ArisApps.TextUndo.mark(element) else { return XCTFail("no text undo") }
        XCTAssertEqual(mark.inserted, "\nAdded line")
        let range = try XCTUnwrap(ArisApps.TextUndo.range(in: after, mark: mark))
        XCTAssertEqual((after as NSString).replacingCharacters(in: range, with: ""), before)
    }

    // MARK: - Cards say it before it happens

    func testTheLessonCardSaysOnANewLineInBothLanguages() {
        let made = addLine(startsLine: true)
        let english = ArisTeachCopy.step(made.steps[1], in: made, english: true)
        let korean = ArisTeachCopy.step(made.steps[1], in: made, english: false)
        XCTAssertEqual(english, "In TextEdit, put ↵[text] in the document's text, on a new line (looks typed by you: ‘Added line’)")
        XCTAssertEqual(korean, "TextEdit의 ‘본문’에 새 줄로 ↵[본문] 넣기 (직접 입력한 것 같아요: ‘Added line’)")
        XCTAssertTrue(ArisTeachCopy.saveCard(made, replacing: false, english: true).detail.contains("on a new line"))
        XCTAssertTrue(ArisTeachCopy.saveCard(made, replacing: false, english: false).detail.contains("새 줄로"))
        // Unmarked: as before.
        let old = addLine(startsLine: nil)
        XCTAssertEqual(ArisTeachCopy.step(old.steps[1], in: old, english: true), "In TextEdit, put [text] in the document's text (looks typed by you: ‘Added line’)")
        XCTAssertEqual(ArisTeachCopy.step(old.steps[1], in: old, english: false), "TextEdit의 ‘본문’에 [본문] 넣기 (직접 입력한 것 같아요: ‘Added line’)")
    }

    func testALiteralTextStepSaysItToo() {
        var step = ArisTeachStep(action: .type, app: "TextEdit", bundle: bundle, target: "First Text View 칸", role: "textArea", label: "본문", text: "Done")
        step.place = .end
        step.startsLine = true
        step.fromApp = false
        let made = ArisTeachProcedure(name: "끝", steps: [step], parameters: [], created: start)
        XCTAssertEqual(ArisTeachCopy.step(step, in: made, english: true), "In TextEdit, put ‘↵Done’ in the document's text, on a new line")
        XCTAssertEqual(ArisTeachCopy.step(step, in: made, english: false), "TextEdit의 ‘본문’에 새 줄로 ‘↵Done’ 넣기")
        XCTAssertEqual(step.arguments(values: [:])?["text"], .string("\nDone"))
    }

    func testTheValuesCardSaysItGoesOnANewLine() {
        let made = addLine(startsLine: true)
        let missing = ArisTeachReplay.missing(made, given: [:])
        let english = ArisTeachCopy.valuesCard(made, missing: missing, english: true)
        let korean = ArisTeachCopy.valuesCard(made, missing: missing, english: false)
        XCTAssertTrue(english.card.detail.contains("on a new line (↵)"), english.card.detail)
        XCTAssertTrue(korean.card.detail.contains("새 줄(↵)"), korean.card.detail)
        // The field comes up empty (eleventh VM run, T2); last time's value is a suggestion without the break, which is the step's.
        XCTAssertEqual(english.fields.first?.value, "")
        XCTAssertTrue(english.card.detail.contains("Suggestion, last time's text: ‘Added line’"), english.card.detail)
        let old = addLine(startsLine: nil)
        XCTAssertFalse(ArisTeachCopy.valuesCard(old, missing: missing, english: true).card.detail.contains("new line"))
    }

    // MARK: - Old lessons

    func testALessonSavedBeforeTheMarkDecodesAndReplaysAsBefore() throws {
        let saved = """
        [{"changed":"2026-11-19T15:16:43Z","created":"2026-11-19T15:16:43Z","id":"B0DEB9F6-E26F-4F84-8AFE-161E2E932EFD","name":"줄 추가",
          "parameters":[{"app":"TextEdit","example":"Added line","fromApp":false,"key":"p1","label":"본문"}],"skipped":0,
          "steps":[{"action":"open","app":"TextEdit","bundle":"com.apple.TextEdit"},
                   {"action":"type","app":"TextEdit","bundle":"com.apple.TextEdit","fromApp":false,"label":"본문","parameter":"p1","place":"end",
                    "role":"textArea","seen":{"kind":"app","source":"TextEdit"},"target":"First Text View 칸"}]}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lessons = try decoder.decode([ArisTeachProcedure].self, from: Data(saved.utf8))
        let step = try XCTUnwrap(lessons.first?.steps.last)
        XCTAssertNil(step.startsLine)
        XCTAssertEqual(step.arguments(values: lessons[0].examples),
                       ["app": .string("TextEdit"), "target": .string("First Text View 칸"), "text": .string("Added line"), "at": .string("end")])
        // Saved again, it holds no mark it didn't have.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertFalse(String(decoding: try encoder.encode(lessons), as: UTF8.self).contains("startsLine"))
    }

    func testAMarkedLessonRoundTrips() throws {
        let made = addLine(startsLine: true)
        let back = try JSONDecoder().decode(ArisTeachProcedure.self, from: JSONEncoder().encode(made))
        XCTAssertEqual(back.steps[1].startsLine, true)
        XCTAssertEqual(back, made)
    }
}
