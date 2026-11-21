// Tests for jv-vmfix5 defects 1, 2 and the lesson's part of 4, the third VM run (aris-vmcheck notes3/I5-taught.txt,
// I5b-taught.json, I5c-replay-actions.txt; cap3/I5-teach-done-8s.jpg, I5b-teach-done-8s.jpg, I5c-before.jpg,
// I5c-after.jpg). D1: a lesson kept how TextEdit was reached (Finder, ⌘Space, Spotlight, Return) and lost the line typed
// into the window ⌘N opened (TextEdit, just launched, was never observed); File › New chosen with the mouse was lost
// (Aris's composer still had the keyboard) and Return split one text into two values. D2: a replay set the document's
// whole value (app.type replace) and wiped "Existing line keep". D4: the lesson's card and account followed the request's
// language, not the UI's. The pure parts are in Tests/ArisCoreTests/ArisTeachVM3Tests. Nothing here observes a real app.
// Called from main.swift; uses its check().
import Foundation

private let vmfix5TeachRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func vmfix5TeachSource(_ path: String) -> String { (try? String(contentsOf: vmfix5TeachRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

/// A fake observer that, like the live one, reads the text view his keys went into again when the lesson ends.
private final class Vmfix5TeachObserver: ArisTeachObserving {
    var sink: ((ArisTeachEvent) -> Void)?
    var read: [ArisTeachEvent] = []
    func start(sink: @escaping (ArisTeachEvent) -> Void) -> Bool { self.sink = sink; return true }
    func stop() { sink = nil }
    func closing() -> [ArisTeachEvent] { read }
}

func runVmfix5TeachTests() {
    vmfix5TeachDeskTests()
    vmfix5TeachObserverSourceTests()
    vmfix5TeachReplaceTests()
    vmfix5TeachLanguageTests()
}

/// D1: the desk hands the value read at the end to the recorder before it stops, so lesson 1 keeps its line.
private func vmfix5TeachDeskTests() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var clock = start
    let observer = Vmfix5TeachObserver()
    let desk = ArisTeachDesk(observer: observer, now: { clock })
    let finder = ArisTeachApp(bundle: "com.apple.finder", name: "Finder"), spotlight = ArisTeachApp(bundle: "com.apple.Spotlight", name: "Spotlight")
    let textEdit = ArisTeachApp(bundle: "com.apple.TextEdit", name: "TextEdit")
    let view = ArisTeachElement(role: "textArea", label: "", identifier: "First Text View")
    check(desk.start(name: "메모 쓰기") == .started, "vmfix5 D1: the lesson starts")
    let at = { (seconds: Double) in start.addingTimeInterval(seconds) }
    var events = [ArisTeachEvent(.appActivated, at: at(0.1), app: finder), ArisTeachEvent(.shortcut, at: at(2), app: finder, keys: "cmd+space"),
                  ArisTeachEvent(.appActivated, at: at(2.2), app: spotlight), ArisTeachEvent(.shortcut, at: at(4.5), app: spotlight, keys: "return"),
                  ArisTeachEvent(.appActivated, at: at(6), app: textEdit), ArisTeachEvent(.shortcut, at: at(8), app: textEdit, element: view, keys: "cmd+n")]
    events += (0..<15).map { ArisTeachEvent(.input, at: at(9 + Double($0) * 0.1), app: textEdit, element: view, input: .key) }
    for event in events {
        clock = event.at
        observer.sink?(event)
    }
    observer.read = [ArisTeachEvent(.valueChanged, at: at(10.4), app: textEdit, element: view, value: "Lesson line one", before: "")]
    clock = at(20)
    guard let lesson = desk.stop(), case .success(let made) = ArisTeachGeneralise.procedure(lesson) else {
        return check(false, "vmfix5 D1: the lesson becomes steps")
    }
    check(made.steps.map(\.action) == [.open, .press, .type] && made.apps == ["TextEdit"],
          "vmfix5 D1: the VM's lesson 1 is open TextEdit / ⌘N / the typed line, nothing of Finder or Spotlight")
    check(made.parameters.first?.example == "Lesson line one", "vmfix5 D1: the line typed into the new window is kept")
}

/// D1: the live observer (source): registrations checked and tried again, the app in front polled, typed elements read
/// again at the end, menus chosen by the mouse's release or Return, a shortcut told as its menu command.
private func vmfix5TeachObserverSourceTests() {
    let live = vmfix5TeachSource("ArisAgent/Teach/ArisTeachLiveObserver.swift")
    check(live.contains("guard Self.needed.isSubset(of: took) else {") && live.contains("return retry(pid)")
          && live.contains("for pid in Array(pending.keys) { attach(pid) }"),
          "vmfix5 D1: an app still starting is observed once its registrations take, tried again with each poll")
    check(live.contains("let timer = Timer(timeInterval: Self.pollEvery, repeats: true) { [weak self] _ in self?.poll() }")
          && live.contains("if let pid = ArisFrontLive.frontPid(), pid != lastFront"),
          "vmfix5 D1: the app in front is asked for while the lesson runs, not only told by AppKit")
    check(live.contains("func closing() -> [ArisTeachEvent] {") && live.contains("typed(into: element, app: keyboard.app, described: described, at: now)"),
          "vmfix5 D1: a text element his keys go into is read again when the lesson ends")
    check(live.contains("if type == .leftMouseUp { observer.released(at: event.location) }")
          && live.contains("if notification == kAXMenuItemSelectedNotification { return highlighted = (pid, element, now) }")
          && live.contains("if role == \"menuBar\" || role == \"menuBarItem\" { return emit(ArisTeachEvent(.input, at: Date(), app: app, input: .click)) }"),
          "vmfix5 D1: a menu item is chosen by the mouse let go on it, whoever has the keyboard; hovering chooses nothing")
    // Fourth VM run, D2: from the menu bar read when the app was attached, never walked on the main thread at the key.
    check(live.contains("if let path = ArisTeachMenuKeys.command(for: keys, in: items) {"),
          "vmfix5 D1: a shortcut that is a menu command's key equivalent is that command")
    let desk = vmfix5TeachSource("ArisAgent/Teach/ArisTeachDesk.swift")
    check(desk.contains("let read = observer.closing()") && desk.contains("recorder.close(read)"), "vmfix5 D1: the desk keeps what was read at the end")
}

/// D2: a taught text step inserts; a whole value is set only when the lesson replaced it, and that asks.
private func vmfix5TeachReplaceTests() {
    let step = ArisTeachStep(action: .type, app: "TextEdit", bundle: "com.apple.TextEdit", target: "First Text View 칸", role: "textArea", label: "본문", text: "Milk")
    let inserts = step.arguments(values: [:]) ?? [:]
    check(inserts["at"] == .string("end") && inserts["replace"] == nil, "vmfix5 D2: a taught text step adds after what is there (at=end), never replace")
    var replacing = step
    replacing.place = .all
    check(replacing.arguments(values: [:])?["replace"] == .bool(true), "vmfix5 D2: only a lesson that replaced the text replaces it")
    let context = ArisApps.EffectContext()
    let typeSpec = ArisApps.Spec.named("app.type")
    check(typeSpec?.effect(.object(["app": .string("TextEdit"), "text": .string("Milk"), "at": .string("end")]), context) == .changeReversible,
          "vmfix5 D2: inserting is a reversible change")
    check(typeSpec?.effect(.object(["app": .string("TextEdit"), "text": .string("Milk"), "replace": .bool(true)]), context) == .changePermanent,
          "vmfix5 D2: setting a field's whole value is destructive (change-permanent), as the desktop effect rules have it")
    let procedure = ArisTeachProcedure(name: "메모 남기기", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit"), replacing],
                                       parameters: [], created: Date())
    let plan = ArisTeachReplay.plan(procedure, given: [:], run: "r1")
    check(!plan.approved.contains { $0.index == 2 }, "vmfix5 D2: a step that replaces is never approved ahead (it asks)")
    let read = vmfix5TeachSource("ArisAgent/Apps/ArisAppsHands+Read.swift")
    check(read.contains("if Self.insertsByDefault(arguments, field: field?.1), let pid = target.running?.pid ?? running(target.bundle)?.pid {"),
          "vmfix5 D2: app.type into a document's text area inserts at its end by default")
    check(ArisAppsHands.insertsByDefault(.object(["text": .string("x")]), field: nil) == false, "vmfix5 D2: with no text area named nothing changes")
}

/// D4 (the lesson's part): the teach turn's own words follow the UI's language the app sends, never the request's.
private func vmfix5TeachLanguageTests() {
    let turn = vmfix5TeachSource("ArisAgent/Teach/ArisTeachTurn.swift")
    check(turn.contains("ArisSkillLanguage.heard(object[\"lang\"])\n        let english = ArisSkillLanguage.english")
          && !turn.contains("let english = ArisTeachCopy.isEnglish(words)"),
          "vmfix5 D4: a lesson's card and account are in the UI's language")
    check(vmfix5TeachSource("Aris/private/Aris/ArisAgentClient.swift").contains("body[\"lang\"] = ArisSkillWords.language(english: ArisUIWords.english)"),
          "vmfix5 D4: every request says the UI's language")
    check(!ArisCardEnglish.isEnglish(request: "Do memo writing", uiEnglish: false) && ArisCardEnglish.isEnglish(request: "메모 쓰기 해 줘", uiEnglish: true),
          "vmfix5 D4: a card's own words and buttons follow the UI's language")
    // The account of a run in a Korean UI after an English request: the app layer's English reason is said in Korean.
    let procedure = ArisTeachProcedure(name: "memo", steps: [ArisTeachStep(action: .open, app: "Spotlight", bundle: "com.apple.Spotlight")], parameters: [], created: Date())
    let korean = ArisTeachCopy.account(procedure, outcome: .stopped(at: 0, end: .failed("no app on this Mac is called ‘Spotlight’"), done: 0), english: false)
    check(!korean.contains("no app on this Mac"), "vmfix5 D4: a step's English failure isn't put into a Korean line")
}
