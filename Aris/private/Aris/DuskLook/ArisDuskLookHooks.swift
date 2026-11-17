//
//  ArisDuskLookHooks.swift
//  Aris
//
//  The top band's mark in the dusk look. Everything else the look changes is a one-line switch at the place it
//  changes, reading ArisDuskLookNow.
//

import SwiftUI

/// The top band's mark in the dusk look: the system assistant's ring of dots in place of the working mark, in the band's own seat
/// and box (the glyph under it keeps its place and is only hidden, so the voice switch, the lock and the halo beside
/// and behind it are untouched). Listening and speaking stay Aris's own bars and star: the owner's captures of the system assistant
/// are typed, so there is nothing measured to draw them from. With the look off this changes nothing.
struct ArisDuskLookWorkingMark: ViewModifier {
    let phase: ArisSession.Phase
    @ObservedObject private var duskLook = ArisDuskLookGate.shared

    func body(content: Content) -> some View {
        let dots = ArisDuskLookNow.on && phase.glyphMode == .loading
        content
            .opacity(dots ? 0 : 1)
            .overlay { if dots { ArisDuskLookDots(size: 15).transition(.opacity) } }
    }
}
