//
//  ArisDesktopTextLadder.swift
//  aris-agent
//
//  Typing into a field, one rung at a time until the field reads the text back (the benchmark: a field that isn't
//  focused ignores background typing; set-value can report "ok" that the app never commits). Focus it (a background
//  click) unless it already has the focus, and look again: the field itself must have the focus, and it must not be a
//  password field, before anything is typed. Type in the background into the pinned window. Another rung runs only when
//  Peekaboo says nothing reached the app (`retry_safe` and nothing dispatched) and the field is exactly as it was: never
//  after an unverified or dispatched type, so nothing is ever typed twice. Setting the field's value (what it held plus
//  the text) is a rung only when nothing at all was dispatched, the field's raw value is known in full, and the app
//  doesn't send (a sending app never has its field rewritten). Bringing the window forward to type for real is the last
//  rung: only with the user's yes on a card, only in a turn they is there for (never a background job), the focus checked again
//  right before the keys go (security review C2, I5, I6).
//

import Foundation

extension ArisDesktopSession {
    static let foregroundCard = "앞으로 가져와서 할게요"
    /// How old a look may be before the foreground rung looks at the window again (a seam for the tests).
    nonisolated(unsafe) static var staleLook: TimeInterval = 5
    /// How every type that isn't confirmed begins (QA BUG-10), so the brain can't call it done.
    static let notTypedLead = "NOT TYPED (not confirmed): don't tell the user it was typed."
    /// A field that can't be read back after the keys went out: maybe typed, maybe not (QA follow-up to BUG-10).
    static let notConfirmedLead = "NOT CONFIRMED: the keys were sent but the field can't be read back; don't tell the user it was typed."

    /// A type's result as the brain gets it: a failure always leads with notTypedLead, or notConfirmedLead when the keys
    /// went out into a field that can't be read back.
    static func typeOutcome(_ result: ArisDesktopResult) -> ArisDesktopResult {
        guard !result.ok, !result.text.hasPrefix(notTypedLead), !result.text.hasPrefix(notConfirmedLead) else { return result }
        return ArisDesktopResult(ok: false, text: (result.text.hasPrefix("Not confirmed") ? notConfirmedLead : notTypedLead) + " " + result.text)
    }
    static let focusLine = "Couldn't put the cursor in that field (another control has the focus), so nothing was typed."
    static let stopLine = "Not tried again, since that could type it twice: look at the field below."

    func typeText(_ request: ArisDesktopRequest) -> ArisDesktopResult { Self.typeOutcome(typeLadder(request)) }

    private func typeLadder(_ request: ArisDesktopRequest) -> ArisDesktopResult {
        guard let ref = request.ref, let text = request.text else { return .failed(ArisDesktopWords.usage) }
        let fresh: ArisDesktopObservation, found: ArisDesktopElement
        switch freshTarget(ref) {
        case .failure(let result): return result
        case .success(let hit): (fresh, found) = (hit.observation, hit.element)
        }
        if found.isSecure { return .failed(ArisDesktopGate.secureFieldRefusal) }
        // Rung 1: the focus, in the background; then the field must really have it, and not be a password field.
        var look = fresh, dispatched = false
        if !fresh.isFocused(found) {
            let click = run(ArisPeekabooCommands.click(found.id, snapshot: fresh.peekaboo))
            dispatched = click?.dispatched ?? true
            guard let again = lookAfter(fresh.window) else { return report(.notSeen("the window is gone"), envelope: click, after: nil) }
            look = again
        }
        guard let field = ArisDesktopVerify.find(found, in: look), look.isFocused(field), !look.focusIsSecure, !field.isSecure else {
            if look.focusIsSecure { return .failed(ArisDesktopGate.secureFieldRefusal) }
            // Nothing was typed: the window brought forward (the user's card) is the only other way to the field.
            return foreground(text, field: found, in: look, background: .notSeen(Self.focusLine))
        }
        if let refused = held(look, field: field) { return refused }
        if engine.apps.secureInput { return .failed(ArisDesktopGate.secureRefusal) }
        let before = field.rawValue
        // Rung 2: type, in the background, into the pinned window.
        let typed = run(ArisPeekabooCommands.type(text, window: look.window))
        guard let after = lookAfter(look.window) else { return report(.notSeen("the window is gone"), envelope: typed, after: nil) }
        let landed = ArisDesktopVerify.typed(text, field: field, after: after, before: before)
        if case .done = landed { return report(landed, envelope: typed, after: after, how: "typed in the background") }
        // A field that gives no value (KakaoTalk's): confirmed from the window read back, never typed again.
        if basis.blindField || field.rawValue == nil { return blindCheck(text, field: field, envelope: typed, after: after) }
        // Peekaboo must say nothing reached the app, and the field must be exactly as it was: anything else could mean
        // the text is on its way (or partly in), and another rung would type it twice.
        // The keyboard focus in another of the app's windows refuses background typing before anything is sent: the
        // window brought forward (the user's card) is the next way.
        if let typed, typed.focusElsewhere, let now = ArisDesktopVerify.find(field, in: after), now.rawValue == before {
            return foreground(text, field: now, in: after, background: landed)
        }
        guard let typed, typed.safeToRepeat, let now = ArisDesktopVerify.find(field, in: after), now.rawValue == before, !now.rawCapped else {
            return ArisDesktopResult(ok: false, text: "Typing into “\(ArisDesktopVerify.short(field.label))” isn't confirmed (\(landed.detail); Peekaboo said: \(why(typed))). " +
                                     Self.stopLine + "\n\n" + after.render())
        }
        // Rung 3: the field's value, set to what it held plus the text: only with nothing dispatched at all, its raw value
        // known in full, and never in an app that sends.
        if !dispatched, !target.sending, let before, !field.rawCapped {
            let set = run(ArisPeekabooCommands.setValue(before + text, element: now.id, snapshot: after.peekaboo))
            guard let again = lookAfter(fresh.window) else { return report(.notSeen("the window is gone"), envelope: set, after: nil) }
            let check = ArisDesktopVerify.typed(text, field: field, after: again, before: before)
            if case .done = check { return report(check, envelope: set, after: again, how: "set as the field's value; background typing didn't land") }
            guard let set, set.safeToRepeat, let still = ArisDesktopVerify.find(field, in: again), still.rawValue == before else {
                return ArisDesktopResult(ok: false, text: "Setting “\(ArisDesktopVerify.short(field.label))” isn't confirmed (\(check.detail)). " + Self.stopLine + "\n\n" + again.render())
            }
            return foreground(text, field: still, in: again, background: check)
        }
        return foreground(text, field: now, in: after, background: landed)
    }

    /// A field that can't be read back: the text must show in the window (its tree, or the text on its screenshot when
    /// Screen Recording is on). Unconfirmed, it is never typed again.
    private func blindCheck(_ text: String, field: ArisDesktopElement, envelope: ArisDesktopEnvelope?, after: ArisDesktopObservation) -> ArisDesktopResult {
        // Confirmed, it is kept for the turn: a send from this field is then asked about with this text (audit desk-4).
        if ArisDesktopVerify.appears(text, in: after) {
            turn.ledger.noteBlindTyped(window: after.window, text: ArisPeekabooCommands.composed(text))
            return report(.done("the window shows the text"), envelope: envelope, after: after, how: "typed in the background; the field itself can't be read, the window shows it")
        }
        if engine.access.screenRecording, !engine.apps.secureInput, let window = windows.first(where: { $0.id == after.window }),
           let (seen, _) = lookWithText(window), ArisDesktopVerify.appears(text, in: seen) {
            turn.ledger.noteBlindTyped(window: after.window, text: ArisPeekabooCommands.composed(text))
            return report(.done("the window shows the text"), envelope: envelope, after: seen, how: "typed in the background; read back from the window's text")
        }
        return ArisDesktopResult(ok: false, text: "Not confirmed: “\(ArisDesktopVerify.short(field.label))” can't be read back, and the window doesn't show the text (Peekaboo said: \(why(envelope))). " +
                                 "Don't type it again: look at the window, or ask the user.\n\n" + after.render())
    }

    /// Rung 4: with the user's yes and only while they is there, the window comes forward, the field is clicked, the focus is
    /// checked again (the field itself, no password field, no secure input) and only then the text is typed for real;
    /// the pointer and the front app are put back after.
    private func foreground(_ text: String, field: ArisDesktopElement, in look: ArisDesktopObservation, background: ArisDesktopCheck) -> ArisDesktopResult {
        guard !turn.isTask else {
            return ArisDesktopResult(ok: false, text: "The text didn't land in the background (\(background.detail)), and a background job never brings a window forward. Say so in the report.\n\n" + look.render())
        }
        guard basis.cardYes || consent(Self.foregroundCard, detail: ArisDesktopCopy.forwardTypeDetail(title: look.title, text: text, english: english)) else {
            return .failed(consentRefusal)
        }
        if engine.windows.promptOnScreen() != nil { return .failed(Self.promptLine) }
        let saved = engine.pointer.save()
        defer { restore(saved) }
        // The focus click goes for real too: the app in front with this window key first (security review of BUG-53).
        guard let raised = windows.first(where: { $0.id == look.window }), keysReachTarget(raised) else { return .failed(ArisDesktopFocus.refusalLine) }
        // A yes that came late (the held turn: QA retest on 0c370061, +31 s): the look from before the card is old, its
        // snapshot and ids may be gone; the pinned window is looked at again and the field found in it.
        var aimed = (look: look, field: field)
        if Date().timeIntervalSince(look.taken) > Self.staleLook {
            guard case .success(let (seen, _)) = self.look(raised) else { return notFocused("the window couldn't be looked at again after the raise") }
            guard let again = ArisDesktopVerify.find(field, in: seen) else { return notFocused("field not found in the fresh look (\(Self.described(field)))") }
            guard titleHolds(seen, was: look.title, window: look.window, field: (field, again)) else {
                return notFocused("the window's title changed (‘\(ArisWindowTitleMatch.safeTitle(look.title))’ → ‘\(ArisWindowTitleMatch.safeTitle(seen.title))’)")
            }
            aimed = (seen, again)
        }
        // Right before the real click (security review of b7997da3): no prompt, no secure input, no password field.
        if engine.windows.promptOnScreen() != nil { return .failed(Self.promptLine) }
        if engine.apps.secureInput { return .failed(ArisDesktopGate.secureRefusal) }
        if aimed.look.focusIsSecure || aimed.field.isSecure { return .failed(ArisDesktopGate.secureFieldRefusal) }
        // Still in front and key right before the real click (the look again may have taken a moment).
        guard keysReachTarget(raised) else { return .failed(ArisDesktopFocus.refusalLine) }
        _ = run(ArisPeekabooCommands.click(aimed.field.id, snapshot: aimed.look.peekaboo, foreground: true))
        guard let focused = lookAfter(look.window) else { return notFocused("the window couldn't be looked at after the click") }
        guard let now = ArisDesktopVerify.find(aimed.field, in: focused) else { return notFocused("field not found after the click (\(Self.described(aimed.field)))") }
        guard focused.isFocused(now) else {
            return notFocused("the field doesn't have the focus after the click (focus: \(focused.focusedElement.map(Self.described) ?? focused.focused.map { "frame \(Self.frame($0))" } ?? "none"); field: \(Self.described(now)))")
        }
        if focused.focusIsSecure || now.isSecure || engine.apps.secureInput { return .failed(ArisDesktopGate.secureFieldRefusal) }
        guard titleHolds(focused, was: look.title, window: look.window, field: (field, now)) else {
            return notFocused("the window's title changed (‘\(ArisWindowTitleMatch.safeTitle(look.title))’ → ‘\(ArisWindowTitleMatch.safeTitle(focused.title))’)")
        }
        if let refused = held(focused, field: now) { return refused }
        guard let window = windows.first(where: { $0.id == look.window }), keysReachTarget(window) else { return .failed(ArisDesktopFocus.refusalLine) }
        let typed = run(ArisPeekabooCommands.type(text, window: look.window, foreground: true))
        guard let after = lookAfter(look.window) else { return report(.notSeen("the window is gone"), envelope: typed, after: nil) }
        let check = ArisDesktopVerify.typed(text, field: field, after: after, before: now.rawValue)
        if case .notSeen = check, basis.blindField || field.rawValue == nil { return blindCheck(text, field: field, envelope: typed, after: after) }
        return report(check, envelope: typed, after: after, how: "typed with the window brought forward, after the user's yes")
    }

    /// The cursor didn't get into the field: the exact check that stopped it, for the brain, the audit and QA's log.
    private func notFocused(_ why: String) -> ArisDesktopResult {
        turn.audit(["answer": "not typed (\(why.prefix(200)))", "action": "desktop type · \(target.name)", "brain": turn.brainName])
        return .failed(Self.focusLine + " (why: \(why))")
    }

    /// An element as a reason line names it: its role and frame.
    static func described(_ element: ArisDesktopElement) -> String { "role \(element.role.isEmpty ? "?" : element.role), frame \(frame(element.bounds))" }
    static func frame(_ rect: CGRect) -> String { "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))" }

    /// The user's card for something that brings a window forward or moves the pointer: never remembered.
    func consent(_ title: String, detail: String) -> Bool {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var yes = false
        let card = ArisMCPCard(title: "\(ArisDesktopCard.shown(target.name)): \(ArisDesktopCopy.consentTitle(title, english: english))", detail: detail, full: nil, fields: [])
        cardFront.target = engine.apps.frontmostPid().flatMap(engine.apps.identity)
        // Its yes brings the window forward: it names the process the app hands activation back to.
        cardFront.unanswered = false
        turn.ask(turn.isTask ? card : card.aimed(pid: target.pid, bundle: target.bundle)) { answer in
            if case .yes = answer { yes = true }
            if answer == .unanswered { self.cardFront.unanswered = true }
            done.signal()
        }
        done.wait()
        // A yes that comes after the turn ended does nothing (M5).
        if yes, !turn.live { yes = false }
        turn.audit(["answer": yes ? "yes" : "no", "action": "desktop foreground · \(target.name)", "brain": turn.brainName])
        return yes
    }
}

extension ArisDesktopCheck {
    var detail: String {
        switch self {
        case .done(let text), .notSeen(let text): return text
        }
    }
}
