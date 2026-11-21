import XCTest
@testable import ArisCore

/// "Show it once" against what a real app did (second VM run, defect 3): TextEdit, ⌘N, a line typed, then "다 했어"
/// typed into Aris's own composer. The saved lesson had 13 steps: TextEdit's own font controls set on the new document
/// as "chose" steps, the font size and the text area named by their developer's words, and the composer's ⌘A, ⌘V and
/// Return as TextEdit's. The fixture is the event stream behind the real `taught.json` (notes2), as the observer
/// reports it now: keys and clicks go to the app that has the keyboard at that instant.
final class ArisTeachVMTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let textEdit = ArisTeachApp(bundle: "com.apple.TextEdit", name: "TextEdit")
    private let aris = ArisTeachApp(bundle: "com.lumenjsn.aris", name: "Aris")
    private let mail = ArisTeachApp(bundle: "com.apple.mail", name: "Mail")

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private var textView: ArisTeachElement { ArisTeachElement(role: "textArea", label: "First Text View") }
    private var typeface: ArisTeachElement { ArisTeachElement(role: "popUpButton", label: "typeface") }
    private var style: ArisTeachElement { ArisTeachElement(role: "popUpButton", label: "style") }
    private var size: ArisTeachElement { ArisTeachElement(role: "comboBox", label: "font size") }
    private var spacing: ArisTeachElement { ArisTeachElement(role: "popUpButton", label: "line spacing") }

    /// What TextEdit does by itself to a new document's (and a typing caret's) font controls, each change preceded by
    /// the hardware's presence-only input the observer reports with every value change.
    private func fontControls(at time: Double) -> [ArisTeachEvent] {
        [(typeface, "Helvetica"), (style, "Regular"), (size, "12"), (spacing, "1.0")].enumerated().flatMap { index, control in
            let when = time + Double(index) * 0.02
            return [ArisTeachEvent(.input, at: at(when - 0.005), app: textEdit, input: .hand),
                    ArisTeachEvent(.valueChanged, at: at(when), app: textEdit, element: control.0, value: control.1)]
        }
    }

    /// The VM run: TextEdit in front; ⌘N (File › New); a new window; its text view takes the keyboard; TextEdit sets
    /// its font controls; "Shopping list milk eggs" typed key by key (the font controls follow the caret again); then
    /// the notch is clicked, "다 했어" typed into the composer with ⌘A, ⌘V and Return, while TextEdit's controls change
    /// once more.
    private func vmRun() -> [ArisTeachEvent] {
        var events: [ArisTeachEvent] = [
            ArisTeachEvent(.appActivated, at: at(0.5), app: textEdit),
            ArisTeachEvent(.shortcut, at: at(1), app: textEdit, element: ArisTeachElement(role: "textArea", label: "First Text View"), keys: "cmd+n"),
            ArisTeachEvent(.menuChosen, at: at(1.1), app: textEdit, menu: ["File", "New"]),
            ArisTeachEvent(.windowOpened, at: at(1.3), app: textEdit, window: "Untitled 3"),
            ArisTeachEvent(.focused, at: at(1.4), app: textEdit, element: textView),
        ]
        events += fontControls(at: 1.5)
        let line = "Shopping list milk eggs"
        for (index, end) in [1, 8, 13, 18, 23].enumerated() {
            let time = 3 + Double(index) * 0.5
            events.append(ArisTeachEvent(.input, at: at(time), app: textEdit, element: textView, input: .key))
            events.append(ArisTeachEvent(.input, at: at(time + 0.001), app: textEdit, input: .hand))
            events.append(ArisTeachEvent(.valueChanged, at: at(time + 0.01), app: textEdit, element: textView, value: String(line.prefix(end))))
            if index == 0 { events += fontControls(at: time + 0.05) }
        }
        // To Aris: the notch clicked, the stop phrase typed and sent in its composer.
        events.append(ArisTeachEvent(.input, at: at(8), app: aris, input: .click))
        for index in 0..<4 { events.append(ArisTeachEvent(.input, at: at(8.5 + Double(index) * 0.2), app: aris, input: .key)) }
        events += fontControls(at: 9.4)
        events += [ArisTeachEvent(.shortcut, at: at(9.5), app: aris, keys: "cmd+a"),
                   ArisTeachEvent(.shortcut, at: at(9.7), app: aris, keys: "cmd+v"),
                   ArisTeachEvent(.shortcut, at: at(10), app: aris, keys: "return")]
        return events
    }

    private func lesson(_ events: [ArisTeachEvent], name: String = "메모 쓰기") -> ArisTeachRecorder.Lesson {
        var recorder = ArisTeachRecorder()
        recorder.start(name: name, at: start)
        events.forEach { recorder.feed($0) }
        return recorder.stop(at: at(11))!
    }

    // MARK: - The worked example

    func testTheVMLessonIsOpenNewAndTypeTheBody() {
        guard case .success(let made) = ArisTeachGeneralise.procedure(lesson(vmRun())) else { return XCTFail("a procedure") }
        XCTAssertEqual(made.steps.map(\.capability), ["app.open", "app.do", "app.type"], "\(made.steps.map { ArisTeachCopy.step($0, in: made, english: false) })")
        XCTAssertEqual(made.steps[1].menuPath, "File › New")
        XCTAssertEqual(made.parameters.map(\.label), ["본문"], "the document's main text is 본문, not its developer's name")
        XCTAssertEqual(made.parameters.first?.example, "Shopping list milk eggs")
        XCTAssertEqual(made.parameters.first?.fromApp, false, "typed key by key in that field")
        XCTAssertEqual(made.steps[2].parameter, "p1")
        XCTAssertEqual(made.steps[2].target, "First Text View 칸", "found again by what the app calls it")
        let card = ArisTeachCopy.saveCard(made, replacing: false, english: false)
        XCTAssertEqual(card.title, "‘메모 쓰기’ 배울까요? (3단계)")
        XCTAssertEqual(Array(card.detail.components(separatedBy: "\n").prefix(3)), [
            "1. TextEdit 열기",
            "2. TextEdit에서 메뉴 ‘File › New’ 누르기",
            "3. TextEdit의 ‘본문’에 [본문] 넣기 (직접 입력한 것 같아요: ‘Shopping list milk eggs’)",
        ])
        XCTAssertTrue(card.detail.contains("바뀌는 값: 본문"))
        XCTAssertFalse(card.detail.contains("⌘A") || card.detail.contains("Return") || card.detail.contains("typeface"), card.detail)
        // The owner names the value by that word when he asks.
        XCTAssertEqual(ArisTeachMatch.values(made, words: "해 줘, 본문은 우유 사기"), ["p1": "우유 사기"])
        let plan = ArisTeachReplay.plan(made, given: ["p1": "우유 사기"], words: "메모 쓰기 해 줘, 본문은 우유 사기", run: "vm")
        XCTAssertEqual(plan.calls.compactMap { $0?.name }, ["app_open", "app_do", "app_type"])
        XCTAssertEqual(plan.calls[2]?.object?["text"] as? String, "우유 사기")
    }

    // MARK: - (a) Aris's own composer is never the lesson

    func testNothingIsKeptWhileArisHasTheKeyboard() {
        var recorder = ArisTeachRecorder()
        recorder.start(name: "x", at: start)
        recorder.feed(ArisTeachEvent(.focused, at: at(1), app: textEdit, element: textView))
        recorder.feed(ArisTeachEvent(.input, at: at(1.1), app: textEdit, element: textView, input: .key))
        XCTAssertNil(recorder.feed(ArisTeachEvent(.valueChanged, at: at(1.2), app: textEdit, element: textView, value: "a")))
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.input, at: at(2), app: aris, input: .key)), .ownApp, "a key in Aris's composer")
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.shortcut, at: at(2.1), app: aris, keys: "cmd+a")), .ownApp)
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.shortcut, at: at(2.2), app: aris, keys: "return")), .ownApp)
        // TextEdit changes by itself, and reports a focus, while Aris has the keyboard: neither is his.
        recorder.feed(ArisTeachEvent(.input, at: at(2.25), app: textEdit, input: .hand))
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.valueChanged, at: at(2.3), app: textEdit, element: textView, value: "ab")), .ownApp)
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.focused, at: at(2.4), app: textEdit, element: textView)), .ownApp)
        XCTAssertEqual(recorder.events.map(\.kind), [.focused, .valueChanged])
        // His own key back in TextEdit: from there on it is the lesson again.
        recorder.feed(ArisTeachEvent(.input, at: at(3), app: textEdit, element: textView, input: .key))
        XCTAssertNil(recorder.feed(ArisTeachEvent(.valueChanged, at: at(3.1), app: textEdit, element: textView, value: "abc")))
        XCTAssertEqual(recorder.events.last?.value, "abc")
    }

    // MARK: - (b) a choice is his click on that control

    func testAnAppsOwnControlChangesAreNoChoice() {
        var recorder = ArisTeachRecorder()
        recorder.start(name: "x", at: start)
        recorder.feed(ArisTeachEvent(.shortcut, at: at(1), app: textEdit, keys: "cmd+n"))
        recorder.feed(ArisTeachEvent(.input, at: at(1.2), app: textEdit, input: .hand))
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.valueChanged, at: at(1.3), app: textEdit, element: typeface, value: "Helvetica")), .unprompted,
                       "a pop-up the app set after ⌘N")
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.valueChanged, at: at(1.35), app: textEdit, element: size, value: "12")), .unprompted,
                       "a combo box that never had the keyboard")
        // His click on the pop-up, then his choice in its menu (read a while): that is a choice.
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.pressed, at: at(5), app: textEdit, element: typeface)), .nothing, "the click only opens the menu")
        recorder.feed(ArisTeachEvent(.input, at: at(9), app: textEdit, input: .hand))
        XCTAssertNil(recorder.feed(ArisTeachEvent(.selected, at: at(9), app: textEdit, element: typeface, value: "Georgia")))
        XCTAssertNil(recorder.feed(ArisTeachEvent(.valueChanged, at: at(9.05), app: textEdit, element: typeface, value: "Georgia")))
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.valueChanged, at: at(9.1), app: textEdit, element: style, value: "Regular")), .unprompted,
                       "another pop-up the app changed with it")
        // A key after the click: a later change of that pop-up is the app's.
        recorder.feed(ArisTeachEvent(.input, at: at(10), app: textEdit, element: textView, input: .key))
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.valueChanged, at: at(10.1), app: textEdit, element: typeface, value: "Helvetica")), .unprompted)
        // A checkbox counts after his click on it, not after a click elsewhere.
        let box = ArisTeachElement(role: "checkBox", label: "Wrap")
        recorder.feed(ArisTeachEvent(.pressed, at: at(11), app: textEdit, element: ArisTeachElement(role: "button", label: "OK")))
        XCTAssertEqual(recorder.feed(ArisTeachEvent(.valueChanged, at: at(11.1), app: textEdit, element: box, value: "1")), .unprompted)
        recorder.feed(ArisTeachEvent(.pressed, at: at(12), app: textEdit, element: box))
        XCTAssertNil(recorder.feed(ArisTeachEvent(.valueChanged, at: at(12.1), app: textEdit, element: box, value: "0")))
        guard case .success(let made) = ArisTeachGeneralise.procedure(recorder.stop(at: at(13))!) else { return XCTFail("a procedure") }
        XCTAssertEqual(made.steps.map(\.action), [.open, .press, .select, .click, .click], "⌘N, his one choice, OK, the checkbox")
        XCTAssertEqual(made.steps[2].option, "Georgia")
    }

    func testAPresenceAfterAKeyLeavesNoTypingHintButAnIdleTimeAtTheKeyDoes() {
        var recorder = ArisTeachRecorder()
        recorder.start(name: "x", at: start)
        recorder.feed(ArisTeachEvent(.focused, at: at(1), app: textEdit, element: textView))
        recorder.feed(ArisTeachEvent(.input, at: at(1.1), app: textEdit, element: textView, input: .key))
        recorder.feed(ArisTeachEvent(.input, at: at(1.1), app: textEdit, input: .hand))
        recorder.feed(ArisTeachEvent(.valueChanged, at: at(1.12), app: textEdit, element: textView, value: "a"))
        XCTAssertEqual(recorder.events.last?.typed, true, "the hardware's idle time read with the key is that same key")
    }

    // MARK: - (e) the parameter's name

    func testADocumentsMainTextIsCalledBody() {
        for label in ["First Text View", "Text View", "text area", "", "Editor", "Body"] {
            XCTAssertEqual(ArisTeachGeneralise.fieldName(ArisTeachElement(role: "textArea", label: label)), "본문", label)
        }
        XCTAssertEqual(ArisTeachGeneralise.fieldName(ArisTeachElement(role: "textArea", label: "메시지")), "메시지", "a text area that says what it is for")
        XCTAssertEqual(ArisTeachGeneralise.fieldName(ArisTeachElement(role: "textField", label: "제목:")), "제목")
        XCTAssertEqual(ArisTeachGeneralise.fieldName(ArisTeachElement(role: "textField", label: "Text View")), "Text View", "only a text area is a document's text")
    }

    // MARK: - (d) a step that didn't work

    private func popupProcedure(failingFollowedBy later: [ArisTeachStep] = []) -> ArisTeachProcedure {
        var steps = [ArisTeachStep(action: .open, app: "TextEdit", bundle: textEdit.bundle),
                     ArisTeachStep(action: .menu, app: "TextEdit", bundle: textEdit.bundle, label: "New", menu: ["File", "New"]),
                     ArisTeachStep(action: .select, app: "TextEdit", bundle: textEdit.bundle, target: "typeface 메뉴", role: "popUpButton", label: "typeface",
                                   option: "Helvetica"),
                     ArisTeachStep(action: .type, app: "TextEdit", bundle: textEdit.bundle, target: "First Text View 칸", role: "textArea", label: "본문", parameter: "p1")]
        steps += later
        return ArisTeachProcedure(name: "메모 쓰기", steps: steps, parameters: [ArisTeachParameter(key: "p1", label: "본문", example: "우유", app: "TextEdit")], created: start)
    }

    func testAFailedValueStepAsksToGoOnAndTheRestRuns() {
        let made = popupProcedure()
        let plan = ArisTeachReplay.plan(made, given: [:], words: "메모 쓰기 해 줘", run: "g1")
        let judge = ArisTeachTests.Judge(home: "/Users/user")
        judge.failing = ["app_select"]
        judge.feed(plan, owner: "메모 쓰기 해 줘")
        var asked: [(Int, String)] = []
        let outcome = ArisTeachReplay.run(plan, ports: judge.ports, goOn: { asked.append(($0, $1)); return true })
        XCTAssertEqual(asked.map(\.0), [2], "asked once, about step 3")
        XCTAssertEqual(asked.first?.1, "no control called 보내기 in Mail")
        XCTAssertEqual(outcome, .partly(done: 3, skipped: [2]))
        XCTAssertEqual(judge.executed, ["app_open", "app_do", "app_select", "app_type"])
        let account = ArisTeachCopy.account(made, outcome: outcome, english: false)
        XCTAssertTrue(account.contains("3단계 “TextEdit에서 ‘typeface’ 고르기") && account.contains("건너뛰었어요"), account)
        let card = ArisTeachCopy.goOnCard(made, failedAt: 2, why: "found no option ‘Helvetica’", english: false)
        XCTAssertEqual(card.title, "3단계가 안 됐어요. 남은 1단계를 계속할까요?")
        XCTAssertTrue(card.detail.contains("안 된 단계: 3. TextEdit에서 ‘typeface’ 고르기") && card.detail.contains("4. TextEdit의 ‘본문’에 [본문] 넣기"), card.detail)
        // His no stops it there, as before.
        let declined = ArisTeachTests.Judge(home: "/Users/user")
        declined.failing = ["app_select"]
        declined.feed(plan, owner: "메모 쓰기 해 줘")
        XCTAssertEqual(ArisTeachReplay.run(plan, ports: declined.ports, goOn: { _, _ in false }), .stopped(at: 2, end: .failed("no control called 보내기 in Mail"), done: 2))
        XCTAssertEqual(declined.executed, ["app_open", "app_do", "app_select"])
    }

    /// Fifth VM run, D7: a step the rest stands on, or one that asked first, used to stop the run in silence. Now it is
    /// said and he is asked whether to go on; only their yes goes on, and the steps after it are decided as ever.
    func testAStepTheRestStandsOnOrThatAskedAsksBeforeGoingOn() {
        let made = popupProcedure()
        let plan = ArisTeachReplay.plan(made, given: [:], words: "메모 쓰기 해 줘", run: "g2")
        let judge = ArisTeachTests.Judge(home: "/Users/user")
        judge.failing = ["app_do"]
        judge.feed(plan, owner: "메모 쓰기 해 줘")
        var asked = 0
        XCTAssertEqual(ArisTeachReplay.run(plan, ports: judge.ports, goOn: { _, _ in asked += 1; return false }),
                       .stopped(at: 1, end: .failed("no control called 보내기 in Mail"), done: 1), "his no stops it at the step the new window comes from")
        XCTAssertEqual(asked, 1)
        // A step that asked first (a send) and failed: asked about too; his no stops it there.
        let send = ArisTeachStep(action: .click, app: "Mail", bundle: mail.bundle, target: "보내기 버튼", role: "button", label: "보내기")
        let note = ArisTeachStep(action: .menu, app: "TextEdit", bundle: textEdit.bundle, label: "New", menu: ["File", "New"])
        let mixed = ArisTeachProcedure(name: "보내기", steps: [ArisTeachStep(action: .open, app: "Mail", bundle: mail.bundle), send, note], parameters: [], created: start)
        XCTAssertTrue(ArisTeachReplay.canGoOnWithout(1, steps: mixed.steps), "nothing later is in Mail")
        let sending = ArisTeachReplay.plan(mixed, given: [:], words: "보내기 해 줘", run: "g3")
        let asking = ArisTeachTests.Judge(home: "/Users/user")
        asking.failing = ["app_click"]
        asking.feed(sending, owner: "보내기 해 줘")
        XCTAssertEqual(ArisTeachReplay.run(sending, ports: asking.ports, goOn: { _, _ in asked += 1; return false }),
                       .stopped(at: 1, end: .failed("no control called 보내기 in Mail"), done: 1))
        XCTAssertEqual(asking.cards.count, 1, "the send asked on its card")
        XCTAssertEqual(asked, 2, "a step that needed his card is gone past only on his own yes")
        XCTAssertFalse(ArisTeachReplay.canGoOnWithout(2, steps: mixed.steps), "nothing after the last step")
    }

    // MARK: - A run whose words give no value asks for it

    func testARunWithNoValueAsksForItWithLastTimesValueOffered() {
        let made = popupProcedure()
        let noValue = ArisTeachMatch.values(made, words: "해 줘")
        XCTAssertEqual(ArisTeachReplay.missing(made, given: noValue).map(\.key), ["p1"], "\"메모 쓰기 해 줘\" gives no 본문")
        XCTAssertTrue(ArisTeachReplay.missing(made, given: ArisTeachMatch.values(made, words: "해 줘, 본문은 우유 사기")).isEmpty, "named in their words: nothing to ask")
        var unused = made
        unused.parameters.append(ArisTeachParameter(key: "p9", label: "제목", example: "x", app: "TextEdit"))
        XCTAssertEqual(ArisTeachReplay.missing(unused, given: [:]).map(\.key), ["p1"], "only what a step types is asked")
        let asked = ArisTeachCopy.valuesCard(made, missing: ArisTeachReplay.missing(made, given: noValue), english: false)
        XCTAssertEqual(asked.card.title, "‘메모 쓰기’: 본문에 뭐라고 넣을까요?")
        XCTAssertEqual(asked.fields.map(\.key), ["본문"])
        // The field comes up empty (eleventh VM run, T2): last time's value is only a suggestion above it.
        XCTAssertEqual(asked.fields.map(\.value), [""], "nothing is filled in")
        XCTAssertTrue(asked.card.detail.contains("제안: 지난번 본문 ‘우유’ (칸에 적어야 들어가요)."), asked.card.detail)
        // In an English UI the document's text is Aris's own word for it, "text" (fourth VM run, D8).
        XCTAssertEqual(ArisTeachCopy.valuesCard(made, missing: made.parameters, english: true).card.title, "“메모 쓰기”: what goes in text?")
        // What he wrote on the card is his value for this run, last time's value too when he wrote it in; an empty field gives nothing.
        let missing = ArisTeachReplay.missing(made, given: noValue)
        XCTAssertEqual(ArisTeachReplay.answered(missing, edits: ["본문": "회의는 3시"]), ["p1": "회의는 3시"])
        XCTAssertEqual(ArisTeachReplay.answered(missing, edits: [:]), [:])
        XCTAssertEqual(ArisTeachReplay.answered(missing, edits: ["본문": "우유"]), ["p1": "우유"])
        XCTAssertEqual(ArisTeachReplay.answered(missing, edits: ["본문": "  "]), [:])
        let written = ArisTeachReplay.plan(made, given: ArisTeachReplay.answered(missing, edits: ["본문": "회의는 3시"]), words: "메모 쓰기 해 줘", run: "v1")
        XCTAssertEqual(written.calls[3]?.object?["text"] as? String, "회의는 3시")
        XCTAssertTrue(written.instruction.contains("회의는 3시") && written.approved.contains { $0.call == "teach-v1-4" }, "his value, his instruction")
        let kept = ArisTeachReplay.plan(made, given: ArisTeachReplay.answered(missing, edits: [:]), words: "메모 쓰기 해 줘", run: "v2")
        XCTAssertEqual(kept.calls[3]?.object?["text"] as? String, "우유")
        XCTAssertFalse(kept.approved.contains { $0.call == "teach-v2-4" }, "the offered value kept as it was is still the app's content, judged as before")
        XCTAssertEqual(ArisTeachCopy.notRun(made, unanswered: false, english: false), "알겠어요, ‘메모 쓰기’ 하지 않았어요.")
    }
}
