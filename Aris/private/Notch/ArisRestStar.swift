//
//  ArisRestStar.swift
//  Aris
//
//  쉬는 동안 별 보이기 (Settings › 노치, on by default): the closed notch at rest shows Aris's star asleep in the band
//  beside the camera housing (the band the resting star always had: the housing's width and an ear each side, the
//  compact band ArisVNotch sizes). The moment Aris listens, works or has something to show, the band is the turn's,
//  the jobs' or the parked answer's and the star is awake there; once all of that is over it is back at rest, asleep.
//  Off, the closed notch rests empty, only the camera housing showing, and the star comes out only with
//  the band. The hidden `arisClosedRest` = `star` still keeps it resting either way. Foundation only (tested).
//

import Foundation

enum ArisRestStar {
    /// The stored switch (Defaults key `arisRestStar`).
    static let preferenceKey = "arisRestStar"
    /// On until it is turned off.
    static let standard = true

    /// The star sleeps in the band at rest, unless what keeps it there is something to tell (files given for the next
    /// request, a speech model's note): then it stays awake beside it.
    static func sleeps(mode: ArisStarBand.Mode?, filesWaiting: Bool, modelNote: Bool) -> Bool {
        mode == .home && !filesWaiting && !modelNote
    }

    /// The star's mood (ArisCharacterMood: "default", "working" or "sleeping") while it rests asleep: asleep whatever
    /// the clock says, unless a job is running.
    static func mood(_ mood: String, asleep: Bool) -> String {
        asleep && mood != "working" ? "sleeping" : mood
    }
}

extension ArisVNotchRest {
    /// How a closed Aris rests: the star in the band while the switch is on or the hidden preference asks for it,
    /// else the empty rest.
    init(stored: String?, starShown: Bool) {
        self = starShown ? .star : ArisVNotchRest(stored: stored)
    }
}
