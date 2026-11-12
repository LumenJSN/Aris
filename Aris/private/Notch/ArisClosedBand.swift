//
//  ArisClosedBand.swift
//  Aris
//
//  The closed notch under the pointer, as plain rules (the second VM run, on a display with no camera housing, where
//  the pill is one piece: while a timer ran, the whole band was the timer's click target and resting on it never
//  opened Aris).
//  - Where a rest or a click opens Aris: the whole closed surface, less what a band keeps for something else. At rest
//    the star's ears are only its room (ArisStarBand.hitWidth); while a timer runs its left ear, the ring, is the
//    timer's own control (click: pause or resume; right-click: its menu) and everything else opens Aris, as on any band.
//  The surface is the band (ear, camera's width, ear) with a 13-point shoulder each side. CoreGraphics only (tested).
//

import CoreGraphics

enum ArisClosedBand {
    /// The surface's own inset each side of the band's content (the closed corner radius).
    static let shoulder = ArisBand.radius

    /// How far in from the closed surface's left and right edges the notch's own hover and click begin.
    struct Insets: Equatable {
        var leading: CGFloat
        var trailing: CGFloat
    }

    /// What the pointer does at one place across the closed surface.
    enum Spot: Equatable {
        /// A rest here opens Aris after the hover time, and so does a click.
        case opensAris
        /// The timer's ring: a click pauses or resumes, a right-click brings its menu. Nothing opens.
        case timerControl
        /// The resting star's ear: its room only.
        case starRoom
    }

    /// The closed surface's width while a band is drawn: the band and its two shoulders.
    static func surfaceWidth(notchWidth: CGFloat, body: CGFloat? = nil) -> CGFloat {
        (body ?? ArisBand.bodyWidth(notchWidth: notchWidth)) + 2 * shoulder
    }

    /// The timer's control: its ear, from the band's left edge to the camera's (never past it, so on a display with a
    /// camera it is exactly the visible ear).
    static func timerControlWidth(notchWidth: CGFloat, body: CGFloat? = nil) -> CGFloat {
        ArisBand.earWidth(notchWidth: notchWidth, body: body)
    }

    /// The control's centre, from the surface's centre (the band is centred on the camera).
    static func timerControlOffset(notchWidth: CGFloat, body: CGFloat? = nil) -> CGFloat {
        -(notchWidth + timerControlWidth(notchWidth: notchWidth, body: body)) / 2
    }

    /// Nil: the whole surface opens Aris.
    static func hoverInsets(_ closed: ArisNotchDecisions.Closed, notchWidth: CGFloat, body: CGFloat? = nil) -> Insets? {
        let side = shoulder + ArisBand.earWidth(notchWidth: notchWidth, body: body)
        switch closed {
        case .star(let mode):
            // The same strip ArisStarBand.hitWidth gives: the camera's width at rest, everything otherwise.
            return ArisStarBand.hitWidth(mode: mode, notchWidth: notchWidth) == nil ? nil : Insets(leading: side, trailing: side)
        case .timer:
            return Insets(leading: side, trailing: 0)
        case .notice, .dueAlert, .claude, .music, .empty:
            return nil
        }
    }

    /// The part of a surface (any rectangle of its size) the notch's own hover and click cover: all of it without insets.
    static func region(_ surface: CGRect, insets: Insets?) -> CGRect {
        guard let insets else { return surface }
        return CGRect(x: surface.minX + insets.leading, y: surface.minY,
                      width: max(0, surface.width - insets.leading - insets.trailing), height: surface.height)
    }

    /// The same region reaching `pad` further out: where a rest on a closed notch begins (the 2-point hover
    /// target padding, ArisVNotch.hoverTargetPadding).
    static func region(_ surface: CGRect, insets: Insets?, pad: CGFloat) -> CGRect {
        region(surface, insets: insets).insetBy(dx: -pad, dy: -pad)
    }

    /// `x`: from the closed surface's left edge.
    static func spot(x: CGFloat, closed: ArisNotchDecisions.Closed, notchWidth: CGFloat, body: CGFloat? = nil) -> Spot {
        guard let insets = hoverInsets(closed, notchWidth: notchWidth, body: body) else { return .opensAris }
        let width = surfaceWidth(notchWidth: notchWidth, body: body)
        if x >= insets.leading && x <= width - insets.trailing { return .opensAris }
        return closed == .timer ? .timerControl : .starRoom
    }
}
