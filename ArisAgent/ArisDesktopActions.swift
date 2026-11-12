//
//  ArisDesktopActions.swift
//  aris-agent
//
//  The controller's actions. On a ref: the stale-snapshot guard first (the ref must come from its window's latest look;
//  otherwise nothing is done and the window comes back as it is now), then a fresh look in which the control must still
//  be there with the same role and name, the action against that fresh look, and a read-back that says what changed.
//  An action is repeated only when Peekaboo says nothing reached the app, and never in a messaging app (a send is never
//  repeated). Keys, menus, dialogs, windows, apps and the Dock go to the pinned window or the resolved app.
//

import CoreGraphics
import Foundation

extension ArisDesktopSession {
    static func staleLine(_ window: ArisDesktopObservation) -> String {
        "That ref is from an older look at this window (it changed since), so nothing was done. Act on the refs below.\n\n" + window.render()
    }

    /// How far (points, inside the window) a control may have moved since the look its ref came from, and how far a text
    /// mark read again may be from where it was (I4).
    static let drift: CGFloat = 4
    static let markDrift: CGFloat = 12

    static func movedLine(_ label: String) -> String { "“\(ArisDesktopVerify.short(label))” moved since that look, so nothing was done. Act on the refs below." }
    static let searchLine = "The focus moved off the search field the user's card named, so the key wasn't pressed (it could send instead)."
    static let titleLine = "The window's title changed since that look (or since the user's card), so nothing was done. Look again."
    /// The title line with the titles it compared (QA's log names the exact check).
    static func titleChanged(was: String, now: String) -> String {
        titleLine + " (why: ‘\(ArisWindowTitleMatch.safeTitle(was))’ → ‘\(ArisWindowTitleMatch.safeTitle(now))’)"
    }
    static let composerLine = "What the message field holds changed since the user's card, so nothing was done (the card no longer shows what would go)."
    static let promptLine = "Refused: a sign-in, password or permission prompt is on screen, and Aris never acts while one is up. Ask the user to answer it."

    /// The window as the action is about to use it, held to what the user's card (or the ref's look) showed: the same title,
    /// and in a sending app the same text in the field (I1, I4). Nil when it matches; else what to tell the brain.
    /// The window `now` is the one a look or the card saw by that title: the exact title; or, renamed by an app that
    /// renames its one document itself, the same pinned window with the very same field in it (`field`: as it was, and
    /// as it is now). Without a field, only the exact title (ArisDesktopFocus.renameHolds).
    func titleHolds(_ now: ArisDesktopObservation, was title: String, window: Int?, field: (was: ArisDesktopElement, now: ArisDesktopElement)? = nil) -> Bool {
        if ArisWindowTitleMatch.sameTitle(now.title, title) { return true }
        guard let field else { return false }
        return ArisDesktopFocus.renameHolds(bundle: target.bundle, known: target.known, sending: target.sending, sameWindow: window == now.window,
                                            tabbed: ArisDesktopFocus.hasTabs(now), was: field.was, now: field.now)
    }

    /// The pointer back, and the app that was in front when the user's card went up back in front (as the card says), only
    /// while that pid is still the same process (a reused pid is skipped).
    func restore(_ saved: ArisDesktopPointerState) {
        let before = (basis.frontBefore ?? cardFront.target).flatMap { was -> Int32? in
            engine.apps.identity(pid: was.pid).map { $0.matches(bundle: was.bundle, started: was.started) } == true ? was.pid : nil
        }
        let front = ArisDesktopFocus.restoreFront(beforeCard: before, atAction: saved.frontmost, target: target.pid,
                                                  isAris: { self.engine.apps.isAris(pid: $0) })
        engine.pointer.restore(ArisDesktopPointerState(location: saved.location, frontmost: front))
    }

    /// What a consent card that wasn't a yes says: the user's no, or that they didn't answer (never their no).
    var consentRefusal: String { cardFront.unanswered ? ArisDesktopEngine.unansweredLine : ArisDesktopEngine.noLine }

    func held(_ look: ArisDesktopObservation, field: ArisDesktopElement?) -> ArisDesktopResult? {
        if let refused = settingsHeld(look) { return refused }
        // The field the basis was made with, found again when the call names none (a batch's keys after its own text
        // step: the window may carry a new name by then, and is still held by that field).
        let current = field ?? basis.field.flatMap { ArisDesktopVerify.find($0, in: look) }
        if let title = basis.title, !titleHolds(look, was: title, window: basis.window, field: current.flatMap { now in basis.field.map { (was: $0, now: now) } }) {
            return .failed(Self.titleChanged(was: title, now: look.title) + "\n\n" + look.render())
        }
        if let search = basis.searchFocus, look.focusedElement.map({ !$0.isSearch || $0.label != search }) ?? true {
            return .failed(Self.searchLine + "\n\n" + look.render())
        }
        if target.sending, basis.send || basis.composer != nil {
            let now = look.composer(for: field)
            guard let now, !now.rawCapped, now.rawValue == basis.composer else { return .failed(Self.composerLine + "\n\n" + look.render()) }
        }
        // A send from a field that gives no value: what Aris typed, and the user's card said, must still show in the window.
        if let typed = basis.blindSend, !windowShows(typed, in: look) { return .failed(Self.blindGoneLine + "\n\n" + look.render()) }
        return nil
    }

    static let pasteChangedLine = "The clipboard changed after the user's card, so nothing was pasted (the card no longer shows what would go in). Ask again in a new call if the user still wants it."

    /// A paste the user's card showed: the clipboard must still hold exactly that text right before the keys go. Nil when
    /// it does (or the call is no such paste); else what to tell the brain.
    func pasteHeld() -> ArisDesktopResult? {
        guard let shown = basis.paste else { return nil }
        return ArisDesktopGate.pasteHolds(card: shown, now: engine.apps.clipboardText()) ? nil : .failed(Self.pasteChangedLine)
    }

    static let blindGoneLine = "The text Aris typed is no longer shown in the window, so nothing was sent (the message field can't be read, and the user's card no longer says what would go)."

    static let settingsCard = "이 설정 화면에서 할까요"

    /// System Settings as the action is about to run: never in a protected pane; a pane not told for sure (or no look
    /// at all) when the action was decided on a safe one asks the user once, never kept.
    func settingsHeld(_ look: ArisDesktopObservation?) -> ArisDesktopResult? {
        guard target.settings else { return nil }
        let now = look?.settingsPane ?? .unknown
        if now == .protected { return .failed(ArisDesktopGate.settingsRefusal) }
        guard now != .safe, basis.settingsPane == .safe, !settingsAsked.isSet else { return nil }
        settingsAsked.isSet = true
        return consent(Self.settingsCard, detail: ArisDesktopCopy.settingsDetail(title: look?.title ?? "", english: english)) ? nil : .failed(consentRefusal)
    }

    /// The fresh look an action on `ref` uses, and the control in it; or what to tell the brain instead.
    func freshTarget(_ ref: ArisDesktopRef) -> Result<(observation: ArisDesktopObservation, element: ArisDesktopElement, before: ArisDesktopObservation), ArisDesktopResult> {
        guard let before = turn.ledger.observation(ref.snapshot) else { return .failure(.failed(ArisDesktopEngine.notOursLine)) }
        guard let element = before.element(ref) else { return .failure(.failed("There is no \(ref.text) in that look.")) }
        let window = windows.first { $0.id == before.window }
        guard turn.ledger.isLatest(ref.snapshot) else {
            guard let window, case .success(let (now, _)) = look(window) else { return .failure(.failed("That ref is from an older look, and the window is gone. Look again.")) }
            return .failure(.failed(Self.staleLine(now)))
        }
        guard let window else { return .failure(.failed("That window is gone (closed or moved off screen), so nothing was done. Look again.")) }
        // A text mark is read from the screen again: the same words must still be there, near where they were.
        if ref.mark {
            guard engine.access.screenRecording, let (now, _) = lookWithText(window) else {
                return .failure(.failed("Couldn't read the window's text again before acting, so nothing was done."))
            }
            if !titleHolds(now, was: before.title, window: before.window) { return .failure(.failed(Self.titleChanged(was: before.title, now: now.title) + "\n\n" + now.render())) }
            let was = before.position(of: element)
            let distance = { (mark: ArisDesktopElement) in hypot(now.position(of: mark).x - was.x, now.position(of: mark).y - was.y) }
            guard let mark = now.marks.filter({ $0.label == element.label }).min(by: { distance($0) < distance($1) }), distance(mark) <= Self.markDrift else {
                return .failure(.failed("“\(ArisDesktopVerify.short(element.label))” isn't where it was on the window any more, so nothing was done.\n\n" + now.render()))
            }
            if let refused = held(now, field: nil) { return .failure(refused) }
            return .success((now, mark, before))
        }
        let now: ArisDesktopObservation
        switch look(window) {
        case .failure(let why): return .failure(.failed("Couldn't look at the window again before acting (\(why.text)), so nothing was done."))
        case .success(let (found, _)): now = found
        }
        guard let current = ArisDesktopVerify.find(element, in: now) else {
            return .failure(.failed("“\(ArisDesktopVerify.short(element.label))” (\(element.role)) isn't there any more: the window changed, so nothing was done.\n\n" + now.render()))
        }
        if !titleHolds(now, was: before.title, window: before.window, field: (element, current)) {
            return .failure(.failed(Self.titleChanged(was: before.title, now: now.title) + "\n\n" + now.render()))
        }
        if Self.moved(element, in: before, to: current, in: now) { return .failure(.failed(Self.movedLine(element.label) + "\n\n" + now.render())) }
        if let refused = held(now, field: current) { return .failure(refused) }
        return .success((now, current, before))
    }

    /// The control sits somewhere else in its window than it did (more than `drift`).
    static func moved(_ element: ArisDesktopElement, in before: ArisDesktopObservation, to current: ArisDesktopElement, in now: ArisDesktopObservation) -> Bool {
        let was = before.position(of: element), place = now.position(of: current)
        return hypot(place.x - was.x, place.y - was.y) > drift
    }

    /// Runs an action against a fresh look; once more against a newer look only when Peekaboo says nothing reached the app
    /// and the app isn't a messaging one (and the control is still the same, where it was).
    func attempt(_ fresh: ArisDesktopObservation, element: ArisDesktopElement, make: (ArisDesktopObservation, ArisDesktopElement) -> [String])
        -> (envelope: ArisDesktopEnvelope?, used: ArisDesktopObservation) {
        let envelope = run(make(fresh, element))
        guard let envelope, envelope.safeToRepeat, !target.sending, let window = windows.first(where: { $0.id == fresh.window }),
              case .success(let (again, _)) = look(window), let same = ArisDesktopVerify.find(element, in: again), titleHolds(again, was: fresh.title, window: fresh.window, field: (element, same)),
              !Self.moved(element, in: fresh, to: same, in: again) else { return (envelope, fresh) }
        return (run(make(again, same)), again)
    }

    /// The app's windows by id right now (before an action, to tell a window it opened).
    var windowIds: Set<Int> { Set(windows.map(\.id)) }

    /// A window the action opened (a sheet, a panel, a popover): its look, read through its parent when it can't be read
    /// itself. The action's result is in it, not in the window it was aimed at (bench te_saveas, form_save).
    func opened(since before: Set<Int>) -> (window: ArisDesktopWindow, look: ArisDesktopObservation)? {
        // A panel or sheet comes up a moment after the action (TextEdit's save panel): waited for, briefly.
        var found: ArisDesktopWindow?
        for attempt in 0..<Self.openWaits {
            if attempt > 0 { Thread.sleep(forTimeInterval: openPause) }
            found = windows.first(where: { !before.contains($0.id) })
            if found != nil { break }
        }
        guard let window = found, case .success(let look) = lookOrParent(window, alone: false) else { return nil }
        return (window, look)
    }

    /// How often, and how far apart, the app's windows are read again for one the action opened.
    static let openWaits = 8
    static let openWait: TimeInterval = 0.1

    /// The read-back, with a window the action opened counted as what changed.
    func readBack(_ check: ArisDesktopCheck, envelope: ArisDesktopEnvelope?, after: ArisDesktopObservation?, before: Set<Int>, how: String? = nil) -> ArisDesktopResult {
        if case .notSeen = check, let (window, look) = opened(since: before) {
            return report(.done("a new window opened (window \(window.id) “\(look.title)”)"), envelope: envelope, after: look, how: how)
        }
        return report(check, envelope: envelope, after: after, how: how)
    }

    /// The answer after an action: what the read-back shows, then the window as it is now (its refs are the ones to use).
    func report(_ check: ArisDesktopCheck, envelope: ArisDesktopEnvelope?, after: ArisDesktopObservation?, how: String? = nil) -> ArisDesktopResult {
        var lines: [String] = []
        switch check {
        case .done(let what):
            if let after { turn.ledger.noteDone(window: after.title, typed: how?.contains("typed") == true || what.lowercased().contains("typed")) }
            // The window it really happened in, its title in its own field as outside text (QA BUG-47, security review).
            let place = after.map { " It was done in the window named below (say that title when you tell the user)." + ArisWindowTitleMatch.windowField($0.title) } ?? ""
            lines.append("Done\(how.map { " (\($0))" } ?? ""): \(what).\(place)")
        case .notSeen(let what):
            lines.append("Not confirmed: the window shows no sign of it (\(what)). Peekaboo said: \(why(envelope)). Don't repeat it blindly: look at the window below first.")
        }
        if let after { lines.append("\n" + after.render()) } else { lines.append("(The window is gone now.)") }
        if case .done = check { return ArisDesktopResult(ok: true, text: lines.joined(separator: "\n")) }
        return ArisDesktopResult(ok: false, text: lines.joined(separator: "\n"))
    }

    /// click, set-value, scroll and drag on a ref.
    func actOnRef(_ request: ArisDesktopRequest) -> ArisDesktopResult {
        guard let ref = request.ref else { return .failed(ArisDesktopWords.usage) }
        let fresh: ArisDesktopObservation, element: ArisDesktopElement
        switch freshTarget(ref) {
        case .failure(let result): return result
        case .success(let found): (fresh, element) = (found.observation, found.element)
        }
        // A text mark: a plain click at its spot only (ArisDesktopWords refuses any other verb on one: I3).
        if ref.mark {
            guard request.verb == .click, !request.double, !request.right else { return .failed(ArisDesktopWords.markLine) }
            return clickPoint(element.centre, in: fresh, label: element.label, consented: false)
        }
        if request.verb == .setValue, element.isSecure { return .failed(ArisDesktopGate.secureFieldRefusal) }
        // A plain click into a document's text area that already has the keyboard focus isn't made: in the background it
        // changes nothing (QA live on 827cfdb4: the batch stopped there as not confirmed). Said as it is: not clicked, the
        // caret where it was; the next step types or presses into that text.
        if request.verb == .click, !request.double, !request.right, ArisDesktopVerify.isTextArea(element), fresh.isFocused(element), !fresh.focusIsSecure {
            let caret = element.selectedRange.map { " (its caret stays \($0.shown))" } ?? ""
            return report(.done("“\(ArisDesktopVerify.short(element.label))” already has the keyboard focus, so it wasn't clicked\(caret)"), envelope: nil, after: fresh)
        }
        let before = windowIds
        let (envelope, used): (ArisDesktopEnvelope?, ArisDesktopObservation)
        switch request.verb {
        case .click:
            (envelope, used) = attempt(fresh, element: element) { look, current in
                ArisPeekabooCommands.click(current.id, snapshot: look.peekaboo, double: request.double, right: request.right)
            }
        case .setValue:
            (envelope, used) = attempt(fresh, element: element) { look, current in ArisPeekabooCommands.setValue(request.text ?? "", element: current.id, snapshot: look.peekaboo) }
        case .scroll:
            (envelope, used) = attempt(fresh, element: element) { look, current in
                ArisPeekabooCommands.scroll(request.direction ?? "down", amount: request.amount ?? 5, element: current.id, snapshot: look.peekaboo)
            }
        case .drag:
            guard let to = request.to, let drop = turn.ledger.observation(to.snapshot)?.element(to), let target = ArisDesktopVerify.find(drop, in: fresh) else {
                return .failed("The place to drop isn't in the window any more.\n\n" + fresh.render())
            }
            (envelope, used) = attempt(fresh, element: element) { look, current in ArisPeekabooCommands.drag(from: current.id, to: target.id, snapshot: look.peekaboo) }
        default: return .failed(ArisDesktopWords.usage)
        }
        guard let after = lookAfter(used.window) else { return readBack(.notSeen("the window is gone"), envelope: envelope, after: nil, before: before) }
        let check = request.verb == .setValue ? ArisDesktopVerify.set(request.text ?? "", field: element, after: after)
            : request.verb == .click && !request.double && !request.right ? ArisDesktopVerify.clicked(element, before: used, after: after)
            : ArisDesktopVerify.acted(on: element, before: used, after: after)
        // A Finder name set in its rename field: committed with Return, then read back from the window.
        if request.verb == .setValue, case .done = check, let committed = commitRename(element, after: after) {
            let renamed = committed.elements.contains { ($0.rawValue ?? $0.label).precomposedStringWithCanonicalMapping == (request.text ?? "").precomposedStringWithCanonicalMapping }
            return report(renamed ? .done("“\(ArisDesktopVerify.short(request.text ?? ""))” is set and committed with Return") : .notSeen("the name didn't stay after Return"),
                          envelope: envelope, after: committed)
        }
        if request.verb == .setValue, case .done = check, let envelope, !envelope.success {
            return report(check, envelope: envelope, after: after, how: "the field reads it back, though Peekaboo wasn't sure")
        }
        return readBack(check, envelope: envelope, after: after, before: before)
    }

    /// press: keys (several in one step) to the pinned window, against a fresh look of it.
    func press(_ request: ArisDesktopRequest) -> ArisDesktopResult {
        let window: ArisDesktopWindow
        switch pinned(request.window, title: request.title) {
        case .failure(let why): return .failed(why.text)
        case .success(let found): window = found
        }
        // A sheet or dialog in front that can't be read is read through the window behind it (keys go to the app's focus).
        guard case .success(let fresh) = lookOrParent(window, alone: request.window != nil) else {
            return .failed("Couldn't look at \(target.name)'s window before pressing, so nothing was pressed.")
        }
        if let refused = held(fresh, field: nil) { return refused }
        let before = windowIds
        // Keys go to whatever has the focus: never a password field (I6).
        if fresh.focusIsSecure { return .failed(ArisDesktopGate.secureFieldRefusal) }
        // What a copy or a save can be told by, read before the keys go (they change nothing in the window's tree).
        let copies = request.keys.contains(where: ArisDesktopVerify.copies), saves = request.keys.contains(where: ArisDesktopVerify.saves)
        let clipboard = copies ? engine.apps.clipboardChanges() : nil
        var evidence = ArisPressEvidence(editedBefore: saves ? engine.apps.documentEdited(pid: target.pid, frame: window.frame) : nil)
        if let refused = pasteHeld() { return refused }
        var envelope = run(ArisPeekabooCommands.press(request.keys, snapshot: fresh.peekaboo))
        // The keys can't reach the window in the background (its keyboard focus is in another one): the user's card, then
        // forward, the keys, and the front app put back.
        if envelope?.focusElsewhere == true {
            switch forward(keys: request.keys, in: fresh, window: window) {
            case .failure(let refused): return refused
            case .success(let sent): envelope = sent
            }
        }
        let sent = envelope?.dispatched == true
        let after = lookAfter(fresh.window)
        // The app takes a moment to copy or to save: each is waited for briefly, only when its keys went out.
        if sent, let clipboard { evidence.clipboardChanged = Self.settles({ self.engine.apps.clipboardChanges().map { $0 != clipboard } ?? false }) }
        if sent, saves {
            // A save that opened its panel is told as the panel, whatever the document's own mark says.
            if let (panel, look) = opened(since: before) {
                var result = report(.done("a new window opened (window \(panel.id) “\(look.title)”)"), envelope: envelope, after: look)
                result.keysSent = true
                return result
            }
            _ = Self.settles({ self.engine.apps.documentEdited(pid: self.target.pid, frame: window.frame) != true })
            evidence.editedAfter = engine.apps.documentEdited(pid: target.pid, frame: window.frame)
        }
        var result = readBack(after.map { ArisDesktopVerify.pressed(request.keys, dispatched: sent, before: fresh, after: $0, evidence: evidence) } ?? .notSeen("the window is gone"),
                              envelope: envelope, after: after, before: before)
        result.keysSent = sent
        // A paste the user's card showed, into a message field that gives no value (KakaoTalk's): once the window shows the
        // text, it is kept as text Aris typed there is, so its send can go to the card that says it (audit desk-4).
        if let pasted = basis.paste, result.ok, let after, let field = after.composer(for: nil), field.rawValue == nil, !field.rawCapped, windowShows(pasted, in: after) {
            turn.ledger.noteBlindTyped(window: after.window, text: pasted)
        }
        return result
    }

    /// Menus, dialogs, windows, apps and the Dock: by the resolved app (its bundle id) or the pinned window, then read back.
    func appAction(_ request: ArisDesktopRequest) -> ArisDesktopResult {
        // The never-list again, and the prompts that show no window of this app at all (a sign-in or permission prompt
        // at any level over it): Peekaboo's menus and dialogs could reach one (I7).
        if target.never { return .failed(ArisDesktopGate.neverRefusal) }
        if engine.windows.promptOnScreen() != nil { return .failed(Self.promptLine) }
        if target.settings, request.path.map(ArisDesktopGate.namesBlockedPanePath) == true { return .failed(ArisDesktopGate.settingsRefusal) }
        switch request.verb {
        case .app: return launchOrFocus(request)
        case .window: return windowAction(request)
        default: break
        }
        let front = windows.first
        let before = front.flatMap { window -> ArisDesktopObservation? in
            if case .success(let found) = lookOrParent(window, alone: false) { return found }
            return nil
        }
        // What the card showed must still be so (and with nothing to look at, a card that showed something can't be held).
        if let refused = settingsHeld(before) { return refused }
        if basis.title != nil || (target.sending && (basis.send || basis.composer != nil)) {
            guard let before else { return .failed(Self.titleLine) }
            if let refused = held(before, field: nil) { return refused }
        }
        let argv: [String]
        switch request.verb {
        case .menuClick: argv = ArisPeekabooCommands.menuClick(request.path ?? "", target)
        case .dialogClick: argv = ArisPeekabooCommands.dialogClick(request.button ?? "", target)
        case .dialogInput: argv = ArisPeekabooCommands.dialogInput(request.text ?? "", field: request.field, target)
        default: argv = ArisPeekabooCommands.dialogFile(path: request.path.map { ($0 as NSString).expandingTildeInPath }, name: request.name, select: request.select,
                                                         window: panelWindow(), target)
        }
        // A file panel goes "for real" (--foreground): only into the panel's own window, the app in front with it key.
        if request.verb == .dialogFile {
            let panel = panelWindow().flatMap { id in windows.first { $0.id == id } } ?? front
            guard let panel, keysReachTarget(panel) else { return .failed(ArisDesktopFocus.refusalLine) }
        }
        let saved = request.verb == .dialogFile ? engine.pointer.save() : nil
        let opening = windowIds
        // A Paste menu item in a messaging app: the clipboard as the user's card showed it, or nothing.
        if let changed = pasteHeld() { return changed }
        let envelope = run(argv)
        if let saved { restore(saved) }
        let after = front.flatMap { lookAfter($0.id) }
        var check: ArisDesktopCheck = .notSeen("the window is gone")
        if let before, let after { check = ArisDesktopVerify.acted(on: nil, before: before, after: after) } else if after != nil { check = .done("the window changed") }
        if envelope?.state == "partial", request.verb == .menuClick {
            return ArisDesktopResult(ok: false, text: "The menu path stopped partway (\(why(envelope))); a menu may be left open (`desktop press escape --app \"\(target.name)\"`). " +
                                     "`desktop menu list --app \"\(target.name)\"` shows the real names (they may be in Korean).")
        }
        // No such menu item: nothing was clicked; the menus' own names say what to use.
        if request.verb == .menuClick, envelope?.dispatched != true, (envelope?.message ?? "").contains("NotFound") || envelope?.code == "MENU_ITEM_NOT_FOUND" {
            return ArisDesktopResult(ok: false, text: "No menu item has that path, so nothing was clicked. `desktop menu list --app \"\(target.name)\"` shows the menus' real names " +
                                     "(this Mac may show them in Korean, like 파일 › 다른 이름으로 저장…).")
        }
        return readBack(check, envelope: envelope, after: after, before: opening)
    }

    /// Keys the background can't deliver, with the window brought forward: only with the user's yes, never in a job, never
    /// with a sign-in prompt or a password field up; the pointer and the front app go back after.
    /// The keys go to `window` (the pinned one): it is brought forward first, then looked at again, and only a window that
    /// can itself be read, still as the card showed it, with no password field holding the focus, gets the keys. A sheet
    /// that can't be read is refused, never pressed into the window behind it.
    func forward(keys: [String], in look: ArisDesktopObservation, window: ArisDesktopWindow) -> Result<ArisDesktopEnvelope?, ArisDesktopResult> {
        guard !turn.isTask else {
            return .failure(.failed("The keys can't reach \(target.name)'s window in the background (its keyboard focus is in another window), and a background job never brings a window forward. Say so in the report."))
        }
        let detail = ArisDesktopCopy.forwardKeysDetail(title: look.title, keys: keys, english: english)
        guard basis.cardYes || consent(Self.foregroundCard, detail: detail) else { return .failure(.failed(consentRefusal)) }
        if engine.apps.secureInput { return .failure(.failed(ArisDesktopGate.secureRefusal)) }
        if engine.windows.promptOnScreen() != nil { return .failure(.failed(Self.promptLine)) }
        let saved = engine.pointer.save()
        defer { restore(saved) }
        _ = run(ArisPeekabooCommands.window("focus", window: window.id))
        guard case .success(let (now, _)) = self.look(window) else { return .failure(.failed(Self.unreadableForwardLine)) }
        // The window the card named, whatever an earlier card held: the same title (another window, a new sheet: no keys).
        if !titleHolds(now, was: look.title, window: look.window) { return .failure(.failed(Self.titleChanged(was: look.title, now: now.title) + "\n\n" + now.render())) }
        if let refused = held(now, field: nil) { return .failure(refused) }
        if now.focusIsSecure || engine.apps.secureInput { return .failure(.failed(ArisDesktopGate.secureFieldRefusal)) }
        // Right before the keys: Calendar (the card's app) in front, its card's window key; once more after a raise, else none.
        guard keysReachTarget(window) else { return .failure(.failed(ArisDesktopFocus.refusalLine)) }
        // Bringing the window forward took a moment: a paste is held to the clipboard once more.
        if let changed = pasteHeld() { return .failure(changed) }
        return .success(run(ArisPeekabooCommands.pressForward(keys, window: window.id)))
    }

    /// The target app in front with `window` key, checked now and once more after another raise (QA BUG-53).
    func keysReachTarget(_ window: ArisDesktopWindow) -> Bool {
        let check = { ArisDesktopFocus.keysMayGo(frontmost: self.engine.apps.frontmostPid(), target: self.target.pid,
                                                   focused: self.engine.apps.focusedWindowFrame(pid: self.target.pid), window: window,
                                                   windows: self.engine.windows.windows(of: self.target.pid)) }
        if check() { return true }
        // The user's card promised the window comes forward: the app is activated, then its window raised, and the check is
        // given time to see it (QA retest: an approved batch typed nothing, the window never in front after one raise).
        let raised = Date()
        _ = run(ArisPeekabooCommands.app("focus", target))
        _ = run(ArisPeekabooCommands.window("focus", window: window.id))
        // And the pinned window made main and raised by Accessibility itself (the app may have put another window first).
        engine.apps.raiseWindow(pid: target.pid, frame: window.frame)
        guard Self.settles(check, tries: 15, wait: 0.1) else { return false }
        // The raise took a moment: the user typing meanwhile (their keys would mix with Aris's), a password field, or a sign-in
        // prompt that came up stops it, checked again right before the keys (security review).
        if engine.apps.secondsSinceKeyDown() < Date().timeIntervalSince(raised) { return false }
        return !engine.apps.secureInput && engine.windows.promptOnScreen() == nil
    }

    static let unreadableForwardLine = "Brought forward, the window that has the focus couldn't be read (a sheet or panel), so the keys weren't pressed: they could land in the window behind it."

    /// Finder keeps a name typed into its rename field until Return: set-value reads back done, the file isn't renamed.
    /// Return commits it, in the background, or forward with the user's card when the background can't.
    func commitRename(_ field: ArisDesktopElement, after look: ArisDesktopObservation) -> ArisDesktopObservation? {
        guard target.bundle == "com.apple.finder", field.isTextEntry else { return nil }
        let sent = run(ArisPeekabooCommands.press(["return"], snapshot: look.peekaboo))
        if sent?.focusElsewhere == true {
            guard let window = windows.first(where: { $0.id == look.window }), case .success = forward(keys: ["return"], in: look, window: window) else { return nil }
        }
        return lookAfter(look.window)
    }

    /// The app's file panel: the first of its windows (front to back) whose look is a dialog. The front window can be a
    /// small helper of the panel's (bench te_saveas). Nil when none is: Peekaboo finds the panel by the app.
    func panelWindow() -> Int? {
        for window in windows.prefix(4) {
            guard case .success(let (look, _)) = look(window, record: false) else { continue }
            turn.ledger.discard(look.peekaboo)
            if look.isDialog { return window.id }
        }
        return nil
    }

    private func windowAction(_ request: ArisDesktopRequest) -> ArisDesktopResult {
        let window: ArisDesktopWindow
        switch pinned(request.window, title: request.title) {
        case .failure(let why): return .failed(why.text)
        case .success(let found): window = found
        }
        let operation = request.operation ?? "focus"
        let saved = operation == "focus" ? nil : engine.pointer.save()
        let envelope = run(ArisPeekabooCommands.window(operation, window: window.id, x: request.x, y: request.y, width: request.width, height: request.height))
        if let saved { engine.pointer.restore(saved) }
        let now = windows.first { $0.id == window.id }
        let check: ArisDesktopCheck
        switch operation {
        case "close", "minimize": check = now == nil ? .done("window \(window.id) is \(operation == "close" ? "closed" : "minimized")") : .notSeen("window \(window.id) is still on screen")
        case "focus":
            // Peekaboo's own confirmation counts here: the front app can take a moment to switch.
            check = engine.pointer.save().frontmost == target.pid || envelope?.state == "confirmed_change" ? .done("\(target.name)'s window is in front") : .notSeen("\(target.name) isn't in front")
        default: check = now.map { $0.frame != window.frame || operation == "restore" ? .done("window \(window.id) is now \(Int($0.frame.width))×\(Int($0.frame.height)) at \(Int($0.frame.minX)),\(Int($0.frame.minY))") : .notSeen("the window didn't move or change size") } ?? .notSeen("the window is gone")
        }
        return report(check, envelope: envelope, after: nil).withoutGoneLine()
    }

    private func launchOrFocus(_ request: ArisDesktopRequest) -> ArisDesktopResult {
        let operation = request.operation ?? "focus"
        let argv = ArisPeekabooCommands.app(operation, target)
        guard !argv.isEmpty else { return .failed("Aris can only open an app it knows by its bundle id.") }
        let envelope = run(argv)
        // A quit is asked of the app itself (never forced): it is done once the process is gone, read back for a moment.
        if operation == "quit" {
            let gone = Self.settles({ !self.engine.apps.isRunning(self.target) }, tries: 20, wait: 0.15)
            let check: ArisDesktopCheck = gone ? .done("\(target.name) has quit")
                : .notSeen("\(target.name) is still running: it may be asking about unsaved changes (`desktop see --app \"\(target.name)\"` shows its dialog)")
            return report(check, envelope: envelope, after: nil).withoutGoneLine()
        }
        let running = target.bundle.flatMap { engine.apps.resolve($0) }
        let check: ArisDesktopCheck
        switch operation {
        case "launch": check = running.map { engine.windows.windows(of: $0.pid).isEmpty ? .done("\(target.name) is running (no window yet)") : .done("\(target.name) is open") } ?? .notSeen("\(target.name) isn't running")
        case "hide": check = running.map { engine.windows.windows(of: $0.pid).isEmpty ? .done("\(target.name) is hidden") : .notSeen("\(target.name)'s windows are still showing") } ?? .notSeen("\(target.name) isn't running")
        default: check = running.map { engine.pointer.save().frontmost == $0.pid ? .done("\(target.name) is in front") : .notSeen("\(target.name) isn't in front") } ?? .notSeen("\(target.name) isn't running")
        }
        return report(check, envelope: envelope, after: nil).withoutGoneLine()
    }
}

private extension ArisDesktopResult {
    /// Window and app actions read back the windows, not a tree: no "(the window is gone)" line.
    func withoutGoneLine() -> ArisDesktopResult {
        ArisDesktopResult(ok: ok, text: text.replacingOccurrences(of: "\n(The window is gone now.)", with: ""))
    }
}
