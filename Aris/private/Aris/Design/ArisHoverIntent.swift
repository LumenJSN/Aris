//
//  ArisHoverIntent.swift
//  Aris
//
//  Hover intent for the pills that grow under the pointer (the notice pill, the dictation pill): what they draw as
//  grown follows the pointer only after it has rested `delay` on them (brushing past leaves them as they are), and
//  folds only `grace` after it left (a pointer back within it keeps them; an edge that flickers in and out never
//  folds them). Plain values: the owner runs the waits (a Task each) and asks `settled()` when one runs out. Pure, so
//  it's tested.
//

import Foundation

struct ArisHoverIntent<Target: Equatable>: Equatable {
    /// The pointer's rest before the pill grows, and the grace before it folds (seconds).
    let delay: Double
    let grace: Double
    /// What is under the pointer, as last told (nil: nothing).
    private(set) var pointer: Target?
    /// What is drawn grown.
    private(set) var expanded: Target?

    init(delay: Double, grace: Double) {
        self.delay = delay
        self.grace = grace
    }

    /// The pointer came onto `target` (nil: it left): the new intent, and how long to wait before `settled()`; nil when
    /// nothing is to wait for (a wait already running is cancelled: brushed past, or back within the grace).
    func pointing(at target: Target?) -> (intent: ArisHoverIntent, wait: Double?) {
        var next = self
        next.pointer = target
        if target == expanded { return (next, nil) }
        return (next, target == nil ? grace : delay)
    }

    /// The wait ran out: what is grown follows the pointer.
    func settled() -> ArisHoverIntent {
        var next = self
        next.expanded = pointer
        return next
    }

    /// Nothing under the pointer, nothing grown, at once (the pill went away or stepped aside).
    func cleared() -> ArisHoverIntent { ArisHoverIntent(delay: delay, grace: grace) }
}
