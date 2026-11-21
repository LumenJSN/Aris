import XCTest
@testable import ArisCore

/// One card for a taught procedure's run (jv-quick): which steps the card may cover, the pass bound to the exact plan
/// and used a step at a time, when it is void, and the run through ArisTeachReplay with it.
final class ArisTeachRunPassTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let bundle = "com.apple.TextEdit"

    private func menu(_ path: [String], keys: String? = nil, app: String = "TextEdit", bundle: String? = nil) -> ArisTeachStep {
        var step = ArisTeachStep(action: .menu, app: app, bundle: bundle ?? self.bundle, label: path.last, menu: path)
        step.keys = keys
        return step
    }

    private func typed(_ place: ArisTeachStep.Place, parameter: String? = "p1", text: String? = nil) -> ArisTeachStep {
        var step = ArisTeachStep(action: .type, app: "TextEdit", bundle: bundle, target: "First Text View 칸", role: "textArea",
                                 label: ArisTeachGeneralise.bodyLabel, text: text, parameter: parameter)
        step.place = place
        return step
    }

    private func click(_ label: String, role: String = "button") -> ArisTeachStep {
        ArisTeachStep(action: .click, app: "TextEdit", bundle: bundle, target: "\(label) 버튼", role: role, label: label)
    }

    /// "서식 정리": TextEdit opened, three menu commands with keys.
    private func tidy() -> ArisTeachProcedure {
        ArisTeachProcedure(name: "서식 정리", steps: [
            ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle),
            menu(["Edit", "Select All"], keys: "cmd+a"),
            menu(["Format", "Make Plain Text"], keys: "cmd+shift+t"),
        ], parameters: [], created: start)
    }

    /// "전체 바꾸기": TextEdit opened, Edit › Select All, the whole text replaced.
    private func replaceAll() -> ArisTeachProcedure {
        ArisTeachProcedure(name: "전체 바꾸기", steps: [
            ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle), menu(["Edit", "Select All"], keys: "cmd+a"), typed(.all),
        ], parameters: [ArisTeachParameter(key: "p1", label: ArisTeachGeneralise.bodyLabel, example: "Replaced all", app: "TextEdit", fromApp: false)],
                           created: start)
    }

    private func plan(_ procedure: ArisTeachProcedure, given: [String: String] = [:], run: String = "q1") -> ArisTeachReplay.Plan {
        ArisTeachReplay.plan(procedure, given: given, words: "\(procedure.name) 해 줘", run: run)
    }

    private let asks = ArisTeachRunPass.Judged(effect: .changeReversible, asks: true)

    // MARK: - Which steps the one card may cover (an explicit list)

    func testTheCoveredKindsAreAnExplicitList() {
        XCTAssertEqual(ArisTeachCover.kinds, [.open, .menu, .click, .select, .type])
        let open = ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle)
        XCTAssertEqual(ArisTeachCover.why(open, ownerGave: []), .covered)
        XCTAssertEqual(ArisTeachCover.why(menu(["Edit", "Select All"], keys: "cmd+a"), ownerGave: []), .covered)
        XCTAssertEqual(ArisTeachCover.why(click("Bold"), ownerGave: []), .covered)
        XCTAssertEqual(ArisTeachCover.why(ArisTeachStep(action: .select, app: "TextEdit", bundle: bundle, target: "Fonts 탭", role: "tab", label: "Fonts"), ownerGave: []), .covered)
        // Text he gave for this run, added to what is there.
        XCTAssertEqual(ArisTeachCover.why(typed(.end), ownerGave: ["p1"]), .covered)
        XCTAssertEqual(ArisTeachCover.why(typed(.caret), ownerGave: ["p1"]), .covered)
    }

    func testAStepThatErasesOrCarriesARecordedValueOrPressesKeysIsNeverCovered() {
        // A replace erases what the field holds: its own card, with what is erased read at that moment.
        XCTAssertEqual(ArisTeachCover.why(typed(.all), ownerGave: ["p1"]), .replaces)
        // A value recorded when he showed it is the app's content, not their words for this run.
        XCTAssertEqual(ArisTeachCover.why(typed(.end), ownerGave: []), .recordedValue)
        XCTAssertEqual(ArisTeachCover.why(typed(.end, parameter: nil, text: "literal"), ownerGave: []), .recordedValue)
        var option = ArisTeachStep(action: .select, app: "TextEdit", bundle: bundle, target: "Size 팝업", role: "popUpButton", label: "Size")
        option.option = "12"
        XCTAssertEqual(ArisTeachCover.why(option, ownerGave: []), .recordedValue)
        // Keys can do anything where they land (Return sends, Delete deletes): not on the list.
        var press = ArisTeachStep(action: .press, app: "TextEdit", bundle: bundle)
        press.keys = "cmd+n"
        XCTAssertEqual(ArisTeachCover.why(press, ownerGave: []), .kind)
    }

    func testAStepWhoseWordsSendDeletePayOrRunIsNeverCovered() {
        for words in ["Send", "보내기", "Submit", "Delete", "삭제", "지우기", "Remove", "Pay now", "결제하기", "Place Order", "Run Script", "Empty Trash"] {
            XCTAssertEqual(ArisTeachCover.why(click(words), ownerGave: []), .namesRisk, words)
        }
        XCTAssertEqual(ArisTeachCover.why(menu(["Message", "Send"], keys: "cmd+shift+d"), ownerGave: []), .namesRisk)
        XCTAssertEqual(ArisTeachCover.why(menu(["File", "Move to Trash"]), ownerGave: []), .namesRisk)
        XCTAssertEqual(ArisTeachCover.why(menu(["Edit", "Delete"]), ownerGave: []), .namesRisk)
        // Commands that go over the selection or take text back change his content with no card of their own.
        for item in ["Cut", "Paste", "Paste and Match Style", "Clear", "Undo Typing", "Redo", "오려두기", "붙여넣기", "실행 취소"] {
            XCTAssertEqual(ArisTeachCover.why(menu(["Edit", item]), ownerGave: []), .namesRisk, item)
        }
        XCTAssertEqual(ArisTeachCover.why(menu(["Edit", "Copy"], keys: "cmd+c"), ownerGave: []), .covered)
        // A browser's page: every act there asks on its own card (decision 2).
        XCTAssertEqual(ArisTeachCover.why(menu(["File", "New Tab"], keys: "cmd+t", app: "Safari", bundle: "com.apple.Safari"), ownerGave: []), .browser)
        XCTAssertEqual(ArisTeachCover.why(menu(["File", "New Tab"], app: "크롬", bundle: "x.unknown"), ownerGave: []), .browser)
    }

    // MARK: - Typing over a selection (security review of 3ddbef9b)

    func testTypingAfterAStepThatMayChangeTheSelectionIsNeverCovered() {
        let open = ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle)
        // Typing over a selection erases it: after Select All, or any step not known to leave the selection alone.
        for before in [menu(["Edit", "Select All"], keys: "cmd+a"), menu(["File", "New"], keys: "cmd+n"), click("Bold"),
                       ArisTeachStep(action: .select, app: "TextEdit", bundle: bundle, target: "Fonts 탭", role: "tab", label: "Fonts")] {
            for place in [ArisTeachStep.Place.end, .caret] {
                let steps = [open, before, typed(place)]
                XCTAssertEqual(ArisTeachCover.why(at: 2, in: steps, ownerGave: ["p1"]), .mayTypeOver, "\(before.action) \(place)")
                XCTAssertEqual(ArisTeachCover.why(at: 1, in: steps, ownerGave: ["p1"]), .covered, "the step before it is as it was")
            }
        }
        // Opening the app, and text added before it, leave no selection: the typing stays on the card's list.
        XCTAssertEqual(ArisTeachCover.why(at: 1, in: [open, typed(.caret)], ownerGave: ["p1"]), .covered)
        XCTAssertEqual(ArisTeachCover.why(at: 2, in: [open, typed(.end), typed(.end)], ownerGave: ["p1"]), .covered)
        // A step in another app can't select anything in this one.
        let other = menu(["Edit", "Select All"], keys: "cmd+a", app: "Notes", bundle: "com.apple.Notes")
        XCTAssertEqual(ArisTeachCover.why(at: 2, in: [open, other, typed(.end)], ownerGave: ["p1"]), .covered)
        // The steps known to leave the selection alone are an explicit list.
        XCTAssertEqual(ArisTeachCover.keepsSelection, [.open, .type])
        // The pass is made with it.
        let made = ArisTeachProcedure(name: "덧쓰기", steps: [open, menu(["Edit", "Select All"], keys: "cmd+a"), typed(.end)],
                                      parameters: [ArisTeachParameter(key: "p1", label: ArisTeachGeneralise.bodyLabel, example: "x", app: "TextEdit", fromApp: false)],
                                      created: start)
        XCTAssertEqual(ArisTeachRunPass(plan: plan(made, given: ["p1": "x"])).covered, [true, true, false])
    }

    func testTheSelectedTextOfAFieldIsReadOrUnknown() {
        typealias E = ArisApps.ReadElement
        XCTAssertEqual(E.selected(in: "Keep text", range: (0, 0)), "")
        XCTAssertEqual(E.selected(in: "Keep text", range: (9, 0)), "", "a caret at the end selects nothing")
        XCTAssertEqual(E.selected(in: "Keep text", range: (0, 9)), "Keep text")
        XCTAssertEqual(E.selected(in: "한글 😀 text", range: (3, 2)), "😀")
        // Unknown is never "nothing selected".
        XCTAssertNil(E.selected(in: "Keep text", range: nil))
        XCTAssertNil(E.selected(in: nil, range: (0, 4)))
        XCTAssertNil(E.selected(in: "short", range: (2, 40)))
        XCTAssertNil(E.selected(in: "x", range: (-1, 1)))
    }

    func testTypingIsRefusedWhenTheSelectionIsNotWhatTheDecisionSaw() {
        typealias T = ArisApps.TypeOver
        func marked(_ mark: String?) -> ArisApps.JSON { .object(mark.map { ["app": .string("TextEdit"), T.argument: .string($0)] } ?? ["app": .string("TextEdit")]) }
        // The decision saw nothing selected: typing goes in only while that is still read to be so.
        let empty = T.mark(erases: nil)
        XCTAssertEqual(empty, "empty")
        XCTAssertFalse(T.refuses(marked(empty), selected: ""))
        XCTAssertTrue(T.refuses(marked(empty), selected: "Keep text"))
        XCTAssertTrue(T.refuses(marked(empty), selected: nil), "unknown at typing time is not empty")
        // He said yes to a card that showed what is selected: only that selection.
        let seen = T.mark(erases: ArisErasedText(text: "Keep text", keepable: false))
        XCTAssertTrue(seen.hasPrefix("is:"))
        XCTAssertFalse(T.refuses(marked(seen), selected: "Keep text"))
        XCTAssertTrue(T.refuses(marked(seen), selected: "Other text"))
        XCTAssertTrue(T.refuses(marked(seen), selected: ""))
        XCTAssertTrue(T.refuses(marked(seen), selected: nil))
        // He said yes to a card that said the selection couldn't be read: whatever it is.
        let any = T.mark(erases: ArisErasedText(text: nil, keepable: false))
        XCTAssertEqual(any, "any")
        XCTAssertFalse(T.refuses(marked(any), selected: "x"))
        XCTAssertFalse(T.refuses(marked(any), selected: nil))
        // A call with no mark (anything but a replay's typing) is as it was; a mark nobody knows refuses.
        XCTAssertFalse(T.refuses(marked(nil), selected: "x"))
        XCTAssertTrue(T.refuses(marked("whatever"), selected: ""))
    }

    func testAReplaceIsRefusedWhenTheFieldHoldsSomethingElseThanItsCardShowed() {
        typealias T = ArisApps.TypeOver
        func marked(_ mark: String?) -> ArisApps.JSON { .object(mark.map { ["replace": .bool(true), T.argument: .string($0)] } ?? ["replace": .bool(true)]) }
        let seen = T.mark(erases: ArisErasedText(text: "Keep text", keepable: true))
        XCTAssertFalse(T.refusesReplace(marked(seen), holds: "Keep text"))
        XCTAssertTrue(T.refusesReplace(marked(seen), holds: "Keep text and more"))
        XCTAssertTrue(T.refusesReplace(marked(seen), holds: ""))
        XCTAssertTrue(T.refusesReplace(marked(seen), holds: nil), "unknown at the replace is not what the card showed")
        // The card said the field was empty: only an empty field.
        let nothing = T.mark(erases: ArisErasedText(text: "", keepable: true))
        XCTAssertFalse(T.refusesReplace(marked(nothing), holds: ""))
        XCTAssertTrue(T.refusesReplace(marked(nothing), holds: "x"))
        // The card said it couldn't be read, and he said yes to that.
        XCTAssertFalse(T.refusesReplace(marked(T.mark(erases: ArisErasedText(text: nil, keepable: false))), holds: "x"))
        // Nothing known of the decision: only an empty field is replaced. No mark: as it was. An unknown mark refuses.
        XCTAssertTrue(T.refusesReplace(marked(T.mark(erases: nil)), holds: "x"))
        XCTAssertFalse(T.refusesReplace(marked(T.mark(erases: nil)), holds: ""))
        XCTAssertFalse(T.refusesReplace(marked(nil), holds: "x"))
        XCTAssertTrue(T.refusesReplace(marked("whatever"), holds: ""))
    }

    func testACardThatErasesIsNeverCoveredByAnEarlierYesAndSaysSoAloud() {
        var asks = ArisAskPlan()
        func item(_ call: String, erases: ArisErasedText?) -> ArisAskItem {
            var facts = ArisCallFacts(capability: "app.type", arguments: [ArisKeyArgument(kind: .app, value: "TextEdit"), ArisKeyArgument(kind: .body, value: "x")])
            facts.erases = erases
            return ArisAskItem(call: call, facts: facts, effect: .changePermanent, decision: .ask, provenance: .ownStep)
        }
        let first = asks.plan([item("a", erases: ArisErasedText(text: "one", keepable: false))], intent: "i", home: "/Users/x")
        _ = asks.answer(first.cards[0].id, .yes, home: "/Users/x")
        // The same kind of call in the same app, erasing something else: its own card.
        let second = asks.plan([item("b", erases: ArisErasedText(text: "two", keepable: false))], intent: "i", home: "/Users/x")
        XCTAssertEqual(second.covered, [])
        XCTAssertEqual(second.cards.count, 1)
        XCTAssertTrue(second.cards[0].detail.contains("two"), second.cards[0].detail)
        // One that erases nothing is covered as before.
        XCTAssertEqual(asks.plan([item("c", erases: nil)], intent: "i", home: "/Users/x").covered, ["c"])
        // A replay's step whose typing turns out to erase is asked in the words that say so.
        var described = ArisAskDescription(title: "‘덧쓰기’ 3/3단계", line: "TextEdit의 ‘본문’에 ‘x’ 넣기", spoken: "‘덧쓰기’ 3단계, 할까요?")
        described.spokenErases = "‘덧쓰기’ 3단계, TextEdit 글이 지워져요. 할까요?"
        let erasing = ArisAskPlan.card([item("d", erases: ArisErasedText(text: "Keep text", keepable: false))], id: "c", intent: "i", countdown: false,
                                       home: "/Users/x", described: ["d": described])
        XCTAssertEqual(erasing.spoken, "‘덧쓰기’ 3단계, TextEdit 글이 지워져요. 할까요?")
        XCTAssertTrue(erasing.detail.contains("Keep text") && erasing.detail.contains(ArisAskPlan.erasesLost), erasing.detail)
        let plain = ArisAskPlan.card([item("d", erases: nil)], id: "c", intent: "i", countdown: false, home: "/Users/x", described: ["d": described])
        XCTAssertEqual(plain.spoken, "‘덧쓰기’ 3단계, 할까요?")
    }

    // MARK: - The pass: bound to the plan, used a step at a time

    func testThePassIsBoundToTheExactPlan() {
        let base = ArisTeachRunPass(plan: plan(tidy()))
        XCTAssertEqual(base.hash, ArisTeachRunPass(plan: plan(tidy())).hash, "the same plan, the same pass")
        XCTAssertEqual(base.covered, [true, true, true])
        // Another order, another app, another control name, another value, another run: each another plan.
        var swapped = tidy()
        swapped.steps.swapAt(1, 2)
        var renamed = tidy()
        renamed.steps[2] = menu(["Format", "Make Rich Text"], keys: "cmd+shift+t")
        var elsewhere = tidy()
        elsewhere.steps[1] = menu(["Edit", "Select All"], keys: "cmd+a", app: "Notes", bundle: "com.apple.Notes")
        var rekeyed = tidy()
        rekeyed.steps[1] = menu(["Edit", "Select All"], keys: "cmd+shift+a")
        for other in [swapped, renamed, elsewhere, rekeyed] {
            XCTAssertNotEqual(base.hash, ArisTeachRunPass(plan: plan(other)).hash)
        }
        XCTAssertNotEqual(base.hash, ArisTeachRunPass(plan: plan(tidy(), run: "q2")).hash, "a pass is one run's")
        let his = ArisTeachRunPass(plan: plan(replaceAll(), given: ["p1": "회의는 3시"]))
        XCTAssertNotEqual(his.hash, ArisTeachRunPass(plan: plan(replaceAll(), given: ["p1": "회의는 4시"])).hash, "another value is another plan")
        XCTAssertEqual(his.covered, [true, true, false], "the replace is never covered")
    }

    func testEachStepIsTakenOnceInOrderAndOnlyAWaitingCoveredStepRunsOnIt() {
        let made = plan(tidy())
        let pass = ArisTeachRunPass(plan: made)
        // Step 1 didn't wait (nothing judged): the pass moves on and lets nothing run by itself.
        let first = pass.taking(0, made.calls[0], judged: nil)
        XCTAssertFalse(first.runs)
        XCTAssertEqual(first.pass.next, 1)
        let second = first.pass.taking(1, made.calls[1], judged: asks)
        XCTAssertTrue(second.runs)
        // The same step again: its pass is used, and the rest goes with it.
        let again = second.pass.taking(1, made.calls[1], judged: asks)
        XCTAssertFalse(again.runs)
        XCTAssertEqual(again.pass.void, .outOfOrder(at: 1))
        XCTAssertFalse(again.pass.taking(2, made.calls[2], judged: asks).runs, "a void pass lets nothing run")
        let third = second.pass.taking(2, made.calls[2], judged: asks)
        XCTAssertTrue(third.runs)
        XCTAssertNil(third.pass.void)
        XCTAssertFalse(third.pass.taking(3, made.calls[2], judged: asks).runs, "nothing past the plan")
    }

    func testACallThatDiffersFromThePlanVoidsThePass() {
        let made = plan(tidy())
        let pass = ArisTeachRunPass(plan: made)
        let other = plan(tidy(), run: "q9")
        let taken = pass.taking(0, other.calls[0], judged: asks)
        XCTAssertFalse(taken.runs)
        XCTAssertEqual(taken.pass.void, .differs(at: 0))
        // The same id and tool with another argument.
        let call = made.calls[1]!
        let changed = ArisMindToolCall(id: call.id, name: call.name, arguments: #"{"app":"TextEdit","command":"=Edit › Delete"}"#)
        let moved = pass.taking(0, made.calls[0], judged: nil).pass.taking(1, changed, judged: asks)
        XCTAssertFalse(moved.runs)
        XCTAssertEqual(moved.pass.void, .differs(at: 1))
        XCTAssertFalse(moved.pass.taking(2, made.calls[2], judged: asks).runs)
        // A step that couldn't be made, or one skipped.
        XCTAssertEqual(pass.taking(0, nil, judged: asks).pass.void, .differs(at: 0))
        XCTAssertEqual(pass.taking(1, made.calls[1], judged: asks).pass.void, .outOfOrder(at: 1))
    }

    func testAFailedStepAStopOrANewTurnVoidsThePass() {
        let made = plan(tidy())
        for why in [ArisTeachRunPass.Void.failed(at: 0), .stopped, .newTurn] {
            let gone = ArisTeachRunPass(plan: made).voided(why)
            XCTAssertEqual(gone.void, why)
            XCTAssertFalse(gone.taking(0, made.calls[0], judged: asks).runs)
            XCTAssertEqual(gone.voided(.stopped).void, why, "the first reason stays")
        }
    }

    func testWhatTheGateJudgedAtTheRunDecidesWhetherTheStepIsCovered() {
        let made = plan(tidy())
        let at1 = ArisTeachRunPass(plan: made).taking(0, made.calls[0], judged: nil).pass
        func runs(_ judged: ArisTeachRunPass.Judged?) -> Bool { at1.taking(1, made.calls[1], judged: judged).runs }
        XCTAssertTrue(runs(asks))
        XCTAssertTrue(runs(ArisTeachRunPass.Judged(effect: .observe, asks: true)))
        // Unknown is never less strict than known: nothing judged, the step asks.
        XCTAssertFalse(runs(nil))
        // Above what a taught step may run by itself.
        XCTAssertFalse(runs(ArisTeachRunPass.Judged(effect: .changePermanent, asks: true)))
        XCTAssertFalse(runs(ArisTeachRunPass.Judged(effect: .outward, asks: true)))
        XCTAssertFalse(runs(ArisTeachRunPass.Judged(effect: .never, asks: true)))
        // A read-back, a countdown or a refusal is not a plain ask.
        XCTAssertFalse(runs(ArisTeachRunPass.Judged(effect: .changeReversible, asks: false)))
        // A provenance warning, a payment, a browser's page, text erased, something sent: each asks on its own card.
        XCTAssertFalse(runs(ArisTeachRunPass.Judged(effect: .changeReversible, asks: true, content: true)))
        XCTAssertFalse(runs(ArisTeachRunPass.Judged(effect: .changeReversible, asks: true, payment: true)))
        XCTAssertFalse(runs(ArisTeachRunPass.Judged(effect: .changeReversible, asks: true, browser: true)))
        XCTAssertFalse(runs(ArisTeachRunPass.Judged(effect: .changeReversible, asks: true, erases: true)))
        XCTAssertFalse(runs(ArisTeachRunPass.Judged(effect: .changeReversible, asks: true, sends: true)))
        // A step that asks its own card doesn't void the pass for the steps after it.
        let after = at1.taking(1, made.calls[1], judged: ArisTeachRunPass.Judged(effect: .changePermanent, asks: true)).pass
        XCTAssertNil(after.void)
        XCTAssertTrue(after.taking(2, made.calls[2], judged: asks).runs)
        // A step not on the card's list is never run on the pass, whatever was judged.
        let replace = plan(replaceAll(), given: ["p1": "x"])
        let at2 = ArisTeachRunPass(plan: replace).taking(0, replace.calls[0], judged: nil).pass.taking(1, replace.calls[1], judged: asks).pass
        XCTAssertFalse(at2.taking(2, replace.calls[2], judged: asks).runs)
    }

    // MARK: - What the card marks

    func testTheMarksSayWhichStepsTheCardCoversAndWhichAskAgain() {
        typealias M = ArisTeachRunPass.Mark
        let ask = ArisTeachRunPass.Judged(effect: .changeReversible, asks: true)
        XCTAssertEqual(M.of(covered: true, waits: false, judged: nil), .runs)
        XCTAssertEqual(M.of(covered: true, waits: true, judged: ask), .covered)
        XCTAssertEqual(M.of(covered: false, waits: true, judged: ask), .asksAgain)
        XCTAssertEqual(M.of(covered: true, waits: true, judged: ArisTeachRunPass.Judged(effect: .changePermanent, asks: true)), .asksAgain)
        XCTAssertEqual(M.of(covered: true, waits: true, judged: nil), .asksAgain, "unknown asks")
        // The one card is asked only when it stands in for at least one step's card.
        XCTAssertTrue(ArisTeachRunPass.asksOnce([.runs, .covered, .asksAgain]))
        XCTAssertFalse(ArisTeachRunPass.asksOnce([.runs, .asksAgain]))
        XCTAssertFalse(ArisTeachRunPass.asksOnce([]))
    }

    // MARK: - The run with a pass

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = [], ran: [String] = [], used: [String] = []
        func ask(_ id: String) { lock.withLock { asked.append(id) } }
        func run(_ id: String) { lock.withLock { ran.append(id) } }
        func use(_ id: String) { lock.withLock { used.append(id) } }
        var all: (asked: [String], ran: [String], used: [String]) { lock.withLock { (asked, ran, used) } }
    }

    /// Ports where every call waits for the owner (as a taught menu step with a key does), he says yes, and `failing` fail.
    private func ports(_ log: Log, failing: Set<String> = [], current: @escaping @Sendable () -> Bool = { true }) -> ArisMindPorts {
        ArisMindPorts(decide: { $0.map { ArisMindDecided(call: $0, verdict: .waits) } },
                      ask: { waiting in
                          waiting.forEach { log.ask($0.call.id) }
                          return Set(waiting.map(\.call.id))
                      },
                      execute: { item in
                          log.run(item.call.id)
                          return ArisMindResult(text: failing.contains(item.call.id) ? "that menu item isn't there now" : "{}", isError: failing.contains(item.call.id))
                      },
                      finish: { _, _, _ in }, isCurrent: current)
    }

    private func approval(_ plan: ArisTeachReplay.Plan, _ log: Log, judged: @escaping @Sendable (String) -> ArisTeachRunPass.Judged?) -> ArisTeachReplay.Approval {
        ArisTeachReplay.Approval(box: ArisTeachPassBox(ArisTeachRunPass(plan: plan)), judged: judged, used: { log.use($0) })
    }

    func testWithoutAPassEveryWaitingStepAsksAsBefore() {
        let made = plan(tidy()), log = Log()
        XCTAssertEqual(ArisTeachReplay.run(made, ports: ports(log)), .done(steps: 3))
        XCTAssertEqual(log.all.asked, made.calls.compactMap { $0?.id })
    }

    func testWithThePassTheCoveredStepsRunWithNoCardOfTheirOwn() {
        let made = plan(tidy()), log = Log()
        let asks = self.asks
        let ended = ArisTeachReplay.run(made, ports: ports(log), approval: approval(made, log) { _ in asks })
        XCTAssertEqual(ended, .done(steps: 3))
        XCTAssertEqual(log.all.asked, [])
        XCTAssertEqual(log.all.ran, made.calls.compactMap { $0?.id })
        XCTAssertEqual(log.all.used, made.calls.compactMap { $0?.id }, "each step that ran on the pass is told, for the record")
    }

    func testTheReplaceStillAsksAtItsOwnMomentUnderThePass() {
        let made = plan(replaceAll(), given: ["p1": "회의는 3시"]), log = Log()
        let asks = self.asks
        let ended = ArisTeachReplay.run(made, ports: ports(log), approval: approval(made, log) { _ in asks })
        XCTAssertEqual(ended, .done(steps: 3))
        XCTAssertEqual(log.all.asked, [made.calls[2]!.id], "only the replace asks")
    }

    func testAPassForAnotherPlanCoversNothing() {
        let made = plan(tidy()), log = Log()
        let asks = self.asks
        let other = ArisTeachReplay.Approval(box: ArisTeachPassBox(ArisTeachRunPass(plan: plan(tidy(), run: "q7"))), judged: { _ in asks }, used: { _ in })
        XCTAssertEqual(ArisTeachReplay.run(made, ports: ports(log), approval: other), .done(steps: 3))
        XCTAssertEqual(log.all.asked, made.calls.compactMap { $0?.id })
        XCTAssertEqual(other.box.pass.void, .differs(at: 0))
    }

    func testAfterAFailedStepTheStepsLeftAskAgain() {
        let made = plan(tidy()), log = Log()
        let asks = self.asks
        let failing: Set<String> = [made.calls[1]!.id]
        let given = approval(made, log) { _ in asks }
        let ended = ArisTeachReplay.run(made, ports: ports(log, failing: failing), goOn: { _, _ in true }, afresh: { self.ports(log) }, approval: given)
        XCTAssertEqual(ended, .partly(done: 2, skipped: [1]))
        XCTAssertEqual(given.box.pass.void, .failed(at: 1))
        XCTAssertEqual(log.all.asked, [made.calls[2]!.id], "the step after the failure asks on its own card")
    }

    func testARunThatEndsLeavesNothingOfThePass() {
        let made = plan(tidy()), log = Log()
        let asks = self.asks
        let given = approval(made, log) { _ in asks }
        XCTAssertEqual(ArisTeachReplay.run(made, ports: ports(log), approval: given), .done(steps: 3))
        XCTAssertEqual(given.box.pass.void, .stopped)
        XCTAssertFalse(given.box.take(0, made.calls[0], judged: asks), "the same plan again needs their yes again")
    }

    func testAStoppedRunVoidsThePass() {
        let made = plan(tidy()), log = Log()
        let asks = self.asks
        let given = approval(made, log) { _ in asks }
        let ended = ArisTeachReplay.run(made, ports: ports(log, current: { false }), approval: given)
        XCTAssertEqual(ended, .stopped(at: 0, end: .stale, done: 0))
        XCTAssertEqual(given.box.pass.void, .newTurn, "a newer turn took the run over")
        XCTAssertEqual(log.all.ran, [])
    }
}
