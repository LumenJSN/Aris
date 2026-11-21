import XCTest
@testable import ArisCore

/// The fifth VM run (aris-vmcheck notes5/cap5): the parts of its defects that are pure.
/// D1  a menu step's reason ("“Select All” is greyed out right now") reaches the message in either UI language;
/// D2  a replay step's card reads as the lesson's sentence in the UI's language, never "$ =File › New [cmd+n]";
/// D7  a step that failed is said and asks whether to go on with the steps left, whatever it was; going on runs the
///     rest under an intent of their own, each through its own decision;
/// M3  the values card shows a line break as ↵ and reads it back as one.
final class ArisTeachVM5Tests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let bundle = "com.apple.TextEdit"

    /// A judge like ArisTeachTests.Judge, with the intent its cards are planned under, and calls failing by id.
    final class Judge: @unchecked Sendable {
        let lock = NSLock()
        var tracker = ArisProvenanceTracker()
        var plan = ArisAskPlan()
        var intent = "teach-1"
        var cards: [ArisAskCard] = []
        var executed: [String] = []
        var decisions: [String: ArisDecision] = [:]
        var facts: [String: (ArisCallFacts, ArisEffectClass, ArisCallProvenance)] = [:]
        var failing: Set<String> = []

        func ports() -> ArisMindPorts {
            let intent = self.intent
            return ArisMindPorts(
                decide: { [self] calls in
                    calls.map { call in
                        let arguments = ArisApps.JSON(any: call.object ?? [:])
                        let effect = ArisApps.Spec.named(call.name)?.effect(arguments, ArisApps.EffectContext()) ?? .changePermanent
                        let capability = ArisApps.Spec.named(call.name)?.name ?? call.name
                        let keys = ArisKeyArguments.extract(call.object ?? [:], capability: capability)
                        return lock.withLock {
                            let verdict = tracker.toolCall(id: call.id, capability: capability, effect: effect, arguments: keys)
                            let facts = ArisCallFacts(capability: capability, arguments: keys)
                            self.facts[call.id] = (facts, effect, verdict.provenance)
                            let decision = ArisTrustPolicy.decide(facts, effect: effect, provenance: verdict.provenance, specified: verdict.specified,
                                                                  ownerNamed: verdict.ownerNamed, context: .init(home: "/Users/user"))
                            decisions[call.id] = decision
                            return ArisMindDecided(call: call, verdict: ArisMindVerdict(decision))
                        }
                    }
                },
                ask: { [self] waiting in
                    lock.withLock {
                        let items = waiting.map { item in
                            let known = facts[item.call.id]!
                            return ArisAskItem(call: item.call.id, facts: known.0, effect: known.1, decision: decisions[item.call.id]!, provenance: known.2)
                        }
                        let planned = plan.plan(items, intent: intent, home: "/Users/user")
                        cards += planned.cards
                        var allowed = Set(planned.covered)
                        for card in planned.cards { allowed.formUnion(plan.answer(card.id, .yes, home: "/Users/user").run) }
                        return allowed
                    }
                },
                execute: { [self] item in
                    lock.withLock { executed.append(item.call.id) }
                    return failing.contains(item.call.id) ? ArisMindResult(text: #"{"did":"“Select All” is greyed out right now","ok":false}"#, isError: true)
                                                          : ArisMindResult(text: "done")
                },
                finish: { _, _, _ in },
                isCurrent: { true })
        }

        func feed(_ plan: ArisTeachReplay.Plan, owner: String) {
            lock.withLock {
                tracker.ownerTurn(owner)
                tracker.taskInstruction(plan.instruction)
                for seen in plan.seen { tracker.toolResult(seen.text, source: seen.source) }
                tracker.approve(plan.approved)
            }
        }
    }

    /// A text step into TextEdit's document, its value the parameter p1.
    private func typed(_ place: ArisTeachStep.Place) -> ArisTeachStep {
        var step = ArisTeachStep(action: .type, app: "TextEdit", bundle: bundle, target: "First Text View 칸", role: "textArea", label: "본문", parameter: "p1")
        step.place = place
        return step
    }

    /// "전체 바꾸기" as the VM taught it: TextEdit, Edit › Select All (⌘A), the text replaced.
    private func replaceAll() -> ArisTeachProcedure {
        ArisTeachProcedure(name: "전체 바꾸기", steps: [
            ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle),
            ArisTeachStep(action: .menu, app: "TextEdit", bundle: bundle, label: "Select All", menu: ["Edit", "Select All"], keys: "cmd+a"),
            typed(.all),
        ], parameters: [ArisTeachParameter(key: "p1", label: "본문", example: "Korean replaced", app: "TextEdit")], created: start)
    }

    /// "메모 쓰기": TextEdit, File › New (⌘N), a line typed.
    private func newMemo() -> ArisTeachProcedure {
        ArisTeachProcedure(name: "메모 쓰기", steps: [
            ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle),
            ArisTeachStep(action: .menu, app: "TextEdit", bundle: bundle, label: "New", menu: ["File", "New"], keys: "cmd+n"),
            typed(.end),
        ], parameters: [ArisTeachParameter(key: "p1", label: "본문", example: "Memo line", app: "TextEdit")], created: start)
    }

    // MARK: - D1: the reason reaches him

    func testAGreyedOutMenuItemsReasonIsSaidInEitherLanguage() {
        let why = "“Select All” is greyed out right now"
        XCTAssertEqual(ArisTeachCopy.reason(why, english: false), "‘Select All’ 메뉴가 지금은 비활성화되어 있어요")
        XCTAssertEqual(ArisTeachCopy.reason(why, english: true), "‘Select All’ is greyed out in the menu right now")
        let korean = ArisTeachCopy.account(replaceAll(), outcome: .stopped(at: 1, end: .failed(why), done: 1), english: false)
        XCTAssertTrue(korean.contains("비활성화되어 있어요"), korean)
        // Inside the app layer's longer line too, naming the item and not what comes before it.
        XCTAssertEqual(ArisTeachCopy.reason("couldn't run “Select All” in TextEdit: menu: “Select All” is greyed out now", english: true),
                       "‘Select All’ is greyed out in the menu right now")
        XCTAssertNotNil(ArisTeachCopy.reason("no menu item “Wrap” under “Format”", english: false))
    }

    // MARK: - D2: a step's card is the lesson's sentence

    func testAReplayStepsCardReadsAsTheLessonsSentence() {
        let made = newMemo()
        let plan = ArisTeachReplay.plan(made, given: ["p1": "Memo line"], words: "메모 쓰기 해 줘", run: "d2")
        let english = ArisTeachReplay.described(made, plan: plan, english: true)
        let korean = ArisTeachReplay.described(made, plan: plan, english: false)
        let call = plan.calls[1]!.id
        XCTAssertEqual(english[call]?.line, "In TextEdit, choose ‘File › New’")
        XCTAssertEqual(english[call]?.title, "“메모 쓰기”, step 2 of 3")
        XCTAssertEqual(korean[call]?.line, "TextEdit에서 메뉴 ‘File › New’ 누르기")
        XCTAssertEqual(korean[call]?.title, "‘메모 쓰기’ 2/3단계")
        XCTAssertEqual(english.count, 3, "every step has its words")
        // The gate's card for that call, as the replay words it: no call syntax anywhere on it.
        let arguments = plan.calls[1]!.object ?? [:]
        let facts = ArisCallFacts(capability: "app.do", arguments: ArisKeyArguments.extract(arguments, capability: "app.do"))
        let item = ArisAskItem(call: call, facts: facts, effect: .changeReversible, decision: .ask, provenance: .ownStep)
        let card = ArisAskPlan.card([item], id: "c1", intent: "i", countdown: false, home: "/Users/user", described: english)
        XCTAssertEqual(card.title, "“메모 쓰기”, step 2 of 3")
        XCTAssertEqual(card.detail, "In TextEdit, choose ‘File › New’")
        XCTAssertEqual(card.spoken, "“메모 쓰기”, step 2?")
        let full = card.full ?? ""
        XCTAssertTrue(full.hasPrefix("In TextEdit, choose ‘File › New’\n") && full.contains("명령: ‘File › New’ (⌘N)") && full.contains("앱: TextEdit"), full)
        for text in [card.title, card.detail, full, card.spoken] {
            XCTAssertFalse(text.contains("$ ") || text.contains("=File") || text.contains("[cmd+n]"), text)
        }
        // A call the replay doesn't word: the command still reads as the item, not the call's syntax.
        let plain = ArisAskPlan.card([item], id: "c2", intent: "i", countdown: false, home: "/Users/user")
        XCTAssertEqual(plain.detail, "바꾸기 TextEdit ‘File › New’ (⌘N)")
        XCTAssertEqual(ArisAskPlan.commandShown("ls -la", capability: "shell.run"), "$ ls -la", "a shell line keeps its $")
    }

    func testAWordedCardKeepsEveryFactTheGateReadsBack() {
        let made = replaceAll()
        let plan = ArisTeachReplay.plan(made, given: ["p1": "New text"], words: "전체 바꾸기 해 줘", run: "d2b")
        let call = plan.calls[2]!.id
        let described = ArisTeachReplay.described(made, plan: plan, english: false)
        let arguments = plan.calls[2]!.object ?? [:]
        var facts = ArisCallFacts(capability: "app.type", arguments: ArisKeyArguments.extract(arguments, capability: "app.type"))
        facts.erases = ArisErasedText(text: "Korean keep text", keepable: true)
        let source = ArisContentSource(kind: "app", source: "TextEdit · 배운 단계")
        let item = ArisAskItem(call: call, facts: facts, effect: .changePermanent, decision: .ask, provenance: .content(source))
        let card = ArisAskPlan.card([item], id: "c3", intent: "i", countdown: false, home: "/Users/user", described: described)
        // Where it came from stays, said as it is (seventh VM run, item 6): his saved step, the value he gave, and the
        // erased text read from the app just now.
        XCTAssertTrue(card.detail.hasPrefix("저장한 단계 ‘전체 바꾸기’ 그대로예요. 지워질 글은 방금 TextEdit에서 읽었어요.\n"), "where it came from stays: \(card.detail)")
        XCTAssertTrue(card.detail.contains("지워지는 글 (16자, 1줄):") && card.detail.contains("「Korean keep text」"), "what it erases stays: \(card.detail)")
        XCTAssertTrue(card.detail.contains("TextEdit의 ‘본문’ 내용을 지우고 ‘New text’ 넣기"), card.detail)
        XCTAssertTrue((card.full ?? "").contains("내용: New text"), "its arguments are read back in full")
    }

    // MARK: - D7: a failed step asks whether to go on

    func testAFailedStepTheRestStandsOnAsksAndGoesOnOnlyOnAYes() {
        let made = replaceAll()
        let plan = ArisTeachReplay.plan(made, given: ["p1": "New text"], words: "전체 바꾸기 해 줘", run: "d7")
        let judge = Judge()
        judge.failing = [plan.calls[1]!.id]
        judge.feed(plan, owner: "전체 바꾸기 해 줘")
        var asked: [(Int, String)] = []
        let outcome = ArisTeachReplay.run(plan, ports: judge.ports(), goOn: { asked.append(($0, $1)); return true })
        XCTAssertEqual(asked.map(\.0), [1], "the menu step the typing stands on asks too (it used to stop in silence)")
        XCTAssertEqual(asked.first?.1, "“Select All” is greyed out right now")
        XCTAssertEqual(outcome, .partly(done: 2, skipped: [1]))
        XCTAssertEqual(judge.executed, plan.calls.map { $0!.id })
        XCTAssertEqual(judge.cards.count, 2, "the menu step asked on its card, and the replace after it still asked on its own")
        // No (or no answer): it stops there.
        let stopped = Judge()
        stopped.failing = [plan.calls[1]!.id]
        stopped.feed(plan, owner: "전체 바꾸기 해 줘")
        XCTAssertEqual(ArisTeachReplay.run(plan, ports: stopped.ports(), goOn: { _, _ in false }),
                       .stopped(at: 1, end: .failed("“Select All” is greyed out right now"), done: 1))
        XCTAssertEqual(stopped.executed.count, 2)
        // The last step failing has nothing left to ask about.
        let last = Judge()
        last.failing = [plan.calls[2]!.id]
        last.feed(plan, owner: "전체 바꾸기 해 줘")
        var lastAsked = 0
        XCTAssertEqual(ArisTeachReplay.run(plan, ports: last.ports(), goOn: { _, _ in lastAsked += 1; return true }),
                       .stopped(at: 2, end: .failed("“Select All” is greyed out right now"), done: 2))
        XCTAssertEqual(lastAsked, 0)
    }

    func testGoingOnCarriesNoYesAcrossSteps() {
        // A replace that asked, was allowed and failed, then the same replace again: going on, it asks again.
        let step = typed(.all)
        let made = ArisTeachProcedure(name: "두 번 바꾸기", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle), step, step],
                                      parameters: [ArisTeachParameter(key: "p1", label: "본문", example: "x", app: "TextEdit")], created: start)
        let plan = ArisTeachReplay.plan(made, given: ["p1": "New text"], words: "두 번 바꾸기 해 줘", run: "d7b")
        let judge = Judge()
        judge.failing = [plan.calls[1]!.id]
        judge.feed(plan, owner: "두 번 바꾸기 해 줘")
        var intents = 1
        let outcome = ArisTeachReplay.run(plan, ports: judge.ports(), goOn: { _, _ in true }, afresh: {
            intents += 1
            judge.intent = "teach-\(intents)"
            return judge.ports()
        })
        XCTAssertEqual(outcome, .partly(done: 2, skipped: [1]))
        XCTAssertEqual(judge.cards.count, 2, "the step after his go-on had its own card: the failed step's yes didn't cover it")
        // The same run without a fresh intent: the earlier yes would have covered it (what afresh is there to stop).
        let same = Judge()
        same.failing = [plan.calls[1]!.id]
        same.feed(plan, owner: "두 번 바꾸기 해 줘")
        _ = ArisTeachReplay.run(plan, ports: same.ports(), goOn: { _, _ in true })
        XCTAssertEqual(same.cards.count, 1)
    }

    func testTheGoOnCardNamesWhatIsLeftInTheUILanguage() {
        let made = replaceAll()
        let english = ArisTeachCopy.goOnCard(made, failedAt: 1, why: "“Select All” is greyed out right now", english: true)
        XCTAssertEqual(english.title, "Step 2 didn't work. Go on with the 1 step left?")
        XCTAssertTrue(english.detail.contains("Why: ‘Select All’ is greyed out in the menu right now") && english.detail.contains("3. In TextEdit, replace everything")
                      && english.detail.contains("may need it"), english.detail)
        let korean = ArisTeachCopy.goOnCard(made, failedAt: 1, why: "“Select All” is greyed out right now", english: false)
        XCTAssertEqual(korean.title, "2단계가 안 됐어요. 남은 1단계를 계속할까요?")
        XCTAssertEqual(ArisTeachCopy.goOnAllow(english: true), "Continue")
        XCTAssertEqual(ArisTeachCopy.goOnAllow(english: false), "계속")
        XCTAssertEqual(ArisTeachCopy.failedLine(made, at: 1, why: "“Select All” is greyed out right now", english: true),
                       "Step 2 didn't work (In TextEdit, choose ‘Edit › Select All’): ‘Select All’ is greyed out in the menu right now.")
    }

    // MARK: - M3: ↵ on the values card

    func testTheValuesCardShowsALineBreakAsTheLessonCardDoes() {
        let made = ArisTeachProcedure(name: "quick note", steps: [
            ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle),
            typed(.end),
        ], parameters: [ArisTeachParameter(key: "p1", label: "본문", example: "\nEnglish line", app: "TextEdit")], created: start)
        let missing = ArisTeachReplay.missing(made, given: [:])
        let asked = ArisTeachCopy.valuesCard(made, missing: missing, english: true)
        // The field comes up empty (eleventh VM run, T2); the suggestion shows the line break as the lesson card does.
        XCTAssertEqual(asked.fields.first?.value, "")
        XCTAssertTrue(asked.card.detail.contains("‘↵English line’"), asked.card.detail)
        XCTAssertTrue(ArisTeachReplay.answered(missing, edits: ["text": ""]).isEmpty, "left empty: nothing of his")
        XCTAssertEqual(ArisTeachReplay.answered(missing, edits: ["text": "↵English line"]), ["p1": "\nEnglish line"], "last time's value written in by them is his")
        XCTAssertEqual(ArisTeachReplay.answered(missing, edits: ["text": "↵Other line"]), ["p1": "\nOther line"], "his ↵ is a line break")
        XCTAssertEqual(ArisTeachReplay.answered(missing, edits: ["text": "Plain"]), ["p1": "Plain"])
    }
}
