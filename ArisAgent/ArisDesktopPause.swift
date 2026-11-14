//
//  ArisDesktopPause.swift
//  aris-agent
//
//  Pause instead of failing: a step stopped by a sign-in, password or permission window (the controller's own "a prompt
//  is on screen" or "a password field is active" refusal, which it gives before doing anything) doesn't end the turn.
//  The notch says what to do in one line, the turn keeps the desktop lock (marked paused: nobody else's action waits
//  behind the window, theirs are refused), the screen is asked again politely until the window is gone or the time
//  limit, and then the step runs again from its own start, with a fresh look, through every check it had. Aris never
//  types into the window or presses anything in it; a website's sign-in is said to be the browser agent's job. Pure
//  apart from `wait`.
//

import Foundation

enum ArisDesktopPause {
    /// How long one step waits for the user, and how often it looks again.
    struct Policy: Equatable {
        var limit: TimeInterval = 180
        var poll: TimeInterval = 1.5
        static let live = Policy()
    }

    /// What stopped the step.
    enum Blocker: Equatable {
        /// A sign-in or permission window of the system's (its owner's name), or a website's sign-in.
        case prompt(owner: String, web: Bool)
        /// A password field is active somewhere (secure input).
        case secureInput
        /// The target window's keyboard focus is in a password or secret field (an app's own sign-in sheet).
        case secretField
    }

    /// How a pause ended.
    enum Ended: Equatable {
        /// The window went away after this long: the step runs again.
        case cleared(waited: TimeInterval)
        /// Still there at the limit.
        case timedOut(Blocker)
        /// The turn ended (cancelled, its time up) while it waited.
        case turnEnded
    }

    /// The system process that shows a website's or an app's web sign-in (passkeys, "Sign in with…"): such a sign-in is
    /// a web page's, which the browser agent handles, never desktop control.
    static func isWebSignIn(_ owner: String) -> Bool {
        let folded = owner.lowercased()
        return folded.contains("authenticationservices") || folded.contains("safariviewservice") || folded.contains("webauthn")
    }

    static func blocker(prompt: String?) -> Blocker? {
        prompt.map { .prompt(owner: $0, web: isWebSignIn($0)) }
    }

    /// What a step's refusal says it was stopped by, before anything was done (exactly the controller's own lines, with
    /// nothing after them); nil for every other result. `prompt`/`secure` are the screen as it is now; `focusSecret`
    /// looks at the target window again: its focus is in a password or secret field (an app's own sign-in sheet). A
    /// step aimed at a password field itself (`targetSecret`) never waits: it is refused, as it always was.
    static func stoppedBy(_ text: String, prompt: String?, secure: Bool, targetSecret: Bool = false, focusSecret: () -> Bool = { false }) -> Blocker? {
        if text == ArisDesktopSession.promptLine { return blocker(prompt: prompt) ?? .prompt(owner: "", web: false) }
        if text == ArisDesktopGate.secureRefusal { return secure ? .secureInput : blocker(prompt: prompt) }
        if text == ArisDesktopGate.secureFieldRefusal, !targetSecret {
            if let shown = blocker(prompt: prompt) { return shown }
            return focusSecret() ? .secretField : nil
        }
        return nil
    }

    /// Secure input is on for another process's password field than the target's (a system password dialog: SecurityAgent),
    /// or, when its owner can't be told, while a sign-in or permission prompt is up: the step then pauses for it instead of
    /// being refused (eighth VM pass: a password dialog ended the step with the secure-input line). Never for a step aimed
    /// at a password field itself, and never for the target's own (both are refused as before). Pure.
    static func secureElsewhere(secure: Bool, owner: Int32?, target: Int32, prompt: String?, aimedAtSecret: Bool) -> Bool {
        guard secure, !aimedAtSecret else { return false }
        if let owner, owner > 0 { return owner != target }
        return prompt != nil
    }

    /// The screen still blocks the step: a prompt is up, or (for a step stopped by secure input) a password field is, or
    /// (for one stopped by the window's own sign-in sheet) the window's focus is still in a secret field.
    static func stillBlocked(_ stopped: Blocker, prompt: String?, secure: Bool, focusSecret: () -> Bool = { false }) -> Blocker? {
        if let now = blocker(prompt: prompt) { return now }
        if case .secureInput = stopped, secure { return .secureInput }
        if case .secretField = stopped, focusSecret() { return .secretField }
        return nil
    }

    /// Waits for the window to go: `now` reads the screen again (nil: it is gone), `live` whether the turn is still
    /// under way, `wait` sleeps one poll. At most `policy.limit` in all (`spent` already used by this call).
    static func waitOut(_ first: Blocker, policy: Policy, spent: TimeInterval = 0, now: () -> Blocker?, live: () -> Bool,
                        wait: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) -> Ended {
        var waited: TimeInterval = 0
        var last = first
        while true {
            if spent + waited >= policy.limit { return .timedOut(last) }
            let step = min(policy.poll, policy.limit - spent - waited)
            wait(step)
            waited += step
            guard live() else { return .turnEnded }
            guard let still = now() else { return .cleared(waited: waited) }
            last = still
        }
    }

    // MARK: - Words

    /// The notch's one line while it waits (the user's language).
    static func line(_ blocker: Blocker, english: Bool) -> String {
        switch blocker {
        case .prompt(_, true):
            return english ? "That's a website's sign-in: please handle it yourself (websites are Aside's job) — I'll carry on when it's done"
                : "웹사이트 로그인 창이에요. 직접 처리해 주세요 (웹사이트 일은 Aside가 해요) — 끝나면 이어서 할게요"
        case .prompt, .secureInput, .secretField:
            return english ? "Please handle the sign-in or permission window — I'll carry on when it's done"
                : "로그인/권한 창을 처리해 주세요 — 끝나면 이어서 할게요"
        }
    }

    /// Put before the step's own result once it ran after a pause (what the brain reads): it did the step only when the
    /// step was done (tenth VM pass: "did the step" stood before a result that wasn't done).
    static func resumedNote(waited: TimeInterval, done: Bool = true) -> String {
        "(A sign-in, password or permission window blocked this step, so Aris paused \(Int(waited.rounded())) s while the user answered it; " +
            (done ? "it is gone now, so Aris looked at the window again and did the step from its start."
                  : "it is gone now, so Aris looked at the window again and tried the step again from its start, and it wasn't done: what stopped it is below.") +
            " Nothing was typed into that window.)"
    }

    /// The brain's line when the pause ended without the window going.
    static func gaveUpLine(_ ended: Ended) -> String {
        switch ended {
        case .timedOut(let blocker):
            let web: Bool
            if case .prompt(_, true) = blocker { web = true } else { web = false }
            return "Refused: a sign-in, password or permission window stayed on screen for \(Int(Policy.live.limit / 60)) minutes, so this step wasn't done " +
                "(Aris never types into such a window or acts while one is up). Tell the user what's left to do once it's answered" +
                (web ? "; a website's sign-in is for the user's browser agent (Aside), not desktop control." : ".")
        case .turnEnded:
            return "The turn ended while Aris waited for a sign-in or permission window to be answered, so this step wasn't done."
        case .cleared:
            return ""
        }
    }
}
