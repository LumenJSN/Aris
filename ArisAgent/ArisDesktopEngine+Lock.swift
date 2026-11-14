//
//  ArisDesktopEngine+Lock.swift
//  aris-agent
//
//  Where the engine takes its turn at the keys and pointer (ArisDesktopLock) and where a step stopped by a sign-in or
//  permission window waits for the user instead of failing (ArisDesktopPause).
//

import Foundation

extension ArisDesktopTurn {
    /// The desktop lock's owner id: the same for every call of one turn. By default the turn object itself (one per
    /// turn); a runner's calls each make their own object and say their turn's credential instead.
    var desktopOwner: String { "turn:\(ObjectIdentifier(self).hashValue)" }
    // noteDesktopAction has no default: every kind of turn says where its actions go (a runner's turn, agy's relay
    // turn, a replay), so none is dropped by a default no one meant (seventh VM pass).
}

/// The step a call would be saved as, set once the engine knows it.
final class ArisSavedStepBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<ArisSavedStep, ArisSavedStepsRefusal>?
    var value: Result<ArisSavedStep, ArisSavedStepsRefusal>? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// A callback called at most once (the lock's `done` must not count a call twice).
final class ArisDesktopOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func first() -> Bool { lock.withLock { defer { fired = true }; return !fired } }
}

extension ArisDesktopEngine {
    /// An action's `done`, its turn at the keys and pointer taken (and given back with its answer); a read's `done` as it
    /// is. Nil when the call was refused here (`done` already got why).
    func takeTurn(_ request: ArisDesktopRequest, scope: ArisDesktopLock.Scope, turn: ArisDesktopTurn, done: @escaping (ArisMCPOutcome) -> Void) -> ((ArisMCPOutcome) -> Void)? {
        guard let lock, request.verb.kind == .action else { return done }
        let owner = turn.desktopOwner
        let started = Date()
        let english = ArisDesktopCopy.isEnglish(turn.request)
        switch lock.acquire(ArisDesktopLock.Owner(id: owner, live: { turn.live }), scope: scope, waiting: { turn.quiet(ArisDesktopLockWords.waitingLine(english: english)) }) {
        case .refused(let why):
            turn.audit(["answer": "refused (desktop lock: \(why))", "action": "desktop \(request.verb.rawValue)", "brain": turn.brainName])
            done(.failed(ArisDesktopLockWords.refusal(why, waited: Date().timeIntervalSince(started))))
            return nil
        case .acquired:
            let once = ArisDesktopOnce()
            return { outcome in
                if once.first() { lock.done(owner, scope: scope) }
                done(outcome)
            }
        }
    }

    /// Before an action's card: it waits its turn at the keys and pointer as the action would (refused, with its line,
    /// when another turn keeps them past the wait), then lets go of everything its turn holds while the card waits, so
    /// a card left for later never keeps another turn waiting. False when it was refused (`done` got why).
    func waitsItsTurn(_ request: ArisDesktopRequest, scope: ArisDesktopLock.Scope, turn: ArisDesktopTurn, done: @escaping (ArisMCPOutcome) -> Void) -> Bool {
        guard let lock else { return true }
        guard takeTurn(request, scope: scope, turn: turn, done: done) != nil else { return false }
        lock.release(turn.desktopOwner)
        return true
    }

    /// `performed`, and when its step was stopped by a sign-in, password or permission window before anything was done,
    /// a pause for the user (one line in the notch, the lock held and marked paused) and the step again from its start;
    /// at most the policy's limit in all. With no policy: `performed` as it is.
    func performedPausing(_ request: ArisDesktopRequest, target: ArisDesktopTarget, turn: ArisDesktopTurn, basis: ArisDesktopBasis,
                          openPause: TimeInterval) -> Performed {
        var spent: TimeInterval = 0
        var resumedAfter: TimeInterval?
        var basis = basis
        while true {
            let outcome = performed(request, target: target, turn: turn, basis: basis, openPause: openPause)
            let secretFocus = { self.focusIsSecret(request, target: target, turn: turn) }
            guard let policy = pausePolicy, request.verb.kind == .action, let stopped = Self.stoppedText(outcome),
                  let blocker = ArisDesktopPause.stoppedBy(stopped, prompt: windows.promptOnScreen(), secure: apps.secureInput,
                                                           targetSecret: request.ref.flatMap { turn.ledger.element($0) }?.isSecure == true,
                                                           focusSecret: secretFocus) else {
                return Self.noted(outcome, resumedAfter)
            }
            let owner = turn.desktopOwner
            let english = ArisDesktopCopy.isEnglish(turn.request)
            turn.quiet(ArisDesktopPause.line(blocker, english: english))
            turn.audit(["answer": "paused (a sign-in or permission window)", "action": "desktop \(request.verb.rawValue) · \(target.name)", "brain": turn.brainName])
            lock?.pause(owner, true)
            let ended = ArisDesktopPause.waitOut(blocker, policy: policy, spent: spent,
                                                 now: { ArisDesktopPause.stillBlocked(blocker, prompt: self.windows.promptOnScreen(), secure: self.apps.secureInput,
                                                                                      focusSecret: secretFocus) },
                                                 live: { turn.live })
            lock?.pause(owner, false)
            guard case .cleared(let waited) = ended else {
                turn.audit(["answer": "stopped after a pause (\(ended))", "action": "desktop \(request.verb.rawValue) · \(target.name)", "brain": turn.brainName])
                return .refused(.failed(ArisDesktopPause.gaveUpLine(ended)))
            }
            spent += waited
            resumedAfter = spent
            basis.resumed = true
            turn.audit(["answer": "resumed after \(Int(spent)) s", "action": "desktop \(request.verb.rawValue) · \(target.name)", "brain": turn.brainName])
        }
    }

    /// The window the step works in, looked at again (nothing recorded, nothing typed): its keyboard focus is in a
    /// password or secret field. False when it can't be looked at (the step's own checks run again anyway).
    func focusIsSecret(_ request: ArisDesktopRequest, target: ArisDesktopTarget, turn: ArisDesktopTurn) -> Bool {
        guard case .success(let binary) = installer.ready() else { return false }
        let session = ArisDesktopSession(engine: self, binary: binary, target: target, turn: turn)
        let id = request.ref.flatMap { turn.ledger.window(ofSnapshot: $0.snapshot) } ?? request.window
        guard case .success(let window) = session.pinned(id, title: request.title), case .success(let (look, _)) = session.look(window, record: false) else { return false }
        turn.ledger.discard(look.peekaboo)
        return look.focusIsSecure || look.focusedElement.map { ArisSavedStepsWords.namesSecret($0.label) } == true
    }

    /// A step's own text when it is a refusal (raw, or a result that wasn't done).
    private static func stoppedText(_ outcome: Performed) -> String? {
        switch outcome {
        case .refused(let refused): return refused.status == 0 ? nil : refused.output
        case .result(let result): return result.ok ? nil : result.text
        }
    }

    /// The result with the pause's note before it: what happened to the step run again (done, or tried and not done).
    private static func noted(_ outcome: Performed, _ waited: TimeInterval?) -> Performed {
        guard let waited else { return outcome }
        switch outcome {
        case .refused(let refused):
            let note = ArisDesktopPause.resumedNote(waited: waited, done: refused.status == 0)
            return .refused(ArisMCPOutcome(status: refused.status, output: note + "\n" + refused.output))
        case .result(let result):
            var changed = ArisDesktopResult(ok: result.ok, text: ArisDesktopPause.resumedNote(waited: waited, done: result.ok) + "\n" + result.text)
            changed.keysSent = result.keysSent
            return .result(changed)
        }
    }
}
