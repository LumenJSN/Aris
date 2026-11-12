//
//  ClaudeCharacterView.swift
//  Aris
//
//  The Claude Code teammate on the Claude card's head and in the closed notch's left ear: the character the owner picked in
//  팀원 (ArisTeamModel; the ghost by default), playing what Claude is doing (ClaudeCharacter) from its baked sprites
//  (ArisCharacterView), so it costs nothing per frame. Its colour is the accent (ClaudeAccent): editing the look in
//  팀원 changes the character and the accent at once.
//

import SwiftUI

extension ArisTeamModel {
    /// The Claude Code teammate's look (the ghost until the list is in).
    var claudeLook: ArisCharacterLook { ClaudeAccent.look(in: teammates) }
    var claudePalette: ClaudeAccent.Palette { ClaudeAccent.palette(for: claudeLook) }
}

struct ClaudeCharacterView: View {
    let state: ClaudeState
    let size: CGFloat
    /// The accent's soft light behind it while Claude works (the card's head only).
    var glows = false

    @ObservedObject private var team = ArisTeamModel.shared
    /// Each rise plays upstream's poke once (Claude has just finished).
    @State private var pokes = 0

    var body: some View {
        let pose = ClaudeCharacter.pose(state)
        ArisCharacterView(look: team.claudeLook, state: pose.mood, size: size, canSleep: ClaudeCharacter.canSleep, pokes: pokes,
                          follows: pose.follows, still: pose.still, muted: pose.muted)
            .background {
                if glows && state.tone == .accent {
                    // Still: drawn once per change, nothing moves (a glow, never a blinking dot).
                    RadialGradient(colors: [Color(team.claudePalette.glow), .clear], center: .center, startRadius: 0, endRadius: size * 0.8)
                        .frame(width: size * 1.6, height: size * 1.6)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: state) { old, new in
                if ClaudeCharacter.pokes(from: old, to: new) { pokes += 1 }
            }
    }
}
