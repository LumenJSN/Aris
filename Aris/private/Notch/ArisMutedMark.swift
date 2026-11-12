//
//  ArisMutedMark.swift
//  Aris
//
//  Where the closed notch says that Aris is muted, as a plain rule (the views are in ArisMutedMarks.swift): the second
//  VM run, on a display with no camera housing, showed nothing at all while muted, and neither did a parked answer's
//  band on any display. CoreGraphics only (tested).
//

import CoreGraphics

/// Where the closed notch shows that Aris is muted: a still, faint struck speaker (nothing blinks). On a display with
/// a camera the resting star's right ear holds it; an answer waiting keeps its dot and the mark sits beside it; on a
/// display with no camera the resting pill is a bare strip, and the mark sits at its right end.
enum ArisMutedMark {
    enum Place: Equatable {
        /// Alone in the right ear, across the camera from the star.
        case ear
        /// In the right ear, left of what is already there (the waiting answer's dot, the paused-listening mark).
        case besideMark
        /// At the right end of the resting strip of a display with no camera housing.
        case strip
    }

    /// `earTaken`: the right ear already shows something (the dot, the pause mark, the jobs' count or check).
    /// Nil: not muted, or a band whose two ears belong to something else (a timer's ring and clock, Claude, music).
    static func place(closed: ArisNotchDecisions.Closed, muted: Bool, hasNotch: Bool, earTaken: Bool = false) -> Place? {
        guard muted else { return nil }
        switch closed {
        case .star(.home): return .ear
        case .star(.turn), .star(.parked): return earTaken ? .besideMark : .ear
        case .star(.tasks): return earTaken ? nil : .ear
        case .empty: return hasNotch ? nil : .strip
        case .notice, .dueAlert, .timer, .claude, .music: return nil
        }
    }
}
