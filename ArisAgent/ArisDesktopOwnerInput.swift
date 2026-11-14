//
//  ArisDesktopOwnerInput.swift
//  aris-agent
//
//  "Is the owner using the Mac right now": before keys or a click go out for real (foreground), the last input on this
//  Mac counts as the owner's when it is a key, a click, a scroll, or the mouse or trackpad moving, and only when it
//  isn't Aris's own: every Peekaboo action Aris runs (and the pointer it puts back) is kept as a span of its own input,
//  with the turn it was for, and an event that falls in one of that turn's own spans never counts to that turn (another
//  turn's actions never hide the owner from it). There is no mode that acts in the foreground while the owner is away;
//  this only stops Aris when the owner is there. Pure apart from the clock.
//

import Foundation

/// Spans of Aris's own synthetic input (its Peekaboo actions, the pointer it puts back), each kept with the turn it was
/// for (its desktop lock owner), the last few of each. A turn's check counts only its own spans: another turn's actions
/// never hide the owner's input from it (security review 10, L3).
final class ArisOwnInput: @unchecked Sendable {
    static let shared = ArisOwnInput()

    /// How long after one of its own actions an event may still be its own (the window server delivers it a moment late).
    static let grace: TimeInterval = 0.4
    /// Spans kept per turn, and turns kept.
    static let kept = 16
    static let turnsKept = 32

    private let lock = NSLock()
    private var spans: [(owner: String, span: DateInterval)] = []

    /// One of Aris's own actions for `owner` (a turn's desktop lock owner) ran from `start` to `end`.
    func note(from start: Date, to end: Date, owner: String) {
        let span = DateInterval(start: start, end: max(start, end).addingTimeInterval(Self.grace))
        lock.withLock {
            spans.append((owner, span))
            let mine = spans.indices.filter { spans[$0].owner == owner }
            if mine.count > Self.kept { spans.remove(at: mine[0]) }
            var owners: [String] = []
            for entry in spans.reversed() where !owners.contains(entry.owner) { owners.append(entry.owner) }
            if owners.count > Self.turnsKept {
                let keep = Set(owners.prefix(Self.turnsKept))
                spans.removeAll { !keep.contains($0.owner) }
            }
        }
    }

    /// Runs `work` as `owner`'s own input.
    func during<T>(owner: String, _ work: () -> T) -> T {
        let start = Date()
        defer { note(from: start, to: Date(), owner: owner) }
        return work()
    }

    /// `owner`'s own spans, oldest first.
    func recent(for owner: String) -> [DateInterval] { lock.withLock { spans.filter { $0.owner == owner }.map(\.span) } }
}

enum ArisOwnerActivity {
    /// Seconds since the owner's own last input: of the last event of each kind (seconds ago, as the window server says),
    /// the newest that isn't inside one of Aris's own spans. An event inside one is Aris's own and never counts; the
    /// owner's earlier input of that kind is then older than it. Infinity when nothing counts.
    static func secondsSinceOwner(lastEvents: [Double], ownSpans: [DateInterval], now: Date = Date()) -> Double {
        lastEvents.filter { $0.isFinite && $0 >= 0 }.filter { ago in
            let at = now.addingTimeInterval(-ago)
            return !ownSpans.contains { $0.contains(at) }
        }.min() ?? .infinity
    }

    /// The owner used the Mac in the last `seconds`.
    static func active(within seconds: TimeInterval, lastEvents: [Double], ownSpans: [DateInterval], now: Date = Date()) -> Bool {
        secondsSinceOwner(lastEvents: lastEvents, ownSpans: ownSpans, now: now) < seconds
    }
}
