//
//  ArisHelperReturn.swift
//  Aris
//
//  What the notch does after a question was lost because aris-agent (the helper) was not there: stopped before the
//  question, or gone in the middle of the answer. The rule is about the outcome, not about having watched the helper
//  go down (final VM run: since the helper lives in the app, launchd or the app's quiet restart brings it back in
//  0.3 to 10 s, before or right after the press, so a rule that waited to see it off after the press never fired):
//   · from the failure on, the helper is asked every second and a half whether it answers;
//   · once it answers, however it came back, the same question is asked again once, by itself, when it was his own
//     words and the lost turn had not started a tool or put up a card; then the line and its button go with the new turn;
//   · a turn that had already worked (its step may have run), and one that was itself the question asked again, is
//     never asked again by itself: the line then says the helper is running again, with "다시 해보기" as the button;
//   · he asked something else meanwhile: nothing is asked by itself;
//   · the helper does not come back: the button reads "Restarting the helper…" for a minute after his press
//     (ArisFixWords.restartLimit), then is the button again; the watch itself ends five minutes after the failure or
//     his last press.
//  Pure, so the tests run it over recorded sequences; ArisFixModel runs it against the real helper.
//

import Foundation

/// Who answered on the helper's port: its process and when that process started. Sent by the helper's /health.
struct ArisHelperIdentity: Equatable {
    let pid: Int
    let started: Double

    init(pid: Int, started: Double) {
        self.pid = pid
        self.started = started
    }

    /// From /health's body; nil when it names no process (an older helper).
    init?(json: Data) {
        guard let body = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let pid = body["pid"] as? Int, pid > 0, let started = body["started"] as? Double else { return nil }
        self.init(pid: pid, started: started)
    }

    var json: Data { (try? JSONSerialization.data(withJSONObject: ["pid": pid, "started": started])) ?? Data("{}".utf8) }
}

/// One look at the helper's port.
enum ArisHelperSeen: Equatable {
    /// Nothing listens there.
    case refused
    /// Something answered; `who` when it said which process it is.
    case answered(ArisHelperIdentity?)

    var answers: Bool { self != .refused }
}

/// A stream that ended with no last line: the helper went away, or the AI did not answer.
enum ArisHelperGone {
    /// `before`: the helper as it was asked just before the question. `after`: as it is asked now. The helper went
    /// away when nothing answers now, or when another process answers than the one that took the question (launchd
    /// started a new one in between). The same process still answering did not go away: its AI did not answer.
    static func wentAway(before: ArisHelperSeen, after: ArisHelperSeen) -> Bool {
        guard case .answered(let now) = after else { return true }
        guard case .answered(let then) = before, let then, let now else { return false }
        return then != now
    }
}

struct ArisHelperWatch: Equatable {
    /// How often the helper is asked whether it is back.
    static let every: TimeInterval = ArisFixWords.restartLook
    /// How long the watch goes on after the failure or his last press on the button.
    static let window: TimeInterval = ArisFixReturn.window

    /// A question lost to a helper that was not there.
    struct Lost: Equatable {
        /// His words ("" when there are none to ask again: a turn with circled shots, a line that is nobody's request).
        let request: String
        /// When it was lost, or when he last pressed the button.
        var at: Date
        /// When he pressed the button, if he did.
        var pressedAt: Date?
        /// The lost turn had started a tool or put up a card.
        let worked: Bool
        /// The lost turn was itself this question asked again by Aris, or Aris asked these very words again by itself
        /// a moment ago (`repeatWindow`).
        let again: Bool
        /// The lost turn was heard without the key (the wake word, a follow-up). Such a turn runs under limits of its
        /// own (a sealed route, no standing permission, no learned shortcut, no spoken yes), and Aris never puts its
        /// words in again as if he had typed them: it gets the line with its button, and the press is his
        /// (security review 6, M1).
        var handsFree = false

        /// Whether Aris asks it again by itself once the helper answers.
        var asksAgain: Bool { !request.isEmpty && !worked && !again && !handsFree }
    }

    /// The words Aris asked again by itself, and when.
    struct Asked: Equatable {
        let words: String
        let at: Date
    }

    /// Aris never asks the same words again by itself twice within this long, whatever happened in between (review
    /// 6, M2: a question whose answer made the helper die in mid-stream was asked again each time launchd brought
    /// the helper back, a full AI turn each time).
    static let repeatWindow: TimeInterval = 600

    enum Step: Equatable {
        case wait
        /// The helper answers: the same question, asked again by itself.
        case askAgain(String)
        /// The helper answers, and the question is left to them: the line says it is running again.
        case back
        /// Nothing more to do (another turn began, or the time is up).
        case drop
    }

    private(set) var lost: Lost?
    /// The turn under way started a tool or put up a card.
    private(set) var worked = false
    /// The question Aris asked again by itself, until a turn ends answered: never a second time before that.
    private(set) var askedAgain: String?
    /// The last words Aris asked again by itself and when: never the same words twice within `repeatWindow`. Nothing
    /// clears this but time and the next such question.
    private(set) var lastAsked: Asked?

    /// Whether a loss of `words` at `now` is one Aris already asked again: the mark still stands, or it asked these
    /// very words by itself within `repeatWindow`.
    func askedAlready(_ heard: String, now: Date) -> Bool {
        // As the lost request itself is kept: without the blanks around it (heard words can end in a space, the
        // words asked again never do: security review 7, L7).
        let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return false }
        if askedAgain == words { return true }
        guard let lastAsked, lastAsked.words == words else { return false }
        return now.timeIntervalSince(lastAsked.at) <= Self.repeatWindow
    }

    /// Whether `line` is the one a lost helper earns.
    static func isLostLine(_ line: String) -> Bool {
        line == ArisAgentCopy.notRunning(english: true) || line == ArisAgentCopy.notRunning(english: false)
    }

    /// The turn moved from `old` to `new`. `handsFree`: the turn `new` belongs to was heard without the key.
    func moving(from old: ArisFixMoment, to new: ArisFixMoment, now: Date, handsFree: Bool = false) -> ArisHelperWatch {
        var next = self
        let listens = new.phase == .listening && old.phase != .listening
        let asksNew = new.phase == .thinking && old.phase != .thinking && !old.asking
        // Other words in the notch (an announcement, another answer). An answer that was only put away (no words
        // left) is not another turn: he hasn't asked anything else, so the lost question still stands.
        let otherWords = new.phase != .listening && old.phase != .listening && new.heard != old.heard && !new.heard.isEmpty
        let fresh = listens || asksNew || otherWords
        if fresh {
            next.worked = false
            next.lost = nil
        }
        // `old` too, when it is the same turn: a step that was still running is dropped from a failed turn's tags.
        if new.worked || (!fresh && old.worked) { next.worked = true }
        // A turn ended answered (its answer was said and the turn is over): what comes later is a new loss. A piece
        // of an answer that is still streaming is no answer yet: the helper can die under it, and the mark must hold.
        if new.phase == .idle, old.phase == .speaking, !old.asking, !old.reply.isEmpty { next.askedAgain = nil }
        if new.phase == .failed, old.phase != .failed, Self.isLostLine(new.reply) {
            next.lost = Lost(request: new.heard.trimmingCharacters(in: .whitespacesAndNewlines), at: now, pressedAt: nil,
                             worked: next.worked, again: askedAlready(new.heard, now: now), handsFree: handsFree)
        }
        return next
    }

    /// He pressed the helper's button under `moment`: the minute of "Restarting the helper…" and the watch begin again
    /// (also when the watch had ended and the line is still there).
    func pressed(under moment: ArisFixMoment, now: Date, handsFree: Bool = false) -> ArisHelperWatch {
        var next = self
        if var lost {
            lost.at = now
            lost.pressedAt = now
            next.lost = lost
        } else if Self.isLostLine(moment.reply) {
            next.lost = Lost(request: moment.heard.trimmingCharacters(in: .whitespacesAndNewlines), at: now, pressedAt: now,
                             worked: worked, again: askedAlready(moment.heard, now: now), handsFree: handsFree)
        }
        return next
    }

    /// Whether the button reads "Restarting the helper…" now: for a minute after his press, while the watch goes on.
    func restarting(now: Date) -> Bool {
        guard let pressedAt = lost?.pressedAt else { return false }
        return ArisFixWords.stillRestarting(answering: false, waited: now.timeIntervalSince(pressedAt))
    }

    /// The helper was asked: `answering` whether it answered. `moment`: the turn the notch holds now.
    func looked(answering: Bool, moment: ArisFixMoment, now: Date) -> (ArisHelperWatch, Step) {
        guard let lost else { return (self, .drop) }
        var next = self
        let busy = moment.phase == .listening || moment.phase == .thinking || moment.asking
        let sameTurn = moment.heard.trimmingCharacters(in: .whitespacesAndNewlines) == lost.request || moment.heard.isEmpty
        guard !busy, sameTurn, now.timeIntervalSince(lost.at) <= Self.window else {
            next.lost = nil
            return (next, .drop)
        }
        guard answering else { return (self, .wait) }
        next.lost = nil
        guard lost.asksAgain else { return (next, .back) }
        next.askedAgain = lost.request
        next.lastAsked = Asked(words: lost.request, at: now)
        return (next, .askAgain(lost.request))
    }
}
