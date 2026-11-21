// jv-focus: F4 "act on what I am looking at". The resolution itself is pure and tested with fake trees in
// Tests/ArisCoreTests/ArisFocusTests.swift (swift test); here: the helper's bounded tree reader on a fake element
// source (a password field's value is never kept, a slow or huge app is cut short), the /look request's regions and
// reply, the desk Judgment's focus hook reads, the look's context with the focus first, the app's "여기" deixis, the
// circled regions handed from the gesture to the look, and the wiring the AppKit controller can't run here.
import CoreGraphics
import Foundation

private func focusSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// A fake app: elements by number, each with its attributes and children.
private struct FakeElements: ArisFocusElements {
    var reads: [Int: ArisFocusElementRead]
    var kids: [Int: [Int]]
    var silent: Set<Int> = []

    func read(_ element: Int) -> ArisFocusElementRead? { silent.contains(element) ? nil : reads[element] }
    func children(_ element: Int) -> [Int] { kids[element] ?? [] }
    func same(_ a: Int, _ b: Int) -> Bool { a == b }
}

private func focusReaderTests() {
    var reads: [Int: ArisFocusElementRead] = [
        0: ArisFocusElementRead(role: "AXWindow", title: "로그인"),
        1: ArisFocusElementRead(role: "AXTextField", value: "user@example.com", editable: true),
        2: ArisFocusElementRead(role: "AXSecureTextField", value: "hunter2", selectedText: "hunter2", editable: true),
        3: ArisFocusElementRead(role: "AXTextField", subrole: "AXSecureTextField", value: "1234"),
        4: ArisFocusElementRead(role: "AXStaticText", value: String(repeating: "가", count: 9_000)),
    ]
    let source = FakeElements(reads: reads, kids: [0: [1, 2, 3, 4]])
    let read = ArisFocusReader(source: source, exhausted: { false }).tree(0, focused: 1)
    let tree = read.tree
    check(tree?.children.count == 4 && !read.cut, "focus reader: the window and its four elements")
    check(tree?.children[0].focused == true && tree?.children[0].value == "user@example.com", "focus reader: the focused field is marked")
    check(tree?.children[1].value == nil && tree?.children[1].selectedText == nil, "focus reader: a password field's value is never kept")
    check(tree?.children[2].value == nil, "focus reader: a field whose subrole says password, the same")
    check((tree?.children[3].value?.count ?? 0) == ArisFocusReader<FakeElements>.valueLimit, "focus reader: a long value is cut")
    check(!(tree.map { ArisAXNode("AXGroup", children: [$0]).text() } ?? "").contains("hunter2"), "focus reader: no password in the window's words")

    // Bounds: the clock, an app that stops answering, too many children.
    var calls = 0
    let timed = ArisFocusReader(source: source, exhausted: { calls += 1; return calls > 2 }).tree(0, focused: nil)
    check(timed.cut && (timed.tree?.children.count ?? 0) < 4, "focus reader: the clock stops the read, what was read is kept, marked cut")
    let quiet = ArisFocusReader(source: FakeElements(reads: reads, kids: [0: [1, 2]], silent: [2]), exhausted: { false }).tree(0, focused: nil)
    check(quiet.cut && quiet.tree?.children.count == 1, "focus reader: an element that doesn't answer is skipped and the read marked cut")
    for index in 10..<(10 + ArisFocusReader<FakeElements>.perNode + 5) { reads[index] = ArisFocusElementRead(role: "AXStaticText", value: "줄 \(index)") }
    let wide = ArisFocusReader(source: FakeElements(reads: reads, kids: [0: Array(10..<(10 + ArisFocusReader<FakeElements>.perNode + 5))]),
                               exhausted: { false }).tree(0, focused: nil)
    check(wide.cut && wide.tree?.children.count == ArisFocusReader<FakeElements>.perNode, "focus reader: at most perNode children of one element")
    let deep = Dictionary(uniqueKeysWithValues: (0..<50).map { ($0, [$0 + 1]) })
    let deepReads = Dictionary(uniqueKeysWithValues: (0...50).map { ($0, ArisFocusElementRead(role: "AXGroup")) })
    let nested = ArisFocusReader(source: FakeElements(reads: deepReads, kids: deep), exhausted: { false }).tree(0, focused: nil)
    var depth = 0, node = nested.tree
    while let next = node?.children.first { depth += 1; node = next }
    check(nested.cut && depth == ArisFocusReader<FakeElements>.deepest, "focus reader: at most `deepest` levels")
}

private func focusRouteTests() {
    let regions = ArisFocusLive.regions([[10, 20, 300, 40], [1, 2, 0, 5], ["x", 1, 2, 3], [1, 2, 3], [Double.infinity, 0, 1, 1]] as [[Any]])
    check(regions == [ArisFocusRect(x: 10, y: 20, width: 300, height: 40)], "focus route: only well-formed regions are kept")
    check(ArisFocusLive.regions(Array(repeating: [0, 0, 10, 10], count: 20) as [[Any]]).count == 8, "focus route: at most eight regions")
    check(ArisFocusLive.regions("nonsense").isEmpty && ArisFocusLive.regions(nil).isEmpty, "focus route: anything else is none")

    let field = ArisAXNode("AXTextArea", value: "", frame: ArisFocusRect(x: 0, y: 500, width: 400, height: 40), focused: true, editable: true)
    let chat = ArisFocusObservation(app: ArisFocusApp(name: "Messages", bundleID: "com.apple.MobileSMS"), windowTitle: "엄마",
                                    tree: ArisAXNode("AXWindow", frame: ArisFocusRect(x: 0, y: 0, width: 400, height: 600), children: [
                                        ArisAXNode("AXStaticText", value: "엄마: 언제 와?"), field]))
    let resolution = ArisFocusResolver.resolve("이 사람한테 곧 간다고 답장 써 줘", chat)
    let reply = ArisFocusLive.reply(resolution, words: "이 사람한테 곧 간다고 답장 써 줘")
    check(reply["focusKind"] as? String == "chat" && reply["writesHere"] as? Bool == true && reply["landing"] as? String == "insertAtCaret",
          "focus route: a reply in a chat whose field has the keyboard is written in place")
    check(ArisFocusLive.reply(resolution, words: "이거 요약해 줘")["writesHere"] as? Bool == false, "focus route: a summary is said, not typed")
    check(ArisFocusLive.reply(nil, words: "x").isEmpty, "focus route: no focus, nothing added")
    check(resolution.focus?.mentioned == "엄마" && resolution.focus?.person == nil,
          "focus route: Messages' window title names the person as a hint, never a trusted sender")
}

private func focusDeskTests() {
    let desk = ArisFocusDesk()
    let start = Date()
    let focus = ArisFocus(kind: .mail, app: ArisFocusApp(name: "Mail"), person: "민수 <minsu@example.com>", title: "회의", how: "selected")
    desk.keep(ArisFocusResolution(pointing: ArisFocusWords.parse("이 메일"), focus: focus), at: start)
    check(desk.worldFacts(now: start.addingTimeInterval(5)).focus?.sender == "민수 <minsu@example.com>", "focus desk: Judgment's hook gets the mail's sender")
    check(desk.worldFacts(now: start.addingTimeInterval(5)).frontApp == "Mail", "focus desk: and the app it is in")
    check(desk.worldFacts(now: start.addingTimeInterval(ArisFocusDesk.freshFor + 1)).focus == nil, "focus desk: a focus goes stale")
    let gate = ArisTrustGate(home: NSTemporaryDirectory() + "aris-focus-tests-\(UUID().uuidString)")
    ArisFocusDesk.install(gate: gate, desk: desk)
    desk.keep(ArisFocusResolution(pointing: ArisFocusWords.parse("이 메일"), focus: focus))
    check(gate.world("any session").focus?.source.kind == "mail", "focus desk: installed as the trust gate's world")
    check(focusSource("ArisAgent/Trust/ArisCore2Trust.swift").contains("ArisFocusDesk.install()"), "focus desk: installed at the helper's start")
    // "이 사람" (decision 3): the desk hands Judgment the person resolved for the words of that turn only.
    let personWords = "이 사람한테 내일 괜찮다고 답장해 줘"
    desk.keep(ArisFocusResolution(pointing: ArisFocusWords.parse(personWords), focus: focus), words: personWords)
    let held = desk.worldFacts().focus
    check(held?.resolvedPerson == "민수 <minsu@example.com>" && held?.person(forTurn: personWords) == "민수 <minsu@example.com>",
          "focus desk: a trusted person resolved for 이 사람 is kept with its turn's words")
    check(held?.person(forTurn: "이 사람한테 다시 답장해 줘") == nil, "focus desk: the resolved person counts for its own turn only")
    desk.keep(ArisFocusResolution(pointing: ArisFocusWords.parse("이 메일"), focus: focus), words: "이 메일 요약해 줘")
    check(desk.worldFacts().focus?.resolvedPerson == nil, "focus desk: words that named no person resolve no person")
    var hinted = focus
    hinted.person = nil
    hinted.mentioned = "민수"
    desk.keep(ArisFocusResolution(pointing: ArisFocusWords.parse(personWords), focus: hinted), words: personWords)
    check(desk.worldFacts().focus?.resolvedPerson == nil, "focus desk: a name only read off the screen is never the resolved person")
}

private func focusLookTests() {
    var look = ArisLook(app: "Mail", window: "받은 편지함", selection: nil, editable: false, tab: nil, screen: "OCR words", pointer: "link: x")
    look.focusBlock = "Focus: block"
    let context = look.context
    let focusAt = context.range(of: "Focus: block")?.lowerBound, pointerAt = context.range(of: "Under the pointer")?.lowerBound
    check(focusAt != nil && pointerAt != nil && focusAt! < pointerAt!, "focus look: the focus comes before the look's other outside lines")
    check(ArisLook(app: "X", window: nil, selection: nil, editable: false, tab: nil, screen: nil).context == "Front app: X", "focus look: no focus, as before")
    let main = focusSource("ArisAgent/main.swift")
    check(main.contains(#"words: (object["words"] as? String).map { String($0.prefix(4_000)) }, regions: ArisFocusLive.regions(object["regions"]),"#),
          "focus look: /look hands the words and the circled regions to the look")
    check(main.contains("ArisFocusLive.reply(look.focus"), "focus look: /look answers the focus's kind and whether it writes in place")
    let gather = focusSource("ArisAgent/ArisLook.swift")
    check(gather.contains("if look.confirmed { ArisFocusDesk.shared.keep(resolution, words: words) }"), "focus look: an unconfirmed look teaches Judgment nothing (a confirmed one keeps the words it was resolved for)")
    check(focusSource("ArisAgent/ArisAgentStream.swift").contains("<screen>"), "focus look: the look's context still rides in the turn's <screen> fence")
}

private func focusAppTests() {
    check(ArisDeixis.refersToScreen("여기 고쳐 줘"), "focus deixis: 여기 고쳐 줘 points at the screen")
    check(ArisDeixis.refersToScreen("여기에 결론 한 줄 써 줘"), "focus deixis: 여기에 써 줘")
    check(ArisDeixis.refersToScreen("put it here"), "focus deixis: put it here")
    check(!ArisDeixis.refersToScreen("여기 날씨 어때"), "focus deixis: 여기 날씨 is the owner's place")
    check(!ArisDeixis.refersToScreen("여기서 가까운 카페 찾아 줘"), "focus deixis: 여기서 가까운 카페 too")
    check(!ArisDeixis.refersToScreen("come here"), "focus deixis: here without an act points at nothing")
    check(!ArisDeixis.refersToScreen("내일 날씨 알려 줘"), "focus deixis: no pointing, no screen")
    check(ArisDeixis.wantsRewrite("여기 고쳐 줘"), "focus deixis: 여기 고쳐 줘 on an editable selection is a rewrite in place")

    MainActor.assumeIsolated { focusGestureTests() }
    focusControllerTests()
}

@MainActor private func focusGestureTests() {
    // The circle's regions reach the look; an earlier turn's never do.
    let capture = ArisTurnCapture(dependencies: .init(shoot: { nil }, enabled: { false }, permission: { false }, nextNotice: { nil }, notify: { _ in }))
    let image = ArisTurnImage(kind: .gesture, name: "gesture-screenshot-1.jpg", format: .jpeg, data: Data([1]), badge: 1, app: "Safari", title: "t")
    capture.began(notchShowsAnswer: false)
    capture.attachGesture([image], regions: [CGRect(x: 10, y: 20, width: 300, height: 40)])
    check(capture.gestureRegions == [CGRect(x: 10, y: 20, width: 300, height: 40)], "focus gesture: this turn's circled region is there for the look")
    check(capture.takeGesture().count == 1, "focus gesture: the shot still goes with the ask")
    capture.cancel()
    check(capture.gestureRegions.isEmpty, "focus gesture: the next turn has no region of this one")
    let shot = ArisGestureShot(badge: 1, app: nil, title: nil, jpeg: Data(), thumb: Data(), voicedMsAtCapture: 0, capturedAtMs: 0, display: 1,
                               region: CGRect(x: 1, y: 2, width: 3, height: 4))
    let turn = ArisGestureTurn(result: ArisGestureResult(shots: [shot], references: [], speech: nil, handsFree: false))
    check(turn?.regions == [CGRect(x: 1, y: 2, width: 3, height: 4)], "focus gesture: a circled shot carries its region into the turn")
    check(focusSource("Aris/private/Aris/Gesture/ArisGestureCapture.swift").contains("display: r.screen.id, region: box)"),
          "focus gesture: the capture keeps the circle's box in global points")
    check(focusSource("Aris/private/Aris/ArisController+Gesture.swift").contains("attachGesture(gesture.images, regions: gesture.regions)"),
          "focus gesture: the controller hands the regions on")

}

private func focusControllerTests() {
    // The controller (AppKit, not compiled here): the look gets the words and regions; a draft is typed only where
    // the keyboard already is, and is never sent.
    let controller = focusSource("Aris/private/Aris/ArisController+Look.swift")
    check(controller.contains("words: text, regions: ArisTurnCapture.shared.gestureRegions)"), "focus app: the look gets the words and the circle")
    check(controller.contains("if let look, look.writesHere, let target = look.target"), "focus app: writing in place only when the helper says the field has the keyboard")
    check(controller.contains("noActions: true"), "focus app: the field write declines every action, as the rewrite did")
    // (rel12 S3: the line says what actually happened: added at the caret, nothing erased, nothing sent.)
    check(controller.contains("ArisTypeHere.insertedLine(korean: korean, undoable: undoable)") && ArisTypeHere.insertedLine(korean: true, undoable: false).contains("보내기 전에 확인해 주세요"),
          "focus app: Aris says it added it and that nothing was sent (Korean first)")
    check(ArisControllerLookWords.draft.contains("nothing is sent"), "focus app: the brain is told nothing is sent")
}

/// The controller's instructions, read from its source (the controller itself needs AppKit).
private enum ArisControllerLookWords {
    static var draft: String {
        let source = focusSource("Aris/private/Aris/ArisController+Look.swift")
        return source.components(separatedBy: "\n").first { $0.contains("static let draftInstruction") } ?? ""
    }
}

func runFocusTests() {
    focusReaderTests()
    focusRouteTests()
    focusDeskTests()
    focusLookTests()
    focusAppTests()
}
