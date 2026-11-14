//
//  ArisDesktopFocusedType.swift
//  aris-agent
//
//  `desktop type --focused --app "<App>" --stdin`: how `aris-tools type` types (ninth VM pass: it typed by itself,
//  wherever the caret was, with no pause for a password dialog, and said "끝에 입력했어요" after typing at the start).
//  Aris looks at the app's window first (a read like any other: aimed at the window the user named, gated, judged on a
//  careful turn), takes the field that has the keyboard focus in that look as the ref, and the type then goes the one
//  way every type goes: its gate and card, the desktop lock, the pause for a sign-in or password window, the caret put
//  where the user's words say, the read-back of where the text landed. Nothing else in Aris types text.
//  Also a background job's `app launch` of an app that already runs: done as it is, nothing launched or brought forward
//  (ninth VM pass: the job gave up on "a background job never brings a window forward").
//

import Foundation

extension ArisDesktopEngine {
    /// What finding the focused field came to: the type with its ref, or the answer for the brain (nothing typed).
    enum FocusedField {
        case success(ArisDesktopRequest)
        case failure(ArisMCPOutcome)
    }

    static let noFocusedFieldLine = ArisDesktopSession.notTypedLead + " No text field has the keyboard focus in that app's window, so nothing was typed. " +
        "Look at the window below and type into a field by its ref: `desktop type <ref> --stdin`."
    static let focusedNotLookedLine = ArisDesktopSession.notTypedLead + " Aris couldn't look at the app's window first, so nothing was typed."

    /// The look, then the focused field as the type's ref. `done` is called once.
    func focusedField(_ asked: ArisDesktopRequest, turn: ArisDesktopTurn, done: @escaping (FocusedField) -> Void) {
        var look = ArisDesktopRequest(verb: .see)
        look.app = asked.app
        // The window the brain named (`aris-tools type … --title`), aimed and checked as any look's --title is.
        look.title = asked.title
        let before = turn.ledger.lastLook?.snapshot
        let pid = asked.app.flatMap { apps.resolve($0) }?.pid
        handleHeld(look, turn: turn, candidate: ArisSavedStepBox()) { seen in
            guard seen.status == 0 else { return done(.failure(ArisMCPOutcome(status: 1, output: Self.focusedNotLookedLine + "\n" + seen.output))) }
            done(Self.focused(in: turn.ledger.lastLook, since: before, pid: pid, asked: asked, seen: seen.output))
        }
    }

    /// The type aimed at `look`'s focused field: a text field, never a password one, in a look taken just now of the
    /// app that was asked for. Pure.
    static func focused(in look: ArisDesktopObservation?, since before: String?, pid: Int32?, asked: ArisDesktopRequest, seen: String) -> FocusedField {
        guard let look, look.snapshot != before, pid == nil || look.target.pid == pid else {
            return .failure(ArisMCPOutcome(status: 1, output: focusedNotLookedLine))
        }
        if look.focusIsSecure { return .failure(.failed(ArisDesktopSession.notTypedLead + " " + ArisDesktopGate.secureFieldRefusal)) }
        guard let field = look.focusedElement, field.isTextEntry, !field.isSecure, let ref = ArisDesktopRef.parse(look.ref(field)), !ref.mark else {
            return .failure(ArisMCPOutcome(status: 1, output: noFocusedFieldLine + "\n\n" + seen))
        }
        var typed = ArisDesktopRequest(verb: .type)
        typed.ref = ref
        typed.text = asked.text
        typed.at = asked.at
        return .success(typed)
    }

    // MARK: - A job's launch of an app that runs

    /// `app launch` of an app that is running now (the process resolve found, still the same one).
    func launchesRunning(_ request: ArisDesktopRequest, target: ArisDesktopTarget) -> Bool {
        guard request.verb == .app, request.operation == "launch", let name = request.app, let running = apps.resolve(name) else { return false }
        return running.pid == target.pid && apps.isRunning(target)
    }

    /// A job's launch of an app that already runs. Aris's own words only (no window title).
    static func alreadyRunningLine(app: String, windows: Int) -> String {
        "\(app) is already running (\(windows) window\(windows == 1 ? "" : "s") open), so nothing was launched and no window was brought forward. " +
            "Work on its window in the background: look at it with `desktop see --app \"\(app)\"`, then act on its refs." +
            (windows == 0 ? " It has no window open now; if the job needs one, say so plainly in the report." : "")
    }
}
