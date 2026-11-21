//
//  ArisCardHearing.swift
//  Aris
//
//  Whether the card on screen hears a spoken answer, said on the card itself. A card that waits for a click only (Aris
//  muted, quiet time, a card the user opened from 확인 대기, the speech model not ready, or the listening window over) used
//  to look exactly like one that listens, so he said "응" to a card with no microphone. Pure (tested); the card's
//  footer draws it (ArisCardHearingNote).
//

import Foundation

enum ArisCardHearing: Equatable {
    /// The microphone is open for a yes or no.
    case listening
    /// No microphone: a click, Y or N answers.
    case clickOnly
    /// The words heard are being read by the fast model (ArisCardIntent): a moment, and the microphone stays open.
    case thinking
    /// A change was asked for that the card could not make: it says so and goes on listening.
    case missedChange

    /// The microphone is open (the note's microphone is lit).
    var hears: Bool { self != .clickOnly }

    /// `keys`: a Y or N pressed right now would be taken by Aris and answer this card (ArisCardKeyReach). The card names
    /// the keys only then (tenth VM run, item 5: it said "press Y / N" while an N went into the document in front).
    static func words(_ hearing: ArisCardHearing, english: Bool, keys: Bool = false) -> String {
        switch hearing {
        case .listening: return english ? "Listening · say yes or no" : "듣는 중 · “응” 또는 “아니”"
        case .clickOnly where keys: return english ? "Not listening. Click or press Y / N." : "지금은 듣지 않아요. 누르거나 Y / N 키로 답해 주세요."
        case .clickOnly: return english ? "Not listening. Click to answer." : "지금은 듣지 않아요. 눌러서 답해 주세요."
        case .thinking: return english ? "One moment…" : "잠시만요…"
        case .missedChange: return english ? "Didn't catch the change. Say it again or edit it." : "바꿀 내용을 못 알아들었어요. 다시 말하거나 직접 고쳐 주세요."
        }
    }
}

/// Which card says what about hearing: one card at a time, and only its own.
struct ArisCardEarState: Equatable {
    private(set) var card: String?
    private(set) var hearing: ArisCardHearing?

    func hearing(card id: String) -> ArisCardHearing? { card == id ? hearing : nil }

    func setting(_ hearing: ArisCardHearing, card id: String) -> ArisCardEarState { ArisCardEarState(card: id, hearing: hearing) }

    /// The card closed: its sign goes; another card's stays.
    func clearing(card id: String) -> ArisCardEarState { card == id ? ArisCardEarState() : self }
}

/// Whether a Y or N pressed now reaches the waiting card: the key tap is on and still takes them (ArisCardKeys.window
/// from when the card came), or the card's panel has the keyboard (the pointer is on it, or the answer hotkey was
/// pressed). Anything else and the keys go to the app in front, so the card must not name them.
struct ArisCardKeyReachState: Equatable {
    /// The session tap is on for a card shown at this time (seconds, the tap's clock).
    var tapSince: Double?
    /// The notch's own key monitor is on (Aris has the keyboard).
    var panelArmed = false

    func reaches(at now: Double) -> Bool {
        panelArmed || (tapSince.map { now - $0 < ArisCardKeys.window } ?? false)
    }

    /// When the tap stops taking Y and N, if it is what makes them reach now.
    func tapEnds() -> Double? { panelArmed ? nil : tapSince.map { $0 + ArisCardKeys.window } }
}
