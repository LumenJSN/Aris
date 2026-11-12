//
//  ArisCharacterView.swift
//  Aris
//
//  A character on screen: its look's baked sprites on a layer (ArisSpriteView), so nothing is drawn per frame and an
//  animating character costs the app nothing per frame. What plays is upstream's Bot Avatars as libraries.dev/bots has
//  them (ArisSpritePlay): the idle state (and the face toward the pointer when it comes near), the working state, the
//  sleeping state, and a poke when a job is done; plus Aris's own 1.5-point lift while it listens. 모션 줄이기 (or the
//  system's Reduce Motion) holds the state's rest pose. No glow, ring or circling light.
//

import BotAvatarsKit
import Defaults
import SwiftUI

struct ArisCharacterView: View {
    /// What it draws, unless `isAris`.
    var look: ArisCharacterLook = .star
    /// The mood (ArisCharacterMood): "default", "working" or "sleeping".
    var state = "default"
    /// Points up (ArisCharacterMotion.lift).
    var lift: Double = 0
    let size: CGFloat
    /// Read out by VoiceOver; nil keeps the character decorative.
    var label: String?
    /// May show its sleeping pose (Aris's own star); the others never sleep.
    var canSleep = false
    /// A count; each rise plays upstream's poke (a hop and a full turn), for a job just done.
    var pokes = 0
    /// A count; each rise plays a landing squash (A6's hop between the band and the pill).
    var lands = 0
    /// Faces the pointer when it comes within reach.
    var follows = true
    /// Holds the state's rest pose (a picker tile: one small atlas each, nothing playing).
    var still = false
    /// Greyed and tilted (the star dozing while the agent is down, audit ① B).
    var muted = false
    /// Aris itself: wears the face picked on the 팀원 page (ArisFace), and changes with it at once.
    var isAris = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Default(.arisReduceMotion) private var reduceSetting
    @AppStorage(ArisFace.key, store: ArisFace.store) private var arisFace = ""

    /// The lift settles in 280 ms on a strong ease-out (0.23, 1, 0.32, 1), the mockup's `.a5` transition.
    private static let liftCurve = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)

    private var reduced: Bool { systemReduceMotion || reduceSetting }

    var body: some View {
        let look = isAris ? ArisFace.decode(arisFace) : look
        let play = ArisSpritePlay.from(state: state, canSleep: canSleep, reduceMotion: reduced || still)
        // Baked at a standard size at or above this one, scaled down by the layer.
        let sprite = ArisSpriteLook(type: look.type, colorHex: look.colorHex, shading: look.shading, size: ArisSpriteLook.bakeSize(size),
                                    scale: min(2, displayScale), dark: colorScheme == .dark)
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                // Where BotAvatar puts its canvas: 1.5 times the box, the body's centre on the box's.
                ArisSpriteView(look: sprite, play: play, pokes: pokes, lands: lands, muted: muted, bursts: !reduced && !still, follows: follows && !reduced && !still)
                    .frame(width: size * BOT_AVATAR_OVERSCAN, height: size * BOT_AVATAR_OVERSCAN)
                    .offset(y: -BOT_AVATAR_RISE * size)
            }
            .offset(y: reduced ? 0 : -lift)
            .animation(Self.liftCurve, value: lift)
            .allowsHitTesting(false)
            .modifier(CharacterLabel(label: label))
    }
}

/// Decorative unless named: the avatar's own "Star bot, idle" never reaches VoiceOver.
private struct CharacterLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityAddTraits(.isImage)
        } else {
            content.accessibilityHidden(true)
        }
    }
}

/// Aris's star in the mood the app is in: what the main turn does, the background jobs, and how long it has been idle
/// (it dozes after 10 minutes, and at night). The clock that checks for sleep ticks once a minute.
struct ArisMainCharacter: View {
    @ObservedObject private var aris = ArisController.shared
    @ObservedObject private var agent = ArisAgentMonitor.shared
    var size: CGFloat = 20
    /// Landings to play (ArisStarStage's hops).
    var lands = 0
    /// Resting in the closed band: asleep, whatever the clock says (ArisRestStar).
    var asleep = false
    /// Jobs seen finishing done while this star was on screen: each pokes it.
    @State private var pokes = 0

    private var phase: ArisMainPhase { ArisCharacterMood.mainPhase(aris.session.phase) }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let hour = Calendar.current.component(.hour, from: context.date)
            let state = ArisRestStar.mood(ArisCharacterMood.state(phase: phase, jobs: aris.jobs, idleFor: context.date.timeIntervalSince(aris.lastActivity), hour: hour), asleep: asleep)
            // The agent can't be reached: asleep, still, grey and tilted, until it answers (audit ① B).
            let dozing = agent.link.dozes && state != "working" && phase == .idle
            ArisCharacterView(state: dozing ? "sleeping" : state, lift: ArisCharacterMotion.lift(phase: phase), size: size,
                              label: dozing ? ArisUIWords.text("Aris, 에이전트 연결 끊김", "Aris, helper not connected") : "Aris", canSleep: true, pokes: pokes, lands: lands, still: dozing, muted: dozing,
                              isAris: true)
        }
        .onChange(of: aris.jobs) { old, new in pokes += ArisCharacterPlan.newlyDone(before: old, after: new) }
    }
}
