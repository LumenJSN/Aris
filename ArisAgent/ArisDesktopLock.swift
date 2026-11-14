//
//  ArisDesktopLock.swift
//  aris-agent
//
//  One owner of the Mac's keys and pointer at a time, across every turn and job: a voice turn, a typed turn and a
//  teammate job never drive the desktop together. Two levels: anything that uses the real pointer, the keyboard focus
//  or the clipboard holds it for the whole Mac (global); an Accessibility action on one app's element that needs none of
//  those holds it only for that app (ArisDesktopLockScope), so turns working in different apps go at once. A desktop action takes the lock for its turn (its owner id) and keeps
//  it for the rest of that turn: released when the turn ends, when the owner is no longer live (cancelled, crashed,
//  over), or when it has sat unused between calls for `idleHold`. Other owners wait in line, first come first served,
//  for at most `waitLimit`; while they wait their notch line says so. Read-only looks never take it. While the owner is
//  paused on a sign-in or permission window (ArisDesktopPause), nobody else waits: their actions are refused at once,
//  never queued behind the window the user is answering. Pure apart from the clock and the wait.
//

import Foundation

final class ArisDesktopLock {
    /// Who asks: an id that is the same for every call of one turn, and whether that turn is still under way. `live`
    /// is never called while the lock's own state is held (it may ask a runner's queue).
    struct Owner {
        let id: String
        let live: () -> Bool
    }

    /// What a call needs. `global`: the real pointer, the keyboard focus or the clipboard (keys, typing, pastes, pointer
    /// clicks, drags and scrolls, window moves and raises, bringing an app forward): one owner on the whole Mac.
    /// `app`: an Accessibility action on one app's element that needs none of those (an element's own press, its value
    /// set): one owner per app, different apps at once. A global holder excludes every app holder, and the other way.
    enum Scope: Hashable {
        case global
        case app(String)
    }

    enum Refusal: Equatable {
        /// Another owner kept it past the wait limit.
        case timedOut
        /// An owner is paused on a sign-in or permission window: nothing waits behind it.
        case paused
        /// The asking turn ended while it waited.
        case ended
    }

    enum Outcome: Equatable {
        case acquired
        case refused(Refusal)
    }

    /// The lock's state, for the tests and the audit: the global holder (else the first app holder), its calls under way.
    struct State: Equatable {
        var holder: String?
        var busy = 0
        var paused = false
        var waiting = 0
    }

    static let shared = ArisDesktopLock()

    /// How long a call waits for its turn (past a card's own limit would be pointless: the owner's card ends first).
    let waitLimit: TimeInterval
    /// How long an owner keeps the lock between its calls (a brain thinking about its next step).
    let idleHold: TimeInterval
    /// How often a waiter checks again (the holder's liveness, its own).
    let poll: TimeInterval

    private struct Hold {
        let id: String
        let scope: Scope
        let live: () -> Bool
        var busy: Int
        var used: Date
        var paused: Bool
    }

    private struct Ticket {
        let number: Int
        let id: String
        let scope: Scope
    }

    private let condition = NSCondition()
    private var holds: [Hold] = []
    private var line: [Ticket] = []
    private var nextTicket = 0

    init(waitLimit: TimeInterval = 90, idleHold: TimeInterval = 45, poll: TimeInterval = 0.1) {
        self.waitLimit = waitLimit
        self.idleHold = idleHold
        self.poll = poll
    }

    var state: State {
        condition.lock()
        defer { condition.unlock() }
        let shown = holds.first { $0.scope == .global } ?? holds.first
        return State(holder: shown?.id, busy: shown?.busy ?? 0, paused: holds.contains { $0.paused }, waiting: line.count)
    }

    /// Who holds `scope` now (the global holder for every scope while there is one).
    func holder(of scope: Scope) -> String? {
        condition.lock()
        defer { condition.unlock() }
        return (holds.first { $0.scope == .global } ?? holds.first { $0.scope == scope })?.id
    }

    /// Two needs clash: different owners, and either is global or both are the same app.
    static func clash(_ one: Scope, _ oneOwner: String, _ other: Scope, _ otherOwner: String) -> Bool {
        guard oneOwner != otherOwner else { return false }
        return one == .global || other == .global || one == other
    }

    /// One call of `owner` starts: it holds `scope` until `done`, and its turn keeps it after (see the file's note).
    /// `waiting` is called once, outside the lock, when the call has to wait (the notch's line). Fair: a call never goes
    /// before an earlier one it clashes with.
    func acquire(_ owner: Owner, scope: Scope = .global, waiting: () -> Void = {}) -> Outcome {
        let deadline = Date().addingTimeInterval(waitLimit)
        condition.lock()
        if holds.contains(where: { $0.id == owner.id && $0.paused }) {
            condition.unlock()
            return .refused(.paused)
        }
        // Its own hold covers it: the same app, or its own global hold.
        if let index = holds.firstIndex(where: { $0.id == owner.id && ($0.scope == scope || $0.scope == .global) }) {
            holds[index].busy += 1
            holds[index].used = Date()
            condition.unlock()
            return .acquired
        }
        let ticket = Ticket(number: nextTicket, id: owner.id, scope: scope)
        nextTicket += 1
        line.append(ticket)
        var told = false
        while true {
            dropStaleHolds()
            if holds.contains(where: { $0.paused && $0.id != owner.id }) { return leave(ticket, .paused) }
            let free = !holds.contains { Self.clash($0.scope, $0.id, scope, owner.id) }
            let ahead = line.prefix { $0.number != ticket.number }
            if free, !ahead.contains(where: { Self.clash($0.scope, $0.id, scope, owner.id) }) {
                line.removeAll { $0.number == ticket.number }
                holds.append(Hold(id: owner.id, scope: scope, live: owner.live, busy: 1, used: Date(), paused: false))
                condition.broadcast()
                condition.unlock()
                return .acquired
            }
            if Date() >= deadline { return leave(ticket, .timedOut) }
            condition.unlock()
            let ownerLive = owner.live()
            if !told, ownerLive {
                told = true
                waiting()
            }
            condition.lock()
            if !ownerLive { return leave(ticket, .ended) }
            _ = condition.wait(until: min(deadline, Date().addingTimeInterval(poll)))
        }
    }

    /// One call of `id` ended (worked or not): the turn keeps the lock, unused from now. `scope`: the call's own.
    func done(_ id: String, scope: Scope = .global) {
        condition.lock()
        let index = holds.firstIndex { $0.id == id && $0.scope == scope && $0.busy > 0 }
            ?? holds.firstIndex { $0.id == id && $0.scope == .global && $0.busy > 0 }
            ?? holds.firstIndex { $0.id == id && $0.busy > 0 }
        if let index {
            holds[index].busy -= 1
            holds[index].used = Date()
        }
        condition.broadcast()
        condition.unlock()
    }

    /// The turn `id` ended (or was cancelled): everything it holds goes, and the next in line go.
    func release(_ id: String) {
        condition.lock()
        holds.removeAll { $0.id == id }
        condition.broadcast()
        condition.unlock()
    }

    /// The owner waits for the user to answer a sign-in or permission window (true), or goes on (false). While it is
    /// paused it holds the Mac as a global holder does: every other owner's new call, of any scope, is refused.
    func pause(_ id: String, _ paused: Bool) {
        condition.lock()
        for index in holds.indices where holds[index].id == id {
            holds[index].paused = paused
            holds[index].used = Date()
        }
        condition.broadcast()
        condition.unlock()
    }

    /// With the state held: holds that are no longer live, or have sat unused past `idleHold`, are dropped. Liveness is
    /// asked with the state let go (it may wait on a runner's queue, which may be releasing this lock).
    private func dropStaleHolds() {
        let now = Date()
        holds.removeAll { $0.busy == 0 && !$0.paused && now.timeIntervalSince($0.used) > idleHold }
        let owners = Dictionary(holds.map { ($0.id, $0.live) }, uniquingKeysWith: { first, _ in first })
        guard !owners.isEmpty else { return }
        condition.unlock()
        let dead = Set(owners.filter { !$0.value() }.keys)
        condition.lock()
        if !dead.isEmpty { holds.removeAll { dead.contains($0.id) } }
    }

    /// With the state held: the ticket leaves the line, and the state is let go.
    private func leave(_ ticket: Ticket, _ why: Refusal) -> Outcome {
        line.removeAll { $0.number == ticket.number }
        condition.broadcast()
        condition.unlock()
        return .refused(why)
    }
}

/// Which level of the lock a desktop call needs (ArisDesktopLock.Scope), told from how the controller does it, and
/// conservative: anything that may use the real pointer, the keyboard focus or the clipboard, or bring a window
/// forward, or that Aris can't be sure of, is global. Per app only: a plain click on an element ref (sent action-only,
/// `--input-strategy actionOnly`: the element's own press, no pointer, no focus, never Peekaboo's default fallback to
/// synthetic input; a control with no press takes the global lock first and is then clicked the normal way:
/// ArisDesktopSession.wholeMac), and setting an element's
/// value (Accessibility's own set; never in Finder, whose rename is committed with a Return key). Everything else is
/// global: keys, typing and batches (they may type), scrolls and drags (Peekaboo delivers them as events), menus, dialogs
/// and file panels (they may bring the app forward), window and app actions, click-at and text marks (they may click
/// for real). And a step whose card's yes hands the app the front (any card in a conversation, outside a sending app)
/// is global for that call too: the engine decides that after the gate (`call(_:target:card:)`). Pure.
enum ArisDesktopLockScope {
    static let finder = "com.apple.finder"

    static func of(_ request: ArisDesktopRequest, app: ArisDesktopTarget?) -> ArisDesktopLock.Scope {
        call(request, target: app, raisesOnYes: false)
    }

    /// `raisesOnYes`: the call shows a card whose yes brings the target app forward.
    static func call(_ request: ArisDesktopRequest, target app: ArisDesktopTarget?, raisesOnYes: Bool) -> ArisDesktopLock.Scope {
        if raisesOnYes { return .global }
        guard let app else { return .global }
        let perApp = ArisDesktopLock.Scope.app(app.readKey)
        switch request.verb {
        case .click:
            guard let ref = request.ref, !ref.mark, !request.double, !request.right else { return .global }
            return perApp
        case .setValue:
            guard let ref = request.ref, !ref.mark, app.bundle != finder else { return .global }
            return perApp
        default:
            return .global
        }
    }
}

extension ArisDesktopLock {
    /// One piece of work outside the engine that types, pastes, moves windows or replays a learned shortcut: it takes
    /// its turn at the keys and pointer as an action does (the same line, the same limit), runs, and gives it back.
    /// `.failure`: it was refused (nothing ran).
    func holding<T>(_ id: String, live: @escaping () -> Bool = { true }, waiting: () -> Void = {}, _ work: () -> T) -> Result<T, Refusal> {
        if case .refused(let why) = acquire(Owner(id: id, live: live), waiting: waiting) { return .failure(why) }
        defer { release(id) }
        return .success(work())
    }

    /// The same for work that ends later (a paste on the main thread): its turn taken now, nil when it may go; the
    /// caller releases `id` when the work is done.
    func take(_ id: String, live: @escaping () -> Bool = { true }, waiting: () -> Void = {}) -> Refusal? {
        if case .refused(let why) = acquire(Owner(id: id, live: live), waiting: waiting) { return why }
        return nil
    }

    /// A fresh owner id for one such piece of work.
    static func oneOff(_ kind: String) -> String { "\(kind):\(UUID().uuidString)" }

    /// The environment key the agent's own work passes its owner id to `aris-tools window` in, so the command knows
    /// the keys and pointer are held for it (ArisDesktopHoldPlan.heldKey in aris-tools: the same name).
    static let heldKey = "ARIS_DESKTOP_HELD"

    /// POST /desktop-hold {"held"}: `id` is the agent's own one-off work (a learned shortcut's replay, a window
    /// arrangement) and holds the whole Mac right now. A brain can't name such an id: it is made fresh for each piece of
    /// work and passed only to the commands that work runs.
    func holdsForOwnWork(_ id: String) -> Bool {
        guard id.hasPrefix("shortcut:") || id.hasPrefix("arrange:"), UUID(uuidString: String(id.drop { $0 != ":" }.dropFirst())) != nil else { return false }
        // Only a global hold answers for the global level (an app holder is never named for it).
        return holder(of: .global) == id
    }
}

extension ArisDesktopLock.Refusal: Error {}

/// What the lock's waits and refusals say: the notch's line (the user's language), and the brain's line.
enum ArisDesktopLockWords {
    /// What the user hears or reads when their own request couldn't take its turn (a learned shortcut, a paste).
    static func userLine(english: Bool) -> String {
        english ? "Another Aris task is using the keys and pointer right now, so I didn't do it. Ask again in a moment."
            : "다른 Aris 작업이 키보드와 마우스를 쓰고 있어서 하지 못했어요. 잠시 후 다시 말해 주세요."
    }

    /// The error /insert and /paste give back when the lock refused them (nothing was typed).
    static let insertRefusal = "another Aris task is using the keys and pointer, so nothing was typed"

    static func waitingLine(english: Bool) -> String { english ? "Waiting for its turn" : "차례를 기다리는 중" }

    static func refusal(_ why: ArisDesktopLock.Refusal, waited: TimeInterval) -> String {
        switch why {
        case .timedOut:
            return "Another Aris conversation or job is using this Mac's keys and pointer and didn't finish within \(Int(waited)) seconds, so nothing was done. " +
                "Tell the user it was another task's turn; they can ask again in a moment."
        case .paused:
            return "This Mac's keys and pointer are held while the user answers a sign-in or permission window for another step, so nothing was done " +
                "(actions never wait behind such a window). Tell the user; they can ask again once it's answered."
        case .ended:
            return "This turn ended while it waited for its turn at the keys and pointer, so nothing was done."
        }
    }
}
