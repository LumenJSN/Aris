//
//  ArisNotchPointer.swift
//  Aris
//
//  Where the pointer really is, against what the notch was told. The notch opens and closes on hover events, and
//  those are missed when the view under a still pointer changes, or when the pointer leaves in one jump from a
//  control that had just changed under it (the second VM run: after a click on the mute switch the notch stayed open
//  for 45 seconds with the pointer far away, until the pointer came back in and went out again). So while the notch
//  believes the pointer is on it, that is checked against the pointer's place on the screen a few times a second, and
//  a pointer that has plainly left is treated as having left: the notch closes as it would have, and every hover-shown
//  control under it lets go too (ArisNotchHovered). The side notches have always worked from the pointer's place
//  (ArisSidePanels); this gives the top notch the same footing without changing what opens it.
//  CoreGraphics only (tested).
//

import CoreGraphics
import Foundation

enum ArisNotchPointer {
    /// How often the pointer's place is read while the notch believes it is hovered.
    static let checkEvery: TimeInterval = 0.4
    /// Checks in a row that must find the pointer gone (one could catch it mid-way across an edge).
    static let missesToLeave = 2
    /// Around the surface that still counts as on it: a pointer resting on the rim never closes the notch.
    static let slack: CGFloat = 8

    /// The notch's surface on the screen. `surface`: its frame in its window, measured from the window's top-left
    /// corner (SwiftUI's global space). `window`: the window's frame on the screen, measured from the bottom-left.
    static func onScreen(surface: CGRect, window: CGRect) -> CGRect {
        CGRect(x: window.minX + surface.minX, y: window.maxY - surface.maxY, width: surface.width, height: surface.height)
    }

    /// Whether the pointer (screen coordinates) is on the notch. Nothing measured yet counts as on it: the notch is
    /// never closed on a guess.
    static func isOn(pointer: CGPoint, surface: CGRect, window: CGRect?, insets: ArisClosedBand.Insets? = nil, slack: CGFloat = ArisNotchPointer.slack) -> Bool {
        guard let window, surface.width > 0, surface.height > 0 else { return true }
        return onScreen(surface: ArisClosedBand.region(surface, insets: insets), window: window).insetBy(dx: -slack, dy: -slack).contains(pointer)
    }

    /// Whether the measured place may overrule the hover events at all: only when, at the moment a hover began (the
    /// pointer is then on the notch for certain), the measurement agreed. A measurement that is off (a window or a
    /// screen it does not know) is never acted on: the notch then behaves exactly as before.
    static func trusted(measured: Bool, onNotchAtEnter: Bool) -> Bool { measured && onNotchAtEnter }

    /// A hover exit is not believed while the pointer is exactly on the notch (no slack: a pointer that stopped just
    /// off the pill has left it).
    static func ignoresExit(inside: Bool, hovering: Bool, trusted: Bool, onNotch: Bool) -> Bool {
        !inside && hovering && trusted && onNotch
    }

    /// The count of checks in a row that found the pointer gone. A held mouse button (a drag that began on the notch:
    /// selecting text, moving a shelf file) never counts, and neither does a pointer found on the notch.
    static func misses(_ before: Int, onNotch: Bool, buttonDown: Bool) -> Int {
        onNotch || buttonDown ? 0 : before + 1
    }

    /// The pointer has left without the notch being told.
    static func hasLeft(misses: Int) -> Bool { misses >= missesToLeave }

    // MARK: - An open notch that was never told of a hover (third VM run, new install)
    //
    // The watch above runs only once a hover began. A notch that opened under a pointer that did not move, or onto
    // which the pointer came in one jump, is never told of a hover at all, so it was never told the pointer left
    // either: it stayed open for a minute after a typed turn. While the notch is open and no hover is known, the
    // pointer's place is read the same way: once it has been found on the notch, finding it gone twice in a row counts
    // as having left. A pointer that was never on the notch closes nothing (a notch opened from the keyboard or by
    // Aris itself stays as it was).

    /// What the open notch's own watch knows: whether the pointer was found on the notch, and the misses since.
    struct OpenWatch: Equatable {
        var seenOn = false
        var misses = 0
    }

    /// One look while the notch is open and no hover is known. `left`: the pointer was on the notch and has gone.
    static func openStep(_ watch: OpenWatch, onNotch: Bool, buttonDown: Bool) -> (next: OpenWatch, left: Bool) {
        if onNotch { return (OpenWatch(seenOn: true, misses: 0), false) }
        guard watch.seenOn else { return (watch, false) }
        let count = misses(watch.misses, onNotch: false, buttonDown: buttonDown)
        return (OpenWatch(seenOn: true, misses: count), hasLeft(misses: count))
    }

    /// A hover that began while the measurement disagreed (the surface was still moving) earns its trust later: once
    /// the hover events and the measured place agree that the pointer is on the notch.
    static func trustGained(trusted: Bool, hovering: Bool, measured: Bool, onNotch: Bool) -> Bool {
        trusted || (hovering && measured && onNotch)
    }
}
