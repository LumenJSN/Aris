//
//  ArisFastLane.swift
//  aris-agent
//
//  The fast lane's warm spare (ARCHITECTURE 3.3, jv-fastlane): a conversation never pays a cold start. Every brain and
//  model whose conversation runner /warm starts keeps one more runner started beside it, with nothing asked. When a
//  conversation starts over ("fresh") on a brain that can't open a new thread in its process (Claude Code, agy), or
//  when its runner has lost its process (a crash, a time limit, the idle stop), the spare takes that runner's place
//  and the next spare starts in the background. Measured on claude 2.1.327 (5 plain questions, Sonnet at low): first
//  text 510 ms on a started process against 1321 ms on one started with the question; Codex luna takes 5 s and more.
//
//  The cost is bounded: one spare per brain and model in use (never a sealed, hands-free or job runner's), stopped by
//  the same idle rule as the runner (its own idle timer from when it was warmed), and a dead spare is replaced only
//  when the next one is asked for (/warm or a swap), never in a loop. A spare is a process that has never been asked
//  anything: swapping it in hands over no conversation, no taint and no card, exactly as a cold start would.
//  Pure: the pool is generic over the runner, so the tests drive it with fakes.
//

import Foundation

/// A runner as the pool sees it, published under the runner's own lock (never its queue).
struct ArisSpareState: Equatable {
    /// Its process is running.
    var alive = false
    /// A turn is under way or on its way (an ask not yet started on its queue counts).
    var busy = false
    /// Its running process has been asked something.
    var asked = false
}

enum ArisFastLane {
    /// Brains whose conversation keeps a spare: every one whose process takes seconds to start. An API brain's process
    /// is the agent itself and starts at once.
    static func keepsSpare(_ brain: ArisBrain) -> Bool { brain != .api }

    /// Brains that open a new thread in the running process (ArisBrainDriver.newConversation): a fresh start needs no
    /// spare while their process lives.
    static func startsOverInProcess(_ brain: ArisBrain) -> Bool { brain == .codex || brain == .api }

    /// Whether a conversation starting over takes the spare in place of `current`. Never while a turn is under way (that
    /// turn keeps its runner and the old way: its next question starts over). In-process brains only when the process is
    /// gone. A started process that was never asked has nothing to forget: it stays.
    static func swapsOnFresh(current: ArisSpareState?, spare: ArisSpareState?, inProcess: Bool) -> Bool {
        guard let spare, spare.alive, !spare.busy, !spare.asked else { return false }
        guard let current else { return true }
        guard !current.busy else { return false }
        if !current.alive { return true }
        return current.asked && !inProcess
    }

    /// Whether a question about to go to `current` takes the spare first: its process is gone (a crash, a time limit, the
    /// idle stop, stopped) and no turn is under way, so it would start cold.
    static func swapsOnAsk(current: ArisSpareState?, spare: ArisSpareState?) -> Bool {
        guard let spare, spare.alive, !spare.busy, !spare.asked, let current else { return false }
        return !current.alive && !current.busy
    }

    /// Whether a spare must be started: none, or the one there is unusable (its process ended, or it was asked).
    static func needsSpare(_ spare: ArisSpareState?) -> Bool {
        guard let spare else { return true }
        return !spare.alive || spare.asked || spare.busy
    }
}

/// One spare per slot (a conversation runner's key), and the brain and model each slot is for. Not locked: the caller
/// holds its registry lock around every call.
struct ArisSparePool<Runner: AnyObject> {
    private(set) var spares: [String: Runner] = [:]
    private(set) var lanes: [String: (brain: ArisBrain, model: String)] = [:]
    /// How many spares were ever made (each gets its own key, so its card ids never meet another runner's).
    private(set) var made = 0

    /// Makes sure `slot` has a usable spare: a new one from `make` when it has none or an unusable one (`made`, for the
    /// caller to warm), and the unusable one handed back to be stopped (`dropped`). Nil, nil: the one there is fine.
    mutating func keep(_ slot: String, brain: ArisBrain, model: String, state: (Runner) -> ArisSpareState,
                       make: (Int) -> Runner) -> (made: Runner?, dropped: Runner?) {
        lanes[slot] = (brain, model)
        if let spare = spares[slot], !ArisFastLane.needsSpare(state(spare)) { return (nil, nil) }
        let dropped = spares[slot]
        made += 1
        let spare = make(made)
        spares[slot] = spare
        return (spare, dropped)
    }

    /// The spare that takes `current`'s place in `slot` now, out of the pool (ArisFastLane.swapsOnFresh / swapsOnAsk); nil:
    /// no swap. The caller puts it in, stops `current` and keeps the next spare.
    mutating func swap(_ slot: String, current: Runner?, fresh: Bool, state: (Runner) -> ArisSpareState) -> Runner? {
        guard let lane = lanes[slot], let spare = spares[slot] else { return nil }
        let swaps = fresh ? ArisFastLane.swapsOnFresh(current: current.map(state), spare: state(spare), inProcess: ArisFastLane.startsOverInProcess(lane.brain))
                          : ArisFastLane.swapsOnAsk(current: current.map(state), spare: state(spare))
        return swaps ? spares.removeValue(forKey: slot) : nil
    }

    /// Takes the spare out of `slot` (for a swap); nil when there is none.
    mutating func take(_ slot: String) -> Runner? { spares.removeValue(forKey: slot) }

    func spare(_ slot: String) -> Runner? { spares[slot] }

    func lane(_ slot: String) -> (brain: ArisBrain, model: String)? { lanes[slot] }

    /// Every spare of `brain` leaves the pool (its settings changed): handed back to be stopped; its slots keep no spare.
    mutating func remove(brain: ArisBrain) -> [Runner] {
        let slots = lanes.filter { $0.value.brain == brain }.keys
        let gone = slots.compactMap { spares.removeValue(forKey: $0) }
        for slot in slots { lanes[slot] = nil }
        return gone
    }
}

/// When the question came in, by its connection, for the turn's timing line (ArisTurnClock).
final class ArisTurnArrivals {
    static let shared = ArisTurnArrivals()
    private let lock = NSLock()
    private var arrived: [ObjectIdentifier: Date] = [:]

    func received(_ owner: AnyObject, at time: Date = Date()) {
        lock.withLock {
            // Only the last few matter: a connection whose turn never started is never taken.
            if arrived.count > 64 { arrived = arrived.filter { time.timeIntervalSince($0.value) < 600 } }
            arrived[ObjectIdentifier(owner)] = time
        }
    }

    func take(_ owner: AnyObject?) -> Date? {
        guard let owner else { return nil }
        return lock.withLock { arrived.removeValue(forKey: ObjectIdentifier(owner)) }
    }
}

/// One turn's timing (target 8): when the question came in, when its line went to the brain, the brain's first line of
/// any kind, its first piece of text, and its answer. Logged once per turn to agent.log, where the helper logs turns.
struct ArisTurnClock {
    let received: Date
    let started: Date
    /// The process was already running when the turn started (else it was started for it).
    let warm: Bool
    let effort: String
    private(set) var written: Date?
    private(set) var firstEvent: Date?
    private(set) var firstDelta: Date?
    private(set) var result: Date?
    private(set) var logged = false

    init(received: Date?, started: Date = Date(), warm: Bool, effort: String) {
        self.received = received ?? started
        self.started = started
        self.warm = warm
        self.effort = effort
    }

    mutating func wrote(at time: Date = Date()) { if written == nil { written = time } }
    /// A line from the brain: counts only once the question went out (a cold start's own lines come before).
    mutating func line(at time: Date = Date()) { if written != nil, firstEvent == nil { firstEvent = time } }
    mutating func delta(at time: Date = Date()) { if firstDelta == nil { firstDelta = time } }

    /// The answer came: the line to log, once.
    mutating func answered(at time: Date = Date(), brain: String, model: String) -> String? {
        guard !logged else { return nil }
        logged = true
        result = time
        func ms(_ date: Date?) -> String { date.map { "\(Int(($0.timeIntervalSince(received) * 1000).rounded())) ms" } ?? "-" }
        return "turn timing \(brain)/\(model) effort \(effort) \(warm ? "warm" : "cold"): written \(ms(written)), first line \(ms(firstEvent)), "
            + "first text \(ms(firstDelta)), answer \(ms(result)) (from the request)"
    }
}
