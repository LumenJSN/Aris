// Tests for the QA session's bugs (jdoe-62, deployed 868051ee with the Codex brain): a maps lookup is a read on every
// brain (BUG-1), the map card's values survive a long route (BUG-2), and ⌥⇧ typed while Aris answers leaves the turn
// alone, with no raw error text (BUG-3).
import AppKit
import Foundation
import SwiftUI

func runQAFixesTests() {
    qaMapsLookupIsReadTests()
    qaMapCardValuesTests()
    qaGestureTypingTests()
    qaComposerKeysTests()
    qaPanelFieldKeysTests()
}

// MARK: - BUG-1: `maps search|directions … --json` is a read, never a card

private func qaMapsLookupIsReadTests() {
    let tools = "/Users/me/.config/aris/aris-tools"
    let lookup = ["maps", "search", "Daytona Beach", "--json"]
    let route = ["maps", "directions", "Orlando", "Daytona Beach", "--json"]
    let opens = ["maps", "search", "Daytona Beach"]
    check(ArisReadGate.isMapsLookup(lookup) && ArisReadGate.isMapsLookup(route) && !ArisReadGate.isMapsLookup(opens)
          && !ArisReadGate.isMapsLookup(["weather", "--json"]), "BUG-1: maps … --json is the lookup (aris-tools opens nothing), maps without it opens Maps")
    check(ArisReadGate.isJudgedRead(lookup) && !ArisReadGate.isJudgedRead(opens)
          && ArisReadGate.call(arisTools: lookup) == ArisReadCall(tool: "aris-tools maps search", arguments: "Daytona Beach --json"),
          "BUG-1: the lookup is a read the judge checks on a careful turn")

    // The risk policy (Codex, the API brain, hands-free): at once, never outbound, never asked after outside text.
    let action = ArisAction.shell("\(tools) maps search \"Daytona Beach\" --json")
    check(ArisRiskPolicy.risk(of: action, tools: tools, home: "/Users/me") == .auto
          && ArisRiskPolicy.risk(of: action, tools: tools, home: "/Users/me", critical: true) == .auto
          && !ArisRiskPolicy.isOutbound(action, tools: tools) && !ArisRiskPolicy.asksAfterOutsideText(action, tools: tools)
          && !ArisHandsFree.asks(action, tools: tools), "BUG-1: risk policy: the lookup runs at once and never asks")
    let open = ArisAction.shell("\(tools) maps search \"Daytona Beach\"")
    check(ArisRiskPolicy.isOutbound(open, tools: tools) && ArisRiskPolicy.asksAfterOutsideText(open, tools: tools) && ArisHandsFree.asks(open, tools: tools),
          "BUG-1: Maps opened is still outbound (asked after outside text and hands-free)")
    check(ArisRiskPolicy.isOutbound(.shell("\(tools) maps search x --json && \(tools) link https://x.io"), tools: tools),
          "BUG-1: a lookup chained with a link is still outbound")

    // The card's words: never 지도 열기 for the lookup.
    check(ArisCodexDriver.describe(command: "\(tools) maps search \"Daytona Beach\" --json", tools: tools).0 != "지도 열기"
          && ArisCodexDriver.describe(command: "\(tools) maps directions Orlando \"Daytona Beach\" --json", tools: tools).0 != "지도 열기"
          && ArisCodexDriver.describe(command: "\(tools) maps search \"Daytona Beach\"", tools: tools).0 == "지도 열기",
          "BUG-1: 지도 열기 names only Maps opened")

    // Codex, as QA saw it: whatever the thread took in, the lookup is never a card (at once, or the read judge).
    func codexAnswer(_ setup: (ArisCodexDriver) -> Void, _ command: String) -> ArisBrainEvent? {
        let codex = ArisCodexDriver(model: "m", tools: tools, instructions: "", home: "/Users/me")
        _ = codex.ask("올랜도에서 나이아가라 폭포까지 차로 얼마나 걸려")
        codex.setRequest("올랜도에서 나이아가라 폭포까지 차로 얼마나 걸려")   // as the runner does
        setup(codex)
        let request: [String: Any] = ["id": 901, "method": "item/commandExecution/requestApproval", "params": ["command": "/bin/zsh -lc '\(command)'"]]
        let line = (try? JSONSerialization.data(withJSONObject: request)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return codex.read(line).first
    }
    func isJudge(_ event: ArisBrainEvent?) -> Bool { if case .confirm(let ask)? = event { return ask.title == "읽기 확인" } else { return false } }
    func isSend(_ event: ArisBrainEvent?) -> Bool { if case .send? = event { return true } else { return false } }
    let search = "\(tools) maps search \"Daytona Beach\" --json", directions = "\(tools) maps directions Orlando \"Daytona Beach\" --json"
    check(isSend(codexAnswer({ _ in }, search)) && isSend(codexAnswer({ _ in }, directions)), "BUG-1: codex: a clean turn's lookup runs at once")
    // After the screen or outside text, a lookup in the user's own words is a judged read (follow-up M1: other words ask).
    let ownSearch = "\(tools) maps search \"나이아가라 폭포\" --json", ownDirections = "\(tools) maps directions 올랜도 \"나이아가라 폭포\" --json"
    check(isJudge(codexAnswer({ $0.markScreenSeen() }, ownSearch)), "BUG-1: codex: after the screen, the lookup goes to the read judge (no card)")
    check(isJudge(codexAnswer({ $0.markUntrusted() }, ownSearch)) && isJudge(codexAnswer({ $0.markUntrusted() }, ownDirections)),
          "BUG-1: codex: after outside text, the lookup goes to the read judge (no card)")
    check(isJudge(codexAnswer({ $0.setHandsFree(true) }, search)), "BUG-1: codex: hands-free, the lookup goes to the read judge (no card)")
    if case .confirm(let ask)? = codexAnswer({ $0.markUntrusted() }, "\(tools) maps search \"Daytona Beach\"") {
        check(ask.title == "지도 열기", "BUG-1: codex: after outside text, Maps opened still asks on its card")
    } else {
        check(false, "BUG-1: codex: after outside text, Maps opened still asks on its card")
    }

    // The API brain's gate agrees.
    func api(_ setup: (ArisAPIGate) -> Void, _ command: String) -> ArisAPIGateDecision {
        let gate = ArisAPIGate(tools: tools, home: "/Users/me")
        gate.request = "올랜도에서 나이아가라 폭포까지 차로 얼마나 걸려"
        setup(gate)
        return gate.judge(command)
    }
    func apiAllows(_ decision: ArisAPIGateDecision) -> Bool { if case .allow = decision { return true } else { return false } }
    func apiJudges(_ decision: ArisAPIGateDecision) -> Bool { if case .read = decision { return true } else { return false } }
    func apiAsks(_ decision: ArisAPIGateDecision) -> Bool { if case .ask = decision { return true } else { return false } }
    check(apiAllows(api({ _ in }, search)) && apiJudges(api({ $0.markUntrusted() }, ownSearch)) && apiJudges(api({ $0.markScreenSeen() }, ownDirections))
          && apiJudges(api({ $0.handsFree = true }, search)), "BUG-1: API gate: at once on a clean turn, the read judge after outside text or hands-free")
    check(apiAsks(api({ $0.markUntrusted() }, "\(tools) maps search \"Daytona Beach\"")), "BUG-1: API gate: Maps opened after outside text still asks")

    // The open Claude's turn gate: a read like the web's (judged after outside text or in a job, outside text after).
    let lookupLine = "\(tools) maps search \"Daytona Beach\" --json"
    let judged = ArisReadCall(tool: "aris-tools maps search", arguments: "Daytona Beach --json")
    check(ArisTurnGate.verdict(tool: "Bash", command: lookupLine, tools: tools, tainted: false) == .allowMarking,
          "BUG-1: turn gate: a clean turn's lookup runs (and marks, as the web does)")
    check(ArisTurnGate.verdict(tool: "Bash", command: lookupLine, tools: tools, tainted: true) == .judge(judged, marks: false)
          && ArisTurnGate.verdict(tool: "Bash", command: lookupLine, tools: tools, tainted: false, careful: true) == .judge(judged, marks: true),
          "BUG-1: turn gate: after outside text or in a job, the lookup goes to the read judge (not refused)")
    // Audit gate-3: Maps opened after outside text goes to the agent's gate (outbound there: the user's card), no longer refused.
    check(ArisTurnGate.verdict(tool: "Bash", command: "\(tools) maps search \"Daytona Beach\"", tools: tools, tainted: true) == .allow
          && handOffRouting(["maps", "search", "Daytona Beach"], environment: [ArisTurnGate.stateKey: "/nowhere"]) != .direct
          && handOffRouting(lookup, environment: [ArisTurnGate.stateKey: "/nowhere"]) == .direct,
          "BUG-1: turn gate: after outside text, Maps opened goes to the agent's gate; the lookup still runs where it was called")

    // The sealed Claude and agy's relay: the lookup is on their lists, judged; Maps opened still isn't.
    check(ArisSealedTools.allows(lookup) && ArisSealedTools.allows(route) && !ArisSealedTools.allows(opens)
          && !ArisSealedTools.allows(["maps", "search", "x", "--json", "--json"]) && !ArisSealedTools.allows(["maps", "nearby", "x", "--json"]),
          "BUG-1: sealed: the lookup (and only it) is on the list")
    let hookInput = (try? JSONSerialization.data(withJSONObject: ["tool_name": "Bash", "tool_input": ["command": lookupLine]])) ?? Data()
    check(ArisSealedTools.hookVerdict(input: hookInput, tools: tools) == .judge(judged), "BUG-1: sealed: its hook sends the lookup to the read judge")
    check(ArisAgyRelay.permitted(lookup, sealed: true) && ArisAgyRelay.permitted(route, sealed: false) && ArisAgyRelay.readCall(lookup) == judged
          && ArisAgyRelay.isWrite(opens) && !ArisAgyRelay.permitted(opens, sealed: true, handsFree: true),
          "BUG-1: agy relay: the lookup runs judged, sealed or not; Maps opened only unsealed (audit gate-16: once sealed, on the user's card, never hands-free)")
}

// MARK: - BUG-2: the map card's values come through whole, however long the route

private func qaMapCardValuesTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("aris-qa-maps-\(UUID().uuidString)").path
    try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }
    // Orlando to Daytona Beach by car: MapKit's route has hundreds of points, thinned to the card's 100.
    let start = ArisMapsCard.Point(latitude: 43.6532, longitude: -79.3832), end = ArisMapsCard.Point(latitude: 43.0896, longitude: -79.0849)
    let points = (0..<800).map { index -> ArisMapsCard.Point in
        let t = Double(index) / 799
        return ArisMapsCard.Point(latitude: start.latitude + (end.latitude - start.latitude) * t + 0.000123 * sin(Double(index)),
                                  longitude: start.longitude + (end.longitude - start.longitude) * t)
    }
    let card = ArisMapsCard.card(name: "Daytona Beach", address: "Daytona Beach, ON, Canada", place: end, origin: (start, .current),
                                 eta: ["car": 5_400, "transit": 9_000, "walk": 140_000], distance: ["car": 130_000, "transit": 140_000, "walk": 125_000],
                                 route: points)
    let json = (try? JSONSerialization.data(withJSONObject: card, options: [.sortedKeys])) ?? Data()
    check(json.count > ArisLook.limit, "BUG-2: a long route's card is longer than the look's \(ArisLook.limit) characters (\(json.count))")
    // A stand-in aris-tools that prints it, as `maps directions Orlando "Daytona Beach" --json` does.
    let output = root + "/card.json", tool = root + "/aris-tools"
    FileManager.default.createFile(atPath: output, contents: json)
    FileManager.default.createFile(atPath: tool, contents: Data("#!/bin/sh\ncat '\(output)'\n".utf8), attributes: [.posixPermissions: 0o755])
    let values = ArisLook.cardValues(tool, ["maps", "directions", "Orlando", "Daytona Beach", "--json"], [:], timeout: 10)
    let parsed = values.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }.flatMap(ArisMapCard.parse)
    check(parsed?.eta[.car] == 5_400 && parsed?.route.count == ArisMapsCard.mostRoutePoints && parsed?.name == "Daytona Beach",
          "BUG-2: the agent hands the app the whole card (ETA by car, the route), never a cut one")
    check(parsed?.primaryLine?.how.hasPrefix("차로") == true, "BUG-2: the card leads with the car's ETA")
    // What isn't JSON is still no card.
    FileManager.default.createFile(atPath: output, contents: Data("couldn't find x in Maps".utf8))
    check(ArisLook.cardValues(tool, ["maps", "search", "x", "--json"], [:], timeout: 10) == nil, "BUG-2: output that isn't JSON is no card")
    FileManager.default.createFile(atPath: output, contents: Data(String(repeating: "x", count: ArisLook.cardLimit + 10).utf8))
    check(ArisLook.cardValues(tool, ["maps", "search", "x", "--json"], [:], timeout: 10) == nil, "BUG-2: an overlong reply is no card, never cut")
}

// MARK: - BUG-3: ⌥⇧ typed while Aris answers leaves the turn as it was

private func qaGestureTypingTests() {
    typealias K = ArisGestureKey
    func mods(_ o: Bool, _ s: Bool, other: Bool = false, _ t: Double) -> K.Event { .modifiers(option: o, shift: s, other: other, at: t) }
    check(K.waitsLonger(.thinking) && K.waitsLonger(.speaking) && !K.waitsLonger(.idle) && !K.waitsLonger(.listening) && !K.waitsLonger(.failed),
          "BUG-3: a press waits longer only while a turn is answering")
    check(K.busyDebounceMs > K.debounceMs && K.busyDebounceMs >= 400, "BUG-3: the busy wait is long enough to see the typed key")

    // ⌥⇧ then a key, as when typing a character, while Aris answers: nothing starts, nothing is cancelled.
    var typing = K.State()
    check(typing.handle(mods(true, true, 0), busy: true) == .none && typing.dueAt == K.busyDebounceMs, "BUG-3: busy, the press waits the longer debounce")
    check(typing.handle(.tick(at: K.debounceMs + 10)) == .none, "BUG-3: busy, the usual debounce doesn't start a turn")
    check(typing.handle(.otherKey(at: 300)) == .none && typing.handle(.tick(at: 900)) == .none && typing.handle(mods(false, false, 950)) == .none,
          "BUG-3: busy, ⌥⇧ + a key is typing: no start and no cancel (the answer goes on)")
    check(typing.handle(mods(true, true, 1_000)) == .none && typing.handle(.tick(at: 1_000 + K.debounceMs)) == .start,
          "BUG-3: after the answer (not busy), the usual debounce again")

    // Held alone past the longer wait while busy: a deliberate press, which barges in as before.
    var held = K.State()
    _ = held.handle(mods(true, true, 0), busy: true)
    check(held.handle(.tick(at: K.busyDebounceMs)) == .start && held.handle(mods(false, false, 1_200)) == .finish(heldForMs: 1_200),
          "BUG-3: busy, ⌥⇧ held alone still starts (and ends) a turn")
    // A short tap while busy, no other key: the tap still counts (start, then finish with its own length).
    var tap = K.State()
    _ = tap.handle(mods(true, true, 0), busy: true)
    check(tap.handle(.tick(at: K.debounceMs + 5)) == .none && tap.handle(mods(false, false, 200)) == .tap(heldForMs: 200),
          "BUG-3: busy, a clean ⌥⇧ tap past the usual debounce is a tap")
    var flick = K.State()
    _ = flick.handle(mods(true, true, 0), busy: true)
    check(flick.handle(mods(false, false, 60)) == .none, "BUG-3: busy, a release inside the usual debounce is nothing")
    // Not busy: as before (the existing tests hold the rest).
    var idle = K.State()
    _ = idle.handle(mods(true, true, 0))
    check(idle.dueAt == K.debounceMs && idle.handle(.tick(at: K.debounceMs)) == .start, "BUG-3: not busy, the usual 120 ms")

    // Raw NSError text never reaches the notch: an ArisFailure says its own words.
    let failure: Error = ArisFailure(message: "듣기를 그만뒀어요.")
    check(failure.localizedDescription == "듣기를 그만뒀어요.", "BUG-3: an ArisFailure's text is its message: \(failure.localizedDescription)")
    check(ArisStartFailure.line(failure, timedOut: false, abandoned: true) == nil,
          "BUG-3: a start abandoned by a cancel (a gesture that was typing) says nothing")
    let shown = ArisStartFailure.line(ArisFailure(message: "Couldn't read the microphone."), timedOut: false, abandoned: false) ?? ""
    check(shown == "듣기를 시작하지 못했어요: Couldn't read the microphone." && !shown.contains("ArisFailure") && !shown.contains("오류 1"),
          "BUG-3: a real start failure says why, in words: \(shown)")
    check(ArisStartFailure.line(failure, timedOut: true, abandoned: false) == "마이크를 여는 데 너무 오래 걸렸어요. 다시 해 주세요.",
          "BUG-3: a start that took too long says so")
}

// MARK: - BUG-22: what is typed in the composer is never a hidden Claude card's answer

private func qaComposerKeysTests() {
    MainActor.assumeIsolated {
        let editor = NSTextView(), answer = NSTextView()
        answer.isEditable = false
        // The Claude page shows its card: a digit or Y/N answers it, unless a field of its own is being typed in.
        check(KeyboardTextInput.claudeCardTakesKeys(claudePageShown: true, responder: nil)
              && KeyboardTextInput.claudeCardTakesKeys(claudePageShown: true, responder: answer)
              && !KeyboardTextInput.claudeCardTakesKeys(claudePageShown: true, responder: editor),
              "BUG-22: on the Claude page its card takes 1–9 and Y/N, but never from a field being typed in")
        // Aris's page (the composer): a Claude card waiting out of sight never takes a key, focused field or not.
        check(!KeyboardTextInput.claudeCardTakesKeys(claudePageShown: false, responder: nil)
              && !KeyboardTextInput.claudeCardTakesKeys(claudePageShown: false, responder: answer)
              && !KeyboardTextInput.claudeCardTakesKeys(claudePageShown: false, responder: editor),
              "BUG-22: off the Claude page, digits and Y/N go to what has focus (the composer), never a hidden card")
        // Korean IME composing in the composer: its editor still owns the keys.
        editor.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        check(editor.hasMarkedText() && KeyboardTextInput.takesKeys(editor), "BUG-22: a field composing Korean (marked text) still takes the keys")
    }
}

// MARK: - BUG-22: a field in a non-activating panel takes the keyboard (or shows no caret), and gives it back

private func qaPanelFieldKeysTests() {
    let own: pid_t = 100, weChat: pid_t = 200, other: pid_t = 300
    var focus = ArisPanelFocus()
    check(focus.hovered() == .none && !focus.editing && !focus.canBecomeKey(armed: false),
          "BUG-22: hovering a field takes nothing (no key, no focus stolen)")
    check(focus.pressed(onField: false, frontmost: weChat, own: own) == .none && !focus.editing,
          "BUG-22: a press beside the fields takes nothing")
    check(focus.pressed(onField: true, frontmost: weChat, own: own) == .takeKey && focus.editing && focus.previous == weChat
          && focus.canBecomeKey(armed: false), "BUG-22: a press on a field takes the keyboard (the panel may become key), remembering WeChat")
    check(!focus.caretAllowed(panelIsKey: false) && focus.caretAllowed(panelIsKey: true),
          "BUG-22: a caret only while the panel really is key")
    check(focus.pressed(onField: true, frontmost: own, own: own) == .takeKey && focus.previous == weChat,
          "BUG-22: another field in Aris keeps the app to give back")
    check(focus.responder(takesKeys: true) == .none && focus.editing, "BUG-22: moving between fields keeps editing")
    check(focus.responder(takesKeys: false) == .giveBack(weChat) && !focus.editing && focus.previous == nil,
          "BUG-22: the field let go: the keyboard goes back to WeChat")
    var focused = ArisPanelFocus()
    // Follow-up M7: only a press (or the composer's drop path) takes the keyboard; a field focused on its own loses its caret.
    check(focused.responder(takesKeys: true, frontmost: weChat, own: own) == .dropCaret && !focused.editing && focused.previous == nil,
          "BUG-22: a field focused without a press never takes the keyboard; its caret goes")
    var closing = ArisPanelFocus()
    _ = closing.pressed(onField: true, frontmost: other, own: own)
    check(closing.closed(arisActive: true) == .giveBack(other), "BUG-22: the panel closed while editing: back to the app the user was in")
    var away = ArisPanelFocus()
    _ = away.pressed(onField: true, frontmost: other, own: own)
    check(away.closed(arisActive: false) == .forget && !away.editing, "BUG-22: the user clicked another app himself: nothing is taken back from it")
    var fromAris = ArisPanelFocus()
    check(fromAris.pressed(onField: true, frontmost: own, own: own) == .takeKey && fromAris.responder(takesKeys: false) == .giveBack(nil),
          "BUG-22: started from Aris itself: nothing to give back")
    var idle = ArisPanelFocus()
    check(idle.closed(arisActive: true) == .none && idle.canBecomeKey(armed: true),
          "BUG-22: not editing, closing does nothing; a card's arm still lets the panel be key")

    // Offscreen (never on a display, nothing posted): the panels' fields are found where a press lands.
    MainActor.assumeIsolated {
        struct Fields: View {
            @State var a = ""
            @State var b = ""
            var body: some View {
                VStack(spacing: 0) {
                    TextField("", text: $a, axis: .vertical).textFieldStyle(.plain).frame(height: 30)
                    TextField("검색", text: $b).textFieldStyle(.plain).frame(height: 30)
                    Text("label").frame(height: 30)
                }.frame(width: 300, height: 90)
            }
        }
        let panel = NSPanel(contentRect: NSRect(x: -30_000, y: -30_000, width: 300, height: 90), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.alphaValue = 0
        panel.contentView = NSHostingView(rootView: Fields())
        panel.layoutIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()
        let view = panel.contentView
        func at(_ y: CGFloat) -> NSView? { view?.hitTest(NSPoint(x: 150, y: y)) }
        check(ArisPanelKeys.isField(at(75)) && ArisPanelKeys.isField(at(45)) && !ArisPanelKeys.isField(at(15)) && !ArisPanelKeys.isField(nil),
              "BUG-22: a press on a vertical or plain TextField is on a field; on a label it isn't")
        let readOnly = NSTextView()
        readOnly.isEditable = false
        check(!ArisPanelKeys.isField(readOnly) && ArisPanelKeys.isField(NSTextView()), "BUG-22: a read-only answer isn't a field")
    }

    // Every text field Aris shows in a panel goes through the one helper: both panels route presses and key-ability
    // through ArisPanelKeys, and no field lives anywhere else unreviewed.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private").standardized
    func source(_ path: String) -> String { (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? "" }
    let notch = source("Notch/ArisNotchPanel.swift"), side = source("Aris/Side/ArisSidePanels.swift")
    // QA BUG-22 reopened: presses are seen by ArisPanelKeys' one monitor (installed at launch) on every ArisKeyPanel.
    let entry = source("App/ArisEntry.swift")
    check(notch.contains("ArisPanelKeys.canBecomeKey") && notch.contains("ArisKeyPanel") && notch.contains("ArisPanelKeys.responderChanged(")
          && side.contains("ArisKeyPanel") && side.contains("ArisPanelKeys.responderChanged(") && side.contains("ArisPanelKeys.take(")
          && entry.contains("ArisPanelKeys.installPressMonitor()"),
          "BUG-22: the notch and the side panels both take the keyboard through ArisPanelKeys")
    let covered: Set<String> = ["Aris/Home/ArisComposer.swift", "Aris/ArisTodoView.swift", "Aris/ArisClipboardView.swift",
                                "Aris/Home/ArisEditableRows.swift", "Claude/ClaudeAnswerViews.swift",
                                // The live currency card's amount: an NSTextField in the notch, which takes the keyboard through
                                // ArisPanelKeys.take after the user's own press (ArisCurrencySlot.takeKeyboard).
                                "Aris/Currency/ArisCurrencyLiveCard.swift",
                                // The sent request's editor (vnotch): it takes the keyboard through ArisPanelKeys, as the composer does.
                                "Aris/Home/ArisPromptEditViews.swift"]
    var found: Set<String> = []
    let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    while let file = walker?.nextObject() as? URL {
        guard file.pathExtension == "swift" else { continue }
        let relative = String(file.standardized.path.dropFirst(root.path.count + 1))
        // Settings and onboarding are ordinary windows that bring Aris forward.
        guard !relative.hasPrefix("Aris/components/") && !relative.contains("/Onboarding/") && !relative.contains("Settings") else { continue }
        let code = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        if code.contains("TextField(") || code.contains("TextEditor(") { found.insert(relative) }
    }
    check(found == covered, "BUG-22: every panel text field is one the helper covers (new: \(found.subtracting(covered).sorted()), gone: \(covered.subtracting(found).sorted()))")
    // Hover never takes the keyboard for a field: the composer and the clipboard no longer arm on hover.
    check(!source("Aris/Home/ArisComposer.swift").contains("KeyboardFocus.arm(") && !source("Aris/ArisClipboardView.swift").contains(".onHover { KeyboardFocus.arm"),
          "BUG-22: hovering the composer or the clipboard never makes a panel key")
}
