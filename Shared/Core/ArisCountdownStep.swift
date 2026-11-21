//
//  ArisCountdownStep.swift
//  Aris (Shared/Core, Foundation only)
//
//  How a dictated message's countdown ends (ArisController+Countdown), as one pure function so every way it ends is
//  tested. Its ring stopped for one of these: the kernel settled the card (↩, 보내기, esc, 취소, Y or N; another card or
//  The user's turn covered it; its turn ended), a clear spoken yes or no, words that were no clear yes or no ("잠깐만"), or
//  the ring ran out. Only then, with the microphone closed, the final words decide: silence and a clear yes send, a clear
//  no stops, anything else pauses with the card kept. A turn that is over sends nothing, whatever was said.
//
//  It is asked twice: before the microphone closes (`final` nil), so a settled card says so at once, and after, with the
//  final words. Nil only when it still needs them.
//

import Foundation

enum ArisCountdownStep: Equatable, Sendable {
    /// The message goes: the card settles into "on its way".
    case send
    /// It does not go: the card settles into "not sent".
    case stop
    /// Words that were no clear yes or no: the ring stops and the card waits for a click, Y or N.
    case pause
    /// Another card or the user's turn took its place before an answer: not sent, and nobody answered.
    case covered
    /// The card's turn ended before an answer: nothing is sent and nothing follows (never a no).
    case turnEnded

    /// The words heard by the time the microphone closed, as ArisConfirmReply reads them.
    struct Words: Equatable, Sendable {
        /// A clear yes (true) or no (false); nil: neither.
        var answer: Bool?
        /// Any word at all was heard (silence and noise are none).
        var said: Bool

        static let silence = Words(answer: nil, said: false)
    }

    /// `outcome`: the kernel's settlement of the card, if any. `said`: a clear spoken answer (a no at once, a yes once it
    /// held still). `paused`: words that were no clear yes or no held still mid-ring. `final`: the words once the
    /// microphone closed (nil: not closed yet). `current`: the card's turn is still the current one and not cancelled.
    static func decide(outcome: ArisCardOutcome?, said: Bool?, paused: Bool, final: Words?, current: Bool) -> ArisCountdownStep? {
        // The kernel's word on the card comes first: it already knows a turn that ended (.cancelled).
        if let outcome { return ArisCountdownStep(outcome) }
        // Nothing goes for a turn that is over, not even on a spoken yes.
        guard current else { return .turnEnded }
        if let said { return said ? .send : .stop }
        if paused { return .pause }
        guard let final else { return nil }
        if let answer = final.answer { return answer ? .send : .stop }
        // Silence until the ring ran out sends, as designed; any other words pause it.
        return final.said ? .pause : .send
    }

    /// The kernel's settlement of the card: an answer sends or stops it, covered is nobody's answer, cancelled its turn's end.
    init(_ outcome: ArisCardOutcome) {
        switch outcome {
        case .answered(let sent): self = sent ? .send : .stop
        case .covered: self = .covered
        case .cancelled: self = .turnEnded
        }
    }

    /// For the card's one line: true sent, false not sent; nil when the card doesn't settle into one (yet).
    var sent: Bool? {
        switch self {
        case .send: true
        case .stop: false
        case .pause, .covered, .turnEnded: nil
        }
    }

    var logLine: String {
        switch self {
        case .send: "let go, to be sent"
        case .stop: "stopped"
        case .pause: "paused: words that are no clear yes or no; the card waits for a click"
        case .covered: "covered before an answer: not sent"
        case .turnEnded: "its turn ended: nothing sent"
        }
    }
}
