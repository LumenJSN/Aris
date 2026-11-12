//
//  ArisConversation.swift
//  Aris
//
//  The always-on conversation (the owner, 2026-11-05, "ChatGPT voice"): once a turn starts (wake word, ⌥Space, the
//  gesture), Aris goes straight back to listening after each answer, with no wake word and no key, until it ends.
//  It ends on an end phrase, Esc, ⌥Space while it's listening between turns, a stretch of silence (a setting,
//  30 s by default, counted from the last heard turn, local or AI, or from when Aris stopped speaking: QA BUG-49; noise
//  never counts), 10 minutes after it opened, or the screen
//  locking or sleeping. Long work goes to teammates and background jobs, whose
//  results Aris says at the next pause (ArisPause, ArisAnnouncements).
//  Times are seconds on one clock (the system's uptime), so the rules are plain values to test.
//

import Foundation

struct ArisConversation: Equatable {
    enum Stage: Equatable {
        case closed
        /// A turn is going: the user talking, Aris thinking or speaking (or speaking up on its own).
        case turn
        /// Listening between turns: nobody is talking.
        case between
    }

    enum EndReason: String, Equatable {
        case donePhrase = "end phrase", escape = "esc", key = "talk key", silence, screenAway = "screen away"
        case dismissed = "닫기", tapped = "tap", dictation
    }

    static let defaultSilenceSeconds = 30

    /// A turn the wake word started while another app played sound (a video, a call, music) counts as hands-free: the
    /// "아리스" may have come from it, so the turn acts only as far as anyone's words may (ArisHandsFree: no vouch, no
    /// standing permission, no memory in or out).
    static func wakeTurnIsHandsFree(otherAudio: Bool) -> Bool { otherAudio }
    /// However the conversation goes, it ends this long after it opened (security review C1: what the microphone
    /// hears without a key or the name has the user's say for a bounded time).
    static let longestSeconds: Double = 600

    private(set) var stage: Stage = .closed
    /// When the last turn that reached the AI ended: the silence between turns counts from here.
    private(set) var quietSince: Double = 0
    private(set) var openedAt: Double = 0

    var isOpen: Bool { stage != .closed }
    var isBetweenTurns: Bool { stage == .between }

    static func enabled(silenceSeconds: Int) -> Bool { silenceSeconds > 0 }

    /// A turn starts: a closed conversation opens, quiet from now; an open one just starts the turn.
    func opened(at now: Double) -> ArisConversation {
        guard isOpen else { return ArisConversation(stage: .turn, quietSince: now, openedAt: now) }
        return turnStarted()
    }

    /// Voice between turns started a turn; the quiet clock waits for words to move.
    func turnStarted() -> ArisConversation {
        guard isOpen else { return self }
        return ArisConversation(stage: .turn, quietSince: quietSince, openedAt: openedAt)
    }

    /// The turn is over and Aris listens again. `reachedAI`: the turn went to the AI; `heard`: the user's words were answered
    /// here (the time, a timer: QA BUG-49, a dialogue of local answers closed 2 s after an answer). Either restarts the
    /// quiet clock; noise or a false start leaves it where it was.
    func settled(at now: Double, reachedAI: Bool, heard: Bool = false) -> ArisConversation {
        guard isOpen else { return self }
        return ArisConversation(stage: .between, quietSince: reachedAI || heard ? now : quietSince, openedAt: openedAt)
    }

    /// Aris stopped speaking (an answer, or its own news): the silence is counted from now (QA BUG-49).
    func spoke(at now: Double) -> ArisConversation {
        guard isOpen else { return self }
        return ArisConversation(stage: stage, quietSince: max(quietSince, now), openedAt: openedAt)
    }

    func closed() -> ArisConversation { ArisConversation() }

    /// Between turns: `silenceSeconds` since the last turn that reached the AI (0: never), or the 10-minute cap.
    func timedOut(at now: Double, silenceSeconds: Int) -> Bool {
        guard isBetweenTurns else { return false }
        if now - openedAt >= Self.longestSeconds { return true }
        return Self.enabled(silenceSeconds: silenceSeconds) && now - quietSince >= Double(silenceSeconds)
    }

    enum KeyPress: Equatable {
        case endConversation
        /// ArisTalkKey's rules: start, finish or interrupt.
        case asUsual
    }

    /// ⌥Space while Aris listens between turns ends the conversation; the circle gesture's key still starts a turn.
    static func keyPress(betweenTurns: Bool, fromGesture: Bool) -> KeyPress {
        betweenTurns && !fromGesture ? .endConversation : .asUsual
    }
}

/// When Aris may speak up on its own (a job is done, a job asks): never over the user, never over itself.
enum ArisPause {
    /// The user's voice this recently means they may still be going.
    static let afterVoice: Double = 1.0
    /// Right after an answer the user gets the first word.
    static let afterAris: Double = 1.5

    /// Outside a conversation, idle is free (as before). In one, it's also: the user isn't talking, and neither they nor Aris
    /// spoke a moment ago. `sinceVoice`/`sinceAris`: seconds since, nil for never.
    static func isPause(idle: Bool, training: Bool, conversationOpen: Bool, userTalking: Bool, sinceVoice: Double?, sinceAris: Double?) -> Bool {
        guard idle, !training else { return false }
        guard conversationOpen else { return true }
        return !userTalking && (sinceVoice ?? .infinity) >= afterVoice && (sinceAris ?? .infinity) >= afterAris
    }
}

/// Aris's own announcements (job results, failures, the inbox, a job's question) wait in line: first come, first
/// said, one at a time. A ticket leaves the line once it was said or gave up.
struct ArisAnnouncements: Equatable {
    struct Ticket: Hashable { let number: Int }

    private(set) var waiting: [Ticket] = []
    private var issued = 0

    var count: Int { waiting.count }

    func adding() -> (ArisAnnouncements, Ticket) {
        let ticket = Ticket(number: issued)
        var next = self
        next.waiting = waiting + [ticket]
        next.issued = issued + 1
        return (next, ticket)
    }

    func removing(_ ticket: Ticket) -> ArisAnnouncements {
        var next = self
        next.waiting = waiting.filter { $0 != ticket }
        return next
    }

    func isFirst(_ ticket: Ticket) -> Bool { waiting.first == ticket }
}

/// The one line Aris says when it hands work out: who took it, and that it'll say when it's done.
enum ArisHandoffLine {
    /// `names`: who took each job, nil for Aris itself (a clone).
    static func line(_ names: [String?], korean: Bool) -> String {
        let count = max(1, names.count)
        var who: [String?] = []
        for name in names where !who.contains(name) { who.append(name) }
        if who.isEmpty { who = [nil] }
        return korean ? koreanLine(who, count: count) : englishLine(who, count: count)
    }

    private static func koreanLine(_ who: [String?], count: Int) -> String {
        let tail = "맡았어요, 끝나면 알려줄게요."
        let several = who.count == 1 && count > 1 ? "\(count)개 " : ""
        if who.count == 1 {
            return (who[0].map(subject) ?? "제가") + " " + several + tail
        }
        let named = who.compactMap { $0 }
        let all = named + (who.contains(nil) ? ["제"] : [])
        let joined = all.dropLast().joined(separator: "하고 ") + "하고 " + (all.last == "제" ? "제가" : subject(all.last ?? ""))
        return joined + " " + tail
    }

    private static func englishLine(_ who: [String?], count: Int) -> String {
        if who == [nil] {
            return count > 1 ? "I'm on \(count) jobs in the background. I'll let you know when they're done."
                : "I'm on it in the background. I'll let you know when it's done."
        }
        let names = who.compactMap { $0 } + (who.contains(nil) ? ["I"] : [])
        let joined = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names[0]
        return count > 1 ? "\(joined) took \(count) jobs. I'll let you know when they're done."
            : "\(joined) took it. I'll let you know when it's done."
    }

    /// The name with 이 or 가: 이 after a final consonant (민준이), 가 after a vowel or a Latin name (코디가, Aside가).
    static func subject(_ name: String) -> String {
        guard let last = name.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return name + "가" }
        return name + ((last.value - 0xAC00) % 28 == 0 ? "가" : "이")
    }
}
