// Tests for what the second upgrade VM run found in the top notch (build 126bc8fb; qa/vm-run-1111/
// REPORT-second-upgrade.md rows B12 and X7, bug 4): the request editor's keyboard, its Esc and Return, the closed
// band with files waiting, and files going with an edit. Called from main.swift; uses its check(). The presses here
// are NSEvents handed to this process's own NSApp in a panel 20,000 points off every display, fully transparent:
// nothing is posted to the system, no app is brought forward (ArisPanelKeys' activate and giveBack are counted).
import AppKit
import Foundation

private func vm2Source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The notch's panel as ArisNotchPanel has it (key through ArisPanelKeys, every first-responder change told to it).
private final class VM2Panel: NSPanel, ArisKeyPanel {
    override var canBecomeKey: Bool { MainActor.assumeIsolated { ArisPanelKeys.canBecomeKey(armed: false) } }

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

@MainActor private func vm2Spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

/// A press at `point` in the panel, seen first by ArisPanelKeys' press monitor. On a field the release waits in the
/// queue for the field's own tracking; elsewhere it is handed over after the press.
@MainActor private func vm2Press(_ panel: NSWindow, at point: NSPoint, onField: Bool) {
    let time = ProcessInfo.processInfo.systemUptime
    guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: time, windowNumber: panel.windowNumber,
                                        context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
          let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: time + 0.05, windowNumber: panel.windowNumber,
                                      context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else { return }
    if onField {
        NSApp.postEvent(up, atStart: false)
        NSApp.sendEvent(down)
    } else {
        NSApp.sendEvent(down)
        NSApp.sendEvent(up)
    }
}

/// B12 (1): the pencil must give the editor the keyboard in the same act. Found off screen with the real views
/// (tests/vnotch-render/keys.sh): from a composer being typed in, a press on the pencil made the composer step aside,
/// and its field letting go gave the keyboard back to the app the user was in before the editor's field took it, so the
/// keys went to that app until a second click into the card.
@MainActor private func vm2HandOverTests() {
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
    let panel = VM2Panel(contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 90), styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
    panel.alphaValue = 0
    panel.isReleasedWhenClosed = false
    let composer = NSTextField(frame: NSRect(x: 10, y: 10, width: 200, height: 24))
    let editor = NSTextField(frame: NSRect(x: 10, y: 50, width: 200, height: 24))
    panel.contentView?.addSubview(composer)
    panel.orderFrontRegardless()
    vm2Spin(0.2)
    let pencil = NSPoint(x: 260, y: 60)
    /// The pencil's act: the composer steps aside, and the editor is laid out and takes its field a moment later.
    func openEditor() {
        composer.removeFromSuperview()
        DispatchQueue.main.async {
            panel.contentView?.addSubview(editor)
            _ = panel.makeFirstResponder(editor)
        }
    }

    vm2Press(panel, at: NSPoint(x: 60, y: 20), onField: true)
    vm2Spin(ArisPanelKeys.keyCheckDelay + 0.3)
    check(ArisPanelKeys.focus.editing && composer.currentEditor() != nil, "vm2 B12: (the composer is being typed in, as in the VM run)")
    vm2Press(panel, at: pencil, onField: false)
    openEditor()
    vm2Spin(0.6)
    check(givenBack == 0, "vm2 B12: the composer stepping aside for the editor gives nothing back to the app the user was in")
    check(ArisPanelKeys.focus.editing && panel.isKeyWindow && editor.currentEditor() != nil,
          "vm2 B12: one press on the pencil and the editor's field has the keyboard in a key panel")

    // Esc in the editor long after the press: nothing takes over, so the keyboard goes back at once, as before.
    vm2Spin(ArisPanelKeys.pressOpensField + 0.2)
    editor.removeFromSuperview()
    vm2Spin(0.15)
    check(givenBack == 1 && !ArisPanelKeys.focus.editing, "vm2 B12: a field that closes with no press behind it gives the keyboard back at once, as before")

    // A press that opens no field: the keyboard still goes back, only after the hand-over wait.
    panel.contentView?.addSubview(composer)
    vm2Press(panel, at: NSPoint(x: 60, y: 20), onField: true)
    vm2Spin(ArisPanelKeys.keyCheckDelay + 0.3)
    vm2Press(panel, at: pencil, onField: false)
    composer.removeFromSuperview()
    vm2Spin(ArisPanelKeys.handOver + 0.3)
    check(givenBack == 2 && !ArisPanelKeys.focus.editing, "vm2 B12: a press that opens no field still gives the keyboard back, once the hand-over wait is over")
    check(ArisPanelKeys.handOver > 0 && ArisPanelKeys.handOver < ArisPanelKeys.pressOpensField,
          "vm2 B12: the hand-over wait is short, and within the time a press counts as opening a field")
    _ = panel.makeFirstResponder(nil)
    vm2Spin(0.1)
    panel.orderOut(nil)
    panel.close()

    let views = vm2Source("Aris/private/Aris/Home/ArisPromptEditViews.swift")
    check(views.contains(".background(ArisFieldAnchor(seat: seat)") && views.contains("NSWindow.didBecomeKeyNotification")
          && views.contains("ArisPanelKeys.take(window)") && !views.contains("NSEvent.mouseLocation"),
          "vm2 B12: wiring: the editor asks for the keyboard once its field is in the panel and again when the panel becomes key, through ArisPanelKeys")
}

/// B12 (1), the rule: a field letting go right after a press waits for the field that press opens.
private func vm2HandOverRuleTests() {
    let own: pid_t = 10, finder: pid_t = 20
    var focus = ArisPanelFocus()
    _ = focus.pressed(onField: true, frontmost: finder, own: own)
    check(focus.responder(takesKeys: false, pressedJustNow: true, opening: true) == .awaitField && focus.editing && focus.previous == finder,
          "vm2 B12: the composer letting go right after the pencil's press waits for the editor, still editing, the app to give back kept")
    check(focus.responder(takesKeys: true, frontmost: own, own: own, pressedJustNow: true) == .none && focus.editing && focus.previous == finder,
          "vm2 B12: the editor's field taking it over keeps the keyboard with Aris (and the app to give back later)")
    check(focus.responder(takesKeys: false) == .giveBack(finder) && !focus.editing,
          "vm2 B12: the editor letting go later (Esc, Return) gives the keyboard back to that app")
    var idle = ArisPanelFocus()
    check(idle.responder(takesKeys: false, pressedJustNow: true, opening: true) == .none, "vm2 B12: nothing to wait for when no field had the keyboard")
    var onField = ArisPanelFocus()
    _ = onField.pressed(onField: true, frontmost: finder, own: own)
    check(onField.responder(takesKeys: false, pressedJustNow: true) == .giveBack(finder),
          "vm2 B12: a field letting go right after a press on a field itself (no field is being opened) gives the keyboard back at once, as before")
}

/// ArisFieldLocator finds the field laid out over an anchor among the window's fields, and knows a field's own editor.
@MainActor private func vm2LocatorTests() {
    let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 120), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let top = NSTextField(frame: NSRect(x: 10, y: 80, width: 200, height: 24))
    let bottom = NSTextField(frame: NSRect(x: 10, y: 10, width: 200, height: 24))
    let label = NSTextField(labelWithString: "a label")
    label.frame = NSRect(x: 10, y: 80, width: 200, height: 24)
    let anchor = NSView(frame: NSRect(x: 12, y: 78, width: 190, height: 26))
    [label, top, bottom, anchor].forEach { window.contentView?.addSubview($0) }
    check(ArisFieldLocator.field(over: anchor) === top, "vm2 B12: the editor's field is the one laid out over its anchor (never the composer's, never a label)")
    anchor.removeFromSuperview()
    check(ArisFieldLocator.field(over: anchor) == nil, "vm2 B12: an anchor not in a window finds nothing yet (it is asked again)")
    check(ArisFieldLocator.holds(top, top) && !ArisFieldLocator.holds(bottom, top) && !ArisFieldLocator.holds(nil, top),
          "vm2 B12: the field itself counts as holding the keyboard, another field does not")
    _ = window.makeFirstResponder(top)
    check(ArisFieldLocator.holds(window.firstResponder, top) && !ArisFieldLocator.holds(window.firstResponder, bottom),
          "vm2 B12: so does the field's own editor while it is typed in")
    window.close()
}

/// B12 (2): Esc in the editor emptied its field and left it open. The field, on its way out, wrote its text back once
/// (by then the empty string of a draft that was gone), and that write opened the editor again, empty. Found off
/// screen with the real views (tests/vnotch-render/keys.sh; it fails on 0f817fea and passes now).
private func vm2EscTests() {
    typealias E = ArisPromptEdit
    check(E.draft(nil, typed: "") == nil && E.draft(nil, typed: "compare the weather") == nil,
          "vm2 B12: a field on its way out writing its text back never opens the editor again (Esc used to leave it open, emptied)")
    check(E.draft("compare the weather", typed: "compare the weather in Oslo") == "compare the weather in Oslo" && E.draft("a", typed: "") == "",
          "vm2 B12: while the editor is open what is typed is the draft, an emptied field included (Return then sends nothing)")
    check(E.escIsEditors(editing: true) && !E.escIsEditors(editing: false),
          "vm2 B12: Esc while a request is edited is the editor's alone; with no editor up Esc does what it does elsewhere")
    let turn = vm2Source("Aris/private/Aris/Home/ArisTurnView.swift")
    check(turn.contains("set: { draft = ArisPromptEdit.draft(draft, typed: $0) }") && turn.contains("send: sendEdit, cancel: endEdit"),
          "vm2 B12: wiring: the card's editor writes its draft through that rule, and its Esc throws the edit away")
    let views = vm2Source("Aris/private/Aris/Home/ArisPromptEditViews.swift")
    check(views.contains(".onExitCommand(perform: cancel)"), "vm2 B12: wiring: Esc in the field is the editor's cancel")
    let guardLine = "ArisPromptEdit.escIsEditors(editing: ArisPromptEditing.shared.active)"
    let conversation = vm2Source("Aris/private/Aris/ArisController+Conversation.swift"), widget = vm2Source("Aris/private/Aris/ArisWidgetModel.swift")
    check(conversation.contains("guard !\(guardLine) else { return }\n                aris.closeConversation(.escape)")
          && widget.contains("!\(guardLine) {\n                        ArisWidgetModel.shared.dismiss()"),
          "vm2 B12: wiring: the first Esc neither ends the conversation nor puts the parked card away; the next one does")
}

/// B12 (3): after Return the new turn ran but its card stayed empty. It was the editor still open over the new turn,
/// emptied by the same write-back as Esc (vm2EscTests); the typed path does not start a fresh card (the turn goes
/// straight to thinking), so the card that was edited is the new turn's card, and it now shows that turn's words.
private func vm2ReturnTests() {
    typealias E = ArisPromptEdit
    let edited = "what is the weather in Oslo right now"
    guard case .send(let words, let stopsFirst) = E.send(draft: edited + " ", phase: .idle, offer: .editable(saysDone: true)) else {
        return check(false, "vm2 B12: Return sends the edited words")
    }
    check(words == edited && !stopsFirst, "vm2 B12: Return sends the edited words, trimmed")
    let turn = ArisSession().listening().hearing(words).thinking()
    check(turn.phase == .thinking && turn.heard == edited && ArisPendingFiles.shown(turn.heard) == edited,
          "vm2 B12: the new turn has the edited words as its request from its first frame, so the card shows them at once")
    check(E.draft(nil, typed: "") == nil, "vm2 B12: and the editor, closed by Return, is not reopened empty over it")
    let typed = vm2Source("Aris/private/Aris/ArisController+Typed.swift"), view = vm2Source("Aris/private/Aris/Home/ArisTurnView.swift")
    check(typed.contains("session = ArisSession().listening().hearing(text).thinking()")
          && view.contains("if !session.heard.isEmpty { return (ArisPendingFiles.shown(session.heard), false) }")
          && view.contains("endEdit()\n        guard case .send(let words, let stopsFirst) = sent else { return }"),
          "vm2 B12: wiring: the typed path sets the request in one step, the card reads it from the turn, and the editor closes before the words are sent")
}

/// X7, as the tester did it on 126bc8fb: "show my to-dos" answered; "100 USD to KRW.pdf" given to Aris (its chip and
/// "Got 100 USD to KRW.pdf. What should I do with it?"); the pencil on that older request, edited to "list my to-dos",
/// Return. On that build the file went with the edit; 384ba605 (after that build) keeps it waiting. Replayed here
/// through the same pieces in the order the app calls them (ArisPromptPill.sendEdit, submitTyped, answer's take).
private func vm2FilesWithEditTests() {
    typealias E = ArisPromptEdit
    let pdf = URL(fileURLWithPath: "/private/tmp/g2drop/100 USD to KRW.pdf")
    let waiting = ArisPendingFiles().adding([pdf], at: Date())
    guard case .send(let words, _) = E.send(draft: "list my to-dos", phase: .idle, offer: .editable(saysDone: false)) else {
        return check(false, "vm2 X7: the edit is sent")
    }
    let token = E.Sent.sending(words)
    let said = ArisSession().listening().hearing(words).thinking().heard
    let asked = token.taken(by: said)
    let turn = waiting.taking(into: said, handsFree: false, shown: E.chipsInSight(notchOpen: true, editedRequest: asked.isEdit),
                              contents: { _ in "100 USD = 138,000 KRW" })
    check(asked.isEdit && turn.text == "list my to-dos" && !ArisPendingFiles.carriesFiles(turn.text) && turn.left.files == [pdf],
          "vm2 X7: the tester's steps: the edited older request goes out as \"list my to-dos\" alone, and the PDF keeps waiting")
    let next = turn.left.taking(into: "what is in this file", handsFree: false,
                                shown: E.chipsInSight(notchOpen: true, editedRequest: asked.left.taken(by: "what is in this file").isEdit),
                                contents: { _ in "100 USD = 138,000 KRW" })
    check(ArisPendingFiles.carriesFiles(next.text) && next.left.files.isEmpty,
          "vm2 X7: the next request asked from the composer, its chip back in sight, takes the PDF")
}

/// B12 and bug 4: with a file waiting and an answer parked the closed band showed the star and the blue dot, no
/// paperclip: the count was drawn only while the star rested. Now the count shows whenever files wait, and the
/// answer's dot (or the paused listening mark) rides on its corner.
private func vm2BandEarTests() {
    typealias E = ArisBandEar
    check(E.shows(resting: false, files: 1, handsFreeLock: false, answerDot: true, paused: false) == .files(count: 1, badge: .dot),
          "vm2 bug 4: an answer parked and a file waiting: the paperclip and \"1\", the answer's blue dot on the count's corner")
    check(E.shows(resting: false, files: 2, handsFreeLock: false, answerDot: false, paused: false) == .files(count: 2, badge: nil),
          "vm2 bug 4: while Aris works with files waiting: the paperclip and the count")
    check(E.shows(resting: false, files: 1, handsFreeLock: false, answerDot: true, paused: true) == .files(count: 1, badge: .paused),
          "vm2 bug 4: listening paused by another app's sound: the pause mark on the count's corner")
    check(E.shows(resting: true, files: 3, handsFreeLock: false, answerDot: false, paused: false) == .files(count: 3, badge: nil),
          "vm2 bug 4: at rest with files waiting: the paperclip and the count, as before")
    check(E.shows(resting: false, files: 1, handsFreeLock: true, answerDot: false, paused: false) == .lock,
          "vm2 bug 4: Aris listening by itself keeps its lock (a press ends the listening); the files wait in the open notch")
    check(E.shows(resting: false, files: 0, handsFreeLock: false, answerDot: true, paused: false) == .answer
          && E.shows(resting: true, files: 0, handsFreeLock: false, answerDot: false, paused: false) == .rest,
          "vm2 bug 4: with no files the ear is as before: the answer's dot, or the resting mute mark")
    let ear = ArisBand.earWidth(notchWidth: 224, body: 321)
    check(ArisVNotch.edgeInset + 13 + 4 + 15 <= ear && E.badgeSize / 2 - E.badgeInset < ArisVNotch.edgeInset,
          "vm2 bug 4: on the user's display the count and its badge fit in the ear beside the camera (a dot beside the count would not)")
    let activity = vm2Source("Aris/private/Aris/ArisActivity.swift")
    check(activity.contains("switch ArisBandEar.shows(resting: resting, files: files.files.count, handsFreeLock: lock, answerDot: dot != nil, paused: paused)")
          && activity.contains("case .turn, .parked, .home:\n            starEar")
          && activity.contains("ArisAttachCount(count: count, dot: badge == .dot ? dot : nil, paused: badge == .paused)"),
          "vm2 bug 4: wiring: the turn's, the parked answer's and the resting band all ask the one rule")
}

func runVNotchVM2Tests() {
    vm2HandOverRuleTests()
    vm2EscTests()
    vm2ReturnTests()
    vm2FilesWithEditTests()
    vm2BandEarTests()
    MainActor.assumeIsolated {
        vm2HandOverTests()
        vm2LocatorTests()
    }
}
