// Tests for jv-quick (the owner's three decisions of 2026-11-19, to make a replay feel like "do it" → done):
// 1  the card's click hold is half a second (one named constant);
// 2  a taught procedure's run asks once, up front, on one card: their yes is a pass bound to exactly the plan shown, taken
//    a step at a time through the real Mind judge on the real trust gate; a replace still asks at its own moment, a
//    pass for another plan covers nothing, a failed step voids it, and a run with nothing to cover is as it was;
// 3  what Aris says for a card is short, in both languages, bounded, and still says what is sent, deleted or erased.
// The pure parts (the pass, which steps are covered, the card's text) are tested with `swift test`
// (Tests/ArisCoreTests/ArisTeachRunPassTests, ArisTeachRunCardTests). Nothing here observes or drives a real app.
// Called from main.swift.
import Foundation

private let quickRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func quickSource(_ path: String) -> String { (try? String(contentsOf: quickRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runQuickTests() {
    let pure = ArisAppsBook.effectContext
    ArisAppsBook.effectContext = { ArisApps.EffectContext() }
    defer { ArisAppsBook.effectContext = pure }
    quickHoldTests()
    quickQuestionTests()
    // A field's selection reads as empty here unless a test says otherwise (the gate's default is "can't be read").
    let selection = ArisTrustGate.peekSelection
    ArisTrustGate.peekSelection = { _, _ in "" }
    defer { ArisTrustGate.peekSelection = selection }
    quickRunOnceTests()
    quickTypeOverTests()
    quickFreshSelectionTests()
    quickFreshReplaceTests()
    quickWiringTests()
}

// MARK: - 1: the hold

private func quickHoldTests() {
    typealias H = ArisCardHold
    check(H.hold == 0.5, "quick 1: the hold is half a second (\(H.hold))")
    check(quickSource("Aris/private/Aris/ArisCardHold.swift").components(separatedBy: "static let hold: Double").count == 2, "quick 1: one named constant")
    // Everything else about it is as it was: counted from when the card is fully drawn, an early press dropped and noted.
    let up = H().shown("a", at: 10).entering(card: "a", at: 10)
    check(up.readyAt == 10 + H.entry + H.hold && !up.clickCounts(card: "a", at: 10 + H.entry + H.hold - 0.01) && up.clickCounts(card: "a", at: 10 + H.entry + H.hold),
          "quick 1: a click counts half a second after the card is fully drawn, not before")
    let pressed = up.refused(card: "a", at: 10.4)
    check(pressed.readyAt == up.readyAt && !pressed.clickCounts(card: "a", at: 10.41) && pressed.noteShows(card: "a", at: 10.41),
          "quick 1: an early press is dropped, never kept, and the card says it wasn't taken")
    check(H.applies(allow: true, source: .click) && !H.applies(allow: false, source: .click), "quick 1: only a yes by click waits")
}

// MARK: - 3: the short spoken question

private func quickQuestionTests() {
    typealias R = ArisConfirmReply
    func card(_ title: String, spoken: String? = nil, countdown: Bool = false) -> ArisConfirmation {
        ArisConfirmation(id: "q", title: title, detail: "d", countdown: countdown, spoken: spoken)
    }
    check(R.question(for: card("보내기 · 엄마"), english: false) == "보내기 · 엄마, 할까요?" && R.question(for: card("Send · Mom"), english: true) == "Send · Mom. Go ahead?",
          "quick 3: the action in a few words and 할까요? / Go ahead?")
    check(R.question(for: card("‘출근 준비’ 배울까요? (4단계)"), english: false) == "‘출근 준비’ 배울까요?" && R.question(for: card("지울까요? 파일 전부"), english: false) == "지울까요? 파일 전부, 할까요?"
          && R.question(for: card("‘전체 바꾸기’ 3단계 할까요?"), english: false) == "‘전체 바꾸기’ 3단계 할까요?"
          && R.question(for: card("Run “Tidy”, 3 steps?"), english: true) == "Run “Tidy”, 3 steps?",
          "quick 3: a title that ends as a question is the question")
    // A card's own short question, in the card's language, is what is asked.
    let erase = "‘전체 바꾸기’ 3단계, TextEdit 글이 지워져요. 할까요?"
    check(R.question(for: card("‘전체 바꾸기’ 3/3단계", spoken: erase), english: false) == erase, "quick 3: a replace's card still says aloud that text is erased")
    check(R.question(for: card("“전체 바꾸기”, step 3 of 3", spoken: "“전체 바꾸기” step 3 erases TextEdit’s text. OK?"), english: true)
          == "“전체 바꾸기” step 3 erases TextEdit’s text. OK?", "quick 3: in English too")
    check(R.question(for: card("글 바꾸기 · TextEdit", spoken: "1건 글 바꾸기, 할까요?"), english: true) != "1건 글 바꾸기, 할까요?"
          && R.question(for: card("보내기 · 엄마", spoken: String(repeating: "가", count: R.questionLimit + 1)), english: false) == "보내기 · 엄마, 할까요?"
          && R.question(for: card("보내기 · 엄마", spoken: "   "), english: false) == "보내기 · 엄마, 할까요?",
          "quick 3: words in another language, too long or empty are not said: the title's short question is")
    // Bounded, whatever the card: the title leads with what is done, so the cut keeps it.
    let long = String(repeating: "아주 긴 제목 ", count: 40), longEnglish = String(repeating: "a very long title ", count: 40)
    for (title, english) in [("보내기 · " + long, false), ("지우기 · " + long, false), ("결제 · " + long, false), ("Send · " + longEnglish, true), ("Delete · " + longEnglish, true)] {
        let said = R.question(for: card(title), english: english)
        check(said.count <= R.questionLimit && said.hasPrefix(String(title.prefix(4))), "quick 3: a long title is cut, its action kept (\(said.count): \(said))")
        let job = R.question(for: card(title), english: english, job: long)
        check(job.count <= R.questionLimit + R.jobLimit + 24, "quick 3: a task's question is bounded too (\(job.count))")
    }
    check(R.questionLimit == ArisTeachCopy.spokenLimit, "quick 3: the helper's short questions fit what the app will say")
    // A countdown's words and the stopped card's are as they were.
    check(R.question(for: card("메시지", spoken: "엄마한테 보낼게요.", countdown: true), english: false) == "메시지, 할까요?", "quick 3: a countdown's own words are not its question")
}

// MARK: - 2: one card for a run, through the real judge and gate

private final class QuickRig: @unchecked Sendable {
    let home: String
    let gate: ArisTrustGate
    let judge: ArisMindJudge
    let lock = NSLock()
    var cards: [ArisConfirmation] = []
    var ran: [String] = []
    var failing: Set<String> = []

    init() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-quick-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let home = URL(fileURLWithPath: folder.path).resolvingSymlinksInPath().path
        self.home = home
        gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(home: home) })
        judge = ArisMindJudge(gate: gate, tools: "/Applications/Aris.app/Contents/Helpers/aris-tools")
        judge.cardWait = 2
    }

    var runner: ArisTeachRunner {
        ArisTeachRunner(judge: judge, gate: gate) { [unowned self] item, _, _ in
            lock.withLock { ran.append(item.call.id) }
            if failing.contains(item.call.id) { return ArisMindResult(text: "that menu item isn't there now", isError: true) }
            return ArisMindResult(text: #"{"did":"done","ok":true}"#)
        }
    }

    var card: ArisMindJudge.Card {
        { [unowned self] card, answer in
            lock.withLock { cards.append(card) }
            DispatchQueue.global().async { answer(true) }
        }
    }

    var record: [ArisRecordEntry] { ArisRecordJournal.entries(home: home) }
}

private let quickBundle = "com.apple.TextEdit"
private let quickStart = Date(timeIntervalSince1970: 1_800_000_000)

private func quickMenu(_ path: [String], keys: String?) -> ArisTeachStep {
    var step = ArisTeachStep(action: .menu, app: "TextEdit", bundle: quickBundle, label: path.last, menu: path)
    step.keys = keys
    return step
}

/// "서식 정리": TextEdit opened, two menu commands chosen by their keys.
private func quickTidy() -> ArisTeachProcedure {
    ArisTeachProcedure(name: "서식 정리", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: quickBundle),
                                              quickMenu(["Edit", "Select All"], keys: "cmd+a"), quickMenu(["Format", "Make Plain Text"], keys: "cmd+shift+t")],
                       parameters: [], created: quickStart)
}

/// "전체 바꾸기", as the real-screen check ran it: TextEdit opened, Edit › Select All, the whole text replaced.
private func quickReplaceAll() -> ArisTeachProcedure {
    var typed = ArisTeachStep(action: .type, app: "TextEdit", bundle: quickBundle, target: "First Text View 칸", role: "textArea", label: ArisTeachGeneralise.bodyLabel,
                              parameter: "p1")
    typed.place = .all
    return ArisTeachProcedure(name: "전체 바꾸기", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: quickBundle),
                                                    quickMenu(["Edit", "Select All"], keys: "cmd+a"), typed],
                              parameters: [ArisTeachParameter(key: "p1", label: ArisTeachGeneralise.bodyLabel, example: "Replaced all", app: "TextEdit", fromApp: false)],
                              created: quickStart)
}

private func quickRunOnceTests() {
    typealias Pass = ArisTeachRunPass
    let tidy = quickTidy()
    let words = "서식 정리 해 줘"
    // As it was: the first menu step chosen by its key asks on its own card when it comes up (mid-run), and that yes
    // covers the next step of the same kind in the same app (the gate's one card per intent).
    let before = QuickRig()
    let old = before.runner.run(tidy, words: words, rest: "해 줘", run: "k0", card: before.card, isCurrent: { true })
    check(old.outcome == .done(steps: 3) && before.cards.map(\.title) == ["‘서식 정리’ 2/3단계"],
          "quick 2: without the one card, the step that asks has its own card mid-run as before: \(before.cards.map(\.title))")
    check(before.cards.first?.spoken == "‘서식 정리’ 2단계, 할까요?", "quick 3: a step's card comes with its short question: \(before.cards.first?.spoken ?? "")")

    // The marks for the card: which steps it covers.
    let rig = QuickRig()
    let plan = ArisTeachReplay.plan(tidy, given: [:], words: words, run: "k1")
    let marks = rig.runner.marks(plan)
    check(marks == [.runs, .covered, .covered] && Pass.asksOnce(marks), "quick 2: the open runs as ever, the two menu steps are the one card's: \(marks)")
    check(rig.record.isEmpty, "quick 2: marking the card decides nothing and records nothing")
    // His yes on the one card: the run asks nothing more.
    let ended = rig.runner.run(tidy, words: words, rest: "해 줘", run: "k1", card: rig.card, isCurrent: { true }, pass: Pass(plan: plan))
    check(ended.outcome == .done(steps: 3) && rig.cards.isEmpty && rig.ran == ["teach-k1-1", "teach-k1-2", "teach-k1-3"],
          "quick 2: with the pass every covered step runs with no card of its own: \(ended.outcome) \(rig.cards.map(\.title))")
    let lines = rig.record
    check(lines.count == 3 && lines.dropFirst().allSatisfy { $0.decision == "ask" && $0.answer == ArisTrustGate.runCardAnswer && $0.ok == true }
          && lines.first?.answer == nil,
          "quick 2: the record keeps the gate's own decision for each step and that it ran on the run's card: \(lines.map { "\($0.decision ?? "")/\($0.answer ?? "-")" })")
    check(lines.allSatisfy { $0.session == "teach-k1" } && !lines.contains { $0.provenance == .ownerSaid || $0.provenance == .ownerEarlier },
          "quick 2: one run, one session (the undo takes it back as one), and no step becomes the owner's own words")

    // A pass for another plan (another run of the same lesson) covers nothing.
    let other = QuickRig()
    let stray = Pass(plan: ArisTeachReplay.plan(tidy, given: [:], words: words, run: "zz"))
    let strayRun = other.runner.run(tidy, words: words, rest: "해 줘", run: "k2", card: other.card, isCurrent: { true }, pass: stray)
    check(strayRun.outcome == .done(steps: 3) && other.cards.count == 1, "quick 2: a pass that isn't this plan's lets nothing run: \(other.cards.count) cards")

    // The replace keeps its own card at the moment it runs, with what it erases read then.
    let replace = quickReplaceAll()
    let erasing = QuickRig()
    let peek = ArisTrustGate.peekReplaced
    ArisTrustGate.peekReplaced = { _, _ in ArisErasedText(text: "Keep text", keepable: true) }
    defer { ArisTrustGate.peekReplaced = peek }
    let replaceWords = "전체 바꾸기 해 줘, 본문은 회의는 3시"
    let given = ArisTeachMatch.values(replace, words: "해 줘, 본문은 회의는 3시")
    let replacePlan = ArisTeachReplay.plan(replace, given: given, words: replaceWords, run: "k3")
    let replaceMarks = erasing.runner.marks(replacePlan)
    check(given["p1"] == "회의는 3시" && replaceMarks == [.runs, .covered, .asksAgain], "quick 2: the replace is marked as asking again: \(replaceMarks) \(given)")
    let replaced = erasing.runner.run(replace, words: replaceWords, rest: "해 줘, 본문은 회의는 3시", run: "k3", card: erasing.card, isCurrent: { true },
                                      pass: Pass(plan: replacePlan))
    check(replaced.outcome == .done(steps: 3) && erasing.cards.map(\.title) == ["‘전체 바꾸기’ 3/3단계"] && erasing.cards.first?.detail.contains("Keep text") == true,
          "quick 2: only the replace asks, and its card shows what is erased: \(erasing.cards.map(\.title))")
    check(erasing.cards.first?.spoken == "‘전체 바꾸기’ 3단계, TextEdit 글이 지워져요. 할까요?", "quick 3: its question says the text is erased: \(erasing.cards.first?.spoken ?? "")")
    check(erasing.record.last?.answer == "yes" && erasing.record.last?.decision == "ask", "quick 2: the replace ran on its own card's yes")
    // The card for it: three steps, the replace's own line saying it asks each time.
    let card = ArisTeachCopy.runCard(replace, plan: replacePlan, marks: replaceMarks, english: false)
    check(card.card.title == "‘전체 바꾸기’ 3단계 할까요?" && card.card.detail.contains("3. TextEdit의 ‘본문’ 내용을 지우고 ‘회의는 3시’ 넣기 (원래 내용은 지워져요, 할 때마다 물어봐요)")
          && card.spoken == "‘전체 바꾸기’ 3단계, 할까요?", "quick 2: the one card names the run and lists its steps: \(card.card.detail)")

    // A step that fails voids the pass: the steps left ask on their own cards, after his go-on.
    let failing = QuickRig()
    failing.failing = ["teach-k4-2"]
    let failedPlan = ArisTeachReplay.plan(tidy, given: [:], words: words, run: "k4")
    let failed = failing.runner.run(tidy, words: words, rest: "해 줘", run: "k4", card: failing.card, isCurrent: { true }, goOn: { _, _ in true }, pass: Pass(plan: failedPlan))
    check(failed.outcome == .partly(done: 2, skipped: [1]) && failing.cards.map(\.title) == ["‘서식 정리’ 3/3단계"],
          "quick 2: after a failed step the pass is void and the step left asks: \(failed.outcome) \(failing.cards.map(\.title))")

    // A stopped run does nothing, pass or no pass.
    let stopped = QuickRig()
    let stale = stopped.runner.run(tidy, words: words, rest: "해 줘", run: "k5", card: stopped.card, isCurrent: { false },
                                   pass: Pass(plan: ArisTeachReplay.plan(tidy, given: [:], words: words, run: "k5")))
    check(stale.outcome == .stopped(at: 0, end: .stale, done: 0) && stopped.ran.isEmpty, "quick 2: a stopped run runs nothing: \(stale.outcome)")

    // Nothing the card could cover: no one card, the run as it was.
    var end = ArisTeachStep(action: .type, app: "TextEdit", bundle: quickBundle, target: "First Text View 칸", role: "textArea", label: ArisTeachGeneralise.bodyLabel,
                            parameter: "p1")
    end.place = .end
    let memo = ArisTeachProcedure(name: "메모", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: quickBundle), end, quickReplaceAll().steps[2]],
                                  parameters: quickReplaceAll().parameters, created: quickStart)
    let none = QuickRig().runner.marks(ArisTeachReplay.plan(memo, given: ["p1": "내 글"], words: "메모 해 줘", run: "k6"))
    check(none == [.runs, .runs, .asksAgain] && !Pass.asksOnce(none), "quick 2: a run with no step to cover asks no card up front: \(none)")
    // A browser's page, a payment's button: never the one card's.
    let safari = ArisTeachProcedure(name: "탭", steps: [ArisTeachStep(action: .menu, app: "Safari", bundle: "com.apple.Safari", label: "New Tab", menu: ["File", "New Tab"]),
                                                      ArisTeachStep(action: .click, app: "TextEdit", bundle: quickBundle, target: "Pay now 버튼", role: "button", label: "Pay now")],
                                    parameters: [], created: quickStart)
    let strict = QuickRig().runner.marks(ArisTeachReplay.plan(safari, given: [:], words: "탭 해 줘", run: "k7"))
    check(strict == [.asksAgain, .asksAgain], "quick 2: a browser's page and a payment ask on their own cards: \(strict)")
}

// MARK: - 2b: typing over a selection is never the one card's (security review of 3ddbef9b)

private func quickTypeOverTests() {
    typealias Pass = ArisTeachRunPass
    var end = ArisTeachStep(action: .type, app: "TextEdit", bundle: quickBundle, target: "First Text View 칸", role: "textArea", label: ArisTeachGeneralise.bodyLabel,
                            parameter: "p1")
    end.place = .end
    var caret = end
    caret.place = .caret
    let parameters = [ArisTeachParameter(key: "p1", label: ArisTeachGeneralise.bodyLabel, example: "old", app: "TextEdit", fromApp: false)]
    let open = ArisTeachStep(action: .open, app: "TextEdit", bundle: quickBundle)
    let before = ArisTrustGate.peekSelection
    defer { ArisTrustGate.peekSelection = before }

    // [open, Select All, type "x"]: the plan holds no replace, yet the typing goes over everything selected.
    let over = ArisTeachProcedure(name: "덧쓰기", steps: [open, quickMenu(["Edit", "Select All"], keys: "cmd+a"), end], parameters: parameters, created: quickStart)
    let words = "덧쓰기 해 줘, 본문은 x"
    let given = ArisTeachMatch.values(over, words: "해 줘, 본문은 x")
    for (place, typed) in [("end", end), ("caret", caret)] {
        let made = ArisTeachProcedure(name: "덧쓰기", steps: [open, over.steps[1], typed], parameters: parameters, created: quickStart)
        ArisTrustGate.peekSelection = { app, target in app == "TextEdit" && target == "First Text View 칸" ? "Keep text" : nil }
        let rig = QuickRig()
        let plan = ArisTeachReplay.plan(made, given: given, words: words, run: "o1")
        let marks = rig.runner.marks(plan)
        check(given["p1"] == "x" && marks == [.runs, .covered, .asksAgain], "quick 2b (\(place)): the up-front card says the typing asks again: \(marks)")
        check(ArisTeachCopy.runCard(made, plan: plan, marks: marks, english: false).card.detail.contains("넣기 — 이 단계 전에 다시 물어봐요"),
              "quick 2b (\(place)): and marks it plainly")
        let ended = rig.runner.run(made, words: words, rest: "해 줘, 본문은 x", run: "o1", card: rig.card, isCurrent: { true }, pass: Pass(plan: plan))
        check(ended.outcome == .done(steps: 3) && rig.cards.map(\.title) == ["‘덧쓰기’ 3/3단계"],
              "quick 2b (\(place)): under the pass the typing still asks on its own card: \(rig.cards.map(\.title))")
        let card = rig.cards.first
        check(card?.detail.contains("지워지는 글 (9자, 1줄):") == true && card?.detail.contains("「Keep text」") == true && card?.detail.contains(ArisAskPlan.erasesLost) == true,
              "quick 2b (\(place)): its card shows the text that is erased, and that it can't be put back: \(card?.detail ?? "")")
        check(card?.spoken == "‘덧쓰기’ 3단계, TextEdit 글이 지워져요. 할까요?", "quick 2b (\(place)): and says so aloud: \(card?.spoken ?? "")")
        let line = rig.record.last
        check(line?.capability == "app.type" && line?.decision == "ask" && line?.answer == "yes" && line?.effect == .changePermanent,
              "quick 2b (\(place)): the record has it as a permanent change he said yes to: \(line?.decision ?? "") \(line?.answer ?? "")")
        // With no pass at all it asks the same (the rule is the gate's, for every replay).
        let plain = QuickRig()
        _ = plain.runner.run(made, words: words, rest: "해 줘, 본문은 x", run: "o2", card: plain.card, isCurrent: { true })
        check(plain.cards.map(\.title).contains("‘덧쓰기’ 3/3단계") && plain.cards.last?.detail.contains("Keep text") == true,
              "quick 2b (\(place)): without the one card too: \(plain.cards.map(\.title))")
    }

    // [open, type] with nothing selected: as it was, no card.
    for (place, typed) in [("end", end), ("caret", caret)] {
        let made = ArisTeachProcedure(name: "메모", steps: [open, typed], parameters: parameters, created: quickStart)
        ArisTrustGate.peekSelection = { _, _ in "" }
        let rig = QuickRig()
        let plan = ArisTeachReplay.plan(made, given: ["p1": "x"], words: "메모 해 줘, 본문은 x", run: "o3")
        check(Pass(plan: plan).covered == [true, true] && rig.runner.marks(plan) == [.runs, .runs], "quick 2b (\(place)): typing with nothing selected stays covered and unmarked")
        let ended = rig.runner.run(made, words: "메모 해 줘, 본문은 x", rest: "해 줘, 본문은 x", run: "o3", card: rig.card, isCurrent: { true }, pass: Pass(plan: plan))
        check(ended.outcome == .done(steps: 2) && rig.cards.isEmpty && rig.record.last?.decision == "runWithUndo",
              "quick 2b (\(place)): and runs with its undo, no card: \(rig.cards.map(\.title)) \(rig.record.last?.decision ?? "")")
        // The selection can't be read: it asks, and the card says it couldn't be read.
        ArisTrustGate.peekSelection = { _, _ in nil }
        let blind = QuickRig()
        let unknown = blind.runner.run(made, words: "메모 해 줘, 본문은 x", rest: "해 줘, 본문은 x", run: "o4", card: blind.card, isCurrent: { true },
                                       pass: Pass(plan: ArisTeachReplay.plan(made, given: ["p1": "x"], words: "메모 해 줘, 본문은 x", run: "o4")))
        check(unknown.outcome == .done(steps: 2) && blind.cards.count == 1 && blind.cards.first?.detail.contains(ArisAskPlan.erasesUnread) == true,
              "quick 2b (\(place)): an unknown selection asks: \(blind.cards.map(\.detail))")
    }
    // The rule is for a replay's typing: a replace keeps its own read, and another session's typing is the policy's as before.
    ArisTrustGate.peekSelection = { _, _ in "Keep text" }
    let gate = QuickRig().gate
    let other = gate.decide(session: "s", call: "c1", capability: "app.type", effect: .changeReversible, arguments: ["app": "TextEdit", "target": "t", "text": "x", "at": "end"])
    // A model's typing reads its field's selection now too (exp11 security review): over selected text it erases and asks.
    check(other.facts.erases != nil && other.effect == .changePermanent, "quick 2b: a call that isn't a replay's step reads its selection the model's way")
    let live = quickSource("ArisAgent/Mind/ArisMindLive.swift")
    check(live.contains("ArisTrustGate.peekSelection = { app, target in ArisAppsHands.shared.peekSelection(app: app, target: target) }"),
          "quick 2b: wiring: the live helper reads the field's selection through the app layer")
    check(quickSource("ArisAgent/Trust/ArisTrustGate.swift").contains("static var peekSelection: (_ app: String, _ target: String?) -> String? = { _, _ in nil }"),
          "quick 2b: with no reader the selection is unknown, which asks")
}

// MARK: - 2c: the selection is read fresh at the decision, and checked again at the typing (security review of 5fa78fc2)

private final class QuickSystem: ArisAppsSystem {
    let editor = ArisAppsRunning(bundle: "com.apple.TextEdit", name: "TextEdit", pid: 701)
    func installedApps() -> [ArisApps.AppRecord] { [.init(bundle: "com.apple.TextEdit", names: ["TextEdit"], path: "/System/Applications/TextEdit.app")] }
    func runningApps() -> [ArisAppsRunning] { [editor] }
    func frontmost() -> ArisAppsRunning? { nil }
    func defaultBrowser() -> String? { "com.apple.Safari" }
    func open(_ request: ArisAppsOpenRequest) -> (ok: Bool, message: String) { (true, "opened") }
    func quit(pid: Int32) -> Bool { true }
    func hide(pid: Int32) -> Bool { true }
    func activate(pid: Int32) -> Bool { true }
    func bundleInfo(path: String) -> ArisApps.BundleInfo? { nil }
    func scriptingDictionary(path: String) -> Data? { nil }
    func includedDictionary(path: String) -> Data? { nil }
    func intentsMetadata(path: String) -> Data? { nil }
    func shortcuts() -> [String] { [] }
    func runShortcut(_ name: String, input: String?) -> (ok: Bool, output: String) { (true, "") }
    func automation(bundle: String) -> ArisApps.Grant { .notAsked }
    func runScript(_ source: String, timeout: TimeInterval) -> (ok: Bool, output: String, code: Int?) { (false, "", nil) }
    func pathKind(_ path: String) -> ArisApps.PathKind { .document }
    func displays() -> [ArisApps.Rect] { [ArisApps.Rect(x: 0, y: 25, width: 1440, height: 875)] }
}

private final class QuickAX: ArisAppsAccessibility {
    func menuBar(pid: Int32) -> ArisApps.MenuBar? { nil }
    func pressMenu(pid: Int32, path: [String]) -> (ok: Bool, message: String) { (true, "pressed") }
    func setFullScreen(pid: Int32, window: Int, on: Bool) -> Bool { true }
    func focusedRole(pid: Int32) -> String? { "textArea" }
    func caretToEnd(pid: Int32, at point: (x: Double, y: Double)?) -> ArisApps.CaretEnd { .moved }
}

/// TextEdit's one document as the engine reads it now: its text and its selected range (nil: none exposed).
private final class QuickEngine: ArisAppsEngine {
    var calls: [[String]] = []
    var text = "Keep text"
    var selection: (Int, Int)? = (9, 0)
    var seeFails = false
    func run(_ arguments: [String], background: Bool) -> ArisApps.JSON {
        calls.append(arguments)
        switch (arguments.first ?? "", arguments.dropFirst().first ?? "") {
        case ("window", "list"):
            return .object(["success": .bool(true), "data": .object(["windows": .array([.object([
                "window_id": .number(60), "window_title": .string("Untitled"), "is_frontmost": .bool(true),
                "bounds": .object(["x": .number(100), "y": .number(100), "width": .number(800), "height": .number(600)])])])])])
        case ("see", _):
            if seeFails { return .object(["success": .bool(false), "error": .object(["message": .string("no window")])]) }
            var area: [String: ArisApps.JSON] = ["id": .string("elem_1"), "role": .string("textArea"), "label": .string("First Text View"), "value": .string(text),
                                                 "bounds": .object(["x": .number(100), "y": .number(150), "width": .number(800), "height": .number(400)])]
            if let selection { area["selected_text_range"] = .object(["location": .number(Double(selection.0)), "length": .number(Double(selection.1))]) }
            return .object(["success": .bool(true), "data": .object(["snapshot_id": .string("ps_q"), "window_title": .string("Untitled"), "ui_elements": .array([.object(area)])])])
        case ("type", _):
            text += arguments[2]
            return .object(["success": .bool(true), "data": .object(["delivery": .string("typed")])])
        case ("set-value", _):
            text = arguments[6]
            return .object(["success": .bool(true), "data": .object([:])])
        default:
            return .object(["success": .bool(true), "data": .object([:])])
        }
    }
    var typed: Bool { calls.contains { $0.first == "type" } }
    var replaced: Bool { calls.contains { $0.first == "set-value" } }
}

private func quickHands() -> (ArisAppsHands, QuickEngine) {
    let engine = QuickEngine()
    let hands = ArisAppsHands(system: QuickSystem(), ax: QuickAX(), engine: engine, store: ArisAppsMemoryStore())
    hands.pollSeconds = 0
    return (hands, engine)
}

private func quickFreshSelectionTests() {
    let field = "First Text View 칸"
    // A read kept from before (nothing selected), then Select All in the app: the decision must see what is selected now.
    do {
        let (hands, engine) = quickHands()
        _ = hands.call("app.read", .object(["app": .string("TextEdit")]))
        check(hands.peekSelection(app: "TextEdit", target: field) == "", "quick 2c: nothing selected reads as nothing")
        engine.selection = (0, 9)
        let seen = hands.peekSelection(app: "TextEdit", target: field)
        check(seen == "Keep text", "quick 2c: a kept read saying nothing is selected is never the answer: the field is read again (\(seen ?? "nil"))")
        check(!engine.calls.contains { ["click", "type", "set-value", "press"].contains($0.first ?? "") }, "quick 2c: reading the selection does nothing else")
        // An element id names a kept read's element: what it holds now can't be told.
        check(hands.peekSelection(app: "TextEdit", target: "e1") == nil, "quick 2c: an element id of a kept read is unknown")
        // The fresh read fails: unknown, whatever was kept.
        engine.selection = (9, 0)
        _ = hands.call("app.read", .object(["app": .string("TextEdit")]))
        engine.seeFails = true
        check(hands.peekSelection(app: "TextEdit", target: field) == nil, "quick 2c: a read that fails is unknown, never the kept one")
        engine.seeFails = false
        engine.selection = nil
        check(hands.peekSelection(app: "TextEdit", target: field) == nil, "quick 2c: a field that shows no selection range is unknown")
    }
    // Through the gate: the kept read says empty, the app has everything selected, and the replay's typing gets its card.
    do {
        let (hands, engine) = quickHands()
        _ = hands.call("app.read", .object(["app": .string("TextEdit")]))
        engine.selection = (0, 9)
        let before = ArisTrustGate.peekSelection
        ArisTrustGate.peekSelection = { app, target in hands.peekSelection(app: app, target: target) }
        defer { ArisTrustGate.peekSelection = before }
        var end = ArisTeachStep(action: .type, app: "TextEdit", bundle: quickBundle, target: field, role: "textArea", label: ArisTeachGeneralise.bodyLabel, parameter: "p1")
        end.place = .end
        let made = ArisTeachProcedure(name: "메모", steps: [end],
                                      parameters: [ArisTeachParameter(key: "p1", label: ArisTeachGeneralise.bodyLabel, example: "old", app: "TextEdit", fromApp: false)], created: quickStart)
        let rig = QuickRig()
        _ = rig.runner.run(made, words: "메모 해 줘, 본문은 x", rest: "해 줘, 본문은 x", run: "f1", card: rig.card, isCurrent: { true })
        check(rig.cards.count == 1 && rig.cards.first?.detail.contains("「Keep text」") == true,
              "quick 2c: a stale kept read never lets the typing go without its card: \(rig.cards.map(\.detail))")
    }
    // At the typing: the mark says what the decision saw; the field as read right then must show the same.
    func type(_ mark: String?, selection: (Int, Int)?, target: String = field) -> (ArisApps.Outcome, QuickEngine) {
        let (hands, engine) = quickHands()
        _ = hands.call("app.read", .object(["app": .string("TextEdit")]))   // a kept read with nothing selected
        engine.selection = selection
        var arguments: [String: ArisApps.JSON] = ["app": .string("TextEdit"), "text": .string(" more"), "target": .string(target), "at": .string("end")]
        if let mark { arguments[ArisApps.TypeOver.argument] = .string(mark) }
        return (hands.call("app.type", .object(arguments)), engine)
    }
    let empty = ArisApps.TypeOver.empty
    let silent = type(empty, selection: (0, 9))
    check(!silent.0.ok && !silent.1.typed && silent.1.text == "Keep text" && silent.0.did.contains("the selection changed since this step was checked"),
          "quick 2c: the decision saw nothing selected and text is selected at the typing: nothing is typed (\(silent.0.did))")
    check(ArisTeachCopy.reason(silent.0.did, english: false) == "확인한 뒤에 선택된 글이 바뀌어서 넣지 않았어요", "quick 2c: and the reason is said in Korean")
    let fine = type(empty, selection: (9, 0))
    check(fine.0.ok && fine.1.typed && fine.1.text == "Keep text more", "quick 2c: still nothing selected: it types (\(fine.0.did))")
    // A field named by a read's id is found again in a look taken at the typing (exp11, item 1) and checked as it is then.
    check(!type(empty, selection: nil).1.typed && type(empty, selection: (9, 0), target: "e1").1.typed && !type(empty, selection: (0, 9), target: "e1").1.typed,
          "quick 2c: a selection that can't be read at the typing types nothing; a read's id is checked against the field as it is now")
    let seen = ArisApps.TypeOver.mark(erases: ArisErasedText(text: "Keep text", keepable: false))
    check(type(seen, selection: (0, 9)).1.typed && !type(seen, selection: (0, 4)).1.typed && !type(seen, selection: (9, 0)).1.typed,
          "quick 2c: their yes to a card that showed the selected text is for exactly that selection")
    // A yes to "couldn't be read" types only while it still can't be read: text the card never showed stops it (exp11, item 1).
    check(!type(ArisApps.TypeOver.any, selection: (0, 4)).1.typed && type(ArisApps.TypeOver.any, selection: (9, 0)).1.typed && type(nil, selection: (0, 9)).1.typed,
          "quick 2c: a yes to \"couldn't be read\" never types over text that can be read by then; a call with no mark is as it was")
    // The replay marks its typing from what the gate decided.
    let read = ArisMindJudge.Read(entry: ArisCapabilityBook.entry(named: "app_type")!, arguments: ["app": "TextEdit", "text": "x", "target": field, "at": "end"], argv: nil, stdin: nil)
    check(ArisTeachRunner.typing(read, erases: nil)[ArisApps.TypeOver.argument] as? String == empty
          && ArisTeachRunner.typing(read, erases: ArisErasedText(text: "Keep text", keepable: false))[ArisApps.TypeOver.argument] as? String == seen
          && ArisTeachRunner.typing(read, erases: ArisErasedText(text: nil, keepable: false))[ArisApps.TypeOver.argument] as? String == ArisApps.TypeOver.any,
          "quick 2c: the replay's typing carries what its decision saw")
    let menu = ArisMindJudge.Read(entry: ArisCapabilityBook.entry(named: "app_do")!, arguments: ["app": "TextEdit", "command": "Edit › Copy"], argv: nil, stdin: nil)
    check(ArisTeachRunner.typing(menu, erases: nil)[ArisApps.TypeOver.argument] == nil, "quick 2c: a step that types nothing carries no mark")
    let desk = quickSource("ArisAgent/Teach/ArisTeachDesk.swift")
    check(desk.contains("let arguments = Self.typing(read, erases: judge.outcome(session: caller.session ?? \"\", call: item.call.id)?.facts.erases)")
          && desk.contains(".run(read.entry, arguments: arguments,"), "quick 2c: wiring: the replay runs its typing with that mark")
}

// MARK: - 2d: what a replace erases is read fresh for its card, and checked again at the replace

private func quickFreshReplaceTests() {
    let field = "First Text View 칸"
    // A read kept from before, then the document changes: the card must show what is there now.
    do {
        let (hands, engine) = quickHands()
        _ = hands.call("app.read", .object(["app": .string("TextEdit")]))
        engine.text = "New text he wrote since"
        let seen = hands.peekField(app: "TextEdit", target: field)
        check(seen == "New text he wrote since", "quick 2d: a kept read is never what a replace's card shows: the field is read again (\(seen ?? "nil"))")
        check(!engine.calls.contains { ["click", "type", "set-value", "press"].contains($0.first ?? "") }, "quick 2d: reading it does nothing else")
        check(hands.peekField(app: "TextEdit", target: "e1") == nil, "quick 2d: an element id of a kept read is unknown")
        engine.seeFails = true
        check(hands.peekField(app: "TextEdit", target: field) == nil, "quick 2d: a read that fails is unknown, never the kept one")
    }
    // Through the gate: the replay's replace card shows the text as it is now, and says so when it can't be read.
    do {
        let (hands, engine) = quickHands()
        _ = hands.call("app.read", .object(["app": .string("TextEdit")]))
        engine.text = "New text he wrote since"
        let before = ArisTrustGate.peekReplaced
        ArisTrustGate.peekReplaced = { app, target in ArisErasedText(text: hands.peekField(app: app, target: target), keepable: true) }
        defer { ArisTrustGate.peekReplaced = before }
        let made = ArisTeachProcedure(name: "바꾸기", steps: [quickReplaceAll().steps[2]], parameters: quickReplaceAll().parameters, created: quickStart)
        let rig = QuickRig()
        _ = rig.runner.run(made, words: "바꾸기 해 줘, 본문은 x", rest: "해 줘, 본문은 x", run: "r1", card: rig.card, isCurrent: { true })
        check(rig.cards.count == 1 && rig.cards.first?.detail.contains("「New text he wrote since」") == true && rig.cards.first?.detail.contains("Keep text") == false,
              "quick 2d: the replace's card shows what is erased now, never a kept read: \(rig.cards.map(\.detail))")
        engine.seeFails = true
        let blind = QuickRig()
        _ = blind.runner.run(made, words: "바꾸기 해 줘, 본문은 x", rest: "해 줘, 본문은 x", run: "r2", card: blind.card, isCurrent: { true })
        check(blind.cards.count == 1 && blind.cards.first?.detail.contains(ArisAskPlan.erasesUnread) == true,
              "quick 2d: unread, it is still a card, and the card says so: \(blind.cards.map(\.detail))")
    }
    // At the replace: the field as read right then must hold what the card showed.
    func replace(_ mark: String?, holds: String, target: String = field) -> (ArisApps.Outcome, QuickEngine) {
        let (hands, engine) = quickHands()
        _ = hands.call("app.read", .object(["app": .string("TextEdit")]))   // a kept read holding "Keep text"
        engine.text = holds
        var arguments: [String: ArisApps.JSON] = ["app": .string("TextEdit"), "text": .string("회의는 3시"), "target": .string(target), "replace": .bool(true)]
        if let mark { arguments[ArisApps.TypeOver.argument] = .string(mark) }
        return (hands.call("app.type", .object(arguments)), engine)
    }
    let shown = ArisApps.TypeOver.mark(erases: ArisErasedText(text: "Keep text", keepable: true))
    let changed = replace(shown, holds: "Something he wrote after the card")
    check(!changed.0.ok && !changed.1.replaced && changed.1.text == "Something he wrote after the card"
          && changed.0.did.contains("what the field holds changed since this step was checked"),
          "quick 2d: the card showed one text and the field holds another at the replace: nothing is replaced (\(changed.0.did))")
    check(ArisTeachCopy.reason(changed.0.did, english: false) == "확인한 뒤에 칸의 글이 바뀌어서 바꾸지 않았어요", "quick 2d: and the reason is said in Korean")
    let same = replace(shown, holds: "Keep text")
    check(same.0.ok && same.1.replaced && same.1.text == "회의는 3시", "quick 2d: the same text as the card showed: it is replaced (\(same.0.did))")
    // A read's id is found again in a look taken at the replace (exp11, item 1): set only when it holds what the card showed.
    check(replace(shown, holds: "Keep text", target: "e1").1.replaced && !replace(shown, holds: "Something else", target: "e1").1.replaced,
          "quick 2d: a marked replace by a read's id goes by the field as it is now, never by the kept read")
    check(!replace(ArisApps.TypeOver.any, holds: "anything").1.replaced && replace(nil, holds: "anything").1.replaced,
          "quick 2d: a yes to \"couldn't be read\" never replaces text that can be read by then (exp11, item 1); a call with no mark is as it was")
    let read = ArisMindJudge.Read(entry: ArisCapabilityBook.entry(named: "app_type")!, arguments: ["app": "TextEdit", "text": "x", "target": field, "replace": true], argv: nil, stdin: nil)
    check(ArisTeachRunner.typing(read, erases: ArisErasedText(text: "Keep text", keepable: true))[ArisApps.TypeOver.argument] as? String == shown
          && ArisTeachRunner.typing(read, erases: ArisErasedText(text: nil, keepable: false))[ArisApps.TypeOver.argument] as? String == ArisApps.TypeOver.any,
          "quick 2d: the replay's replace carries the text its card showed, or that it couldn't be read")
}

// MARK: - Wiring

private func quickWiringTests() {
    let turn = quickSource("ArisAgent/Teach/ArisTeachTurn.swift")
    let once = turn.range(of: "let once = ArisTeachRunPass.asksOnce(marks)"), made = turn.range(of: "ArisTeachRunPass(plan: ArisTeachReplay.plan(procedure, given: given.merging(answered) { $1 }, words: words, run: run))")
    let yes = turn.range(of: "guard case .yes(let edits)? = reply.get() else {"), hold = turn.range(of: "hands.beginFrontHold()")
    let run = turn.range(of: "}, goOn: goOn, english: english, pass: pass, carryingAll: true)")
    check(once != nil && made != nil && yes != nil && hold != nil && run != nil && once!.upperBound < yes!.lowerBound && yes!.upperBound < made!.lowerBound
          && made!.upperBound < hold!.lowerBound && hold!.upperBound < run!.lowerBound,
          "quick 2: wiring: the one card is asked before anything runs, the pass is made only after their yes, from the plan with their values, and handed to the run")
    check(turn.contains("spoken: whole?.spoken") && turn.contains("full: asked.card.full"), "quick 2: wiring: the card carries its short question and its whole text")
    let desk = quickSource("ArisAgent/Teach/ArisTeachDesk.swift")
    check(desk.contains("approval: pass.map { approval($0, session: session) })") && desk.contains("let afresh = { () -> ArisMindPorts in"),
          "quick 2: wiring: the pass goes to the run; the ports after a failed step are made without it")
    let replay = quickSource("Shared/Core/Teach/ArisTeachReplay.swift")
    check(replay.contains("pass?.void(.failed(at: index))") && replay.contains("approval?.box.void(.stopped)")
          && replay.contains("if let afresh { watched = watching(afresh()) }"),
          "quick 2: wiring: a failed step and the run's end void the pass, and the steps after a failure run on ports with no pass")
    let once2 = quickSource("ArisAgent/Teach/ArisTeachRunOnce.swift")
    check(once2.contains("judge.outcome(session: session, call: call).map(Self.judged)") && once2.contains("content: outcome.verdict.provenance.source != nil"),
          "quick 2: wiring: the pass goes by the gate's own decision of each call, and a provenance warning makes the step ask")
}
