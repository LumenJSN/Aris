//
//  ArisParkedNotice.swift
//  Aris
//
//  A notice that also parks its line as the notch's answer (a timer that ran out: ArisController.notify's `parking`)
//  goes with its notice (thirteenth VM run, T1: rel12 let the timer's pill go a minute after it was seen, but the parked
//  "Timer · 1 minute is up." stayed as the notch's answer and its blue dot, and was still there two minutes after it was
//  seen, and again when the notch was opened later). Once the notice is gone (its own clock ran out a minute after it
//  was seen, or it was closed) and the notch isn't open on it, the parked line goes too, unless something else took the
//  notch meanwhile (a turn, another answer): then it is no longer the notice's to take away. Pure.
//

import Foundation

enum ArisParkedNotice {
    enum Step: Equatable {
        /// Still up somewhere (the notice, or the open notch showing it): look again later.
        case wait
        /// The notice is gone and its line is still what the notch holds, unseen now: put it away.
        case clear
        /// The notch holds something else now: nothing to do, ever.
        case stop
    }

    /// `session`: what the notch holds now; `heard`/`reply`: what the notice parked. `noticeUp`: the notice is still shown
    /// or waiting. `notchOpen`: the notch is open (the parked line may be what is being read).
    static func step(session: ArisSession, heard: String, reply: String, noticeUp: Bool, notchOpen: Bool) -> Step {
        guard session.phase == .idle, session.question == nil, session.heard == heard, session.reply == reply else { return .stop }
        return noticeUp || notchOpen ? .wait : .clear
    }

    /// How often it is looked at.
    static let recheck: TimeInterval = 2
}
