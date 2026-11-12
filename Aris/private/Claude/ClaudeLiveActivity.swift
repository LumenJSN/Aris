//
//  ClaudeLiveActivity.swift
//  Aris
//
//  Closed-notch presence on the band (ArisBand): the Claude Code teammate's character left of the camera, the usage
//  ring with session dots right of it (what the ring shows: ClaudeRingNow). "Done", errors and limits open the notch
//  onto the Claude tab, like an approval (ClaudeTabView).
//

import Defaults
import SwiftUI

struct ClaudeLiveActivity: View {
    @ObservedObject private var store = ClaudeStore.shared
    @ObservedObject private var team = ArisTeamModel.shared
    @Default(.claudeRingMode) private var ringMode
    @Default(.claudeBudgetOn) private var budgetOn
    @Default(.claudeBudget) private var budget

    let height: CGFloat
    let notchWidth: CGFloat
    let openNotch: () -> Void

    var body: some View {
        ArisBandRow(height: height, notchWidth: notchWidth) {
            // A little under the band's box and seated so a hop never leaves the band (ClaudeEarLayout).
            ClaudeCharacterView(state: store.displayState, size: ClaudeEarLayout.characterSize(bandHeight: height))
                .offset(y: ClaudeEarLayout.drop(bandHeight: height))
                .allowsHitTesting(false)
        } trailing: {
            Button(action: openBusiestSession) {
                let sessions = store.sessions.values.sorted { $0.id < $1.id }
                let reading = ClaudeRingNow.reading(store, mode: ringMode, budgetOn: budgetOn, budget: budget)
                ClaudeEarGlyph(states: sessions.map(\.state),
                               center: EarCenter.pick(state: store.displayState, sessions: sessions),
                               usage: reading.percent, size: ClaudeEarLayout.glyphSize,
                               accent: Color(team.claudePalette.accent), sessionIds: sessions.map(\.id), reading: reading)
                    .frame(width: 2 * ArisBand.markCenter, height: height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: store.displayState)
    }

    private func openBusiestSession() {
        if let session = store.sessions.values.max(by: { $0.state.priority < $1.state.priority }) {
            store.focus(session.id)
        }
        openNotch()
    }
}
