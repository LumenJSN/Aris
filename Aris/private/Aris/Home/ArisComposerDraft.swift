//
//  ArisComposerDraft.swift
//  Aris
//
//  The composer's typed words, kept outside the view: the open notch's content is torn down when it closes, and the
//  draft lived in the view's own state, so closing lost it. It stays here until it is sent or cleared. Whether the
//  field has the keyboard is kept too, so the notch doesn't put itself away under the user's typing
//  (ArisNotchDecisions.composerHolds).
//

import Combine

@MainActor
final class ArisComposerDraft: ObservableObject {
    static let shared = ArisComposerDraft()

    @Published var text = ""
    /// The composer's field has the keyboard.
    var focused = false

    /// The notch stays open for the draft (ArisNotchDecisions.composerHolds).
    var holdsNotch: Bool { ArisNotchDecisions.composerHolds(draft: text, focused: focused) }

    private init() {}
}
