import XCTest
@testable import ArisCore

/// The seventh VM run's pure parts (aris-vmcheck notes7/*, cap7/*). The helper's and the app's parts are in
/// tests/vmfix10-tests.swift; the drawn cards in tests/card-text-render.
final class ArisTeachVM7Tests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let textEdit = ArisTeachApp(bundle: "com.apple.TextEdit", name: "TextEdit")
    private var textView: ArisTeachElement { ArisTeachElement(role: "textArea", label: "", identifier: "First Text View") }

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    /// notes7/E-taught.json, "줄 추가": TextEdit opened, a line typed at the end of an empty document.
    private func addLine() -> ArisTeachProcedure {
        var typed = ArisTeachStep(action: .type, app: "TextEdit", bundle: "com.apple.TextEdit", target: "First Text View 칸", role: "textArea",
                                  label: ArisTeachGeneralise.bodyLabel)
        typed.parameter = "p1"
        typed.place = .end
        typed.startsLine = true
        typed.fromApp = false
        return ArisTeachProcedure(name: "줄 추가", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit"), typed],
                                  parameters: [ArisTeachParameter(key: "p1", label: ArisTeachGeneralise.bodyLabel, example: "Added line", app: "TextEdit", fromApp: false)],
                                  created: start)
    }

    /// notes7/E-taught.json, "전체 바꾸기": TextEdit opened, Edit › Select All, the whole text replaced.
    private func replaceAll() -> ArisTeachProcedure {
        let seen = ArisContentSource(kind: "app", source: "TextEdit")
        var select = ArisTeachStep(action: .menu, app: "TextEdit", bundle: "com.apple.TextEdit", label: "Select All", menu: ["Edit", "Select All"])
        select.keys = "cmd+a"
        select.seen = seen
        var typed = ArisTeachStep(action: .type, app: "TextEdit", bundle: "com.apple.TextEdit", target: "First Text View 칸", role: "textArea",
                                  label: ArisTeachGeneralise.bodyLabel)
        typed.parameter = "p1"
        typed.place = .all
        typed.fromApp = false
        typed.seen = seen
        return ArisTeachProcedure(name: "전체 바꾸기", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit"), select, typed],
                                  parameters: [ArisTeachParameter(key: "p1", label: ArisTeachGeneralise.bodyLabel, example: "Replaced all", app: "TextEdit", fromApp: false)],
                                  created: start)
    }

    // MARK: - Item 1: the values card's new-line note is drawn

    /// cap7/J1-card1.jpg: the card drew only its title and its field. The editable card draws the lines above its fields'
    /// own "label: value" lines (ArisCardEdit.note); the values card's text ended with none, so its note was dropped.
    func testTheValuesCardsTextEndsWithItsFieldsSoItsNoteIsDrawn() {
        let made = addLine()
        let missing = ArisTeachReplay.missing(made, given: [:])
        for english in [true, false] {
            let asked = ArisTeachCopy.valuesCard(made, missing: missing, english: english)
            let fields = asked.fields.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            XCTAssertTrue(asked.card.detail.hasSuffix("\n" + fields), asked.card.detail)
            let note = String(asked.card.detail.dropLast(fields.count + 1))
            XCTAssertTrue(note.contains("↵") && note.contains(english ? "on a new line" : "새 줄"), note)
        }
    }

    // MARK: - Item 6: where a replay's own step came from, said truthfully

    /// cap7/F1-card3.jpg: "Suggested by what was read (app window TextEdit)" on the replace step he taught. Why: the
    /// replace is never approved ahead (ArisTeachReplay.plan), and its app's name had first been seen in an earlier
    /// step's result (TextEdit's own words, as content), so the tracker rates the call content. That rating stays.
    func testTheTrackerStillRatesTheTaughtReplaceAsContent() {
        let plan = ArisTeachReplay.plan(replaceAll(), given: [:], words: "전체 바꾸기 해 줘", run: "r7")
        var tracker = ArisProvenanceTracker()
        tracker.ownerTurn("전체 바꾸기 해 줘")
        tracker.taskInstruction(plan.instruction)
        for seen in plan.seen { tracker.toolResult(seen.text, source: seen.source) }
        tracker.approve(plan.approved)
        XCTAssertFalse(plan.approved.contains { $0.index == 3 }, "the replace is never approved ahead")
        // Step 1's result, as the app layer marks it: TextEdit's content.
        tracker.toolResult("{\"did\":\"opened TextEdit (in the background)\"}", source: ArisContentSource(kind: "app", source: "TextEdit"))
        let call = plan.calls[2]!
        let verdict = tracker.toolCall(id: call.id, capability: "app.type", effect: .changePermanent,
                                       arguments: ArisKeyArguments.extract(call.object ?? [:], capability: "app.type"))
        XCTAssertEqual(verdict.provenance.source, ArisContentSource(kind: "app", source: "TextEdit"), "\(verdict.reasons)")
    }

    func testTheReplaySaysItsSavedStepInPlaceOfSuggestedByWhatWasRead() throws {
        let made = replaceAll()
        let plan = ArisTeachReplay.plan(made, given: [:], words: "전체 바꾸기 해 줘", run: "r7")
        let call = try XCTUnwrap(plan.calls[2])
        let arguments = ArisKeyArguments.extract(call.object ?? [:], capability: "app.type")
        let source = ArisContentSource(kind: "app", source: "TextEdit")
        func item(_ arguments: [ArisKeyArgument], erases: ArisErasedText?) -> ArisAskItem {
            var facts = ArisCallFacts(capability: "app.type", arguments: arguments)
            facts.erases = erases
            return ArisAskItem(call: call.id, facts: facts, effect: .changePermanent, decision: .ask, provenance: .content(source))
        }
        for english in [true, false] {
            let described = ArisTeachReplay.described(made, plan: plan, english: english)
            let erased = ArisErasedText(text: "Keep text", keepable: true)
            let card = ArisAskPlan.card([item(arguments, erases: erased)], id: "c", intent: "i", countdown: false, home: "/Users/x", described: described)
            let first = card.detail.components(separatedBy: "\n").first ?? ""
            XCTAssertFalse(card.detail.contains("이 제안한 일이에요"), card.detail)
            if english {
                XCTAssertEqual(first, "From your saved steps “전체 바꾸기”. The text ‘Replaced all’ is last time's, from when you showed it, not something you said now. "
                               + "The text it erases was read from TextEdit just now.")
            } else {
                XCTAssertEqual(first, "저장한 단계 ‘전체 바꾸기’ 그대로예요. 넣는 글(‘Replaced all’)은 보여 주실 때의 지난번 값이에요. 이번에 말씀하신 값은 아니에요. 지워질 글은 방금 TextEdit에서 읽었어요.")
            }
            // The decision and every other line stay: it still asks, shows what it erases, and offers no "always".
            XCTAssertTrue(card.detail.contains("Keep text"), card.detail)
            XCTAssertTrue(card.alwaysScope.isEmpty)
            // A value he gave for this run is his: nothing is said to be read from the app but what it erases.
            let given = ArisTeachReplay.plan(made, given: ["p1": "회의는 3시"], words: "전체 바꾸기 해 줘, 본문은 회의는 3시", run: "r8")
            let his = ArisTeachReplay.described(made, plan: given, english: english)
            let givenCall = try XCTUnwrap(given.calls[2])
            let mine = ArisAskItem(call: givenCall.id, facts: ArisCallFacts(capability: "app.type",
                                                                            arguments: ArisKeyArguments.extract(givenCall.object ?? [:], capability: "app.type")),
                                   effect: .changePermanent, decision: .ask, provenance: .content(source))
            let line = ArisAskPlan.card([mine], id: "c", intent: "i", countdown: false, home: "/Users/x", described: his).detail.components(separatedBy: "\n").first ?? ""
            XCTAssertEqual(line, english ? "From your saved steps “전체 바꾸기”." : "저장한 단계 ‘전체 바꾸기’ 그대로예요.")
        }
        // A call whose key arguments aren't exactly the step's (anything added or changed) keeps the gate's own line.
        let described = ArisTeachReplay.described(made, plan: plan, english: false)
        let changed = ArisAskPlan.card([item(arguments + [ArisKeyArgument(kind: .recipient, value: "someone@example.com")], erases: nil)],
                                       id: "c", intent: "i", countdown: false, home: "/Users/x", described: described)
        XCTAssertTrue(changed.detail.hasPrefix("읽은 내용(앱 화면 TextEdit)이 제안한 일이에요."), changed.detail)
        // The erased text couldn't be read: the line says nothing about reading it.
        let unread = ArisAskPlan.card([item(arguments, erases: ArisErasedText(text: nil, keepable: false))], id: "c", intent: "i", countdown: false,
                                      home: "/Users/x", described: described)
        XCTAssertFalse(unread.detail.components(separatedBy: "\n").first?.contains("방금") ?? true, unread.detail)
    }

    /// Security review of item 6: on a card with several calls, a replay step's saved-steps line never stands in for
    /// another call's "suggested by what was read"; and only exactly the step's arguments (same order, as many) match.
    func testTheSavedStepsLineNeverHidesAnotherCallsWarning() throws {
        let made = replaceAll()
        let plan = ArisTeachReplay.plan(made, given: [:], words: "전체 바꾸기 해 줘", run: "r9")
        let call = try XCTUnwrap(plan.calls[2])
        let arguments = ArisKeyArguments.extract(call.object ?? [:], capability: "app.type")
        let described = ArisTeachReplay.described(made, plan: plan, english: false)
        let source = ArisContentSource(kind: "app", source: "TextEdit")
        let page = ArisContentSource(kind: "web", source: "example.com")
        let step = ArisAskItem(call: call.id, facts: ArisCallFacts(capability: "app.type", arguments: arguments), effect: .changePermanent,
                               decision: .ask, provenance: .content(source))
        let other = ArisAskItem(call: "model-1", facts: ArisCallFacts(capability: "app.type", arguments: [ArisKeyArgument(kind: .app, value: "Notes")]),
                                effect: .changePermanent, decision: .ask, provenance: .content(page))
        for items in [[step, other], [other, step]] {
            let card = ArisAskPlan.card(items, id: "c", intent: "i", countdown: false, home: "/Users/x", described: described)
            XCTAssertTrue(card.detail.hasPrefix("읽은 내용(웹 페이지 example.com)이 제안한 일이에요."), card.detail)
            XCTAssertFalse(card.detail.contains("저장한 단계"), card.detail)
        }
        // Alone, the step says where it came from.
        XCTAssertTrue(ArisAskPlan.card([step], id: "c", intent: "i", countdown: false, home: "/Users/x", described: described).detail.hasPrefix("저장한 단계"))
        // Its arguments reordered, or one of them twice: no match, the warning stays.
        for changed in [Array(arguments.reversed()), arguments + [arguments[0]]] where changed != arguments {
            let item = ArisAskItem(call: call.id, facts: ArisCallFacts(capability: "app.type", arguments: changed), effect: .changePermanent,
                                   decision: .ask, provenance: .content(source))
            let card = ArisAskPlan.card([item], id: "c", intent: "i", countdown: false, home: "/Users/x", described: described)
            XCTAssertTrue(card.detail.hasPrefix("읽은 내용(앱 화면 TextEdit)이 제안한 일이에요."), card.detail)
        }
        XCTAssertGreaterThan(arguments.count, 1, "the reordering above changes something")
    }

    // MARK: - Item 7: the app's own change is no typing

    private func recorder(keysHeard: Bool) -> ArisTeachRecorder {
        var recorder = ArisTeachRecorder()
        recorder.start(name: "찾기 단어", at: start)
        recorder.keysHeard = keysHeard
        recorder.feed(ArisTeachEvent(.appActivated, at: at(0.5), app: textEdit))
        recorder.feed(ArisTeachEvent(.focused, at: at(0.6), app: textEdit, element: textView))
        return recorder
    }

    private func change(_ time: Double, _ value: String, before: String) -> ArisTeachEvent {
        ArisTeachEvent(.valueChanged, at: at(time), app: textEdit, element: textView, value: value, before: before)
    }

    /// notes7/E-taught.json: "Copyword" typed before the lesson, TextEdit still offering a correction; the lesson's
    /// double-click took the correction ("Copyworb"), and it became a typed step "taken from the app".
    func testAnAutocorrectionAtHisClickIsNoTypedStep() {
        var watched = recorder(keysHeard: true)
        watched.feed(ArisTeachEvent(.input, at: at(2), app: textEdit, element: textView, input: .click))
        XCTAssertEqual(watched.feed(change(2.1, "Copyworb", before: "Copyword")), .unprompted)
        var copy = ArisTeachEvent(.menuChosen, at: at(3), app: textEdit, element: textView, menu: ["Edit", "Copy"])
        copy.keys = "cmd+c"
        watched.feed(copy)
        XCTAssertEqual(watched.feed(change(3.1, "Copyworb", before: "Copyword")), .unprompted, "⌘C edits nothing")
        let lesson = watched.stop(at: at(5))
        XCTAssertFalse(lesson?.events.contains { $0.kind == .valueChanged } ?? true)
    }

    func testHisTypingPastingAndUndoStillCount() {
        // A character key in the field, then its change.
        var typing = recorder(keysHeard: true)
        typing.feed(ArisTeachEvent(.input, at: at(1), app: textEdit, element: textView, input: .key))
        XCTAssertNil(typing.feed(change(1.05, "A", before: "")))
        // ⌘V, told as Edit › Paste; Edit › Paste chosen with the mouse; ⌥E (an accent typed with ⌥); ⌘Z.
        var pasted = recorder(keysHeard: true)
        var paste = ArisTeachEvent(.menuChosen, at: at(1), app: textEdit, element: textView, menu: ["Edit", "Paste"])
        paste.keys = "cmd+v"
        pasted.feed(paste)
        XCTAssertNil(pasted.feed(change(1.1, "pasted", before: "")))
        var mouse = recorder(keysHeard: true)
        mouse.feed(ArisTeachEvent(.menuChosen, at: at(1), app: textEdit, menu: ["Edit", "Paste and Match Style"]))
        XCTAssertNil(mouse.feed(change(1.1, "pasted", before: "")))
        var korean = recorder(keysHeard: true)
        korean.feed(ArisTeachEvent(.menuChosen, at: at(1), app: textEdit, menu: ["편집", "붙여넣기"]))
        XCTAssertNil(korean.feed(change(1.1, "붙임", before: "")))
        var accent = recorder(keysHeard: true)
        accent.feed(ArisTeachEvent(.shortcut, at: at(1), app: textEdit, element: textView, keys: "opt+e"))
        XCTAssertNil(accent.feed(change(1.1, "´", before: "")))
        var undo = recorder(keysHeard: true)
        undo.feed(ArisTeachEvent(.shortcut, at: at(1), app: textEdit, element: textView, keys: "cmd+z"))
        XCTAssertNil(undo.feed(change(1.1, "", before: "x")))
        // A key long before the change is not this change's.
        var late = recorder(keysHeard: true)
        late.feed(ArisTeachEvent(.input, at: at(1), app: textEdit, element: textView, input: .key))
        late.feed(ArisTeachEvent(.input, at: at(5), app: textEdit, element: textView, input: .click))
        XCTAssertEqual(late.feed(change(5.1, "Copyworb", before: "Copyword")), .unprompted)
    }

    /// Without his keys heard (no Input Monitoring: the observer's key tap doesn't run), his presence still makes a
    /// change his, as before: nothing he typed is lost.
    func testWithoutHisKeysHeardPresenceStillCounts() {
        var watched = recorder(keysHeard: false)
        watched.feed(ArisTeachEvent(.input, at: at(2), app: textEdit, element: textView, input: .click))
        XCTAssertNil(watched.feed(change(2.1, "typed", before: "")))
    }
}
