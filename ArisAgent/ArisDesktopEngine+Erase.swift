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
    /// What a call's erase came to: what it erases (nil: nothing), or why it is refused before any card.
    enum EraseRead: Equatable {
        case erases(ArisDesktopErase?)
        case refused(String)
    }

    func erase(_ request: ArisDesktopRequest, target: ArisDesktopTarget, element: ArisDesktopElement?, turn: ArisDesktopTurn) -> EraseRead {
        if request.verb == .setValue { return setValueErase(request, target: target, element: element, turn: turn) }
        let typing = request.verb == .type
        let deleting = request.verb == .press && request.keys.contains(where: ArisDesktopBatch.isDeletion)
        guard typing || deleting else { return .erases(nil) }
        if typing, ArisDesktopCaret.place(said: turn.request, asked: request.at) != nil { return .erases(nil) }
        let window = eraseWindow(request, target: target, turn: turn)
        let look = freshLook(window: window, target: target, turn: turn)
        let field: ArisDesktopElement?
        if typing {
            field = element.flatMap { found in look.flatMap { ArisDesktopVerify.find(found, in: $0) } } ?? (look == nil ? nil : element)
        } else {
            // Keys go to the focus: an erase only when a text field has it (Finder's delete is a file's, gated as one).
            guard let focused = look?.focusedElement, focused.isTextEntry else { return .erases(nil) }
            field = focused
        }
        let everything = (deleting && ArisDesktopBatch.selectsThenDeletes(request.keys)) || turn.ledger.selectedAll(in: window)
            || turn.ledger.pendingSelectAll(in: window)
        // A type on a bare caret in a turn whose words replace (fifteenth VM run, R1c/R1f: "전부 지우고 '…'라고 써 줘" with
        // the caret at the end appended under a plain "입력하기" card). His words ask for all of it: it replaces everything
        // the field holds, on the one card that shows that text. They replace only a part ("이거 '체리'로 바꿔 줘"): nothing
        // is typed (it would add) and it never widens to everything; the brain selects that text first, or asks. An empty
        // field erases nothing either way: a plain type.
        let caretOnly = typing && !everything && field?.selectedRange?.length == 0 && ArisDesktopBatch.asksToReplace(turn.request)
        if caretOnly, !ArisDesktopBatch.asksToReplaceAll(turn.request) {
            return ArisDesktopErase.whole(of: field) == .nothing ? .erases(nil) : .refused(ArisDesktopErase.partialAtCaretLine)
        }
        let scope: ArisDesktopErase.Scope = everything || caretOnly ? .whole : .selection
        return .erases(ArisDesktopErase(scope: scope, seen: scope == .whole ? ArisDesktopErase.whole(of: field) : ArisDesktopErase.selection(of: field)))
    }

    /// A set-value into a text field replaces everything it holds (sixteenth VM run, R1k/R1e2: "전부 지우고 '…'라고 써 줘"
    /// went as `desktop set-value` on a plain "Set a value" card, with no warning and nothing to undo): with text there,
    /// read fresh, it is the replace card with that text, held to it, and kept for Aris's undo, as a type over everything
    /// is. His words not asking for all of it to go, a value that drops most of a document's text is refused before any
    /// card (R2k: "이거 '체리'로 바꿔 줘" set the whole document to "체리"). An empty field is a plain set-value; a control
    /// that isn't text (a slider, a checkbox, a pop-up), a search field and Finder's rename field are as before.
    func setValueErase(_ request: ArisDesktopRequest, target: ArisDesktopTarget, element: ArisDesktopElement?, turn: ArisDesktopTurn) -> EraseRead {
        guard let element, Self.setsText(element), target.bundle != ArisShownPlace.finder else { return .erases(nil) }
        let look = freshLook(window: eraseWindow(request, target: target, turn: turn), target: target, turn: turn)
        let field = look.flatMap { ArisDesktopVerify.find(element, in: $0) } ?? (look == nil ? nil : element)
        let seen = ArisDesktopErase.whole(of: field)
        if seen == .nothing { return .erases(nil) }
        if case .text(let held) = seen, !ArisDesktopBatch.asksToReplaceAll(turn.request), ArisDesktopErase.guardsPart(field ?? element, holding: held),
           ArisDesktopErase.dropsMost(was: held, now: request.text ?? "") {
            return .refused(ArisDesktopErase.partialSetValueLine)
        }
        return .erases(ArisDesktopErase(scope: .whole, seen: seen))
    }

    /// A control whose value is text a set-value replaces: a text field or area (not a search field, never a password one).
    static func setsText(_ element: ArisDesktopElement) -> Bool { element.isTextEntry && !element.isSearch && !element.isSecure }

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
    /// an erase already, asked on its own erase card, unless their words also give the text that goes in its place
    /// (fourteenth VM run, R1b: "전부 지우고 '교체된 내용'이라고 써 줘"): then it is held back the same way, once per window,
    /// so the type that follows is the one replace card with both texts. Nil: the press goes as it is.
    func deferredSelectAll(_ request: ArisDesktopRequest, target: ArisDesktopTarget, turn: ArisDesktopTurn) -> ArisMCPOutcome? {
        guard request.verb == .press, !request.keys.isEmpty, request.keys.contains(where: ArisDesktopBatch.isSelectAll),
              ArisDesktopBatch.asksToReplace(turn.request), !target.sending else { return nil }
        let window = eraseWindow(request, target: target, turn: turn)
        let loneSelectAll = request.keys.allSatisfy(ArisDesktopBatch.isSelectAll)
        let erasesForNewText = ArisDesktopBatch.selectsThenDeletes(request.keys)
            && request.keys.allSatisfy { ArisDesktopBatch.isSelectAll($0) || ArisDesktopBatch.isDeletion($0) }
            && ArisDesktopErase.writesNewText(turn.request) && !turn.ledger.pendingSelectAll(in: window)
        guard loneSelectAll || erasesForNewText else { return nil }
        guard let focused = freshLook(window: window, target: target, turn: turn)?.focusedElement, focused.isTextEntry, !focused.isSecure else { return nil }
        turn.ledger.notePendingSelectAll(window: window)
        turn.audit(["answer": "held back (a select-all goes with what replaces it, on one card)", "action": "desktop press · \(target.name)", "brain": turn.brainName])
        return ArisMCPOutcome(status: 0, output: ArisMCPPolicy.wrapped(ArisDesktopErase.deferredLine(app: target.name), server: target.name, tool: "desktop press",
                                                                       secrets: [], isError: false))
    }
}
