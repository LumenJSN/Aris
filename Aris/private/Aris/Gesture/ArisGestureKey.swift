//
//  ArisGestureKey.swift
//  Aris
//
//  The circle gesture's own key (the owner, 2026-11-04): hold ⌥⇧ (either ⌥) and nothing else. After a short debounce the
//  turn starts as a talk turn does, with the ink armed and the screen captured; letting go of either key ends it by
//  the talk key's release rules. Any other key or modifier while it's held (⌥⇧K, ⌘⌥⇧…) is a shortcut, never hijacked:
//  inside the debounce nothing starts, after it the turn is cancelled, and nothing starts again until both keys are up.
//  While a turn is answering, the debounce is longer (QA BUG-3): ⌥⇧ typed as part of a character or a shortcut there
//  would throw the answer away, so the press must stay alone longer, and a key inside it leaves the answer as it was.
//  ⌥ Space stays voice only and never arms the ink. Pure, so the tests run it; ArisGestureKeyTap feeds it.
//

import Foundation

enum ArisGestureKey {
    /// How long ⌥⇧ must stay alone before it counts.
    static let debounceMs: Double = 120
    /// The same while a turn is answering: long enough to see the key typed with ⌥⇧ before anything starts.
    static let busyDebounceMs: Double = 500

    /// Whether a press waits the longer debounce: while a turn is answering (thinking or speaking), where a start would
    /// throw that answer away.
    static func waitsLonger(_ phase: ArisSession.Phase) -> Bool { phase == .thinking || phase == .speaking }

    static func debounce(busy: Bool) -> Double { busy ? busyDebounceMs : debounceMs }
    /// How Settings shows it (fixed: it isn't rebindable).
    static let displayName = "⌥⇧"

    enum Event: Equatable {
        /// The modifiers changed: ⌥ (left or right) and ⇧ down, and whether ⌘, ⌃ or fn are down too.
        case modifiers(option: Bool, shift: Bool, other: Bool, at: Double)
        /// Any key that isn't a modifier.
        case otherKey(at: Double)
        /// The debounce timer fired.
        case tick(at: Double)
    }

    enum Action: Equatable {
        case start
        case finish(heldForMs: Double)
        case cancel
        /// Busy, ⌥⇧ let go alone past the usual debounce but inside the longer one: a tap, so the turn starts and
        /// finishes at once with this length (the talk key's tap rule decides).
        case tap(heldForMs: Double)
        case none
    }

    /// Whether a turn's press arms the ink: only this key's, never the talk key's.
    static func armsInk(gestureKey: Bool) -> Bool { gestureKey }

    /// Whether other keys must be watched: only while ⌥ and ⇧ are both down (another key then cancels the press). The
    /// rest of the time the tap hears modifier changes only, never what is typed.
    static func watchesKeys(option: Bool, shift: Bool) -> Bool { option && shift }

    /// Whether the keyboard is watched at all: only with 동그라미로 가리키기 on (off, ⌥⇧ does nothing).
    static func listens(circleGesture: Bool) -> Bool { circleGesture }

    /// How long to wait before looking for the Accessibility permission again: 30 s, doubling, at most 5 minutes.
    static func retryDelay(attempt: Int) -> Duration {
        .seconds(min(300, 30 << min(max(0, attempt), 4)))
    }

    struct State {
        private enum Phase: Equatable {
            case idle
            /// `wait`: the debounce this press waits out (longer while a turn answers).
            case pending(since: Double, wait: Double)
            case active(since: Double)
            /// A shortcut used ⌥⇧, or the press ended: wait until both are up.
            case spoiled
        }

        private var phase = Phase.idle

        /// ⌥⇧ is down alone, waiting out the debounce or already a turn: the pointer is sampled from here on
        /// (ArisPointerSampler), so the stroke's start isn't lost to the debounce.
        var pressing: Bool {
            switch phase {
            case .pending, .active: return true
            case .idle, .spoiled: return false
            }
        }

        /// When the pending press becomes a turn (for the timer); nil when nothing waits.
        var dueAt: Double? {
            if case .pending(let since, let wait) = phase { return since + wait }
            return nil
        }

        /// `busy`: a turn is answering (ArisGestureKey.waitsLonger), read when a press begins.
        mutating func handle(_ event: Event, busy: Bool = false) -> Action {
            switch (phase, event) {
            case let (.idle, .modifiers(option, shift, other, at)):
                if option && shift && !other { phase = .pending(since: at, wait: ArisGestureKey.debounce(busy: busy)) }
                return .none
            case (.idle, _):
                return .none

            case let (.pending(since, wait), .modifiers(option, shift, other, at)):
                if option && shift && !other { return .none }
                phase = option || shift ? .spoiled : .idle
                // Let go alone (no other key or modifier joined) past the usual debounce while waiting the longer one.
                let alone = !other && !(option && shift)
                return alone && wait > ArisGestureKey.debounceMs && at >= since + ArisGestureKey.debounceMs ? .tap(heldForMs: at - since) : .none
            case (.pending, .otherKey):
                phase = .spoiled
                return .none
            case let (.pending(since, wait), .tick(at)):
                guard at >= since + wait else { return .none }
                phase = .active(since: since)
                return .start

            case let (.active(since), .modifiers(option, shift, other, at)):
                if option && shift {
                    guard other else { return .none }
                    phase = .spoiled
                    return .cancel
                }
                phase = option || shift ? .spoiled : .idle
                return .finish(heldForMs: at - since)
            case (.active, .otherKey):
                phase = .spoiled
                return .cancel
            case (.active, .tick):
                return .none

            case let (.spoiled, .modifiers(option, shift, _, _)):
                if !option && !shift { phase = .idle }
                return .none
            case (.spoiled, _):
                return .none
            }
        }
    }

    /// The backstop for a release the tap never heard (audit gesture-1: the system turned the tap off, or secure input
    /// came on mid-hold). While a press is on, ArisGestureKeyTap looks at the real keys on a timer and hands each look
    /// here. Keys seen up twice, `confirmMs` apart, become the release event that was lost, timed when they were first
    /// seen up, so the turn ends as it would have: the ink overlay closes and the microphone with it. One look is not
    /// enough: the real release may only be late, and it must win so a tap is still timed as a tap.
    struct ReleaseWatch {
        /// How often the real keys are looked at while a press is on.
        static let intervalMs = 50
        /// How long the keys must stay up before the release is made up.
        static let confirmMs: Double = 60

        private var upSince: Double?

        /// One look at the real keys. `pressing`: the state machine has a press on (State.pressing). The event to feed
        /// it, or nil.
        mutating func look(pressing: Bool, option: Bool, shift: Bool, other: Bool, at: Double) -> Event? {
            guard pressing, !(option && shift) else {
                upSince = nil
                return nil
            }
            guard let since = upSince else {
                upSince = at
                return nil
            }
            guard at - since >= Self.confirmMs else { return nil }
            upSince = nil
            return .modifiers(option: option, shift: shift, other: other, at: since)
        }

        /// The tap was off and is on again: events were lost for sure, so one look decides. Only ever a release: keys
        /// that went down meanwhile start nothing.
        static func afterTapCameBack(pressing: Bool, option: Bool, shift: Bool, other: Bool, at: Double) -> Event? {
            pressing && !(option && shift) ? .modifiers(option: option, shift: shift, other: other, at: at) : nil
        }
    }
}
