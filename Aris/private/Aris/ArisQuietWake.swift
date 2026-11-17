//
//  ArisQuietWake.swift
//  Aris
//
//  How the notch answers the wake word (the owner's pick "C · 한 바퀴", 2026-11-14, mockup quietwake-mock): it does not
//  open. The closed band keeps its size, the star gives its seat to the voice bars, and the listening rim's light runs
//  exactly one lap round the band (ArisRimSweep.period). That lap is the quiet window:
//  - the user's voice starts during it (the microphone's level over the turn's gate, ArisTalkKey.isVoice, after the call
//    itself has ended; not the first recognised word, which comes about a second behind): the notch opens as it does
//    for a turn, and the light carries on into the open notch's rim.
//  - The lap ends with no voice: the light ends, the bars give the seat back to the star, and the turn ends without a
//    word (ArisController+FalseWake's quiet close).
//  - A borderline wake is held (ArisWakeEvidence): the user's voice or words during the lap don't open the notch until
//    the wake's evidence is in (release), since a song's vocals or the TV are voice too. A lap that ends with nothing
//    said still ends the turn; one that heard something waits for the release.
//  A key press or a tap never goes through this. Pure (times in seconds on one clock), so the tests drive it.
//

import Foundation

struct ArisQuietWake: Equatable {
    enum State: Equatable {
        /// The lap runs: the closed band, the bars and the light's one lap; nothing opens.
        case waiting
        /// The user started talking during the lap: the notch opens and the light carries on.
        case heard
        /// The lap ended with no voice: the turn ends quietly.
        case unheard
    }

    /// The quiet window: one lap of the listening rim's light.
    static let lap: Double = ArisRimSweep.period
    /// The call ("아리스") is over once the level has stayed under the gate this long: the wake fires while the voice
    /// print matches, often before the name has ended, so its tail is never the user starting to talk.
    static let callGap: Double = 0.15
    /// …or once this long has passed since the wake, so a call run straight into the request ("아리스내일…") with no
    /// gap still opens.
    static let callLongest: Double = 1.0
    /// A voiced run this long after the call is the user talking (two readings at ~43 ms each): a click or a key clack is
    /// one reading and isn't.
    static let onsetRun: Double = 0.06

    let wokeAt: Double
    private(set) var state: State
    /// When the call was taken as over (nil while it may still be going).
    private(set) var callOverAt: Double?
    private var quietSince: Double?
    private var voiceSince: Double?
    /// A borderline wake's evidence isn't in yet: what would open the notch is only noted (`spoke`).
    private(set) var held: Bool
    /// Something was heard while held.
    private(set) var spoke = false
    /// The lap ended while held, with something heard: it waits for the release.
    private var lapOver = false

    /// `saidMore`: the check that woke Aris already heard words after the name ("아리스 타이머 3분"): heard at once
    /// (noted only, while `held`).
    init(wokeAt: Double, saidMore: Bool = false, held: Bool = false) {
        self.wokeAt = wokeAt
        self.held = held
        spoke = saidMore
        state = saidMore && !held ? .heard : .waiting
    }

    /// One reading of the turn's microphone at `t`; `voice`: over the turn's gate.
    @discardableResult
    mutating func level(voice: Bool, at t: Double) -> State {
        guard state == .waiting else { return state }
        if lapIsOver(at: t) { return endLap() }
        if callOverAt == nil {
            quietSince = voice ? nil : (quietSince ?? t)
            if let quietSince, t - quietSince >= Self.callGap {
                callOverAt = t
            } else if t - wokeAt >= Self.callLongest {
                callOverAt = t
            } else {
                return state
            }
        }
        guard voice else {
            voiceSince = nil
            return state
        }
        let since = voiceSince ?? t
        voiceSince = since
        return t - since >= Self.onsetRun ? hear() : state
    }

    /// The recognizer wrote words beyond the call at `t`: the user is talking, whatever the level said.
    @discardableResult
    mutating func words(at t: Double) -> State {
        guard state == .waiting else { return state }
        if lapIsOver(at: t), !lapOver { return endLap() }
        return hear()
    }

    /// The borderline wake's evidence says it was the user (ArisWakeEvidence .keep): what was heard opens the notch now;
    /// nothing heard yet and the lap goes on as any other; nothing heard and the lap over ends it.
    @discardableResult
    mutating func release() -> State {
        guard state == .waiting, held else { return state }
        held = false
        if spoke {
            state = .heard
        } else if lapOver {
            state = .unheard
        }
        return state
    }

    /// The clock at `t` (the lap's own timer): past the lap, it ends.
    @discardableResult
    mutating func tick(at t: Double) -> State {
        guard state == .waiting, lapIsOver(at: t) else { return state }
        return endLap()
    }

    /// A hair of slack: a timer that fires on the lap's end, read on another clock, is the end.
    private func lapIsOver(at t: Double) -> Bool { t - wokeAt >= Self.lap - 1e-6 }

    private mutating func hear() -> State {
        if held {
            spoke = true
        } else {
            state = .heard
        }
        return state
    }

    /// The lap's end: a voiced run still going (the user began at the very end) is heard; otherwise nothing was said.
    /// Held, something heard waits for the release.
    private mutating func endLap() -> State {
        let going = callOverAt != nil && voiceSince != nil
        guard held else {
            state = going ? .heard : .unheard
            return state
        }
        lapOver = true
        if going { spoke = true }
        state = spoke ? .waiting : .unheard
        return state
    }
}
