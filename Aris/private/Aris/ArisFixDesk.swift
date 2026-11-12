//
//  ArisFixDesk.swift
//  Aris
//
//  The rules of the button under a failure (ArisFix), pure so the tests run them:
//   · which button shows under what the notch says now: the one aris-agent sent for this turn, else the one the app's
//     own line earns; never while Aris listens, works or asks on a card, never under a turn the user stopped, and never
//     one that needs their words when there are none to ask again;
//   · what a new state of the turn does to it (a new turn takes the old button away; a stop is not a failure);
//   · what happens after he pressed it: a fix Aris can read back (a permission, a key, the helper) is watched for five
//     minutes, and when it turns on Aris asks the same thing again by itself; one it can't read back (a login in
//     Terminal, Automation for one app) leaves "다시 해보기" beside the button instead.
//  Why by itself: he pressed the button for that request a moment ago, the answer to "is it fixed" is known and not
//  guessed, and the request passes every card and gate again exactly as the first time. It never does so when the fix
//  was already on at the press (then nothing changed that could make it work), after another turn began, or past the
//  five minutes.
//

import Foundation

/// The turn as these rules read it (ArisSession's phase, without its other state).
struct ArisFixMoment: Equatable {
    enum Phase: Equatable { case idle, listening, thinking, speaking, failed }

    var phase: Phase = .idle
    var heard = ""
    var reply = ""
    /// A confirm card is up.
    var asking = false
    /// The turn has started a tool (a step shows under it) or put up a card: it may have done something already.
    var worked = false
}

struct ArisFixDesk: Equatable {
    /// The fix aris-agent sent for the turn under way (ArisFixTurns), until the next turn begins.
    private(set) var sent: ArisFix?
    /// What `sent` asks for is already on (read back when it arrived): its button would open something already done.
    private(set) var sentIsOn = false
    /// The fix whose button was pressed, and the reply it was under.
    private(set) var used: ArisFix?
    private(set) var usedUnder = ""
    /// Every fix pressed under that same reply, for a line whose button opens several lists one after another.
    private(set) var pressedUnder: [ArisFix] = []

    func arriving(_ fix: ArisFix) -> ArisFixDesk {
        var next = self
        next.sent = fix
        next.sentIsOn = false
        return next
    }

    /// The fix that arrived was read back as already on.
    func foundOn(_ fix: ArisFix) -> ArisFixDesk {
        guard sent == fix else { return self }
        var next = self
        next.sentIsOn = true
        return next
    }

    func pressing(_ fix: ArisFix, under reply: String) -> ArisFixDesk {
        var next = self
        next.pressedUnder = (usedUnder == reply ? pressedUnder : []) + [fix]
        next.used = fix
        next.usedUnder = reply
        return next
    }

    /// The turn moved from `old` to `new`: a new turn clears everything (Aris listens again, starts on a typed
    /// request, or speaks up about something else, as when a background job ends), and a turn that ends without a
    /// last line (the user stopped it, or cancelled) loses the fix that was sent for it.
    func moving(from old: ArisFixMoment, to new: ArisFixMoment) -> ArisFixDesk {
        let listens = new.phase == .listening && old.phase != .listening
        let asksNew = new.phase == .thinking && old.phase != .thinking && !old.asking
        let otherWords = new.phase != .listening && old.phase != .listening && new.heard != old.heard
        if listens || asksNew || otherWords { return ArisFixDesk() }
        if old.phase == .thinking, new.phase == .idle {
            var next = self
            next.sent = nil
            next.sentIsOn = false
            return next
        }
        return self
    }

    /// What shows under the reply now.
    func offer(_ moment: ArisFixMoment) -> ArisFixOffer? {
        guard !moment.asking, !moment.reply.isEmpty, moment.phase == .failed || moment.phase == .speaking || moment.phase == .idle else { return nil }
        guard let fix = candidate(moment) else { return nil }
        let asksAgain = fix.kind == .retry || fix.kind == .otherBrain
        let hasWords = !moment.heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if asksAgain, !hasWords { return nil }
        let pressed = used == fix && usedUnder == moment.reply
        return ArisFixOffer(fix: fix, again: !asksAgain && hasWords && (fix.again || pressed))
    }

    private func candidate(_ moment: ArisFixMoment) -> ArisFix? {
        if let sent {
            // Already on: under a failure asking again is what is left; under an answer nothing is.
            if !sentIsOn { return sent }
            return moment.phase == .failed ? .retry : nil
        }
        // A line with several lists to open: the next one that was not opened yet, and none once all were.
        let several = ArisAppFix.fixes(forLine: moment.reply)
        if several.count > 1 {
            let opened = usedUnder == moment.reply ? pressedUnder : []
            return several.first { !opened.contains($0) }
        }
        return ArisAppFix.fix(forLine: moment.reply)
    }
}

/// The fix each of the app's own failure lines earns. The lines are told apart by making them again from the functions
/// that make them (ArisPermissionWords, ArisAgentCopy, ArisLocalReply, ArisTurnWatchdog…), the way ArisBrainTrouble knows
/// its own line: when one of them is reworded the button follows, and nothing is guessed from what a sentence happens
/// to say.
enum ArisAppFix {
    /// nil for a line that isn't the app's, and for one with nothing to press (a helper that isn't installed needs
    /// the installer; "못 들었어요" needs him to say it again).
    /// The fixes of a line that has more than one (its button opens them one after another); else what `fix` gives.
    static func fixes(forLine line: String) -> [ArisFix] {
        for english in [false, true] where line == ArisHelperInstallWords.oldRows(english: english) {
            return ArisHelperInstallWords.oldRowsLists.map(ArisFix.pane)
        }
        return fix(forLine: line).map { [$0] } ?? []
    }

    static func fix(forLine line: String) -> ArisFix? {
        guard !line.isEmpty else { return nil }
        for english in [false, true] where line == ArisHelperInstallWords.oldRows(english: english) { return .pane(ArisHelperInstallWords.oldRowsLists[0]) }
        for english in [false, true] {
            // The microphone's list; the button opens Speech Recognition's instead when that is the one still off.
            if line == ArisPermissionWords.turnOn(english: english) { return .pane(.microphone) }
            if line == ArisAgentCopy.notRunning(english: english) { return .settings(.helper, again: true) }
            // The helper came back and the question was left to them (ArisHelperWatch): asking again is the button.
            if line == ArisFixWords.helperBackLine(english: english) { return .retry }
            if line == ArisHelperInstallWords.move(english: english) { return .showApp }
            if line == ArisHelperInstallWords.diskAfterSwitch(english: english) { return .pane(.disk) }
            if line == ArisHelperInstallWords.accessibilityLost(english: english) || line == ArisHelperInstallWords.accessibilityOff(english: english) {
                return .pane(.accessibility)
            }
            if line == ArisStartFailure.tookTooLong(english: english) { return .retry }
            let korean = !english
            if line.hasSuffix(ArisLocalReply.noRemindersAccess(korean: korean)) { return .pane(.reminders) }
            if line == ArisTurnWatchdog.line(korean: korean) || line == ArisLocalReply.undoUnknown(korean: korean) { return .retry }
            if line == ArisUndoWords.failure("not permitted", korean: korean) { return .settings(.control) }
            if line == ArisUndoWords.failure("timed out", korean: korean) { return .retry }
            if line == ArisIntent.arrangeFailure("accessibility", app: "", korean: korean) { return .pane(.accessibility) }
            if line == ArisIntent.arrangeFailure("took too long", app: "", korean: korean)
                || line == ArisIntent.arrangeFailure("", app: "", korean: korean) { return .retry }
        }
        // Lines the app words in the UI's language only.
        if line == ArisAgentCopy.notAnswering || line == ArisAgentCopy.refused { return .retry }
        // An AI that can't start here: also when an older agent sent the line without its fix.
        if let trouble = ArisBrainTrouble.named(in: line) {
            return .settings(trouble.missing == .key || trouble.missing == .setup ? .key : .brain)
        }
        return nil
    }
}

/// After the press.
enum ArisFixReturn {
    /// How long Aris watches for the fix after the press.
    static let window: TimeInterval = 300
    /// How often it looks.
    static let every: TimeInterval = 2

    /// What can be read back to know a fix was made.
    enum Check: Equatable {
        /// aris-agent's Full Disk Access or Screen Recording.
        case agentDisk, agentScreen
        /// The app's own access to Reminders or Calendar.
        case reminders, calendars
        /// The AI the owner chose can answer (its program is there, an API brain has its key).
        case brain
        /// aris-agent answers again.
        case helper
    }

    /// nil when nothing can be read back: the offer to ask again stays beside the button instead.
    static func check(for fix: ArisFix) -> Check? {
        switch fix.kind {
        case .pane:
            switch fix.pane {
            case .disk: return .agentDisk
            case .screen: return .agentScreen
            case .reminders: return .reminders
            case .calendars: return .calendars
            default: return nil
            }
        case .settings:
            switch fix.row {
            case .brain, .key: return .brain
            case .todoAccess: return .reminders
            case .calendarAccess: return .calendars
            case .helper: return .helper
            default: return nil
            }
        case .login, .retry, .otherBrain, .copy, .showApp, .acceptProgram: return nil
        }
    }

    /// What is watched after a press on `fix` under `request`, so the request can be asked again by itself once the
    /// fix shows; nil when nothing is:
    ///  · nothing can be read back, or there are no words to ask again;
    ///  · the helper, whose return has a watch of its own from the failure on (ArisHelperWatch);
    ///  · `handsFree`: the turn was heard without the key. Aris never puts such words in again by itself, also not
    ///    after the permission he opened turns on: his press opened a list, it did not make the heard words his
    ///    typed ones. The quiet "다시 해보기" stays beside the button, and that press is his (security review 7, L9;
    ///    review 6, M1 is the same rule for the helper).
    static func watches(_ fix: ArisFix, request: String, handsFree: Bool) -> Check? {
        guard let check = check(for: fix), check != .helper, !handsFree,
              !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return check
    }

    /// The request waiting on a fix.
    struct Armed: Equatable {
        let request: String
        let fix: ArisFix
        let at: Date
        /// It was read back as still off after the press: only then is turning on a change he made.
        var seenOff = false
    }

    enum Next: Equatable {
        case wait(Armed)
        /// The fix is on: the same request is asked again.
        case askAgain
        case drop
    }

    /// `fixed`: what the check read (nil: no answer). `heard`: the words of the turn the notch holds now (none once
    /// the answer was put away: he hasn't asked anything else, so the request still stands; other words mean another
    /// turn began, and this one is let go). `busy`: Aris is listening, working or asking.
    static func next(_ armed: Armed, fixed: Bool?, heard: String, busy: Bool, now: Date) -> Next {
        guard now.timeIntervalSince(armed.at) <= window, heard == armed.request || heard.isEmpty else { return .drop }
        guard let fixed else { return .wait(armed) }
        guard fixed else {
            var seen = armed
            seen.seenOff = true
            return .wait(seen)
        }
        guard armed.seenOff else { return .drop }
        return busy ? .wait(armed) : .askAgain
    }
}

/// What the voice says for one of the app's own lines that has a button: the line without its way through Settings
/// (the button is there; a path read aloud is noise).
enum ArisFixSpeech {
    static func spoken(_ line: String) -> String {
        for korean in [true, false] {
            let path = ArisLocalReply.noRemindersAccess(korean: korean)
            guard line.hasSuffix(path) else { continue }
            let short = korean ? "미리 알림 접근이 꺼져 있어요." : "Reminders access is off."
            return String(line.dropLast(path.count)) + short
        }
        return line
    }
}
