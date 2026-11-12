// Tests for the fixes of the VM fourth re-check (int at 8a8fd71e): the helper inside the app is never listed as a
// second "Aris" (vm4 1); the calendar card shows the day the answer is about and no to-dos (vm4 2); a request too long
// to take is refused before the screen is captured (vm4 3); keys typed in the instant of a press that opens a field are
// held for it (vm4 4); a conversation answer that says it sent something no send went out for is followed by Aris's
// own line (vm4 5). Nothing of the user's is read or changed.
// Called from main.swift; uses its check().
import AppKit
import Foundation

func runFix8Tests() {
    fix8HelperListingTests()
    fix8CalendarCardDayTests()
    MainActor.assumeIsolated { fix8LongRequestCaptureTests() }
    fix8KeyHoldRuleTests()
    MainActor.assumeIsolated { fix8KeyHoldPanelTests() }
    fix8SendClaimTests()
}

// MARK: - vm4 1: the helper's own id in what LaunchServices lists

private func fix8HelperListingTests() {
    let appInfo: [String: Any] = ["CFBundleIdentifier": "com.lumenjsn.aris", "CFBundleExecutable": "Aris", "CFBundleName": "Aris",
                                  "CFBundleDisplayName": "Aris", "LSUIElement": true, "ArisCommit": "8a8fd71e"]
    let agent = ArisHelperListing.changes(info: appInfo, program: "/Applications/Aris.app/Contents/MacOS/aris-agent")
    check(agent == ["CFBundleIdentifier": "com.lumenjsn.aris.agent", "CFBundleName": "aris-agent", "CFBundleDisplayName": "aris-agent"],
          "vm4 1: aris-agent inside Aris.app is listed under its own id and name, never the app's com.lumenjsn.aris or \"Aris\"")
    let tools = ArisHelperListing.changes(info: appInfo, program: "/Applications/Aris.app/Contents/MacOS/aris-tools")
    check(tools?["CFBundleIdentifier"] == "com.lumenjsn.aris.tools" && tools?["CFBundleName"] == "aris-tools",
          "vm4 1: aris-tools inside the app likewise gets its own id (it asks for the screens too)")
    check(ArisHelperListing.changes(info: appInfo, program: "/Applications/Aris.app/Contents/MacOS/Aris") == nil,
          "vm4 1: the app's own program keeps the app's id: a quit sent to com.lumenjsn.aris still reaches the app")
    check(ArisHelperListing.changes(info: [:], program: "/Users/p/build/aris-agent") == nil
          && ArisHelperListing.changes(info: ["CFBundleIdentifier": "aris-agent"], program: "/Users/p/build/aris-agent") == nil,
          "vm4 1: a loose copy (no app around it) changes nothing")

    // Applied to a dictionary as CFBundle holds it: only the id and the names change, the rest stays (the commit the
    // helper reads from the app's Info.plist, LSUIElement), and a second call changes nothing more.
    let held = NSMutableDictionary(dictionary: appInfo)
    if let agent { ArisHelperListing.apply(agent, to: held) }
    let after = held as? [String: Any] ?? [:]
    check(after["CFBundleIdentifier"] as? String == "com.lumenjsn.aris.agent" && after["ArisCommit"] as? String == "8a8fd71e"
          && after["LSUIElement"] as? Bool == true && after["CFBundleExecutable"] as? String == "Aris",
          "vm4 1: applied, the id and names change and the build stamp and the rest of the app's info stay")
    check(ArisHelperListing.changes(info: after, program: "/Applications/Aris.app/Contents/MacOS/aris-agent") == nil,
          "vm4 1: settling twice changes nothing more (no com.lumenjsn.aris.agent.agent)")
    check(ArisHelperListing.suffix(of: "aris-agent") == "agent" && ArisHelperListing.suffix(of: "odd name") == "odd-name",
          "vm4 1: the id's last part is the program's short name, made of what a bundle id may hold")
}

// MARK: - vm4 2: the calendar card shows the day the answer is about, and no to-dos

private func fix8Calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return calendar
}

private func fix8At(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    fix8Calendar().date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .now
}

private func fix8Item(_ title: String, start: Date, hours: Double = 1, allDay: Bool = false, kind: ArisEventKind = .event(.accepted)) -> ArisCalendarEvent {
    ArisCalendarEvent(id: title, start: start, end: start.addingTimeInterval(hours * 3_600), title: title, location: nil, notes: nil, url: nil, isAllDay: allDay,
                      kind: kind, calendar: ArisCalendarInfo(id: "home", account: "iCloud", title: "Home", color: .systemBlue, isSubscribed: false,
                                                             isReminderList: kind.isReminder),
                      participants: [], timeZone: nil, hasRecurrence: false, isDetached: false, priority: nil, meetingLink: nil)
}

private func fix8CalendarCardDayTests() {
    let calendar = fix8Calendar()
    let now = fix8At(12, 9, 30)  // Thursday 12 November 2026
    let D = ArisCalendarCardDay.self
    let plain = ArisWidgetRequest(kind: .calendar)

    // The tester's turn: "what's on my calendar tomorrow", the block naming no day.
    let tomorrow = D.resolve(plain, asked: "what's on my calendar tomorrow", now: now, calendar: calendar)
    check(tomorrow?.day == "2026-11-13", "vm4 2: a calendar card under \"what's on my calendar tomorrow\" is tomorrow's, though the block named no day")
    check(D.resolve(plain, asked: "내일 일정 뭐 있어?", now: now, calendar: calendar)?.day == "2026-11-13"
          && D.resolve(plain, asked: "내일모레 일정은?", now: now, calendar: calendar)?.day == "2026-11-14"
          && D.resolve(plain, asked: "what about the day after tomorrow", now: now, calendar: calendar)?.day == "2026-11-14"
          && D.resolve(plain, asked: "어제 뭐 있었지", now: now, calendar: calendar)?.day == "2026-11-11",
          "vm4 2: 내일, 모레, the day after tomorrow and 어제 are placed")
    check(D.resolve(plain, asked: "what's on Saturday?", now: now, calendar: calendar)?.day == "2026-11-14"
          && D.resolve(plain, asked: "목요일 일정", now: now, calendar: calendar)?.day == nil
          && D.resolve(plain, asked: "Monday's plans", now: now, calendar: calendar)?.day == "2026-11-16",
          "vm4 2: a weekday is the coming one (today when it is that day)")
    check(D.resolve(plain, asked: "what's on my calendar", now: now, calendar: calendar)?.day == nil
          && D.resolve(plain, asked: "오늘 일정 알려줘", now: now, calendar: calendar)?.day == nil,
          "vm4 2: no day named, or today: today's card as before")
    check(D.resolve(plain, asked: "when does my last meeting today end?", now: now, calendar: calendar) == plain
          && D.resolve(plain, asked: "what's next on my calendar", now: now, calendar: calendar) == plain,
          "vm4 2: \"last\" and \"next\" alone name no other day")
    check(D.resolve(plain, asked: "what's on next Friday?", now: now, calendar: calendar) == nil
          && D.resolve(plain, asked: "다음 주 일정", now: now, calendar: calendar) == nil
          && D.resolve(plain, asked: "11월 20일 일정 알려줘", now: now, calendar: calendar) == nil
          && D.resolve(plain, asked: "what's on Nov 20", now: now, calendar: calendar) == nil,
          "vm4 2: a day it can't place, with no day in the block, gets no card rather than today's")
    let blockDay = ArisWidget.request(in: "Nov 20: the recital.\n```aris-card\n{\"type\":\"calendar\",\"day\":\"2026-11-20\"}\n```")
    check(blockDay?.day == "2026-11-20" && D.resolve(blockDay!, asked: "what's on Nov 20", now: now, calendar: calendar)?.day == "2026-11-20",
          "vm4 2: the day the brain wrote in its block is the card's when the question names none it can place")
    check(D.resolve(ArisWidgetRequest(kind: .calendar, day: "2026-11-13"), asked: "오늘 일정 알려줘", now: now, calendar: calendar)?.day == nil,
          "vm4 2: a day the question names plainly comes before the block's")
    check(ArisWidget.request(in: "x\n```aris-card\n{\"type\":\"calendar\",\"day\":\"tomorrow\"}\n```") == nil
          && ArisWidget.request(in: "x\n```aris-card\n{\"type\":\"calendar\",\"day\":\"2026-02-30\"}\n```") == nil
          && ArisWidget.request(in: "x\n```aris-card\n{\"type\":\"calendar\"}\n```") == ArisWidgetRequest(kind: .calendar),
          "vm4 2: a block's day that is no real yyyy-MM-dd date makes no card; a block without one is a calendar card")
    check(D.resolve(ArisWidgetRequest(kind: .weather, place: "Lisbon"), asked: "weather tomorrow in Lisbon", now: now, calendar: calendar)
          == ArisWidgetRequest(kind: .weather, place: "Lisbon"), "vm4 2: other cards are not touched by the day words")

    // The card's rows: calendar events only; the due to-do and the ticked one are never "All day" rows.
    let items = [fix8Item("Dentist", start: fix8At(13, 10)), fix8Item("Piano lesson", start: fix8At(13, 17)),
                 fix8Item("water the ferns", start: fix8At(13, 0), allDay: true, kind: .reminder(completed: false)),
                 fix8Item("Pay the 80 dollar choir fee", start: fix8At(13, 0), allDay: true, kind: .reminder(completed: true))]
    let rows = D.rows(items)
    check(rows.map(\.title) == ["Dentist", "Piano lesson"], "vm4 2: the card's rows leave out every reminder, due or ticked")

    // Tomorrow's card: its events, its header, no "next" chip, and today's events not on it.
    let card = ArisCalendarCard.make(rows + [ArisWidgetEvent(start: fix8At(12, 15), end: fix8At(12, 16), title: "tea with sam", location: nil, allDay: false)],
                                     now: now, day: D.date("2026-11-13", calendar: calendar), calendar: calendar, english: true, locale: Locale(identifier: "en_US"))
    check(card.rows.map(\.title) == ["Dentist", "Piano lesson"] && card.rows.map(\.time) == ["10:00", "17:00"],
          "vm4 2: tomorrow's card lists tomorrow's events, not today's tea")
    check(card.title == "Tomorrow" && card.trailing.contains("13") && card.rows.allSatisfy { $0.state == .later && $0.chip == nil },
          "vm4 2: its header says Tomorrow with the date, and no row is marked as next or carries a countdown")
    let korean = ArisCalendarCard.make([], now: now, day: D.date("2026-11-13", calendar: calendar), calendar: calendar, english: false)
    check(korean.title == "내일 일정" && korean.empty == "내일은 일정이 없어요" && korean.rows.isEmpty, "vm4 2: an empty tomorrow says so, in Korean too")
    let saturday = ArisCalendarCard.make([], now: now, day: D.date("2026-11-14", calendar: calendar), calendar: calendar, english: true, locale: Locale(identifier: "en_US"))
    check(saturday.title == "Saturday" && saturday.empty == "Nothing on the calendar that day", "vm4 2: a later day is headed by its weekday")
    let today = ArisCalendarCard.make([ArisWidgetEvent(start: fix8At(12, 15), end: fix8At(12, 16), title: "tea with sam", location: nil, allDay: false)],
                                      now: now, calendar: calendar, english: true, locale: Locale(identifier: "en_US"))
    check(today.title == "Today" && today.rows.first?.state == .next, "vm4 2: today's card is as before")

    // Kept in the history with its day, and shown again for that day.
    let kept = ArisHistoryCard(request: ArisWidgetRequest(kind: .calendar, day: "2026-11-13"), values: .calendar(rows))
    let back = (try? JSONEncoder().encode(kept)).flatMap { try? JSONDecoder().decode(ArisHistoryCard.self, from: $0) }
    let old = try? JSONDecoder().decode(ArisHistoryCard.self, from: Data(#"{"kind":"calendar","values":{"calendar":{"_0":[]}}}"#.utf8))
    check(back?.request?.day == "2026-11-13" && old?.request == ArisWidgetRequest(kind: .calendar),
          "vm4 2: the history keeps the card's day, and a card kept before has none (today)")
    check(ArisAgentPrompt.cardRule(calendar: true).contains("\"day\":\"<that day as YYYY-MM-DD>\"") && !ArisAgentPrompt.cardRule(calendar: false).contains("day\""),
          "vm4 2: every brain is told to name the day of a calendar card that isn't today's")
}

// MARK: - vm4 3: a request too long to take captures nothing

@MainActor private func fix8LongRequestCaptureTests() {
    var shots = 0, grantReads = 0
    func make() -> ArisTurnCapture {
        ArisTurnCapture(dependencies: .init(
            shoot: { shots += 1; return ArisTurnCapture.Shot(png: Data([0x89, 0x50, 0x4E, 0x47]), ms: 5, retried: false) },
            enabled: { true }, permission: { grantReads += 1; return true }, nextNotice: { nil }, notify: { _ in },
            waitAtSend: .milliseconds(100), keepFor: .seconds(5)))
    }
    // The tester's turn: 25,000 characters that point at the screen.
    let long = "Summarize what's on my screen. " + String(repeating: "lantern ", count: 25_000 / 8)
    let refused = make()
    refused.began(notchShowsAnswer: false)
    let started = refused.heard(long)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    check(ArisAgentCopy.overLimit(long) && !started && shots == 0 && grantReads == 0 && !refused.attempted,
          "vm4 3: a request over the length limit that points at the screen takes no screenshot and reads no grant before it is refused")
    let short = make()
    short.began(notchShowsAnswer: false)
    let shortStarted = short.heard("what's on my screen")
    let deadline = Date().addingTimeInterval(2)
    while shots == 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    check(shortStarted && shots == 1 && short.attempted, "vm4 3: the same words within the limit still capture the screen")
    short.cancel()
}

// MARK: - vm4 4: keys typed in the instant of a press that opens a field, whatever had the keyboard before

private func fix8KeyHoldRuleTests() {
    let R = ArisKeyHoldRules.self
    check(R.holdsAfterPress(onField: false) && !R.holdsAfterPress(onField: true),
          "vm4 4: a press beside the fields holds the keys typed with it, whether or not a field was being typed in")
    check(R.holdable(keyCode: 4, command: false, control: false) && R.holdable(keyCode: 51, command: false, control: false)
          && !R.holdable(keyCode: 53, command: false, control: false) && !R.holdable(keyCode: 36, command: false, control: false)
          && !R.holdable(keyCode: 48, command: false, control: false) && !R.holdable(keyCode: 9, command: true, control: false)
          && !R.holdable(keyCode: 8, command: false, control: true),
          "vm4 4: letters and Delete are held; Esc, Return, Tab and ⌘/⌃ shortcuts go on as typed")
    check(R.outcome(fieldReady: true, final: false) == .send && R.outcome(fieldReady: false, final: false) == .wait
          && R.outcome(fieldReady: false, final: true) == .drop && R.outcome(fieldReady: true, final: true) == .send,
          "vm4 4: held keys go to the field once it has the keyboard, wait while none has it, and go nowhere when none took it in time")
}

/// The notch's panel right after an answer: key for a card's keys (armed), no field of it being typed in.
private final class F8Panel: NSPanel, ArisKeyPanel {
    override var canBecomeKey: Bool { MainActor.assumeIsolated { ArisPanelKeys.canBecomeKey(armed: true) } }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let made = super.makeFirstResponder(responder)
        MainActor.assumeIsolated { ArisPanelKeys.responderChanged(firstResponder, in: self) }
        return made
    }

    override func resignKey() {
        super.resignKey()
        MainActor.assumeIsolated { ArisPanelKeys.lostKey(self) }
    }
}

@MainActor private func fix8Spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

/// A press and its release beside the panel's fields, handed to this process's own NSApp (nothing is posted).
@MainActor private func fix8Press(_ panel: NSWindow, at point: NSPoint) {
    let time = ProcessInfo.processInfo.systemUptime
    guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: time, windowNumber: panel.windowNumber,
                                        context: nil, eventNumber: 81, clickCount: 1, pressure: 1),
          let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: time + 0.02, windowNumber: panel.windowNumber,
                                      context: nil, eventNumber: 82, clickCount: 1, pressure: 0) else { return }
    NSApp.sendEvent(down)
    NSApp.sendEvent(up)
}

/// A key typed into the panel, handed to this process's own NSApp.
@MainActor private func fix8Key(_ panel: NSWindow, _ text: String, code: UInt16) {
    guard let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: panel.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
                                     isARepeat: false, keyCode: code) else { return }
    NSApp.sendEvent(key)
}

/// The panel 20,000 points off every display, fully transparent; no app is brought forward (activate and giveBack
/// are counted), nothing is posted to the system.
@MainActor private func fix8KeyHoldPanelTests() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    var givenBack = 0
    let realActivate = ArisPanelKeys.activate, realUser = ArisPanelKeys.isUserPress, realBack = ArisPanelKeys.giveBack
    ArisPanelKeys.activate = {}
    ArisPanelKeys.isUserPress = { _ in true }
    ArisPanelKeys.giveBack = { _ in givenBack += 1 }
    defer {
        ArisPanelKeys.activate = realActivate
        ArisPanelKeys.isUserPress = realUser
        ArisPanelKeys.giveBack = realBack
    }
    ArisPanelKeys.installPressMonitor()
    let panel = F8Panel(contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 90), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    panel.alphaValue = 0
    panel.isReleasedWhenClosed = false
    panel.orderFrontRegardless()
    panel.makeKey()
    fix8Spin(0.2)
    let editor = NSTextField(frame: NSRect(x: 10, y: 50, width: 200, height: 24))
    let pencil = NSPoint(x: 260, y: 60)
    check(!ArisPanelKeys.focus.editing && panel.firstResponder === panel, "vm4 4: (right after an answer: no field of the panel has the keyboard)")

    // The tester's trial: the pencil pressed and a key in the same instant; the editor takes its field a moment later.
    fix8Press(panel, at: pencil)
    fix8Key(panel, "w", code: 13)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        panel.contentView?.addSubview(editor)
        _ = panel.makeFirstResponder(editor)
    }
    fix8Spin(0.7)
    check(editor.stringValue == "w" && ArisPanelKeys.focus.editing,
          "vm4 4: a key typed with the pencil press when no field had the keyboard lands in the editor the press opened")

    // A press that opens no field: the key typed with it goes nowhere (not into the old field, not given anywhere).
    _ = panel.makeFirstResponder(nil)
    editor.removeFromSuperview()
    fix8Spin(ArisPanelKeys.handOver + 0.3)
    let backBefore = givenBack
    fix8Press(panel, at: pencil)
    fix8Key(panel, "q", code: 12)
    fix8Spin(0.7)
    check(editor.stringValue == "w" && givenBack == backBefore, "vm4 4: with no field opened by the press, the held key is dropped and sent nowhere else")
    panel.orderOut(nil)
    panel.close()
}

// MARK: - vm4 5: "I sent it" in a conversation's answer when nothing was sent

private func fix8SendClaimTests() {
    let tools = "/Users/p/.config/aris/aris-tools"
    let C = ArisSendClaim.self
    let asked = "Summarize the following in two sentences and send mom that summary as a text message: The harbour town wakes slowly in winter."
    // The tester's answer, word for word (g4-10d), with no tool called.
    let tester = """
    The summary I sent mom: the town is a slow-waking winter harbour where children walk the sea wall, ferries bring lighthouse-snapping \
    tourists, and fishing boats knock against the pier while gulls fight over scraps. Evening brings blinking harbour lights and a ferry \
    waiting at the pier, while old sailors play cards and complain about the weather, the council argues over breakwater repairs, and the \
    bakery on Water Street sells out of rye by nine.

    **Sent**
    - To: mom
    - The passage repeated the same handful of details many times, so the summary covers each one once.
    """
    let line = C.note(tester, request: asked, record: .init(), tools: tools, korean: false)
    check(line == "It was not sent. To send it for real, ask me again.",
          "vm4 5: the tester's \"The summary I sent mom: …\" with no tool called gets Aris's own line that it was not sent")
    check(C.note("요약을 엄마에게 보냈어요: 겨울 항구 마을 이야기예요.", request: "이거 요약해서 엄마한테 문자로 보내 줘", record: .init(), tools: tools, korean: true)
          == "보내지 않았어요. 실제로 보내려면 다시 말해 주세요.", "vm4 5: the same in Korean, with the Korean line")

    // A summary that merely mentions "sent", quotes it, or supposes it: nothing added.
    let mentions = "Here is the summary: the harbourmaster sent the ferry back, and the letters were sent in spring. Want me to send it to mom?"
    check(C.note(mentions, request: asked, record: .init(), tools: tools, korean: false) == nil,
          "vm4 5: a summary that only mentions something being sent, by someone else, adds nothing")
    check(C.note("The note says \"I sent the invoice on Monday\" and asks for payment.", request: asked, record: .init(), tools: tools, korean: false) == nil
          && C.note("The email reads:\n> I sent the invoice on Monday.\nIt asks for payment.", request: asked, record: .init(), tools: tools, korean: false) == nil,
          "vm4 5: \"I sent\" inside quotation marks or a quoted line is the text's, not a claim")
    check(C.note("If I sent this now, mom would get two sentences. Shall I send it?", request: asked, record: .init(), tools: tools, korean: false) == nil
          && C.note("I would have sent it, but I need you to confirm first.", request: asked, record: .init(), tools: tools, korean: false) == nil,
          "vm4 5: a supposition (\"if I sent\", \"I would have sent\") is no claim")
    check(C.note("엄마가 사진을 보냈어요. 요약하면 겨울 항구 이야기예요.", request: "이거 요약해서 엄마한테 보내 줘", record: .init(), tools: tools, korean: true) == nil
          && C.note("아직 못 보냈어요. 보낼까요?", request: "엄마한테 보내 줘", record: .init(), tools: tools, korean: true) == nil,
          "vm4 5: a Korean sentence with someone else as its subject, or \"못 보냈어요\", is no claim")
    check(C.note("I sent mom the summary.", request: "Summarize this page in two sentences.", record: .init(), tools: tools, korean: false) == nil,
          "vm4 5: a request that asked for no send adds nothing")

    // A send that went through, by a yes on its card or with no card: nothing added.
    let send = "\(tools) message mom 'The town is a slow-waking winter harbour.'"
    var yes = ArisJobClaim.Cards()
    yes.note(.shell(send), allowed: true)
    check(C.note("I sent mom the summary.", request: asked, record: .init(commands: [send], cards: yes), tools: tools, korean: false) == nil,
          "vm4 5: a real send that went through on a yes is never called unsent")
    check(C.note("I sent mom the summary.", request: asked, record: .init(commands: [send]), tools: tools, korean: false) == nil,
          "vm4 5: nor one that went out with no card (a standing permission)")
    // Its card got a no: nothing was sent, and the line is added.
    var no = ArisJobClaim.Cards()
    no.note(.shell(send), allowed: false)
    check(C.note("I've sent mom the summary.", request: asked, record: .init(commands: [send], cards: no), tools: tools, korean: false) != nil,
          "vm4 5: a send whose card got a no or no answer, and nothing else that could send: the line is added")
    // Anything that might have sent another way: in doubt, nothing added.
    check(C.note("I sent it.", request: asked, record: .init(commands: ["\(tools) desktop type @e2 --stdin"]), tools: tools, korean: false) == nil
          && C.note("I sent it.", request: asked, record: .init(commands: ["\(tools) mcp call gmail send '{}'"]), tools: tools, korean: false) == nil
          && C.note("I sent it.", request: asked, record: .init(commands: ["osascript -e 'tell application \"Messages\" to send'"]), tools: tools, korean: false) == nil
          && C.note("I sent it.", request: asked, record: .init(otherTools: true), tools: tools, korean: false) == nil,
          "vm4 5: the desktop, a connected service, a command not Aris's own or another tool: nothing is added")
    check(C.note("I sent it.", request: asked, record: .init(commands: ["\(tools) weather", "\(tools) mail recent"]), tools: tools, korean: false) != nil,
          "vm4 5: reads that cannot send (the weather, recent mail) do not stop the line")
    check(!tester.contains("It was not sent"), "vm4 5: the model's own text is left as it was (the line only follows it)")
}
