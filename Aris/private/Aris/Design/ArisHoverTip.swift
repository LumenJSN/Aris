//
//  ArisHoverTip.swift
//  Aris
//
//  The notch's own tip: the small dark capsule beside a control ("esc" by the stop button, what a press on a
//  running tag does). Drawn inside the notch, so it needs no tooltip window and goes with the hover that shows it.
//

import SwiftUI

/// The small dark tip beside a control.
struct ArisHoverTip: View {
    let text: String

    /// How it comes and goes: opacity and transform over 80 ms, CSS `ease`.
    static let motion = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.08)

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.1)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(red: 22 / 255, green: 24 / 255, blue: 28 / 255).opacity(0.92)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 7, y: 4)
            .fixedSize()
    }
}
