//
//  ArisOnboardingDonePage.swift
//  Aris
//
//  준비 끝 (2026-11-17), the setup's last page, after 받아쓰기 (the owner: the star card does not belong on the dictation page):
//  the heading, one line on how to call Aris from now on (the wake word only when it is on, and the talk shortcut as it
//  is set), the repository card (ArisStarCardView; gone once skipped or starred) and 시작하기, which finishes the setup
//  (ArisOnboardingGuide.finish). Drawn with the setup's own type and buttons: the 30-pt light heading and 18-pt lead of
//  the two-column pages, in one column.
//

import Defaults
import SwiftUI

struct ArisDonePage: View {
    @ObservedObject var guide: ArisOnboardingGuide
    @ObservedObject var card: ArisStarCardModel
    let palette: ArisSetupPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ArisOnboardingCopy.doneTitle)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(palette.t1)
                .padding(.bottom, 16)
                .accessibilityAddTraits(.isHeader)
            Text(ArisOnboardingCopy.doneLine(wakeWord: Defaults[.arisWakeWord], keys: guide.talkKeysText))
                .font(.system(size: 18))
                .lineSpacing(10)
                .foregroundStyle(palette.lead)
                .fixedSize(horizontal: false, vertical: true)
            if card.state != .gone {
                ArisStarCardView(card: card, palette: palette, reduced: guide.reduced)
                    .padding(.top, 24)
                    .transition(.opacity)
            }
            ArisGlassRect(title: ArisOnboardingCopy.doneStart) { guide.next() }
                .padding(.top, 24)
        }
        .frame(maxWidth: 480, alignment: .topLeading)
        .padding(.top, 64).padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 건너뛰기 folds the card away: 220 ms on the mockup's ease-out; Reduce Motion, a fade.
        .animation(guide.reduced ? .easeOut(duration: 0.16) : ArisStarMotion.out(0.22), value: card.state == .gone)
        .onAppear { card.begin() }
    }
}
