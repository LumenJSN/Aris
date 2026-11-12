//
//  ArisBandMark.swift
//  Aris
//
//  The closed band's mark, in the 28-point control (ArisVNotch): the star's seat (the notch's stage draws the
//  star there, 18 points), and while Aris listens the four bars in its place, the band's waveform
//  while recording. The star gives its seat up for the bars and takes it back after: the stage fades it out and in,
//  the bars come and go over 280 ms from 85 %. Working, answering and resting, the star is the mark, with its own
//  working turn.
//

import SwiftUI

struct ArisBandMark: View {
    /// Aris is taking in what is said right now.
    let listening: Bool

    var body: some View {
        ZStack {
            if !listening {
                Color.clear.arisStarSeat(.band)
            }
            ArisVoiceBarsView(listening: listening) { ArisController.shared.level }
        }
        .frame(width: ArisVNotch.orbBox, height: ArisVNotch.orbBox)
    }
}
