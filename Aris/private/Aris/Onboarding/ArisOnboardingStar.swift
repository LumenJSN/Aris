//
//  ArisOnboardingStar.swift
//  Aris
//
//  Aris's star in the onboarding, drawn live by Bot Avatars (BotAvatarsKit) at its own size wherever it sits (the
//  96-pt hero, the 22-pt notch star, the 88-pt stage star, the previews' paused icons), with its idle and working
//  motion; never a bitmap. The mockup's props (mockups/onboarding2/js/star.js): fabric, the key light from 300°, no
//  back light, the rim .85, a fixed seed, no idle flips (the story owns the big moves).
//

import BotAvatarsKit
import SwiftUI

/// Aris's star, drawn live by Bot Avatars at its own size (never a bitmap): fabric, the key light from 300°, no back
/// light, the rim .85, a fixed seed, and no idle flips (the story owns the big moves). In the notch and on the setup
/// stage it wears the face picked on the 팀원 page (N1, ArisOnboardingStage.wearsFace), and changes with it at once.
struct ArisOnboardingStar: View {
    let size: CGFloat
    var state: BotAvatarState = .default
    var paused = false
    var interactive = false
    var spot = ArisOnboardingStage.StarSpot.intro

    @AppStorage(ArisFace.key, store: ArisFace.store) private var arisFace = ""

    private static let noFlips: BotAvatarJumpConfig = {
        var jump = BotAvatarJumpConfig.defaults
        jump.every = 0
        return jump
    }()

    var body: some View {
        let look = ArisOnboardingStage.wearsFace(spot) ? ArisFace.decode(arisFace) : .star
        BotAvatar(type: BotAvatarType(rawValue: look.type) ?? .star, state: state, size: Double(size), color: look.colorHex.flatMap { BotColor($0) },
                  paused: paused, seed: 0.37, shading: .fabric, light: 300, rim: 0.85, backLight: 0,
                  interactive: interactive, theme: .dark, jump: Self.noFlips)
            .accessibilityHidden(true)
    }
}
