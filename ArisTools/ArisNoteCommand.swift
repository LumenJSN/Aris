//
//  ArisNoteCommand.swift
//  aris-tools
//
//  `note "<text>"` adds an Apple Notes note in the background, each line on its own line. `note "<title>" --checklist
//  "<item>" …` adds a list the way Notes shows one: the title, then a checklist with one item per line. `note --markdown
//  "<md>"` adds the answer shape (ArisNoteMarkdown): a title, subheadings, lists, bold, tables, and its `- [ ]` items as
//  real checklists. Notes' AppleScript can't make checklist items, so a note with any is opened and each checklist's
//  paragraphs get Notes' own Format › Checklist (⇧⌘L), sent to Notes alone, only while Notes stays in front, only into
//  the note's text, and only once the text on screen is the planned note (its title and the paragraphs the keys count
//  over), and right before each ⇧⌘L the same note, its text focused and exactly that list's items selected. At most
//  ArisNoteMarkdown.listLimit lists and keyBudget keys a note. When that can't be done safely the items stay plain
//  lines, and it says so. Only a turn the user is in front of (ARIS_FOREGROUND, set by aris-agent for the conversation and
//  his own 메모에 저장) brings Notes forward: a background job, a scheduled run or a teammate's note stays in the
//  background with its items as plain lines. A note with no checklist always stays in the background.
//

import AppKit

private let notesBundle = "com.apple.Notes"
/// Set by aris-agent only for a turn the user is in front of.
private let foregroundKey = "ARIS_FOREGROUND"

func note(_ args: [String]) {
    switch ArisActions.noteRequest(args) {
    case .invalid:
        fail("usage: note <text> | note <title> --checklist <item> <item> … | note --markdown '<markdown>'")
    case .plain(let lines):
        _ = appleScript(ArisActions.noteScript(body: ArisActions.noteBody(title: lines[0], lines: Array(lines.dropFirst())), show: false), app: "Notes")
        logActivity(ArisActSummary.noteSaved(lines[0]), undo: nil)
        print("note added")
    case .checklist(let title, let items):
        add(ArisNoteMarkdown.checklist(title: title, items: items))
    case .markdown(let markdown):
        guard let plan = ArisNoteMarkdown.plan(markdown) else { fail("usage: note --markdown '<title line, then markdown>'") }
        add(plan)
    }
}

private func add(_ plan: ArisNoteMarkdown.Plan) {
    let foreground = ProcessInfo.processInfo.environment[foregroundKey] == "1"
    let show = foreground && !plan.groups.isEmpty
    let id = appleScript(ArisActions.noteScript(body: plan.html, show: show), app: "Notes")
    logActivity(ArisActSummary.noteSaved(plan.title), undo: nil)
    if plan.groups.isEmpty { return print("note added: \(plan.title)") }
    if !show { return print("note added: \(plan.title), its lists as plain lines (not a turn the user is in front of, so Notes stayed in the background)") }
    print(checklistOutcome(note: id, plan: plan))
}

/// What the checklist keys did, said plainly: verified, pressed but not confirmed (the user should check), or not tried.
private func checklistOutcome(note id: String, plan: ArisNoteMarkdown.Plan) -> String {
    let items = plan.groups.reduce(0) { $0 + $1.count }
    let lists = plan.groups.count == 1 ? "a checklist of \(items)" : "\(plan.groups.count) checklists (\(items) items)"
    let pressing = ArisNoteMarkdown.pressing(plan)
    let failures = makeChecklists(note: id, plan: plan, lists: pressing.lists)
        + Array(repeating: "over \(ArisNoteMarkdown.listLimit) lists, \(ArisNoteMarkdown.keyBudget) keys or too far in", count: pressing.skipped)
    if failures.count == plan.groups.count, let reason = failures.first {
        return "note added: \(plan.title) with \(items) lines, but not as a checklist (\(reason))"
    }
    let partly = failures.isEmpty ? "" : "; \(failures.count) of its lists stayed plain lines (\(failures[0]))"
    let body = runCapturing("/usr/bin/osascript", ["-e", "tell application \"Notes\" to return body of note id \(ArisActions.quoted(id))"])
    if body.status == 0, ArisActions.isChecklist(body.printed) { return "note added: \(plan.title) with \(lists)\(partly)" }
    return "note added: \(plan.title); Notes' checklist key (⇧⌘L) was pressed on its \(items) items, but it couldn't be confirmed: ask the user to check\(partly)"
}

/// Presses Notes' checklist keys on each list's paragraphs; the reasons any weren't, one per list.
private func makeChecklists(note id: String, plan: ArisNoteMarkdown.Plan, lists: [(group: ArisNoteMarkdown.Group, keys: [String])]) -> [String] {
    var failures: [String] = []
    for list in lists {
        if let reason = makeChecklist(note: id, plan: plan, group: list.group, keys: list.keys) {
            failures.append(reason)
            // Nothing about Notes changes for the next list: don't try again into a note that isn't ours or isn't in front.
            if reason == notOurs || reason == notInFront { return failures + Array(repeating: reason, count: lists.count - failures.count) }
        }
    }
    return failures
}

private let notOurs = "another note is open"
private let notInFront = "Notes left the front"

/// The reason one checklist's keys weren't pressed, or nil when they were.
private func makeChecklist(note id: String, plan: ArisNoteMarkdown.Plan, group: ArisNoteMarkdown.Group, keys: [String]) -> String? {
    guard AXIsProcessTrusted() else { return "Aris may not press keys: \(ArisFix.Pane.accessibility.title(english: true)) is off" }
    guard let notes = NSRunningApplication.runningApplications(withBundleIdentifier: notesBundle).first?.processIdentifier else {
        return "Notes isn't running"
    }
    // Notes may still be coming to the front (it was just opened): wait for it, a little.
    guard waitForFront(notes) else { return notInFront }
    // Only the note just made: never keys into another note.
    guard isOurNote(id) else { return notOurs }
    // Only into the note's text, and only when it reads as planned (never into the note list or the search field).
    guard let text = focusedNoteText(notes) else { return "the note's text couldn't be focused" }
    guard ArisNoteMarkdown.matchesGroup(text: text, group: group, plan: plan) else { return "the note on screen isn't laid out as planned" }
    for (index, key) in keys.enumerated() {
        guard let chord = ArisKeyChord.parse(key, layout: ArisKeyLayout.current) else { return "unknown key \(key)" }
        // Right before ⇧⌘L (the one key that changes the note): still our note, its text focused, and exactly the
        // list's items selected.
        if index == keys.count - 1 {
            usleep(120_000)
            guard isOurNote(id) else { return notOurs }
            guard let selected = selectedNoteText(notes) else { return "the note's text lost the keys" }
            guard ArisNoteMarkdown.selectionMatches(selected, group: group, plan: plan) else { return "the selection wasn't exactly the list" }
        }
        // The user may have switched apps: every key checks that Notes is still in front, and goes to Notes alone.
        guard ArisFrontLive.frontPid() == notes else { return notInFront }
        press(chord, into: notes)
        usleep(80_000)
    }
    usleep(150_000)
    return nil
}

/// The note Notes has selected is the one just made.
private func isOurNote(_ id: String) -> Bool {
    let open = runCapturing("/usr/bin/osascript", ["-e", "tell application \"Notes\" to return id of item 1 of (get selection)"])
    return open.status == 0 && open.printed.trimmingCharacters(in: .whitespacesAndNewlines) == id
}

/// What's selected in the note's text, when the focused element is still a text area.
private func selectedNoteText(_ pid: pid_t) -> String? {
    guard let focused = attribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
          role(of: focused) == kAXTextAreaRole as String else { return nil }
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
    return value as? String
}

/// Notes in front within about 2.5 seconds.
private func waitForFront(_ pid: pid_t) -> Bool {
    for _ in 0..<25 {
        if ArisFrontLive.frontPid() == pid { usleep(300_000); return true }
        usleep(100_000)
    }
    return false
}

/// The text of the note Notes has focused: its text area, focused first when the list or search field had the keys.
private func focusedNoteText(_ pid: pid_t) -> String? {
    let app = AXUIElementCreateApplication(pid)
    if let focused = attribute(app, kAXFocusedUIElementAttribute), role(of: focused) == kAXTextAreaRole as String {
        return text(of: focused)
    }
    guard let window = attribute(app, kAXFocusedWindowAttribute), let area = textArea(in: window, depth: 0) else { return nil }
    guard AXUIElementSetAttributeValue(area, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else { return nil }
    usleep(200_000)
    guard let focused = attribute(app, kAXFocusedUIElementAttribute), role(of: focused) == kAXTextAreaRole as String else { return nil }
    return text(of: focused)
}

private func attribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
          CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

private func role(of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
    return value as? String
}

private func text(of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
    return value as? String
}

/// The window's first text area (the note's body), breadth by depth, never deeper than 12.
private func textArea(in element: AXUIElement, depth: Int) -> AXUIElement? {
    guard depth < 12 else { return nil }
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let children = value as? [AXUIElement] else { return nil }
    if let area = children.first(where: { role(of: $0) == kAXTextAreaRole as String }) { return area }
    for child in children.prefix(60) {
        if let area = textArea(in: child, depth: depth + 1) { return area }
    }
    return nil
}

/// One key chord, posted to that process only.
private func press(_ chord: ArisKeyChord, into pid: pid_t) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: chord.key, keyDown: down)
        event?.flags = chord.flags
        event?.postToPid(pid)
        usleep(20_000)
    }
}
