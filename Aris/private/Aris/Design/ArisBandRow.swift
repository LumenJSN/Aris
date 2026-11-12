//
//  ArisBandRow.swift
//  Aris
//
//  The closed notch's band as a row, for every activity (Aris, a timer, Claude, background tasks): an ear each side of
//  the camera's width, each holding one mark centred 23 points in from the band's edge (ArisBand). On its own so the
//  off-screen renders draw the real row.
//

import SwiftUI

struct ArisBandRow<Leading: View, Trailing: View>: View {
    let height: CGFloat
    let notchWidth: CGFloat
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing
    /// The band width on this display (ArisVNotch), from the notch.
    @Environment(\.arisBandBody) private var bandBody

    var body: some View {
        let ear = ArisBand.earWidth(notchWidth: notchWidth, body: bandBody), slot = 2 * ArisBand.markCenter
        // Each ear is a fixed frame its mark sits on: a mark that draws nothing (no dot while listening, no count for
        // one job) used to take its ear with it, which pulled the band's middle off the camera and slid the star
        // under the housing on a notched display.
        HStack(spacing: 0) {
            Color.clear.frame(width: slot, height: height).overlay { leading() }.frame(width: ear, alignment: .leading)
            // The camera's width, left to the notch's own surface: over a camera housing that is all black (its
            // gradient's span), and on a display with none the band is one gradient from ear to ear, not a
            // black block between two glass ears.
            Color.clear.frame(width: notchWidth)
            Color.clear.frame(width: slot, height: height).overlay { trailing() }.frame(width: ear, alignment: .trailing)
        }
        .frame(height: height)
        .fixedSize()
    }
}
