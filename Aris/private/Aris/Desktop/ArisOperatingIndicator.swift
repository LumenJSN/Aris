//
//  ArisOperatingIndicator.swift
//  Aris
//
//  The look of the "working on this window" overlay, alone in one small view so the mockup the user picks drops in here
//  without touching the plumbing (ArisOperatingOverlay). For now a neutral placeholder: a thin 2 pt white border at
//  30%, no animation (and never a blinking dot).
//

import SwiftUI

struct ArisOperatingIndicator: View {
    /// What the overlay shows for (the app and the notch's line), for a look that wants it.
    let target: ArisOperatingTarget

    static let border: CGFloat = 2
    static let cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.3), lineWidth: Self.border)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
