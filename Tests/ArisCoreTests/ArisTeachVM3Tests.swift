import XCTest
@testable import ArisCore

/// "Show it once" against the third VM run (aris-vmcheck notes3/I5-taught.txt, I5b-taught.json, cap3/I5-teach-done-8s.jpg,
/// I5b-teach-done-8s.jpg). Lesson 1: the desktop clicked, ⌘Space, "TextEdit" typed into Spotlight, Return (TextEdit
/// launched), ⌘N, "lesson line one" typed (TextEdit made it "Lesson line one"), then "다 했어". Saved were Finder 열기 /
/// Finder에서 ⌘Space / Spotlight 열기 / Spotlight에서 Return / TextEdit 열기 / TextEdit에서 ⌘N with no value, and the
/// replay failed at Spotlight. Lesson 2: TextEdit in front, File › New chosen with the mouse, "Milk and bread" and
/// Return typed: saved were TextEdit 열기 / 본문 넣기 / Return / 본문 2 넣기. Both should be: open TextEdit, File › New,
/// [본문] with the whole typed text as one value, put after what the document holds.
final class ArisTeachVM3Tests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let finder = ArisTeachApp(bundle: "com.apple.finder", name: "Finder")
    private let spotlight = ArisTeachApp(bundle: "com.apple.Spotlight", name: "Spotlight")
    private let textEdit = ArisTeachApp(bundle: "com.apple.TextEdit", name: "TextEdit")
    private let aris = ArisTeachApp(bundle: "com.lumenjsn.aris", name: "Aris")
    private var textView: ArisTeachElement { ArisTeachElement(role: "textArea", label: "", identifier: "First Text View") }
    private var searchField: ArisTeachElement { ArisTeachElement(role: "searchField", label: "Spotlight Search") }

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func keys(_ count: Int, from time: Double, app: ArisTeachApp, element: ArisTeachElement?) -> [ArisTeachEvent] {
        (0..<count).map { ArisTeachEvent(.input, at: at(time + Double($0) * 0.1), app: app, element: element, input: .key) }
    }

    /// Lesson 1 as the observer reports it now. TextEdit was launched by Spotlight and its value changes were never
    /// reported (its observer wasn't registered yet): only his keys in its text view, and the view's value read when the
    /// lesson ends. `resolved`: ⌘N came as File › New (the menu bar's key equivalent), else as the key.
    private func lessonOne(resolved: Bool) -> (events: [ArisTeachEvent], closing: [ArisTeachEvent]) {
        var events: [ArisTeachEvent] = [
            ArisTeachEvent(.appActivated, at: at(0.1), app: finder),
            ArisTeachEvent(.input, at: at(1), app: finder, element: ArisTeachElement(role: "group", label: "desktop"), input: .click),
            ArisTeachEvent(.shortcut, at: at(2), app: finder, keys: "cmd+space"),
            ArisTeachEvent(.appActivated, at: at(2.2), app: spotlight),
            ArisTeachEvent(.focused, at: at(2.3), app: spotlight, element: searchField),
        ]
        events += keys(8, from: 3, app: spotlight, element: searchField)
        events += [ArisTeachEvent(.valueChanged, at: at(3.8), app: spotlight, element: searchField, value: "TextEdit"),
                   ArisTeachEvent(.shortcut, at: at(4.5), app: spotlight, element: searchField, keys: "return"),
                   ArisTeachEvent(.appActivated, at: at(6), app: textEdit)]
        if resolved {
            var chosen = ArisTeachEvent(.menuChosen, at: at(8), app: textEdit, element: textView, menu: ["File", "New"])
            chosen.keys = "cmd+n"
            events.append(chosen)
        } else {
            events.append(ArisTeachEvent(.shortcut, at: at(8), app: textEdit, element: textView, keys: "cmd+n"))
        }
        events += keys(15, from: 9, app: textEdit, element: textView)
        // To Aris: the composer clicked and "다 했어" typed.
        events += [ArisTeachEvent(.input, at: at(14), app: aris, input: .click)] + keys(4, from: 14.5, app: aris, element: nil)
        let closing = [ArisTeachEvent(.valueChanged, at: at(10.4), app: textEdit, element: textView, value: "Lesson line one", before: "")]
        return (events, closing)
    }

    private func lesson(_ events: [ArisTeachEvent], closing: [ArisTeachEvent] = []) -> ArisTeachRecorder.Lesson? {
        var recorder = ArisTeachRecorder()
        recorder.start(name: "메모 쓰기", at: start)
        for event in events { recorder.feed(event) }
        recorder.close(closing)
        return recorder.stop(at: at(20))
    }

    private func procedure(_ events: [ArisTeachEvent], closing: [ArisTeachEvent] = []) throws -> ArisTeachProcedure {
        let made = try XCTUnwrap(lesson(events, closing: closing))
        return try ArisTeachGeneralise.procedure(made).get()
    }

    // MARK: - Lesson 1

    func testLessonOneIsOpenTextEditNewAndTheTypedLine() throws {
        let (events, closing) = lessonOne(resolved: true)
        let made = try procedure(events, closing: closing)
        XCTAssertEqual(made.steps.map(\.action), [.open, .menu, .type])
        XCTAssertEqual(made.steps.map(\.app), ["TextEdit", "TextEdit", "TextEdit"])
        XCTAssertEqual(made.steps[1].menu, ["File", "New"])
        let body = try XCTUnwrap(made.steps[2].parameter.flatMap(made.parameter))
        XCTAssertEqual(body.label, "본문")
        XCTAssertEqual(body.example, "Lesson line one")
        XCTAssertEqual(made.steps[2].place, .end)
        XCTAssertEqual(made.steps[2].arguments(values: made.examples)?["at"], .string("end"))
        XCTAssertNil(made.steps[2].arguments(values: made.examples)?["replace"])
    }

    func testLessonOneWithTheKeyUnresolvedKeepsTheKeyButNoLauncher() throws {
        let (events, closing) = lessonOne(resolved: false)
        let made = try procedure(events, closing: closing)
        XCTAssertEqual(made.steps.map(\.action), [.open, .press, .type])
        XCTAssertEqual(made.steps[1].keys, "cmd+n")
        XCTAssertFalse(made.steps.contains { $0.app == "Spotlight" || $0.app == "Finder" })
    }

    /// The recording the VM saved (no read at the end): still no Finder, no ⌘Space, no Spotlight, no Return in it.
    func testTheSavedRecordingHasNoLauncherSteps() throws {
        let (events, _) = lessonOne(resolved: false)
        let made = try procedure(events)
        XCTAssertEqual(made.steps.map(\.action), [.open, .press])
        XCTAssertFalse(made.steps.contains { ArisTeachLaunchers.isSystemUI(ArisTeachApp(bundle: $0.bundle, name: $0.app)) })
        XCTAssertFalse(made.steps.contains { $0.keys == "cmd+space" || $0.keys == "return" })
    }

    func testAValueReadAtTheEndIsKeptOnlyForAFieldHisKeysWentInto() throws {
        let other = ArisTeachElement(role: "textField", label: "Subject")
        let (events, _) = lessonOne(resolved: true)
        let made = try procedure(events, closing: [ArisTeachEvent(.valueChanged, at: at(10), app: textEdit, element: other, value: "not typed", before: "")])
        XCTAssertFalse(made.steps.contains { $0.action == .type })
    }

    func testAValueReadAtTheEndDoesNotDoubleAReportedOne() throws {
        var (events, closing) = lessonOne(resolved: true)
        events.insert(ArisTeachEvent(.valueChanged, at: at(10.45), app: textEdit, element: textView, value: "Lesson line one", before: ""), at: events.count - 5)
        let made = try procedure(events, closing: closing)
        XCTAssertEqual(made.steps.filter { $0.action == .type }.count, 1)
    }

    // MARK: - Lesson 2

    /// TextEdit in front, Aris's composer still holding the keyboard from the start sentence; File › New with the mouse
    /// (his click on the menu bar, the release on New), "Milk and bread", Return, then "다 했어".
    private func lessonTwo() -> [ArisTeachEvent] {
        var events: [ArisTeachEvent] = [
            ArisTeachEvent(.input, at: at(0.05), app: aris, input: .key),
            ArisTeachEvent(.input, at: at(1), app: textEdit, input: .click),
            ArisTeachEvent(.menuChosen, at: at(1.6), app: textEdit, menu: ["File", "New"]),
            ArisTeachEvent(.windowOpened, at: at(1.8), app: textEdit, window: "Untitled 5"),
            ArisTeachEvent(.focused, at: at(1.9), app: textEdit, element: textView),
        ]
        let line = "Milk and bread"
        for (index, end) in [1, 5, 9, 14].enumerated() {
            let time = 3 + Double(index) * 0.4
            events.append(ArisTeachEvent(.input, at: at(time), app: textEdit, element: textView, input: .key))
            events.append(ArisTeachEvent(.valueChanged, at: at(time + 0.01), app: textEdit, element: textView, value: String(line.prefix(end)),
                                         before: index == 0 ? "" : String(line.prefix([1, 5, 9, 14][index - 1]))))
        }
        events.append(ArisTeachEvent(.shortcut, at: at(5), app: textEdit, element: textView, keys: "return"))
        events.append(ArisTeachEvent(.input, at: at(5.001), app: textEdit, input: .hand))
        events.append(ArisTeachEvent(.valueChanged, at: at(5.01), app: textEdit, element: textView, value: line + "\n", before: line))
        events += [ArisTeachEvent(.input, at: at(7), app: aris, input: .click)] + keys(4, from: 7.5, app: aris, element: nil)
        return events
    }

    func testLessonTwoKeepsTheMenuAndOneValueWithItsNewline() throws {
        let made = try procedure(lessonTwo())
        XCTAssertEqual(made.steps.map(\.action), [.open, .menu, .type])
        XCTAssertEqual(made.steps[1].menuPath, "File › New")
        XCTAssertEqual(made.parameters.count, 1)
        XCTAssertEqual(made.parameters.first?.example, "Milk and bread\n")
        XCTAssertEqual(made.parameters.first?.label, "본문")
        XCTAssertNotEqual(made.parameters.first?.fromApp, true)
        XCTAssertEqual(made.steps[2].place, .end)
    }

    func testReturnInAOneLineFieldOrADialogIsStillAStep() throws {
        let field = ArisTeachElement(role: "textField", label: "To")
        let mail = ArisTeachApp(bundle: "com.apple.mail", name: "Mail")
        let events = [
            ArisTeachEvent(.appActivated, at: at(0.1), app: mail),
            ArisTeachEvent(.focused, at: at(0.5), app: mail, element: field),
            ArisTeachEvent(.input, at: at(1), app: mail, element: field, input: .key),
            ArisTeachEvent(.valueChanged, at: at(1.01), app: mail, element: field, value: "mom", before: ""),
            ArisTeachEvent(.shortcut, at: at(2), app: mail, element: field, keys: "return"),
        ]
        let made = try procedure(events)
        XCTAssertEqual(made.steps.map(\.action), [.open, .type, .press])
    }

    // MARK: - Getting to an app

    func testADockClickOrTheSwitcherIsNoStep() throws {
        let dock = ArisTeachApp(bundle: "com.apple.dock", name: "Dock")
        let events = [
            ArisTeachEvent(.appActivated, at: at(0.1), app: finder),
            ArisTeachEvent(.pressed, at: at(1), app: dock, element: ArisTeachElement(role: "dockItem", label: "TextEdit")),
            ArisTeachEvent(.shortcut, at: at(1.5), app: finder, keys: "cmd+tab"),
            ArisTeachEvent(.appActivated, at: at(2), app: textEdit),
            ArisTeachEvent(.shortcut, at: at(3), app: textEdit, element: textView, keys: "cmd+n"),
        ]
        let made = try procedure(events)
        XCTAssertEqual(made.steps.map(\.action), [.open, .press])
        XCTAssertEqual(made.apps, ["TextEdit"])
    }

    func testAFinderDoubleClickOnTheAppIsJustOpeningIt() throws {
        let row = ArisTeachElement(role: "row", label: "TextEdit.app")
        let events = [
            ArisTeachEvent(.appActivated, at: at(0.1), app: finder),
            ArisTeachEvent(.input, at: at(0.9), app: finder, input: .click),
            ArisTeachEvent(.pressed, at: at(1), app: finder, element: row),
            ArisTeachEvent(.selected, at: at(1.01), app: finder, element: row),
            ArisTeachEvent(.appActivated, at: at(3), app: textEdit),
            ArisTeachEvent(.shortcut, at: at(4), app: textEdit, element: textView, keys: "cmd+n"),
        ]
        let made = try procedure(events)
        XCTAssertEqual(made.apps, ["TextEdit"])
    }

    // MARK: - Where the text went

    func testWhereTheTextWent() {
        XCTAssertEqual(ArisTeachGeneralise.textChange(before: "", after: "Milk"), .init(text: "Milk", place: .end))
        XCTAssertEqual(ArisTeachGeneralise.textChange(before: nil, after: "Milk"), .init(text: "Milk", place: .end))
        XCTAssertEqual(ArisTeachGeneralise.textChange(before: "Existing line keep\n", after: "Existing line keep\nMilk"), .init(text: "Milk", place: .end))
        // Inside what was there: at the caret; text gone with no selection seen is no replace (fourth VM run, D1).
        XCTAssertEqual(ArisTeachGeneralise.textChange(before: "ab", after: "aXYb"), .init(text: "XY", place: .caret))
        XCTAssertEqual(ArisTeachGeneralise.textChange(before: "old text", after: "new"), .init(text: "new", place: .end))
        XCTAssertEqual(ArisTeachGeneralise.textChange(before: "old text", after: "new", overSelection: true), .init(text: "new", place: .all))
        XCTAssertEqual(ArisTeachGeneralise.textChange(before: "old text", after: "old textual", selectedAll: true), .init(text: "old textual", place: .all))
    }

    func testASelectAllThenTypingReplacesAndSaysSo() throws {
        let events = [
            ArisTeachEvent(.appActivated, at: at(0.1), app: textEdit),
            ArisTeachEvent(.focused, at: at(0.5), app: textEdit, element: textView),
            ArisTeachEvent(.shortcut, at: at(1), app: textEdit, element: textView, keys: "cmd+a"),
            ArisTeachEvent(.input, at: at(2), app: textEdit, element: textView, input: .key),
            ArisTeachEvent(.valueChanged, at: at(2.01), app: textEdit, element: textView, value: "N", before: "Existing line keep"),
        ]
        let made = try procedure(events)
        XCTAssertEqual(made.steps.map(\.action), [.open, .type])
        XCTAssertEqual(made.steps[1].place, .all)
        XCTAssertEqual(made.steps[1].arguments(values: made.examples)?["replace"], .bool(true))
        XCTAssertTrue(ArisTeachCopy.step(made.steps[1], in: made, english: false).contains("원래 내용은 지워져요"))
    }

    func testAnOldSavedTypeStepInsertsNow() {
        // Lessons saved before this change have no place: they insert, never set the whole value.
        let step = ArisTeachStep(action: .type, app: "TextEdit", bundle: "com.apple.TextEdit", target: "First Text View 칸", text: "Milk")
        let arguments = step.arguments(values: [:])
        XCTAssertEqual(arguments?["at"], .string("end"))
        XCTAssertNil(arguments?["replace"])
    }

    // MARK: - D2: a replay never sets a whole value unless the lesson replaced it, and then it asks

    func testReplacingAFieldIsDestructiveAndNeverApprovedAhead() throws {
        let spec = try XCTUnwrap(ArisApps.Spec.named("app.type"))
        let context = ArisApps.EffectContext()
        XCTAssertEqual(spec.effect(.object(["app": .string("TextEdit"), "text": .string("Milk"), "at": .string("end")]), context), .changeReversible)
        XCTAssertEqual(spec.effect(.object(["app": .string("TextEdit"), "text": .string("Milk"), "replace": .bool(true)]), context), .changePermanent)
        var step = ArisTeachStep(action: .type, app: "TextEdit", bundle: "com.apple.TextEdit", target: "First Text View 칸", role: "textArea", label: "본문", text: "Milk")
        step.place = .all
        let procedure = ArisTeachProcedure(name: "메모", steps: [step], parameters: [], created: start)
        let plan = ArisTeachReplay.plan(procedure, given: [:], run: "r")
        XCTAssertTrue(plan.approved.isEmpty)
        XCTAssertEqual(plan.calls.first??.object?["replace"] as? Bool, true)
    }

    // MARK: - Shortcuts as menu commands

    func testAShortcutIsTheMenuCommandWithThatKeyEquivalent() {
        let items = [ArisTeachMenuKeys.Item(path: ["File", "New"], character: "N", modifiers: 0),
                     ArisTeachMenuKeys.Item(path: ["File", "Save As…"], character: "S", modifiers: 1),
                     ArisTeachMenuKeys.Item(path: ["File", "Save"], character: "S", modifiers: 0),
                     ArisTeachMenuKeys.Item(path: ["Edit", "Paste"], character: "V", modifiers: 0, enabled: false)]
        XCTAssertEqual(ArisTeachMenuKeys.command(for: "cmd+n", in: items), ["File", "New"])
        XCTAssertEqual(ArisTeachMenuKeys.command(for: "cmd+shift+s", in: items), ["File", "Save As…"])
        XCTAssertEqual(ArisTeachMenuKeys.command(for: "cmd+s", in: items), ["File", "Save"])
        // Greyed out when the menus were read (nothing to paste then) and the only item with ⌘V: still that command
        // (sixth VM run, item 7b: the read is once, at the lesson's start, and its enabled state is no guide to later).
        XCTAssertEqual(ArisTeachMenuKeys.command(for: "cmd+v", in: items), ["Edit", "Paste"])
        XCTAssertNil(ArisTeachMenuKeys.command(for: "cmd+k", in: items))
    }

    // MARK: - D4: the lesson's own words in the UI's language

    private static func hasHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }

    /// The ASCII words of a Korean render, without the user's own (the name, values) and the app's names.
    private static func asciiWords(_ text: String, allowed: [String]) -> [String] {
        var rest = text
        for word in allowed { rest = rest.replacingOccurrences(of: word, with: " ") }
        return rest.components(separatedBy: CharacterSet.letters.inverted).filter { $0.count > 1 && $0.unicodeScalars.allSatisfy { $0.isASCII } }
    }

    func testTheCardAndTheAccountFollowTheUILanguage() throws {
        let made = try procedure(lessonTwo())
        let englishCard = ArisTeachCopy.saveCard(made, replacing: false, english: true)
        // The user's own words (the lesson's name, the field's name they says) may be Korean; nothing else is.
        let ownWords = [made.name, "본문"]
        var english = englishCard.title + "\n" + englishCard.detail
        for word in ownWords { english = english.replacingOccurrences(of: word, with: "") }
        XCTAssertFalse(Self.hasHangul(english), english)
        let koreanCard = ArisTeachCopy.saveCard(made, replacing: false, english: false)
        let allowed = ["TextEdit", "File › New", "File", "New", "Milk and bread"]
        XCTAssertEqual(Self.asciiWords(koreanCard.title + "\n" + koreanCard.detail, allowed: allowed), [])
        // A run that stopped on the app layer's English reason says it in the UI's language.
        let failed = ArisTeachReplay.Outcome.stopped(at: 1, end: .failed("no app on this Mac is called ‘Spotlight’"), done: 1)
        let korean = ArisTeachCopy.account(made, outcome: failed, english: false)
        XCTAssertTrue(korean.contains("이 Mac에 ‘Spotlight’라는 앱이 없어요"), korean)
        XCTAssertEqual(Self.asciiWords(korean, allowed: allowed + ["Spotlight", "Mac"]), [], korean)
        let unknown = ArisTeachCopy.account(made, outcome: .stopped(at: 1, end: .failed("AXError -25204 while pressing"), done: 1), english: false)
        XCTAssertEqual(Self.asciiWords(unknown, allowed: allowed), [], unknown)
        var englishAccount = ArisTeachCopy.account(made, outcome: .stopped(at: 1, end: .refused("그건 되돌릴 수 없어요."), done: 1), english: true)
        englishAccount = englishAccount.replacingOccurrences(of: made.name, with: "").replacingOccurrences(of: "본문", with: "")
        XCTAssertFalse(Self.hasHangul(englishAccount), englishAccount)
    }
}
