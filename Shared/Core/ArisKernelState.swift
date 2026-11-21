//
//  ArisKernelState.swift
//  Aris
//
//  The kernel's state and its pure reducer (ARCHITECTURE.md 3.1): which turn is current, and which card waits for
//  its answer. `reduce` is synchronous and has no side effects; the effects it returns are run by ArisKernel.
//

import Foundation

struct ArisKernelState: Equatable, Sendable {
    /// The last turn opened (zero before the first).
    var latest = ArisTurnID.zero
    /// The turn whose writes count; nil once it ended and before the next one opens.
    var current: ArisTurnID?
    /// The card on screen that waits for its answer.
    var card: ArisCardKey?
    /// The next card showing's serial.
    var nextCard: UInt64 = 1

    /// Whether code working for `turn` may change turn state now. Work for no turn (nil) always may: it is a key
    /// press, a click or a watcher acting on what is there now, never a turn finishing late.
    func admits(_ turn: ArisTurnID?) -> Bool {
        guard let turn else { return true }
        return turn == current
    }

    static func reduce(_ state: ArisKernelState, _ event: ArisEvent) -> (ArisKernelState, [ArisEffect]) {
        var next = state
        var effects: [ArisEffect] = []
        switch event {
        case .turnOpened:
            if state.latest != .zero { effects.append(.cancelWork(state.current ?? state.latest)) }
            next.latest = state.latest.next()
            next.current = next.latest
            if let card = state.card {
                next.card = nil
                effects.append(.resumeCard(card, .cancelled))
            }
        case .turnEnded(let turn, _):
            // A stale end (a turn already over) changes nothing.
            guard state.current == turn else { break }
            next.current = nil
            effects.append(.cancelWork(turn))
            if let card = state.card {
                next.card = nil
                effects.append(.resumeCard(card, .cancelled))
            }
        case .sessionWrite(let from):
            effects.append(state.admits(from) ? .write : .dropWrite(stale: from ?? .zero))
        case .cardShown(let card, let turn):
            let key = ArisCardKey(card: card, turn: turn ?? state.current, serial: state.nextCard)
            next.nextCard = state.nextCard &+ 1
            // A card from a turn that is over never waits: its waiter is told at once.
            guard state.admits(turn) else {
                effects.append(.resumeCard(key, .cancelled))
                break
            }
            if let covered = state.card { effects.append(.resumeCard(covered, .covered)) }
            next.card = key
        case .cardAnswered(let card, let allow):
            guard let open = state.card, open.card == card else { break }
            next.card = nil
            effects.append(.resumeCard(open, .answered(allow)))
        case .cardClosed(let key):
            if state.card == key { next.card = nil }
        case .cardAbandoned(let key):
            guard state.card == key else { break }
            next.card = nil
            effects.append(.resumeCard(key, .cancelled))
        case .turnStage, .world:
            break
        }
        return (next, effects)
    }
}
