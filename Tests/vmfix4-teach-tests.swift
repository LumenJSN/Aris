// Tests for jv-vmfix4 defect 3, the second VM run's lesson (aris-vmcheck notes2/taught.json, t4-record.txt,
// cap2/t3-card-*.jpg, t4-replay-*.jpg): TextEdit, ⌘N, a line typed, "다 했어" typed into Aris's composer. Saved were 13
// steps: TextEdit's own font controls as "chose" steps, the composer's ⌘A, ⌘V and Return as TextEdit's, the text named
// "First Text View"; the save card hid its buttons; the replay stopped at the font step without asking. Here: the live
// observer gives keys to the app that has the keyboard at that instant and clicks to the app they land in (source); the
// desk, fed the run's events, hands on a lesson of three steps; the save card's buttons are in a footer outside its
// scroller (source); and a run whose value step fails asks on a card whether to go on (wiring). The pure parts are in
// Tests/ArisCoreTests/ArisTeachVMTests. Nothing here observes a real app. Called from main.swift; uses its check().
import Foundation

private let vmfix4TeachRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

private func vmfix4TeachSource(_ path: String) -> String { (try? String(contentsOf: vmfix4TeachRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

private final class Vmfix4TeachObserver: ArisTeachObserving {
    var sink: ((ArisTeachEvent) -> Void)?
    func start(sink: @escaping (ArisTeachEvent) -> Void) -> Bool { self.sink = sink; return true }
    func stop() { sink = nil }
}

func runVmfix4TeachTests() {
    vmfix4TeachObserverSourceTests()
    vmfix4TeachDeskTests()
    vmfix4TeachCardTests()
    vmfix4TeachReplayWiringTests()
}

/// (a) Keys go to the app that has the keyboard at that instant (Accessibility), never the menu bar's app; Aris's own
/// keys and clicks reach the recorder as Aris's; clicks on a pop-up are kept so its choice can be told from the app's.
private func vmfix4TeachObserverSourceTests() {
    let live = vmfix4TeachSource("ArisAgent/Teach/ArisTeachLiveObserver.swift")
    let keys = live.components(separatedBy: "private func pressed(_ event: CGEvent)").last ?? ""
    check(!keys.contains("NSWorkspace.shared.frontmostApplication") && keys.contains("let keyboard = keyboardApp()")
          && live.contains("guard let pid = ArisFrontLive.focusedPid(), let app = app(pid) else { return nil }"),
          "vmfix4 teach (a): a key goes to the app with the keyboard at that instant (Accessibility), never the app whose menu bar shows")
    check(keys.contains("if ArisTeachPrivacy.isOwnApp(keyboard.app) { return emit(ArisTeachEvent(.shortcut, at: Date(), app: keyboard.app, keys: keys)) }")
          && keys.contains("if ArisTeachPrivacy.isOwnApp(keyboard.app) { return emit(ArisTeachEvent(.input, at: Date(), app: keyboard.app, input: .key)) }"),
          "vmfix4 teach (a): a key in Aris's composer reaches the recorder as Aris's (which keeps nothing while Aris has the keyboard), its field unread")
    check(live.contains("private func inFront(_ pid: pid_t) -> Bool { ArisFrontLive.frontPid() == pid }"),
          "vmfix4 teach (a): an app's own changes count only while it, not Aris's notch, has the keyboard")
    let clicks = live.components(separatedBy: "private func clicked(at point: CGPoint)").last?.components(separatedBy: "private func startKeyTap()").first ?? ""
    check(clicks.contains("if ArisTeachPrivacy.isOwnApp(app) { return emit(ArisTeachEvent(.input, at: Date(), app: app, input: .click)) }")
          && clicks.contains("emit(ArisTeachEvent(.input, at: Date(), app: app, element: Self.describe(clicked), input: .click))")
          && clicks.contains("if Self.inMenu.contains(role) { return }") && !clicks.contains("inFront(pid)"),
          "vmfix4 teach (a, b): a click is the owner's on the app it lands in (Aris's too), on the element it hits; a click inside an open menu is part of the choice")
    check(live.contains("\"menuButton\", \"popUpButton\", \"row\""), "vmfix4 teach (b): a click on a pop-up is kept, so a choice needs it")
}

private let vmfix4Start = Date(timeIntervalSince1970: 1_800_000_000)
private func vmfix4At(_ seconds: Double) -> Date { vmfix4Start.addingTimeInterval(seconds) }

/// The VM run's events as the observer reports them now (the fixture behind notes2/taught.json).
private func vmfix4TeachRun() -> [ArisTeachEvent] {
    let textEdit = ArisTeachApp(bundle: "com.apple.TextEdit", name: "TextEdit"), aris = ArisTeachApp(bundle: "com.lumenjsn.aris", name: "Aris")
    let view = ArisTeachElement(role: "textArea", label: "First Text View")
    let controls = [(ArisTeachElement(role: "popUpButton", label: "typeface"), "Helvetica"), (ArisTeachElement(role: "popUpButton", label: "style"), "Regular"),
                    (ArisTeachElement(role: "comboBox", label: "font size"), "12"), (ArisTeachElement(role: "popUpButton", label: "line spacing"), "1.0")]
    let font = { (time: Double) in
        controls.enumerated().flatMap { index, control in
            [ArisTeachEvent(.input, at: vmfix4At(time + Double(index) * 0.02 - 0.005), app: textEdit, input: .hand),
             ArisTeachEvent(.valueChanged, at: vmfix4At(time + Double(index) * 0.02), app: textEdit, element: control.0, value: control.1)]
        }
    }
    var events = [ArisTeachEvent(.appActivated, at: vmfix4At(0.5), app: textEdit),
                  ArisTeachEvent(.shortcut, at: vmfix4At(1), app: textEdit, element: view, keys: "cmd+n"),
                  ArisTeachEvent(.menuChosen, at: vmfix4At(1.1), app: textEdit, menu: ["File", "New"]),
                  ArisTeachEvent(.windowOpened, at: vmfix4At(1.3), app: textEdit, window: "Untitled 3"),
                  ArisTeachEvent(.focused, at: vmfix4At(1.4), app: textEdit, element: view)] + font(1.5)
    for (index, end) in [1, 8, 13, 23].enumerated() {
        let time = 3 + Double(index) * 0.5
        events += [ArisTeachEvent(.input, at: vmfix4At(time), app: textEdit, element: view, input: .key),
                   ArisTeachEvent(.valueChanged, at: vmfix4At(time + 0.01), app: textEdit, element: view, value: String("Shopping list milk eggs".prefix(end)))]
        if index == 0 { events += font(time + 0.05) }
    }
    events.append(ArisTeachEvent(.input, at: vmfix4At(8), app: aris, input: .click))
    events += (0..<4).map { ArisTeachEvent(.input, at: vmfix4At(8.5 + Double($0) * 0.2), app: aris, input: .key) }
    events += font(9.4)
    events += ["cmd+a", "cmd+v", "return"].enumerated().map { ArisTeachEvent(.shortcut, at: vmfix4At(9.5 + Double($0.offset) * 0.2), app: aris, keys: $0.element) }
    return events
}

/// The worked example through the helper's desk: open TextEdit, File › New, type [본문].
private func vmfix4TeachDeskTests() {
    let observer = Vmfix4TeachObserver()
    var clock = vmfix4Start
    let desk = ArisTeachDesk(observer: observer, now: { clock })
    check(desk.start(name: "메모 쓰기") == .started, "vmfix4 teach: the desk starts watching")
    for event in vmfix4TeachRun() {
        clock = event.at
        observer.sink?(event)
    }
    clock = vmfix4At(11)
    guard let lesson = desk.stop(), case .success(let made) = ArisTeachGeneralise.procedure(lesson) else {
        return check(false, "vmfix4 teach: the VM run makes a procedure")
    }
    check(made.steps.map(\.capability) == ["app.open", "app.do", "app.type"] && made.steps[1].menuPath == "File › New",
          "vmfix4 teach: the VM lesson is open TextEdit, File › New, type the text: \(made.steps.map(\.capability))")
    check(made.parameters.map(\.label) == ["본문"] && made.parameters.first?.example == "Shopping list milk eggs" && made.steps[2].parameter == "p1",
          "vmfix4 teach (e): the text is a parameter named 본문: \(made.parameters.map(\.label))")
    let card = ArisTeachCopy.saveCard(made, replacing: false, english: false)
    check(card.title == "‘메모 쓰기’ 배울까요? (3단계)" && !card.detail.contains("⌘A") && !card.detail.contains("Return") && !card.detail.contains("typeface")
          && !card.detail.contains("font size"), "vmfix4 teach (a, b): no composer keys and no font controls on the card: \(card.detail)")
}

/// (c) The save card's buttons stay in a footer under its scroller.
private func vmfix4TeachCardTests() {
    let card = vmfix4TeachSource("Aris/private/Aris/Home/ArisConfirmCard.swift")
    let confirm = card.components(separatedBy: "private var confirmCard: some View {").last?.components(separatedBy: "var header: some View {").first ?? ""
    let scroller = confirm.components(separatedBy: "ArisFadingScroll(").last?.components(separatedBy: "            buttons\n").first ?? ""
    check(confirm.contains("ArisFadingScroll(budget: Self.scrollBudget(budget), refresh: question.id,") && confirm.contains("            buttons\n                .padding(.bottom, Self.verticalPadding)")
          && !scroller.contains("buttons") && scroller.contains("header") && scroller.contains("details"),
          "vmfix4 teach (c): only the title and details scroll; 취소 and 허용 are a footer under the scroller")
    check(!confirm.contains(".overlay(alignment: .bottomTrailing)") && !card.contains("allowLabel.hidden()")
          && card.contains("            .help(ArisConfirmWords.noHelp(english: english))\n            allow\n"),
          "vmfix4 teach (c): 허용 sits in the footer beside 취소, never floated over the card's text")
    check(card.contains("max(min(maxHeight, budget) - footerHeight - verticalPadding, 44)") && card.contains("static var footerHeight: CGFloat { allowLane + verticalPadding }"),
          "vmfix4 teach (c): the scroller's room is the card's less the footer, so the whole card still fits its room")
    // Still read to its end before a yes counts (ArisCardRead), and still held while it settles (ArisCardStill).
    check(card.contains("ArisCardEdit.allAccepted(question.fields, editor.values(for: question))) && read") && card.contains(".disabled(!ready)")
          && card.contains(".opacity(!ready ? Self.restOpacity : held ? Self.heldOpacity : 1)"),
          "vmfix4 teach (c): the yes still waits until the card was read to its end and has settled")
}

/// (d) A run's "go on?" card: the turn puts it up on the run's stream and goes on only on their yes.
private func vmfix4TeachReplayWiringTests() {
    let turn = vmfix4TeachSource("ArisAgent/Teach/ArisTeachTurn.swift")
    check(turn.contains("let asked = ArisTeachCopy.goOnCard(procedure, failedAt: index, why: why, english: english)")
          && turn.contains("if case .yes = reply { yes.set(true) }") && turn.contains("stream(.confirm(shown), on: connection)")
          && turn.contains("}, goOn: goOn, english: english, pass: pass, carryingAll: true)"),
          "vmfix4 teach (d): a failed step the rest doesn't stand on asks on a card, and only a yes goes on")
    check(turn.contains("let given = ArisTeachMatch.values(procedure, words: rest)\n            let missing = ArisTeachReplay.missing(procedure, given: given)")
          && turn.contains("let fields = asked.fields.map { ArisMCPCardField(key: $0.key, role: .text, value: $0.value) }")
          && turn.contains("guard case .yes(let edits)? = reply.get() else {") && turn.contains("answered = ArisTeachReplay.answered(missing, edits: edits)")
          && turn.contains("runner.run(procedure, words: words, rest: rest, answered: answered,") && turn.contains("var runner = ArisTeachRunner()"),
          "vmfix4 teach (d): a run whose words give no value asks for it first, last time's value on the card; a no runs nothing")
    let desk = vmfix4TeachSource("ArisAgent/Teach/ArisTeachDesk.swift")
    check(desk.contains("let given = ArisTeachMatch.values(procedure, words: rest).merging(answered) { $1 }"), "vmfix4 teach (d): the card's values are the run's own")
    check(desk.contains("ArisTeachReplay.run(plan, ports: ports, progress: progress, goOn: goOn, afresh: afresh,"), "vmfix4 teach (d): the runner passes the question on")
    let english = ArisTeachCopy.goOnCard(ArisTeachProcedure(name: "memo", steps: [
        ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit"),
        ArisTeachStep(action: .select, app: "TextEdit", bundle: "com.apple.TextEdit", target: "typeface 메뉴", role: "popUpButton", label: "typeface", option: "Helvetica"),
        ArisTeachStep(action: .press, app: "TextEdit", bundle: "com.apple.TextEdit", keys: "cmd+s"),
    ], parameters: [], created: vmfix4Start), failedAt: 1, why: "no option", english: true)
    check(english.title == "Step 2 didn't work. Go on with the 1 step left?" && english.detail.contains("3. In TextEdit, press ⌘S"),
          "vmfix4 teach (d): the card says which step and what is left, in English too")
}
