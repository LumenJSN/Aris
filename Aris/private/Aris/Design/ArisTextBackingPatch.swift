//
//  ArisTextBackingPatch.swift
//  Aris
//
//  글자 뒤 받침 on screen (ArisTextBacking): `.arisTextBacking()` on a run of small text in the open notch puts the
//  soft dark patch behind it while the setting is on and the notch has glass, and nothing at all otherwise.
//

import Defaults
import SwiftUI

extension Defaults.Keys {
    /// 글자 뒤 받침 (Settings › 노치): off on a fresh install.
    static let arisTextBacking = Key<Bool>(ArisTextBacking.preferenceKey, default: ArisTextBacking.standard)
}

/// The patch itself: black 62 %, blurred 5 points, 6 wider and 3 taller than the text each side.
struct ArisTextBackingPatch: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ArisTextBacking.corner, style: .continuous)
            .fill(.black.opacity(ArisTextBacking.opacity))
            .padding(.horizontal, -ArisTextBacking.wider)
            .padding(.vertical, -ArisTextBacking.taller)
            .blur(radius: ArisTextBacking.blur)
            .allowsHitTesting(false)
    }
}

/// The patch behind the text it is put on, while the setting says so.
struct ArisTextBackingModifier: ViewModifier {
    /// False: this text has nothing to back now (the composer's field while it is empty).
    var shown = true
    @Default(.arisTextBacking) private var on
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            if shown && ArisTextBacking.shows(on: on, reduceTransparency: reduceTransparency) { ArisTextBackingPatch() }
        }
    }
}

extension View {
    /// A soft dark patch behind this run of small text while 글자 뒤 받침 is on (ArisTextBacking); `when` false: none.
    func arisTextBacking(when shown: Bool = true) -> some View { modifier(ArisTextBackingModifier(shown: shown)) }
}
