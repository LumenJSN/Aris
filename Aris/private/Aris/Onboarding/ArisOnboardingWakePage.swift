//
//  ArisOnboardingWakePage.swift
//  Aris
//
//  아리스라고 부르기 (fresh install F4, the owner's ruling): the wake word is off on a new install, and the guide asks. The
//  page says what it does and, honestly, what it costs: the microphone then stays on to listen for the name. 네 turns
//  it on, 아니요 leaves it off; either goes on to the next page, and settings can change it any time. Drawn with the
//  try pages' own tile (ArisTrySingle, ArisTryTile).
//

import SwiftUI

struct ArisWakePage: View {
    @ObservedObject var guide: ArisOnboardingGuide
    let palette: ArisSetupPalette

    var body: some View {
        ArisTrySingle(title: ArisOnboardingCopy.wakeTitle, palette: palette) {
            ArisTryTile(question: ArisOnboardingCopy.wakeHow, palette: palette) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ArisOnboardingCopy.wakeHonest)
                        .font(.system(size: 14))
                        .lineSpacing(6)
                        .foregroundStyle(palette.t1)
                    Text(ArisOnboardingCopy.wakeChange)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.t2)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            } actions: {
                Button(ArisOnboardingCopy.wakeNo) { guide.chooseWakeWord(false) }
                    .buttonStyle(ArisQuietButtonStyle(palette: palette, weight: .regular))
                ArisGlassRect(title: ArisOnboardingCopy.wakeYes) { guide.chooseWakeWord(true) }
            }
        }
    }
}
