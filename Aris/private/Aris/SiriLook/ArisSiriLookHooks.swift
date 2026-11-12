//
//  ArisSiriLookHooks.swift
//  Aris
//
//  The top band's mark in the siri look. Everything else the look changes is a one-line switch at the place it
//  changes, reading ArisSiriLookNow.
//

import SwiftUI

/// The top band's mark in the siri look: Siri's ring of dots in place of the working mark, in the band's own seat
/// and box (the glyph under it keeps its place and is only hidden, so the voice switch, the lock and the halo beside
/// and behind it are untouched). Listening and speaking stay Aris's own bars and star: the owner's captures of Siri
/// are typed, so there is nothing measured to draw them from. With the look off this changes nothing.
struct ArisSiriLookWorkingMark: ViewModifier {
    let phase: ArisSession.Phase
    @ObservedObject private var siriLook = ArisSiriLookGate.shared

    func body(content: Content) -> some View {
        let dots = ArisSiriLookNow.on && phase.glyphMode == .loading
        content
            .opacity(dots ? 0 : 1)
            .overlay { if dots { ArisSiriLookDots(size: 15).transition(.opacity) } }
    }
}
