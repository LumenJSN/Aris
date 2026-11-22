//
//  ArisDesktopEngine+Erase.swift
//  aris-agent
//
//  The engine's side of a replace (ArisDesktopErase): what a type or a delete would erase, read when the action is
//  decided (the window's look, taken again when it is older than a few seconds); a replace always goes to its own card,
//  never kept for the app; and a lone select-all in a turn whose words erase or replace is held back, so the select-all
//  and what replaces it go up as one card (thirteenth VM run: "Press keys cmd+a" then "Type …", neither naming the text).
//

import Foundation

extension ArisDesktopEngine {
    /// How old the turn's latest look of the window may be for what a type or a delete erases; older, it is looked at again.
    static let eraseLookAge: TimeInterval = 5

    /// The window a call works in: its ref's look's, the one it names, else the app's front one.
    func eraseWindow(_ request: ArisDesktopRequest, target: ArisDesktopTarget, turn: ArisDesktopTurn) -> Int? {
        request.ref.flatMap { turn.ledger.window(ofSnapshot: $0.snapshot) } ?? request.window ?? windows.windows(of: target.pid).first?.id
    }

    /// A look at that window from the last few seconds: the turn's latest, else one taken now (never recorded).
    func freshLook(window id: Int?, target: ArisDesktopTarget, turn: ArisDesktopTurn) -> ArisDesktopObservation? {
        guard let id else { return nil }
        if let latest = turn.ledger.latestLook(window: id), Date().timeIntervalSince(latest.taken) <= Self.eraseLookAge { return latest }
        guard access.trusted, case .success(let binary) = engineBinary(),
              let window = windows.windows(of: target.pid).first(where: { $0.id == id }) else { return nil }
        let session = ArisDesktopSession(engine: self, binary: binary, target: target, turn: turn)
        guard case .success(let (look, _)) = session.look(window, record: false) else { return nil }
        turn.ledger.discard(look.peekaboo)
        return look
    }

    /// What the call would erase, read now; nil when it erases nothing by its kind (not a type, not a deleting key, no
    /// text field in focus for keys, or a type whose caret the user's words put at the end or the start first).
    func erase(_ request: ArisDesktopRequest, target: ArisDesktopTarget, element: ArisDesktopElement?, turn: ArisDesktopTurn) -> ArisDesktopErase? {
        let typing = request.verb == .type
        let deleting = request.verb == .press && request.keys.contains(where: ArisDesktopBatch.isDeletion)
        guard typing || deleting else { return nil }
        if typing, ArisDesktopCaret.place(said: turn.request, asked: request.at) != nil { return nil }
        let window = eraseWindow(request, target: target, turn: turn)
        let look = freshLook(window: window, target: target, turn: turn)
        let field: ArisDesktopElement?
        if typing {
            field = element.flatMap { found in look.flatMap { ArisDesktopVerify.find(found, in: $0) } } ?? (look == nil ? nil : element)
        } else {
            // Keys go to the focus: an erase only when a text field has it (Finder's delete is a file's, gated as one).
            guard let focused = look?.focusedElement, focused.isTextEntry else { return nil }
            field = focused
        }
        let everything = (deleting && ArisDesktopBatch.selectsThenDeletes(request.keys)) || turn.ledger.selectedAll(in: window)
            || turn.ledger.pendingSelectAll(in: window)
        let scope: ArisDesktopErase.Scope = everything ? .whole : .selection
        return ArisDesktopErase(scope: scope, seen: scope == .whole ? ArisDesktopErase.whole(of: field) : ArisDesktopErase.selection(of: field))
    }

    /// A replace is the user's card every time and never kept for the app; a refusal or a look's judge stay as they are.
    static func asked(_ decision: ArisDesktopDecision, erase: ArisDesktopErase?) -> ArisDesktopDecision {
        guard erase?.replaces == true else { return decision }
        switch decision {
        case .run, .ask: return .ask(remember: false)
        case .judge, .refuse: return decision
        }
    }

    /// A lone select-all (no other key) in a turn whose words erase or replace, with a text field in focus: held back, so
    /// it goes up with what replaces it (the type or the delete that follows) on one card. `cmd+a delete` in one press is
    /// an erase already, asked on its own erase card. Nil: the press goes as it is.
    func deferredSelectAll(_ request: ArisDesktopRequest, target: ArisDesktopTarget, turn: ArisDesktopTurn) -> ArisMCPOutcome? {
        guard request.verb == .press, !request.keys.isEmpty, request.keys.contains(where: ArisDesktopBatch.isSelectAll),
              request.keys.allSatisfy(ArisDesktopBatch.isSelectAll),
              ArisDesktopBatch.asksToReplace(turn.request), !target.sending else { return nil }
        let window = eraseWindow(request, target: target, turn: turn)
        guard let focused = freshLook(window: window, target: target, turn: turn)?.focusedElement, focused.isTextEntry, !focused.isSecure else { return nil }
        turn.ledger.notePendingSelectAll(window: window)
        turn.audit(["answer": "held back (a select-all goes with what replaces it, on one card)", "action": "desktop press · \(target.name)", "brain": turn.brainName])
        return ArisMCPOutcome(status: 0, output: ArisMCPPolicy.wrapped(ArisDesktopErase.deferredLine(app: target.name), server: target.name, tool: "desktop press",
                                                                       secrets: [], isError: false))
    }
}
