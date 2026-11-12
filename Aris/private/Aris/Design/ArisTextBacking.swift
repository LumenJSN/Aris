//
//  ArisTextBacking.swift
//  Aris
//
//  글자 뒤 받침 (Settings › 노치): the open notch's glass lets a bright, text-heavy window behind show through its
//  lower part, and small text there (the composer's hint and typed words, the tags, a card's small labels, the small
//  lines under an answer) measured 2.3 to 2.9:1. With the setting on, each such run of text gets a soft dark patch
//  behind it only: black 62 %, blurred 5 points, 6 points wider and 3 taller than the text each side (the proposal's
//  "b-soft", qa/design-1111/vnotch-renders/scrim-b-soft.png: hint 5.4:1, tag 7.8:1). The glass itself is untouched.
//  Off by default, which keeps today's look. With Reduce Transparency the notch is solid already: no patch then.
//  Foundation only (tested); the patch is drawn by ArisTextBackingPatch.
//

import Foundation

enum ArisTextBacking {
    /// The stored switch (Defaults key `arisTextBacking`).
    static let preferenceKey = "arisTextBacking"
    /// Off until it is turned on: today's look.
    static let standard = false

    /// The patch: black at this much, blurred this far, this much wider and taller than the text on each side, and
    /// rounded like the inline keys it sits behind.
    static let opacity = 0.62
    static let blur = 5.0
    static let wider = 6.0
    static let taller = 3.0
    static let corner = 8.0

    /// Whether a run of small text gets its patch: the setting is on, and the notch has glass to see through.
    static func shows(on: Bool, reduceTransparency: Bool) -> Bool { on && !reduceTransparency }

    /// What is seen behind the text with the patch's middle over a backdrop of sRGB `behind` (0 black, 1 white).
    static func backed(_ behind: Double) -> Double { behind * (1 - opacity) }
}
