//
//  ArisSessionSend.swift
//  aris-agent
//
//  `aris-tools session send <which> <text>`: a prompt typed into one of the user's own Claude Code sessions, in its own
//  terminal tab (the owner, 2026-11-15; he chose this over resuming it headless). Every brain reaches it the same way
//  (POST /session-tool, agy's relay). The order never changes:
//   1. the session is picked (ArisSessionPick; two that fit: the brain asks the user once) and must wait idle at its prompt;
//   2. The user's card, always, for every turn and brain (their own clean turn too): the session and the exact text; their no
//      sends nothing, and a card nobody answers sends nothing;
//   3. after their yes, before anything is typed, both checks again, live: (a) the app's hooks still say it waits idle
//      at its prompt, and its `claude` process runs and is the foreground job of its tty (never a shell, never a
//      suspended job); (b) that tab is brought forward and proven to be that tty (Terminal and iTerm2 by AppleScript;
//      every terminal by a title mark written to the tty and read back from the window in front), and a look at the
//      window shows Claude Code's input box idle;
//   4. only then the paste (the clipboard given back), the window in front checked again, and Return;
//   5. the session's next UserPromptSubmit says it took it; the app is told to say when its next Stop comes.
//  Any check that can't be made stops it, with one line for the user. This is the one narrow way Aris types into a terminal:
//  the desktop engine's and ArisInsert's terminal refusals stay for everything else. Its parts are handed in, so the
//  tests run it with fakes.
//

import Foundation

/// Everything the send reaches outside itself.
struct ArisSessionDeps {
    /// The app's sessions (nil: the app didn't answer).
    var sessions: () -> [ArisLiveSession]?
    /// The session's `claude` process.
    var process: (ArisLiveSession) -> ArisSessionProcessLook
    /// Brings the session's tab forward and proves it is that tty.
    var focus: (ArisLiveSession, ArisSessionProcess) -> Result<ArisSessionTarget, ArisSessionStop>
    /// The look at the proven window: Claude Code's input box idle (nil), or why not.
    var look: (ArisSessionTarget) -> ArisSessionStop?
    /// Pastes the text into the window in front (it must still be the target's).
    var paste: (String, ArisSessionTarget) -> ArisSessionStop?
    /// Presses Return (the target's window must still be in front).
    var submit: (ArisSessionTarget) -> ArisSessionStop?
    /// Whether the session said it took a prompt (UserPromptSubmit) after `since`, waiting a little.
    var submitted: (String, Date) -> Bool
    /// Asks the app to say when the session's next Stop comes.
    var watch: (String) -> Void
    /// The keyboard, pointer and clipboard for this turn (ArisDesktopLock); false when it can't be had.
    var hold: (ArisDesktopTurn) -> Bool
    var release: (ArisDesktopTurn) -> Void
    /// The send is over (sent or stopped): the tab's own title back.
    var finish: (ArisSessionTarget) -> Void = { _ in }
    var home: String = NSHomeDirectory()
}

enum ArisSessionSend {
    static let usage = "usage: session list | session send <session folder or id> <text to type into it>"

    /// How long the user's card may wait (a job's ten minutes; a conversation's runner ends it sooner).
    static let cardWait: TimeInterval = 660

    /// `session list` or `session send …`, from a brain's turn.
    static func answer(_ words: [String], turn: ArisDesktopTurn, deps: ArisSessionDeps) -> ArisMCPOutcome {
        let english = ArisDesktopCopy.isEnglish(turn.request)
        switch words.first {
        case "list" where words.count == 1:
            guard let sessions = deps.sessions() else { return .failed(ArisSessionStop.appUnreachable.note(english: english)) }
            return ArisMCPOutcome(status: 0, output: ArisSessionPick.listing(sessions, home: deps.home))
        case "send" where words.count >= 3:
            return send(which: words[1], text: words.dropFirst(2).joined(separator: " "), turn: turn, deps: deps)
        default:
            return .failed(usage)
        }
    }

    /// `label`: how the fleet named the session it resolved ("3번 aris-jv-world"): the card and the spoken line say it.
    static func send(which: String, text raw: String, turn: ArisDesktopTurn, deps: ArisSessionDeps, label: String? = nil) -> ArisMCPOutcome {
        let english = ArisDesktopCopy.isEnglish(turn.request)
        let action = "session send: " + String(raw.prefix(300))
        func stop(_ why: ArisSessionStop, _ answer: String = "not sent") -> ArisMCPOutcome {
            turn.audit(["answer": "\(answer) (\(why))", "action": action, "brain": turn.brainName])
            return .failed(why.note(english: english))
        }
        var text: String
        switch ArisSessionPick.text(raw) {
        case .failure(let why): return stop(why, "refused")
        case .success(let checked): text = checked
        }
        // A prompt that tells the session to pay, buy, order, subscribe or move money is never typed, on any card
        // (ArisPaymentBoundary; the eleventh VM run, R2).
        if ArisPaymentBoundary.judge(brief: text, request: turn.request, coding: true) == .refused {
            turn.audit(["answer": "refused (it tells the session to pay)", "action": action, "risk": "never", "brain": turn.brainName])
            return .failed(ArisPaymentBoundary.refusedLine)
        }
        // One about paying carries the owner's rule as its last words, shown on the card as typed (exp11, Core 2's hand-offs).
        text = ArisPaymentHandOff.sessionWords(text, request: turn.request, english: english)
        guard let sessions = deps.sessions() else { return stop(.appUnreachable) }
        let session: ArisLiveSession
        switch ArisSessionPick.pick(which, among: sessions, home: deps.home) {
        case .none:
            turn.audit(["answer": "no session fits", "action": action, "brain": turn.brainName])
            return .failed(ArisSessionPick.noneLine(sessions, home: deps.home))
        case .many(let found):
            turn.audit(["answer": "several sessions fit", "action": action, "brain": turn.brainName])
            return .failed(ArisSessionPick.manyLine(found, home: deps.home))
        case .one(let one): session = one
        }
        // A session plainly busy isn't put on a card at all.
        if let why = ArisSessionPick.busy(session) { return stop(why, "refused") }
        // The user's card, always: the exact text, the session it goes to.
        switch ask(ArisSessionPick.card(session, text: text, home: deps.home, english: english, label: label), turn: turn) {
        case .no:
            turn.audit(["answer": "no", "action": action, "brain": turn.brainName])
            return .failed("[Aris] The user said no on the card: nothing was sent. Say in a few words that you didn't send it.")
        case .unanswered:
            turn.audit(["answer": "unanswered", "action": action, "brain": turn.brainName])
            return .failed(ArisRefusalWords.unanswered)
        case .yes:
            break
        }
        guard turn.live else { return stop(.gone, "turn ended") }
        guard deps.hold(turn) else { return stop(.lockBusy) }
        defer { deps.release(turn) }
        // (a) Still idle by its hooks, and its process alive in the foreground of its tty.
        guard let now = deps.sessions()?.first(where: { $0.id == session.id }) else { return stop(.gone) }
        if let why = ArisSessionPick.busy(now) { return stop(why) }
        let process: ArisSessionProcess
        switch deps.process(now) {
        case .none: return stop(.notRunning)
        case .many: return stop(.manyProcesses)
        case .found(let found): process = found
        }
        guard process.foreground else { return stop(.shellInFront) }
        // (b) Its tab in front and proven, and the look says Claude Code waits at its input.
        let target: ArisSessionTarget
        switch deps.focus(now, process) {
        case .failure(let why): return stop(why)
        case .success(let proven): target = proven
        }
        defer { deps.finish(target) }
        if let why = deps.look(target) { return stop(why) }
        // Once more just before the keys: still idle by its hooks, and still the same claude in the foreground of its tty
        // (a tab at a shell prompt takes a paste as a command line: measured in the VM on all three terminals).
        if let latest = deps.sessions()?.first(where: { $0.id == session.id }), let why = ArisSessionPick.busy(latest) { return stop(why) }
        guard case .found(let again) = deps.process(now), again.pid == process.pid, again.tty == process.tty, again.foreground else { return stop(.shellInFront) }
        let started = Date()
        if let why = deps.paste(text, target) { return stop(why) }
        if let why = deps.submit(target) { return stop(why, "pasted, Return not pressed") }
        let took = deps.submitted(session.id, started)
        deps.watch(session.id)
        turn.audit(["answer": took ? "sent" : "sent (no word from the session yet)", "action": action, "brain": turn.brainName,
                    "note": now.terminalName])
        let folder = label ?? session.folder(home: deps.home)
        let said = label != nil
            ? (took ? (english ? "Sent it to \(folder); it started. I'll tell you when it's done." : "\(folder)에 보냈어요. 시작했어요. 끝나면 알려 드릴게요.")
                : (english ? "Typed it into \(folder) and pressed Return, but it hasn't said it started yet." : "\(folder)에 입력하고 엔터를 눌렀는데, 아직 시작했다는 신호는 없어요."))
            : took
            ? (english ? "Sent it to the \(folder) session; it started. I'll tell you when it's done." : "\(folder) 세션에 보냈어요. 시작했어요. 끝나면 알려 드릴게요.")
            : (english ? "Typed it into the \(folder) session and pressed Return, but it hasn't said it started yet." : "\(folder) 세션에 입력하고 엔터를 눌렀는데, 아직 시작했다는 신호는 없어요.")
        return ArisMCPOutcome(status: 0, output: "[Aris] Done: the user's card said yes and Aris typed the text into that session and pressed Return. "
            + "Tell the user this one line and nothing more: \"\(said)\"")
    }

    /// The user's answer on the card (unanswered when it closed with none, or the wait ran out).
    private static func ask(_ card: ArisMCPCard, turn: ArisDesktopTurn) -> ArisMCPAnswer {
        let done = DispatchSemaphore(value: 0)
        let box = ArisSessionAnswerBox()
        turn.ask(card) { answer in
            box.set(answer)
            done.signal()
        }
        return done.wait(timeout: .now() + cardWait) == .success ? box.value ?? .unanswered : .unanswered
    }
}

private final class ArisSessionAnswerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ArisMCPAnswer?
    func set(_ answer: ArisMCPAnswer) { lock.withLock { if stored == nil { stored = answer } } }
    var value: ArisMCPAnswer? { lock.withLock { stored } }
}
