//
//  ClaudeHookHold.swift
//  Aris
//
//  The hook server's time limits, what it counts, who it hands its work to, and the one request it keeps open: a
//  Claude PermissionRequest, held only while the notch really shows its card. A hold ends exactly once: with the
//  card's answer, or with the neutral reply ("no decision": Claude Code asks in its own terminal) the moment Aris is
//  not going to ask: the notch didn't put the card up in time, the card's time passed, the card was answered or
//  dropped elsewhere, the client went away, or the server is closing.
//  Foundation only (tested).
//

import Foundation

struct HookLimits: Equatable {
    /// A whole request is in within this of the connection opening, or the connection is answered and closed
    /// (the neutral reply for a hook event, 408 for anything else). Inside the 2 s Claude Code gives a hook.
    var read: TimeInterval = 1
    /// A hook event with nothing to decide is answered within this of being read. It takes about a millisecond; past
    /// the limit something is wrong, the neutral reply goes out anyway and the event is counted as late.
    var answer: TimeInterval = 0.15
    /// How long the notch has to put a card up. It does so on the main thread, and a stalled one shows nothing:
    /// the longest stalls measured there were 2.4 to 2.7 s (a to-do turn), so a card gets a little more than that.
    var cardShown: TimeInterval = 3
    /// The longest a card keeps its request open: the time Aris's own cards wait (ArisCardEdit.questionTimeout).
    var card: TimeInterval = 120
    /// aris-tools' `todo` and `event` give up after 20 s; the server answers 504 by then and closes.
    var slow: TimeInterval = 20
    /// After an answer, what the client still sends is read and dropped for this long before the connection is
    /// closed, so a client that was still sending gets the answer and not a reset.
    var linger: TimeInterval = 1
    /// At most this many requests are being looked at (token, JSON, event) at once. Each one that never finishes (a
    /// wedged Aris: the deadline has answered it, but its thread stays stuck) keeps a thread, and a process gets 512:
    /// past the limit a request is answered without being looked at (a hook event neutral, the rest 503), so the
    /// deadlines and the replies always have threads. A few at a time is ordinary use.
    var deciding = 64

    static let standard = HookLimits()
}

/// What the server counts; each kind also leaves a line in the log when it isn't the ordinary answer.
struct HookCounts: Equatable {
    enum Kind { case answered, late, unread, tooBig, cardNotShown, cardTimedOut, slowTimedOut, closedByServer, turnedAway }

    var answered = 0
    /// Neutral replies sent by the deadline because the ordinary one hadn't gone out in `HookLimits.answer`.
    var late = 0
    /// Connections whose request didn't arrive in `HookLimits.read`.
    var unread = 0
    var tooBig = 0
    var cardNotShown = 0
    var cardTimedOut = 0
    var slowTimedOut = 0
    var closedByServer = 0
    /// Answered without being looked at, because `HookLimits.deciding` requests were still being looked at.
    var turnedAway = 0

    func counting(_ kind: Kind) -> HookCounts {
        var next = self
        switch kind {
        case .answered: next.answered += 1
        case .late: next.late += 1
        case .unread: next.unread += 1
        case .tooBig: next.tooBig += 1
        case .cardNotShown: next.cardNotShown += 1
        case .cardTimedOut: next.cardTimedOut += 1
        case .slowTimedOut: next.slowTimedOut += 1
        case .closedByServer: next.closedByServer += 1
        case .turnedAway: next.turnedAway += 1
        }
        return next
    }
}

/// How many requests are being looked at now, against `HookLimits.deciding`.
final class HookDeciders: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var inside = 0
    private var full = false

    init(limit: Int) {
        self.limit = limit
    }

    /// A place to look at one request; false when every place is taken. `first` is true for the first refusal since
    /// a place was last given (the log says it once, not once per request).
    func enter() -> (entered: Bool, first: Bool) {
        lock.withLock {
            guard inside < limit else {
                defer { full = true }
                return (false, !full)
            }
            inside += 1
            full = false
            return (true, false)
        }
    }

    func leave() {
        lock.withLock { inside -= 1 }
    }
}

final class HookStats: @unchecked Sendable {
    private let lock = NSLock()
    private var current = HookCounts()

    var counts: HookCounts { lock.withLock { current } }

    func count(_ kind: HookCounts.Kind) { lock.withLock { current = current.counting(kind) } }
}

/// Who the server hands its work to. Events, status reports and cards are passed on its intake queue, in the order
/// the requests were read and after the neutral reply (where there is one) is already on its way: nothing a
/// consumer does, or fails to do, delays an answer. A slow route is called from its own connection's queue.
struct HookConsumer: @unchecked Sendable {
    var event: (ClaudeHookEvent) -> Void
    var status: ([String: Any]) -> Void
    var approval: (ClaudeHookEvent, HookHold) -> Void
    /// `/aris/todos` or `/aris/events` with its JSON body; `reply` is called once with the answer.
    var slow: (String, [String: Any], @escaping (HookReply) -> Void) -> Void
}

final class HookHold: @unchecked Sendable {
    /// Why a hold ended without the card's answer.
    enum End: Equatable { case notShown, timedOut, clientGone, serverClosing }

    private let lock = NSLock()
    private var ended = false
    private var shown = false
    private var onEnd: ((End) -> Void)?
    /// Sends the answer on the held connection (nil: the neutral reply).
    private let reply: (Data?) -> Void

    init(reply: @escaping (Data?) -> Void) {
        self.reply = reply
    }

    var isShown: Bool { lock.withLock { shown } }
    var isOver: Bool { lock.withLock { ended } }

    /// The notch has the card up; `onEnd` drops it if the hold ends without its answer. False when the hold is
    /// already over (the notch came too late): no card must be shown.
    func show(onEnd: @escaping (End) -> Void) -> Bool {
        lock.withLock {
            guard !ended else { return false }
            shown = true
            self.onEnd = onEnd
            return true
        }
    }

    /// The card's answer (nil: no decision, Claude Code asks in its terminal). Only the first ending counts.
    func answer(_ body: Data?) {
        guard finish() != nil else { return }
        reply(body)
    }

    /// Ends the hold with the neutral reply and drops its card. False when it was already over.
    @discardableResult
    func end(_ why: End) -> Bool {
        guard let drop = finish(unlessShown: why == .notShown) else { return false }
        reply(nil)
        drop?(why)
        return true
    }

    /// Marks the hold over; nil when it already was (or, for `unlessShown`, when its card is up), else the card's
    /// drop (if a card is up).
    private func finish(unlessShown: Bool = false) -> ((End) -> Void)?? {
        lock.withLock {
            guard !ended, !(unlessShown && shown) else { return nil }
            ended = true
            let drop = onEnd
            onEnd = nil
            return .some(drop)
        }
    }
}
