// jv-prompts: fewer "allow" presses. Calendar and Reminders go through the app's EventKit (one permission each,
// Aris's, asked once at the first use from a turn the user is in front of, after the line of why); a browser's front tab
// is read through Accessibility; first setup reads Music's Automation and never asks; sleep needs no app; Terminal
// opens the teammate's script as a document. Where only Apple Events can do it (Notes, Messages, Contacts, System
// Events' restart / shut down / log out), macOS is asked once, at the first use, after the app's line, and never from
// a background job. Everything here runs on fakes: no permission is asked or reset.
import Foundation

private func promptsSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func promptsJSON(_ data: Data) -> [String: Any] { ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:] }

// MARK: - The rule before an Apple Event (aris-tools)

private func promptsAutomationStepTests() {
    typealias A = ArisAutomationAsk
    for foreground in [false, true] {
        check(A.step(state: .granted, foreground: foreground, app: "Notes", feature: .notes) == .send,
              "prompts gate: granted is sent (foreground \(foreground))")
        check(A.step(state: .denied, foreground: foreground, app: "Notes", feature: .notes) == .send,
              "prompts gate: refused is sent, so it fails at once with today's words and the pane's button (foreground \(foreground))")
        check(A.step(state: .unknown, foreground: foreground, app: "Notes", feature: .notes) == .send,
              "prompts gate: not known is sent as before (foreground \(foreground))")
    }
    check(A.step(state: .notAsked, foreground: true, app: "Notes", feature: .notes) == .sayThenSend(feature: "notes"),
          "prompts gate: never asked, in a turn the user is in front of: the app says why, then macOS asks at the event")
    if case .refuse(let line) = A.step(state: .notAsked, foreground: false, app: "Messages", feature: .sendMessages) {
        check(line.hasPrefix("NOT DONE") && line.contains("Messages") && line.contains("Nothing was sent"),
              "prompts gate: never asked, from a background job: nothing is sent and nothing asked, and the AI is told so")
    } else {
        check(false, "prompts gate: never asked, from a background job: nothing is sent and nothing asked, and the AI is told so")
    }
    check(A.isForeground(["ARIS_FOREGROUND": "1"]) && !A.isForeground([:]) && !A.isForeground(["ARIS_FOREGROUND": "0"]),
          "prompts gate: only ARIS_FOREGROUND=1 (set by aris-agent for a turn the user is in front of) counts as in front")
    check(A.fallbackAllowed(.granted) && !A.fallbackAllowed(.notAsked) && !A.fallbackAllowed(.unknown) && !A.fallbackAllowed(.denied),
          "prompts gate: a fallback channel (Calendar's or a browser's scripting) is used only with the grant already there")
    check(ArisPowerRoute.withoutAppleEvents("sleep") == ["/usr/bin/pmset", "sleepnow"]
          && ["restart", "shut down", "log out"].allSatisfy { ArisPowerRoute.withoutAppleEvents($0) == nil },
          "prompts power: sleep goes through pmset (no app, no Automation); restart, shut down and log out stay System Events'")
}

// MARK: - The app's route and the features

private func promptsRouteTests() {
    typealias R = ArisPermissionRoute
    check(R.feature(["feature": "notes"]) == .notes && R.feature(["feature": "power"]) == .power
          && R.feature(["feature": "sendMessages"]) == .sendMessages && R.feature(["feature": "findContact"]) == .findContact,
          "prompts route: the features that drive an app by Apple Events are taken")
    check(R.feature(["feature": "calendar"]) == nil && R.feature(["feature": "talk"]) == nil && R.feature(["feature": "nope"]) == nil
          && R.feature([:]) == nil && R.feature(["feature": 3]) == nil,
          "prompts route: anything else is refused (the route never raises a dialog itself)")
    check(promptsJSON(R.reply(proceed: true))["proceed"] as? Bool == true && promptsJSON(R.reply(proceed: false))["proceed"] as? Bool == false,
          "prompts route: the reply says whether to go ahead")
    check(R.asks(["ask": true], granted: false) && !R.asks(["ask": true], granted: true) && !R.asks([:], granted: false)
          && !R.asks(["ask": "yes"], granted: false),
          "prompts route: Calendars or Reminders is asked only for a request from a turn the user is in front of, and only while missing")
    check(ArisPermissionWait.dialog < ArisPermissionWait.request && ArisPermissionWait.requestLimit(asks: true) == ArisPermissionWait.request,
          "prompts route: the route waits for the dialog inside aris-tools' own wait (vmfix3: it waits for the answer, never 'run it again')")
    let model = ArisPermissions()
    check(R.saysLine(.notes, in: model), "prompts route: the line is said the first time")
    let (asked, decision) = model.require(.notes)
    check(decision == .proceedAfterSaying(.automation("com.apple.Notes"), reason: ArisPermissionFeature.notes.reason(english: false)),
          "prompts route: the permission layer says Notes' one line and lets macOS ask at the event")
    check(!R.saysLine(.notes, in: asked), "prompts route: once said, never again (no 'it is off' card for a dialog that never came)")
    for feature in [ArisPermissionFeature.notes, .power, .findContact] {
        check(feature.needs == [.automation] && feature.automationTargets.count == 1 && feature.reason(english: true).hasSuffix(".")
              && !feature.reason(english: false).isEmpty, "prompts features: \(feature.rawValue) names its app and says why in both languages")
    }
    check(ArisPermissionFeature.power.automationTargets == ["com.apple.systemevents"] && ArisPermissionFeature.findContact.automationTargets == ["com.apple.AddressBook"],
          "prompts features: power is System Events, a contact lookup is Contacts")
    check(ArisPermissionSetup.list(for: Set(ArisPermissionFeature.allCases), in: model).allSatisfy { $0.permission != .automation },
          "prompts features: the setup still lists no Automation (each app is asked at its first use)")
    let live = promptsSource("Aris/private/Claude/ClaudeHookLive.swift")
    check(live.contains("case ArisPermissionRoute.path: permission(object, reply)")
          && live.contains("ArisPermissionRoute.saysLine(feature, in: center.model) ? await center.require(feature) : true")
          && ClaudeHookRoute.slowPaths.contains(R.path),
          "prompts route: wiring: POST /aris/permission (token, local only) answers through the permission center")
    check(live.contains("if ArisPermissionRoute.asks(object, granted: ArisLiveEventStore.granted), await !answered(.calendar) {")
          && live.contains("await ArisPermissionCenter.shared.require(feature)")
          && live.contains("if ArisPermissionRoute.asks(object, granted: ArisReminders.shared.accessNow()), await !answered(.reminders) {"),
          "prompts route: wiring: the event and to-do routes ask through the permission layer, after the gate's grant")
}

// MARK: - Calendar and Reminders through the app's EventKit

private func promptsCalendarTests() {
    final class Store: ArisEventStore {
        func events(from: Date, to: Date) -> [ArisEventRecord] { [] }
        func event(id: String) -> ArisEventRecord? { nil }
        func remove(id: String) throws {}
        func move(id: String, start: Date, end: Date, title: String?) throws {}
    }
    let listed = [ArisEventRoute.CalendarName(title: "Home", writable: true), ArisEventRoute.CalendarName(title: "공휴일", writable: false),
                  ArisEventRoute.CalendarName(title: "Work", writable: true)]
    let names = promptsJSON(ArisEventRoute.handle(["op": "calendars"], store: Store(), granted: true, calendars: { listed }))
    check(names["ok"] as? Bool == true && names["names"] as? [String] == ["Home", "공휴일", "Work"] && names["writable"] as? [String] == ["Home", "Work"]
          && names["line"] as? String == "Home, 공휴일, Work",
          "prompts calendar: `calendars` comes from EventKit, in order, printed as Calendar's scripting printed it")
    let off = promptsJSON(ArisEventRoute.handle(["op": "calendars"], store: Store(), granted: false))
    check(off["noAccess"] as? Bool == true && off["line"] as? String == ArisEventRoute.noAccessLine,
          "prompts calendar: without the app's grant, the fixed line that names the app")
    var removed: [String] = []
    let gone = promptsJSON(ArisEventRoute.handle(["op": "remove-uid", "uid": "A1B2-C3@google.com"], store: Store(), granted: true,
                                                 removeByUID: { removed.append($0) }))
    check(gone["ok"] as? Bool == true && removed == ["A1B2-C3@google.com"], "prompts calendar: the undo of an add removes the event by Calendar's uid")
    let odd = promptsJSON(ArisEventRoute.handle(["op": "remove-uid", "uid": "a\"; delete"], store: Store(), granted: true, removeByUID: { removed.append($0) }))
    check(odd["ok"] as? Bool == false && removed.count == 1, "prompts calendar: an id that isn't one Calendar gives is refused, nothing removed")
    let failed = promptsJSON(ArisEventRoute.handle(["op": "remove-uid", "uid": "E9"], store: Store(), granted: true,
                                                   removeByUID: { _ in throw ArisEventKitError.gone }))
    check(failed["ok"] as? Bool == false && (failed["line"] as? String)?.contains("isn't there") == true,
          "prompts calendar: an event already gone says so")

    // The gate's grants: the undo's removal is a write with a key, vouched for only by the agent's /undo.
    let undoKey = ArisActionGrant.key(event: ["op": "remove-uid", "uid": "E1"])
    check(undoKey == "event|remove-uid|uid=E1" && ArisActionGrant.eventUndoKey(uid: "E1") == undoKey
          && ArisActionGrant.isBoundUndoKey(undoKey ?? "") && !ArisActionGrant.isUndoKey(undoKey ?? ""),
          "prompts calendar: removing by uid needs a grant bound to exactly that uid, never a scope key")
    check(ArisActionGrant.eventUndoKey(uid: "a\"; x") == nil && ArisActionGrant.eventUndoKey(uid: "") == nil,
          "prompts calendar: no grant key for an id that isn't a plain one Calendar gives")
    // The undo's event grant: only for exactly its own uid, once (the same mechanism as jv-mind2's to-do grant).
    let grants = ArisActionGrants()
    let a = ArisActionGrant.eventUndoKey(uid: "EV-A") ?? "", b = ArisActionGrant.eventUndoKey(uid: "EV-B") ?? ""
    let grant = grants.mintUndo(exactly: a)
    check(grant != nil && !grants.consume(b) && !grants.consume("event|remove-uid|uid=") && !grants.consume("event|remove-uid")
          && !grants.consume(ArisActionGrant.key(event: ["op": "remove-uid"]) ?? "event|remove-uid"),
          "prompts calendar: with A's undo grant out, a removal of B (or with no uid) gets nothing")
    check(grants.consume(a) && !grants.consume(a), "prompts calendar: A's undo grant works once")
    let todoUndo = grants.mintUndo()
    check(!grants.consume(a) && !grants.consume(b), "prompts calendar: a to-do's scope undo grant never removes an event")
    grants.dropUndo(todoUndo)
    let dropped = grants.mintUndo(exactly: a)
    grants.dropUndo(dropped)
    check(!grants.consume(a), "prompts calendar: an event undo grant dropped when its run returned opens nothing")
    check(ArisActionGrant.key(event: ["op": "calendars"]) == nil, "prompts calendar: listing the calendars is a read (no grant)")
    check(!ArisActionGrant.isUndoKey("event|delete|id=E1"), "prompts calendar: an ordinary delete is never an undo key")

    // remind: the same body the grant is keyed by.
    for argv in [["remind", "우유", "사기"], ["remind", "회의", "준비", "--at", "2026-11-20 09:30"], ["remind", "--at", "2026-11-20 09:30", "약"]] {
        var words = Array(argv.dropFirst())
        var at: String?
        if let index = words.firstIndex(of: "--at") { at = words[index + 1]; words.removeSubrange(index...(index + 1)) }
        let body = ArisActions.remindRequest(text: words.joined(separator: " "), at: at)
        check(ArisActionGrant.key(argv: argv) != nil && ArisActionGrant.key(argv: argv) == ArisActionGrant.key(todo: body)
              && NSDictionary(dictionary: body).isEqual(to: ArisActionGrant.remindBody(Array(argv.dropFirst())) ?? [:]),
              "prompts reminders: `\(argv.joined(separator: " "))` is keyed as the to-do add the app gets, so the gate's yes is the one it takes")
    }
    check(ArisActionGrant.key(argv: ["remind"]) == nil && ArisActionGrant.remindBody(["--at", "2026-11-20 09:30"]) == nil,
          "prompts reminders: no text, no key")
    if let due = ArisTodoDate.due("2026-11-20 09:30", now: Date()) {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        check(parts.year == 2026 && parts.month == 11 && parts.day == 20 && parts.hour == 9 && parts.minute == 30,
              "prompts reminders: remind's --at reaches the to-do as the same moment")
    } else {
        check(false, "prompts reminders: remind's --at reaches the to-do as the same moment")
    }
    check(ArisActions.isRemindersNoAccess("Reminders access hasn't been allowed for Aris (설정 › 할 일)") && !ArisActions.isRemindersNoAccess("couldn't save it")
          && !ArisActions.isRemindersNoAccess(nil), "prompts reminders: only the missing permission lets Reminders' own scripting stand in")

    // The undo: a plain id goes to aris-tools' own undo (the app's EventKit); an odd one is refused before anything.
    var handed: [ArisUndo] = []
    let done = (try? ArisActivity.perform(.deleteEvent(id: "EV-1"), local: { handed.append($0) })) != nil
    check(done && handed == [.deleteEvent(id: "EV-1")], "prompts calendar: the event undo goes to aris-tools' undo (the app, then the granted fallback)")
    check((try? ArisActivity.perform(.deleteEvent(id: "a\"; do shell script \"x"), local: { handed.append($0) })) == nil && handed.count == 1,
          "prompts calendar: an odd id is still refused before anything runs")

    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-prompts-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("activity.jsonl"), now = Date(), stamp = ISO8601DateFormatter()
    let event = UUID().uuidString, todo = UUID().uuidString
    let lines = [["id": event, "summary": "일정 추가: Lunch", "date": stamp.string(from: now.addingTimeInterval(-600)), "undo": ["deleteEvent": ["id": "E1"]]],
                 ["id": todo, "summary": "할 일 추가: 우유", "date": stamp.string(from: now.addingTimeInterval(-300)), "undo": ["removeTodo": ["id": "x"]]]]
        .map { String(decoding: try! JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
    try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    check(ArisActivityBridge.eventUndoKey(ofEntry: event, file: file, now: now) == "event|remove-uid|uid=E1"
          && ArisActivityBridge.eventUndoKey(ofEntry: todo, file: file, now: now) == nil
          && !ArisActivityBridge.undoWritesTodo(ofEntry: event, file: file, now: now),
          "prompts calendar: the agent's /undo reads the entry's own uid for its event grant (and the to-do rule is as it was)")
    let agent = promptsSource("ArisAgent/main.swift")
    check(agent.contains("undoGrant = ArisActivityBridge.eventUndoKey(ofEntry: entry).flatMap { ArisActionGrants.shared.mintUndo(exactly: $0) }"),
          "prompts calendar: wiring: /undo mints the event grant for exactly the entry's uid")

    let mac = promptsSource("ArisTools/ArisMac.swift"), kit = promptsSource("ArisTools/ArisEventKit.swift")
    check(mac.contains("guard automationAlreadyGranted(calendarBundle) else {") && mac.contains("let reply = todosReply(ArisActions.remindRequest(text: text, at: at))")
          && mac.contains("guard automationAlreadyGranted(ArisActions.remindersBundle) else {") && mac.contains("let (names, writable) = calendarNames()"),
          "prompts calendar: wiring: add, remind and use-calendar go through the app; Calendar's and Reminders' scripting only when already allowed")
    // vmfix3: both requests go through ArisAppRoute, which marks a turn the user is in front of and waits for the dialog.
    let route = promptsSource("ArisTools/ArisAppRoute.swift")
    check(kit.contains("appRouteReply(path: \"/aris/events\"") && promptsSource("ArisTools/ArisTodoCommand.swift").contains("appRouteReply(path: \"/aris/todos\"")
          && route.contains("let asks = ArisAutomationAsk.isForeground(ProcessInfo.processInfo.environment)") && route.contains("if asks { body[\"ask\"] = true }")
          && promptsSource("ArisTools/main.swift").contains("case \"calendars\": print(calendarNames().names.joined(separator: \", \"))"),
          "prompts calendar: wiring: a turn the user is in front of says so, and `calendars` reads the app's list")
}

// MARK: - The browser's front tab through Accessibility

private func promptsTabTests() {
    final class Node {
        let element: ArisTabElement
        let children: [Node]
        init(_ element: ArisTabElement, _ children: [Node] = []) {
            self.element = element
            self.children = children
        }
    }
    func address(_ root: Node, limit: Int = ArisTabRead.limit) -> (url: String, title: String?)? {
        ArisTabRead.address(root: root, read: { $0.element }, children: { $0.children }, limit: limit)
    }
    let field = Node(ArisTabElement(role: "AXTextField", value: "https://shown.example/a", identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"))
    let web = Node(ArisTabElement(role: "AXWebArea", url: "https://example.com/page?q=1", title: "Example page"))
    let safari = Node(ArisTabElement(role: "AXWindow", title: "Example page"), [Node(ArisTabElement(role: "AXToolbar"), [field]),
                                                                                  Node(ArisTabElement(role: "AXGroup"), [web])])
    let found = address(safari)
    check(found?.url == "https://example.com/page?q=1" && found?.title == "Example page",
          "prompts tab: the web area's AXURL is the address, with its title (no Apple Event, no Automation dialog)")
    check(ArisTabRead.line(url: "https://example.com/page?q=1", title: "Example page") == "https://example.com/page?q=1, Example page",
          "prompts tab: printed as the browsers' scripting printed {URL, title}")
    let chrome = Node(ArisTabElement(role: "AXWindow"), [Node(ArisTabElement(role: "AXTextField", value: "https://github.com/x", title: "Address and search bar"))])
    check(address(chrome)?.url == "https://github.com/x" && address(chrome)?.title == nil,
          "prompts tab: with no web area, the address field when it shows a whole link")
    let short = Node(ArisTabElement(role: "AXWindow"), [Node(ArisTabElement(role: "AXTextField", value: "github.com/x", title: "Address and search bar"))])
    check(address(short) == nil, "prompts tab: an address field without its scheme is never guessed into a link")
    let other = Node(ArisTabElement(role: "AXWindow"), [Node(ArisTabElement(role: "AXTextField", value: "https://typed.example", title: "Search"))])
    check(address(other) == nil, "prompts tab: a text field that isn't the address field is not the page")
    let local = Node(ArisTabElement(role: "AXWindow"), [Node(ArisTabElement(role: "AXWebArea", url: "file:///Users/p/a.html"))])
    check(address(local) == nil, "prompts tab: only an http(s) page counts")
    let deep = (0..<50).reduce(web) { child, _ in Node(ArisTabElement(role: "AXGroup"), [child]) }
    check(address(deep, limit: 20) == nil && address(deep)?.url == "https://example.com/page?q=1",
          "prompts tab: a read stops after its limit of elements")
    let screen = promptsSource("ArisTools/ArisScreen.swift")
    let ax = screen.range(of: "if let read = tabByAccessibility(browser) {"), granted = screen.range(of: "guard automationAlreadyGranted(browser) else {"),
        script = screen.range(of: "tab = appleScript(script, app: name)")
    check(ax != nil && granted != nil && script != nil && ax!.lowerBound < granted!.lowerBound && granted!.lowerBound < script!.lowerBound,
          "prompts tab: wiring: Accessibility first; the browser's scripting only when that gave nothing and Aris may already control it")
}

// MARK: - First setup, the Apple Event commands, Terminal

private func promptsWiringTests() {
    let setup = promptsSource("Aris/private/Aris/Onboarding/ArisOnboardingSystem.swift")
    check(!setup.contains("AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true)") && !setup.contains("askAutomation")
          && setup.contains("ArisAutomationAccess.state(of: target)"),
          "prompts setup: first setup's Music check only reads (no Automation dialog); Music is asked when it is first driven")
    check(ArisGrant.automation(.granted) == .granted && ArisGrant.automation(.denied) == .denied
          && ArisGrant.automation(.notAsked) == .undecided && ArisGrant.automation(.unknown) == .undecided,
          "prompts setup: the reading shows as the diagnostics' 켜짐 / 거부됨 / 꺼짐")
    let note = promptsSource("ArisTools/ArisNoteCommand.swift")
    let gate = note.range(of: "automationGate(notesBundle, app: \"Notes\", feature: .notes)"), first = note.range(of: "appleScript(ArisActions.noteScript(")
    check(gate != nil && first != nil && gate!.lowerBound < first!.lowerBound, "prompts notes: the rule is read before Notes' first Apple Event")
    let mac = promptsSource("ArisTools/ArisMac.swift")
    let contact = mac.range(of: "automationGate(\"com.apple.AddressBook\", app: \"Contacts\", feature: .findContact"),
        lookup = mac.range(of: "ArisActions.contactScript(who)"),
        messages = mac.range(of: "automationGate(\"com.apple.MobileSMS\", app: \"Messages\", feature: .sendMessages"),
        send = mac.range(of: "let sent = ArisMessageSend.deliver(")
    check(contact != nil && lookup != nil && contact!.lowerBound < lookup!.lowerBound && messages != nil && send != nil && messages!.lowerBound < send!.lowerBound,
          "prompts messages: the rule is read before Contacts' lookup and before Messages' send")
    let power = promptsSource("ArisTools/ArisPowerCommand.swift")
    let pass = power.range(of: "ArisMessagePass.consume(to: ArisMessagePass.powerName"), events = power.range(of: "automationGate(\"com.apple.systemevents\"")
    check(pass != nil && events != nil && pass!.lowerBound < events!.lowerBound && power.contains("ArisPowerRoute.withoutAppleEvents(verb)"),
          "prompts power: only after the user's yes on the card; then sleep by pmset, the others after the rule")
    let opener = promptsSource("ArisAgent/ArisTerminalOpener.swift")
    check(opener.contains("case .document(let scriptPath, let launchScript):") && opener.contains("try write(launchScript, to: scriptPath, mode: 0o700)"),
          "prompts terminal: the teammate's login window opens Terminal with the launch script as its document (no Apple Event)")
    let tools = promptsSource("ArisTools/ArisAutomationGate.swift")
    check(tools.contains("configuration.activates = false") && tools.contains("configuration.hides = true")
          && !tools.contains("AEDeterminePermissionToAutomateTarget"),
          "prompts gate: an app that isn't running is started hidden and behind (as osascript would start it) and only read about, never asked")
}

func runPromptsTests() {
    promptsAutomationStepTests()
    promptsRouteTests()
    promptsCalendarTests()
    promptsTabTests()
    promptsWiringTests()
}
