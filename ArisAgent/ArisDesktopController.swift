//
//  ArisDesktopController.swift
//  aris-agent
//
//  The controller under the gate: what one allowed desktop call does with Peekaboo. Every look is of one exact window
//  of the resolved process (the front one, or one the brain named from `window list`); a sheet or dialog that can't be
//  read is read through the window behind it, its parent. Every look is recorded (ArisComputerUseLedger) and passed on
//  only after the privacy filter. Actions are in ArisDesktopActions, typing in ArisDesktopTextLadder, looking and
//  clicking at a point in ArisDesktopLook.
//

import Foundation

/// What one call comes to: whether it did what it was for, and what the brain reads.
struct ArisDesktopResult: Error {
    let ok: Bool
    let text: String
    /// A press whose keys Peekaboo sent on, whether or not the window showed their effect (a select-all that can't be
    /// read back still selected: audit desk-3).
    var keysSent = false

    static func failed(_ text: String) -> ArisDesktopResult { ArisDesktopResult(ok: false, text: text) }
}

/// One allowed call's work: the checked binary, the resolved app, the turn.
struct ArisDesktopSession {
    let engine: ArisDesktopEngine
    let binary: URL
    let target: ArisDesktopTarget
    let turn: ArisDesktopTurn
    /// What the user's card showed (or the ref's look): the action is held to it (I1, I4).
    var basis = ArisDesktopBasis()
    /// The System Settings card this call already asked (one per call).
    let settingsAsked = ArisDesktopFlag()
    /// The app in front when this session's own consent card went up (ArisDesktopBasis.frontBefore for the others).
    let cardFront = ArisDesktopFront()
    /// How long apart the app's windows are read again for one the action opened (a batch step waits longer: M1).
    var openPause = ArisDesktopSession.openWait
    /// The call's cards for the user are English (their request was), else Korean (ArisDesktopCopy).
    var english: Bool { ArisDesktopCopy.isEnglish(turn.request) }

    /// One Peekaboo run; nil when it printed nothing readable (a timeout).
    func run(_ arguments: [String]) -> ArisDesktopEnvelope? {
        guard !arguments.isEmpty else { return nil }
        let (_, output) = engine.runner.run(binary, arguments, stateFolder: engine.installer.stateFolder, timeout: ArisDesktopEngine.runTimeout)
        return ArisDesktopEnvelope.parse(output)
    }

    /// Peekaboo's own words for a failure, redacted (they can name windows and paths).
    func why(_ envelope: ArisDesktopEnvelope?) -> String {
        guard let envelope else { return "Peekaboo gave no answer (it may have timed out)" }
        let text = [envelope.code, envelope.message].compactMap { $0 }.joined(separator: ": ")
        return ArisDesktopPrivacy.redact(String((text.isEmpty ? (envelope.state ?? "no result") : text).prefix(400)), engine.identity)
    }

    /// The process's windows, front to back.
    var windows: [ArisDesktopWindow] { engine.windows.windows(of: target.pid) }

    /// The window a call works in: the one the brain named (it must be this process's), else the front one.
    func pinned(_ named: Int?, title: String? = nil) -> Result<ArisDesktopWindow, ArisDesktopUsage> {
        let all = windows
        if named == nil, let title {
            if ArisWindowTitleMatch.titlesUnreadable(all) {
                return .failure(ArisDesktopUsage(text: ArisWindowTitleMatch.unreadableLine(wanted: title, app: target.name)))
            }
            let match = ArisWindowTitleMatch.pick(title, in: all)
            // Other windows' titles listed back are text read from the app: the turn counts as having read it.
            if case .several = match { turn.markAppRead(target.readKey) }
            if case .one(let id) = match, let window = all.first(where: { $0.id == id }) { return .success(window) }
            return .failure(ArisDesktopUsage(text: ArisWindowTitleMatch.line(match, wanted: title, app: target.name) ?? ""))
        }
        if let named {
            guard let window = all.first(where: { $0.id == named }) else { return .failure(ArisDesktopUsage(text: "Window \(named) isn't one of \(target.name)'s open windows (`desktop window list --app \"\(target.name)\"` lists them).")) }
            return .success(window)
        }
        guard let front = all.first else { return .failure(ArisDesktopUsage(text: "\(target.name) has no open window on screen.")) }
        return .success(front)
    }

    /// One look at one window, recorded as the window's latest (`record` false: a look only a card is drawn from).
    /// `path`: a screenshot is taken too (Screen Recording), never while a password field is up (I6).
    func look(_ window: ArisDesktopWindow, path: String? = nil, annotate: Bool = false, record: Bool = true) -> Result<(ArisDesktopObservation, ArisDesktopEnvelope), ArisDesktopUsage> {
        if path != nil, engine.apps.secureInput { return .failure(ArisDesktopUsage(text: ArisDesktopGate.secureRefusal)) }
        let envelope = run(ArisPeekabooCommands.see(window: window.id, path: path, annotate: annotate))
        guard let envelope, var observation = ArisDesktopObservation.make(envelope, target: target, window: window.id, identity: engine.identity) else {
            return .failure(ArisDesktopUsage(text: why(envelope)))
        }
        // Whose window Peekaboo read is checked every time: no process named, or another one (or another window), and
        // nothing of it is passed on (M4).
        guard envelope.pid == target.pid, envelope.windowId.map({ $0 == window.id }) ?? true else {
            if let id = envelope.snapshotId { turn.ledger.discard(id) }
            return .failure(ArisDesktopUsage(text: "Peekaboo didn't confirm it read \(target.name)'s own window, so nothing of it is passed on"))
        }
        // Aris made this snapshot: only such folders are ever removed (re-review 4).
        ArisPeekabooSnapshots.noteMade(observation.peekaboo, record: engine.installer.stateFolder.appendingPathComponent(ArisPeekabooSnapshots.recordName))
        observation.taken = Date()
        observation.frame = window.frame
        if record { turn.ledger.record(observation) }
        return .success((observation, envelope))
    }

    /// A look at `window`, else (a sheet or dialog Peekaboo can't read) at the windows behind it, its parent first.
    func lookOrParent(_ window: ArisDesktopWindow, alone: Bool) -> Result<ArisDesktopObservation, ArisDesktopUsage> {
        var tried = [window]
        if !alone { tried += windows.filter { $0.id != window.id }.prefix(2) }
        var first: String?
        for (index, candidate) in tried.enumerated() {
            switch look(candidate) {
            case .success(let (found, _)):
                guard index > 0 else { return .success(found) }
                var parent = found
                parent.note = "(The front window \(window.id) couldn't be read: a sheet or dialog. This is the window behind it, whose tree holds it.)"
                turn.ledger.record(parent)
                return .success(parent)
            case .failure(let why):
                if first == nil { first = why.text }
            }
        }
        return .failure(ArisDesktopUsage(text: first ?? "couldn't read the window"))
    }

    /// The window again after an action: the same one if it's still there, else the process's front one.
    func lookAfter(_ window: Int) -> ArisDesktopObservation? {
        let all = windows
        guard let again = all.first(where: { $0.id == window }) ?? all.first else { return nil }
        if case .success(let found) = lookOrParent(again, alone: false) { return found }
        return nil
    }

    /// A private folder for one screenshot, removed by the caller.
    func shotFolder() -> URL? {
        let folder = engine.installer.stateFolder.appendingPathComponent("look-\(UUID().uuidString.prefix(12))")
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])) != nil else { return nil }
        return folder
    }
}

extension ArisDesktopEngine {
    func perform(_ request: ArisDesktopRequest, target: ArisDesktopTarget, turn: ArisDesktopTurn, basis: ArisDesktopBasis = ArisDesktopBasis()) -> ArisMCPOutcome {
        perform(request, target: target, turn: turn, basis: basis, openPause: ArisDesktopSession.openWait)
    }

    func perform(_ request: ArisDesktopRequest, target: ArisDesktopTarget, turn: ArisDesktopTurn, basis: ArisDesktopBasis, openPause: TimeInterval) -> ArisMCPOutcome {
        switch performed(request, target: target, turn: turn, basis: basis, openPause: openPause) {
        case .refused(let outcome): return outcome
        case .result(let result):
            return ArisMCPOutcome(status: result.ok ? 0 : 1,
                                  output: ArisMCPPolicy.wrapped(result.text, server: target.name, tool: "desktop \(request.verb.rawValue)", secrets: [], isError: !result.ok))
        }
    }

    /// What one allowed call came to: stopped before the controller (permissions, secure input, the runtime), or its result.
    enum Performed {
        case refused(ArisMCPOutcome)
        case result(ArisDesktopResult)
    }

    func performed(_ request: ArisDesktopRequest, target: ArisDesktopTarget, turn: ArisDesktopTurn, basis: ArisDesktopBasis = ArisDesktopBasis(),
                   openPause: TimeInterval = ArisDesktopSession.openWait) -> Performed {
        let english = ArisDesktopCopy.isEnglish(turn.request)
        guard access.trusted else {
            access.guide()
            turn.quiet(ArisDesktopCopy.needsAccessibility(english: english))
            ArisFixTurns.shared.note(.pane(.accessibility))
            return .refused(.failed(Self.accessLine(english: english)))
        }
        if request.ocr || request.annotate || request.verb == .clickAt, !access.screenRecording {
            access.guideScreen()
            turn.quiet(ArisDesktopCopy.needsScreenRecording(english: english))
            ArisFixTurns.shared.note(.pane(.screen))
            return .refused(.failed(Self.screenLine(english: english)))
        }
        // A card can wait a minute: a password field may have come up since the gate looked (typing, keys and looks at
        // the pixels: I6; a plain click on a ref still goes, and a text mark's click looks at the pixels first).
        if request.verb.takesText || [.press, .clickAt].contains(request.verb) || request.ocr || request.annotate, apps.secureInput {
            return .refused(.failed(ArisDesktopGate.secureRefusal))
        }
        if installer.state != .ready, !installer.isInstalled() { turn.quiet(ArisDesktopCopy.installing(english: english)) }
        let binary: URL
        switch installer.ready() {
        case .failure(let why): return .refused(.failed("Computer use isn't ready: \(why.text). Say so in a few words."))
        case .success(let found): binary = found
        }
        let shown = operatingTarget(request, target: target, turn: turn).counted(basis.step)
        turn.quiet(shown.line)
        turn.operating(shown)
        // Whatever comes back is this app's own words.
        turn.markAppRead(target.readKey)
        var session = ArisDesktopSession(engine: self, binary: binary, target: target, turn: turn)
        session.basis = basis
        session.openPause = openPause
        // Across calls too: a select-all in this window earlier in the turn, then text or a delete here, replaces what was
        // there; only when the user's words ask for it (security review).
        let window = request.ref.flatMap { turn.ledger.window(ofSnapshot: $0.snapshot) } ?? request.window ?? windows.windows(of: target.pid).first?.id
        if let why = replaceRefusal(request, target: target, turn: turn) { return .refused(.failed(why)) }
        let menuSelectsAll = request.verb == .menuClick
            && (request.path ?? "").components(separatedBy: CharacterSet(charactersIn: ">›")).last.map(ArisDesktopBatch.selectsAll(label:)) == true
        let result: ArisDesktopResult
        switch request.verb {
        case .see: result = session.see(request)
        case .menuList, .dialogList, .windowList, .dockList: result = session.list(request)
        case .type: result = session.typeText(request)
        case .click, .setValue, .scroll, .drag: result = session.actOnRef(request)
        case .press: result = session.press(request)
        case .clickAt: result = session.clickAt(request)
        case .menuClick, .dialogClick, .dialogInput, .dialogFile, .window, .app: result = session.appAction(request)
        case .batch: result = .failed(ArisDesktopWords.usage)
        }
        noteSelection(request, result: result, window: window, menuSelectsAll: menuSelectsAll, turn: turn)
        return .result(result)
    }

    /// What an action the user would be asked about can't run without, told before their card: Accessibility for any of them,
    /// and for click-at Screen Recording and a brain that can look at the picture (audit desk-9). System Settings is
    /// opened at the permission, as it is when the call runs. Nil when nothing is missing.
    func missingBeforeCard(_ request: ArisDesktopRequest, target: ArisDesktopTarget, turn: ArisDesktopTurn) -> String? {
        let english = ArisDesktopCopy.isEnglish(turn.request)
        guard access.trusted else {
            access.guide()
            turn.quiet(ArisDesktopCopy.needsAccessibility(english: english))
            ArisFixTurns.shared.note(.pane(.accessibility))
            return Self.accessLine(english: english)
        }
        guard request.verb == .clickAt else { return nil }
        guard access.screenRecording else {
            access.guideScreen()
            turn.quiet(ArisDesktopCopy.needsScreenRecording(english: english))
            ArisFixTurns.shared.note(.pane(.screen))
            return Self.screenLine(english: english)
        }
        return vision.available(for: turn.brain) ? nil : Self.noVisionLine(app: target.name)
    }

    /// A call that would replace or empty what its window holds when the user's words didn't ask for that (audit desk-3):
    /// one press that selects everything and deletes it, or text or a delete after a select-all there earlier in the
    /// turn. Nil when it wouldn't, or when he asked.
    func replaceRefusal(_ request: ArisDesktopRequest, target: ArisDesktopTarget, turn: ArisDesktopTurn) -> String? {
        guard !ArisDesktopBatch.asksToReplace(turn.request) else { return nil }
        if request.verb == .press, ArisDesktopBatch.selectsThenDeletes(request.keys) { return ArisDesktopBatch.appendLine }
        let window = request.ref.flatMap { turn.ledger.window(ofSnapshot: $0.snapshot) } ?? request.window ?? windows.windows(of: target.pid).first?.id
        let replacing = [.type, .setValue].contains(request.verb) || (request.verb == .press && request.keys.contains(where: ArisDesktopBatch.isDeletion))
        return replacing && turn.ledger.selectedAll(in: window) ? ArisDesktopBatch.appendLine : nil
    }

    /// What the call left selected in its window, kept for the turn's later calls: a select-all whose keys went out
    /// counts even when the window couldn't show it (a lone cmd+a read back as nothing, then a type, replaced the
    /// document); typing over it, deleting it or moving the caret ends it, so "press cmd+down, then type" adds again.
    private func noteSelection(_ request: ArisDesktopRequest, result: ArisDesktopResult, window: Int?, menuSelectsAll: Bool, turn: ArisDesktopTurn) {
        let now = { window.flatMap { turn.ledger.latestLook(window: $0) } }
        switch request.verb {
        case .press:
            switch ArisDesktopBatch.leavesAllSelected(request.keys) {
            case true?: if result.ok || result.keysSent { turn.ledger.noteSelectAll(window: window) }
            case false?: if result.ok, ArisDesktopBatch.allSelected(in: now()) != true { turn.ledger.clearSelectAll(window: window) }
            case nil: break
            }
        case .menuClick:
            if menuSelectsAll, result.ok { turn.ledger.noteSelectAll(window: window) }
        case .type, .setValue:
            if result.ok { turn.ledger.clearSelectAll(window: window) }
        case .click:
            // A click that put the caret somewhere in the text: only when the look shows the selection gone.
            if result.ok, ArisDesktopBatch.allSelected(in: now()) == false { turn.ledger.clearSelectAll(window: window) }
        default: break
        }
    }
}

extension ArisDesktopSession {
    /// `see`: the window's tree; with --ocr the text on its screenshot as marks too.
    func see(_ request: ArisDesktopRequest) -> ArisDesktopResult {
        let window: ArisDesktopWindow
        // The user named one of several windows and the look names none: it is that one, never the front one (QA BUG-47
        // reopened: `see --app TextEdit` gave the front "무제 2"'s refs for "무제 창에 … 써 줘").
        var title = request.title
        let all = windows
        var pinnedNote: String?
        // Several windows of their own (titled: documents, not a sheet or an alert, which a look reads through).
        if request.window == nil, title == nil, Set(all.compactMap { $0.title.flatMap { $0.isEmpty ? nil : $0 } }).count > 1 {
            // Several windows and the look names none: the one the user's words name, said in the result and logged; none
            // named, the windows' list and no refs (the brain picks with --title or --window).
            guard let named = ArisWindowNaming.named(in: turn.request, windows: all), let namedTitle = named.title else {
                turn.audit(["answer": "several windows, none named: listed, no refs", "action": "desktop see · \(target.name)", "brain": turn.brainName])
                turn.markAppRead(target.readKey)
                return ArisDesktopResult(ok: false, text: ArisWindowNaming.chooseLine(app: target.name, windows: all))
            }
            title = namedTitle
            pinnedNote = ArisWindowNaming.pinnedLine(namedTitle)
            turn.ledger.notePinned(namedTitle)
            turn.audit(["answer": "pinned window ‘\(ArisWindowTitleMatch.safeTitle(namedTitle))’ (named in the request)", "action": "desktop see · \(target.name)", "brain": turn.brainName])
        }
        switch pinned(request.window, title: title) {
        case .failure(let why): return .failed(why.text)
        case .success(let found): window = found
        }
        guard request.ocr || request.annotate else {
            switch lookOrParent(window, alone: request.window != nil || title != nil) {
            case .failure(let why): return .failed("Couldn't read \(target.name)'s window (\(why.text)).")
            case .success(let found):
                let next = ArisDesktopFallback.next(brain: turn.brain, engine: engine.computerEngine())
                // With no brain that can look at a picture, the poor-tree line doesn't send the brain to click-at.
                let poor = next.line(app: target.name) ?? (engine.vision.available(for: turn.brain) ? nil : ArisDesktopObservation.poorLineTextOnly.replacingOccurrences(of: "<App>", with: target.name))
                return ArisDesktopResult(ok: true, text: (pinnedNote.map { $0 + "\n" } ?? "") + found.render(poor: poor))
            }
        }
        guard let marked = lookWithText(window)?.0 else { return .failed("Couldn't look at \(target.name)'s window.") }
        return ArisDesktopResult(ok: true, text: (pinnedNote.map { $0 + "\n" } ?? "") + marked.render())
    }

    /// A look with a screenshot, its text read (Apple Vision) as marks; recorded as the window's latest.
    /// `record` false: a look only a check is made from (nothing becomes the window's latest; its snapshot goes at once).
    func lookWithText(_ window: ArisDesktopWindow, annotate: Bool = false, record: Bool = true) -> (ArisDesktopObservation, annotated: Data?)? {
        guard let folder = shotFolder() else { return nil }
        defer { try? FileManager.default.removeItem(at: folder) }
        guard case .success(let (found, envelope)) = look(window, path: folder.appendingPathComponent("window.png").path, annotate: annotate, record: record) else { return nil }
        var marked = found
        var secret: [CGRect] = found.hiddenRegions.map { region in
            CGRect(x: (region.minX - window.frame.minX) / window.frame.width, y: (region.minY - window.frame.minY) / window.frame.height,
                   width: region.width / window.frame.width, height: region.height / window.frame.height)
        }
        var read = false
        if let shot = envelope.screenshot, let png = try? Data(contentsOf: URL(fileURLWithPath: shot)) {
            read = true
            let pieces = engine.reader.read(png: png)
            secret += pieces.filter { ArisDesktopPrivacy.isPersonal($0.text, engine.identity) || ArisDesktopPrivacy.redact($0.text, engine.identity) != $0.text }.map(\.box)
            marked.marks = marks(pieces, window: window).filter { mark in !found.hiddenRegions.contains { $0.intersects(mark.bounds) } }
        }
        if record { turn.ledger.record(marked) } else { turn.ledger.discard(found.peekaboo) }
        // What a vision brain sees: the same things out of the picture, or no picture. The text was never read (no
        // screenshot to read it from): what it would have painted out is unknown, so no picture either (M3).
        let annotated = !read ? nil : envelope.annotated.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }.flatMap { ArisDesktopPrivacy.blackout(png: $0, boxes: secret) }
        return (marked, annotated)
    }

    /// The window shows `text` now: in its tree, else in the text on its screenshot when Screen Recording is on (a field
    /// that gives no value shows only there). Nothing is recorded.
    func windowShows(_ text: String, in look: ArisDesktopObservation) -> Bool {
        if ArisDesktopVerify.appears(text, in: look) { return true }
        guard engine.access.screenRecording, !engine.apps.secureInput, let window = windows.first(where: { $0.id == look.window }),
              let (seen, _) = lookWithText(window, record: false) else { return false }
        return ArisDesktopVerify.appears(text, in: seen)
    }

    /// Text on the screenshot as marks with boxes in global points (the image covers the window exactly).
    func marks(_ pieces: [(text: String, box: CGRect)], window: ArisDesktopWindow) -> [ArisDesktopElement] {
        pieces.prefix(200).enumerated().compactMap { index, piece in
            let text = ArisDesktopPrivacy.redact(piece.text.trimmingCharacters(in: .whitespacesAndNewlines), engine.identity)
            guard !text.isEmpty, !ArisDesktopPrivacy.isPersonal(text, engine.identity) else { return nil }
            let frame = window.frame
            let box = CGRect(x: frame.minX + piece.box.minX * frame.width, y: frame.minY + piece.box.minY * frame.height,
                             width: piece.box.width * frame.width, height: piece.box.height * frame.height)
            return ArisDesktopElement(id: "ocr_\(index + 1)", role: "text", label: String(text.prefix(160)), bounds: box)
        }
    }

    /// The listings: menus, a dialog's parts, the windows, the Dock.
    func list(_ request: ArisDesktopRequest) -> ArisDesktopResult {
        let identity = engine.identity
        switch request.verb {
        case .menuList:
            let envelope = run(ArisPeekabooCommands.menuList(target))
            guard let envelope, envelope.success, let structure = envelope.data["menu_structure"] as? [[String: Any]] else {
                return .failed("Couldn't list \(target.name)'s menus (\(why(envelope))).")
            }
            var lines: [String] = []
            func walk(_ items: [[String: Any]], depth: Int) {
                for item in items where lines.count < 600 {
                    let title = item["title"] as? String ?? ""
                    let shortcut = (item["shortcut"] as? String).map { " \($0)" } ?? ""
                    let off = item["enabled"] as? Bool == false ? " (disabled)" : ""
                    let sub = item["items"] as? [[String: Any]]
                    lines.append(String(repeating: "  ", count: depth) + title + shortcut + off + (sub == nil ? "" : " ›"))
                    if let sub { walk(sub, depth: depth + 1) }
                }
            }
            walk(ArisDesktopPrivacy.menus(structure, identity), depth: 0)
            return ArisDesktopResult(ok: true, text: "\(target.name)'s menus (click one with `desktop menu click --app \"\(target.name)\" --path \"File › …\"`):\n" + lines.joined(separator: "\n"))
        case .windowList:
            let envelope = run(ArisPeekabooCommands.windowList(target))
            guard let envelope, envelope.success, let list = envelope.data["windows"] as? [[String: Any]] else { return .failed("Couldn't list \(target.name)'s windows (\(why(envelope))).") }
            let lines = list.compactMap { window -> String? in
                guard let id = (window["window_id"] as? NSNumber)?.intValue else { return nil }
                let title = ArisDesktopPrivacy.redact(window["window_title"] as? String ?? "", identity)
                let bounds = window["bounds"] as? [String: Any] ?? [:]
                let size = ["width", "height"].map { (bounds[$0] as? NSNumber)?.intValue ?? 0 }
                return "window \(id) “\(title)” \(size[0])×\(size[1])" + (window["is_frontmost"] as? Bool == true ? " (front)" : "")
            }
            return ArisDesktopResult(ok: true, text: lines.isEmpty ? "\(target.name) has no windows." : lines.joined(separator: "\n"))
        default:
            let envelope = run(request.verb == .dockList ? ArisPeekabooCommands.dockList() : ArisPeekabooCommands.dialogList(target))
            guard let envelope, envelope.success, let data = ArisDesktopPrivacy.scrub(envelope.raw ?? [:], identity),
                  let json = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) else {
                return .failed("Couldn't list it (\(why(envelope))). Try `desktop see --app \"\(target.name)\"`: its tree holds the dialog.")
            }
            return ArisDesktopResult(ok: true, text: String(String(decoding: json, as: UTF8.self).prefix(20_000)))
        }
    }
}
