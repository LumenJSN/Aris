//
//  ArisNotch.swift
//  Aris
//
//  A turn with Aris opens the notch onto Aris. Once the turn is over (and the
//  answer has had a moment to be read), each display puts its notch back.
//
//  The open tab is shared by every display, so this never reads it: each display
//  only trusts what it knows itself (whether Aris opened it, whether it's open).
//

import Foundation

enum ArisNotch {
    /// How long an answer stays on screen after Aris stops talking: a moment, plus time to read it.
    static func readingTime(for answer: String) -> Duration {
        min(.milliseconds(2500 + 40 * answer.count), .seconds(10))
    }

    /// While the pointer is on the notch the answer stays up, but no longer than this (a stray hover
    /// event must not keep the notch open for good).
    static let longestHover: Duration = .seconds(30)

    enum Ending: Equatable {
        /// Aris opened this notch: close it.
        case close
        /// The notch was already open: go back to the tab that was showing.
        case restoreTab
        /// It's already closed.
        case stay

        /// The ending once nothing holds the notch any more (the turn is over, no card waits, the answer had its
        /// reading time): an open notch the pointer is not on closes, whoever opened it and whatever the pointer did
        /// before. A card's yes shrank the notch away from the pointer while the turn still held it; the pointer's
        /// leaving closed nothing then, and nothing closed it later (fourth VM run, bug 1: the answer stayed up for
        /// minutes). A notch the pointer is on stays, as before.
        func whenFree(pointerAway: Bool) -> Ending { self == .restoreTab && pointerAway ? .close : self }
    }

    /// A notch Aris opened always closes, even under the pointer: left open, it would
    /// show whatever tab another display's closing switched the shared tab to.
    /// After a hand-off (a job took the work: "작업할게요", "맡았어요") the notch closes whoever opened it: the jobs' pill
    /// under the closed notch tells how the work goes (the owner, 2026-11-16).
    static func ending(openedNotch: Bool, isOpen: Bool, handedOff: Bool = false) -> Ending {
        guard isOpen else { return .stay }
        return openedNotch || handedOff ? .close : .restoreTab
    }

    /// How long the turn's end leaves the answer up before the notch may go: its reading time, except after a hand-off
    /// (the line was said, the pill takes over) and a dictation.
    /// `undo`: the turn's answer says what an undo did or why it didn't: a short line that is the only word of it, so it
    /// stays at least `undoStay` (ninth VM run, item 7: with the pointer elsewhere it was gone before it was read).
    static func endWait(handedOff: Bool, dictation: Bool, reply: String, undo: Bool = false) -> Duration {
        if handedOff || dictation { return .zero }
        return undo ? max(readingTime(for: reply), undoStay) : readingTime(for: reply)
    }

    /// The least an undo's answer stays up after Aris stops talking.
    static let undoStay: Duration = .seconds(6)

    /// The pointer on the notch keeps the answer up a while (longestHover), but not after a hand-off.
    static func waitsForHover(handedOff: Bool) -> Bool { !handedOff }

    /// How long a turn stays in its answer after Aris stopped talking: none after a hand-off, so the notch goes as the
    /// line ends.
    static func linger(handedOff: Bool) -> Duration { handedOff ? .zero : lingerAfterAnswer }
    static let lingerAfterAnswer: Duration = .seconds(1.5)

    /// Whether the end of a turn finds the pointer off a notch nothing holds any more. `free`: no turn, card, popover,
    /// share or drop holds it and no hover is known; `measured`: the notch's place on screen is known; `onNotch`: the
    /// pointer is found on it. Unmeasured, the hover's own word (in `free`) stands.
    static func pointerAway(free: Bool, measured: Bool, onNotch: Bool) -> Bool { free && !(measured && onNotch) }
}
