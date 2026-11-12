//
//  ArisNotchHeader.swift
//  Aris
//
//  The open notch's top band: 37 tall, Aris's 18-point mark in a 28-point slot 9 from the left edge
//  (bars while you talk, hopping dots while it works, the orb otherwise; tap it for Aris's page), and the slot
//  right of the camera: a stop button while Aris works and "닫기" while an answer is up, both at once while Aris
//  speaks its answer ("닫기" then 30 from the right); otherwise the other places the notch can show
//  (music, shelf, Claude) and settings, as quiet icons, all four always (they shrink to fit beside a wide camera
//  housing, ArisNotchHeaderLayout). "닫기" puts the answer away and closes the notch.
//

import SwiftUI

struct ArisNotchHeader: View {
    @EnvironmentObject private var vm: ArisNotchModel
    @ObservedObject private var coordinator = ArisNotchNavigation.shared
    @ObservedObject private var aris = ArisController.shared
    @ObservedObject private var claude = ClaudeStore.shared
    /// Re-draws this view when the hidden look changes (ArisSiriLookGate).
    @ObservedObject private var siriLook = ArisSiriLookGate.shared

    /// Claude's done notice is up (on the Claude page, but on the 416 answer page, not the 540 sessions list).
    var showingNotice = false
    /// The voice switch drawn as if the pointer were on the mark (the off-screen render only).
    var previewSwitch = false

    static let height: CGFloat = 37

    private var onArisPage: Bool { [.home, .aris].contains(coordinator.currentView) }
    private var working: Bool { onArisPage && [.listening, .thinking, .speaking].contains(aris.session.phase) }
    /// Aris keeps listening by itself (the wake word, a conversation): nobody holds a key.
    private var handsFreeListening: Bool { onArisPage && aris.handsFree && aris.session.phase == .listening }
    /// An answer on screen, spoken or not; a confirm card has its own buttons.
    private var answerUp: Bool { onArisPage && !aris.session.reply.isEmpty && aris.session.question == nil }
    /// Close sits 30 from the right while Stop is beside it.
    private static let closeBesideStop = ArisVNotch.closeBesideStop

    var body: some View {
        // On the band's grid (ArisBandFace): the band spans the body, 12 points past the content each side.
        ArisBandFace(bodyWidth: width + 2 * ArisGlass.inset, height: Self.height) {
            Button { withAnimation(ArisGlass.resize) { coordinator.currentView = .home } } label: {
                ArisLiveVoiceGlyph(mode: aris.session.phase.glyphMode)
                    // The siri look: Siri's ring of dots in the working mark's place, in this same seat and box.
                    .modifier(ArisSiriLookWorkingMark(phase: aris.session.phase))
                    .background { ArisMarkHalo(halo: halo) }
                    .frame(width: ArisVNotch.orbBox, height: ArisVNotch.orbBox)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Aris")
            // On the sessions page the ghost is the one character; the </> place takes the user back home. A turn's bars and
            // dots still show there (N7): only the resting star steps aside.
            .opacity(showsGlyph ? 1 : 0)
            .allowsHitTesting(showsGlyph)
        } beside: {
            // The voice switch shows only beside the orb: never beside the bars or the working mark.
            ArisMuteSwitch(shown: showsGlyph && ArisVNotch.voiceSwitchOffered(indicator: aris.session.phase.indicator), previewHover: previewSwitch)
        } trailing: {
            Group {
                if working || answerUp {
                    ZStack(alignment: .trailing) {
                        if answerUp {
                            ArisCloseAnswerButton(action: close)
                                .padding(.trailing, working ? Self.closeBesideStop : 0)
                                // The siri look's round buttons are wider than the 23-point slot: the ✕ clears the stop.
                                .padding(.trailing, working && ArisSiriLookNow.on ? ArisSiriLookBand.closeBesideStop(band: Self.height) - Self.closeBesideStop : 0)
                                .transition(.opacity)
                        }
                        if handsFreeListening {
                            // The hands-free lock has the slot while Aris keeps listening by itself.
                            ArisHandsFreeLock { aris.stopFromTag() }.transition(.opacity)
                        } else if working {
                            ArisStopButton { aris.stopFromTag() }.transition(.opacity)
                        }
                    }
                } else {
                    // All four, settings included, sized to the room beside the camera (one row, not ViewThatFits:
                    // switching branches rebuilt every icon mid-resize, so they flew in from the corner). Gating the
                    // gear on 23-point room hid it on the 416 page, so it only showed on the 540 </> page.
                    places(placeMetrics)
                }
            }
            .frame(height: ArisVNotch.stopSize)
            .transition(.opacity)
        }
        .padding(.horizontal, -ArisGlass.inset)
        .frame(width: width, height: Self.height)
        .animation(.easeOut(duration: 0.18), value: working)
        .animation(.easeOut(duration: 0.18), value: answerUp)
        .animation(.easeOut(duration: 0.18), value: showsGlyph)
    }

    /// The glow behind the star: while Aris speaks, and after a failure (ArisVNotch.halo).
    private var halo: ArisVNotch.Halo {
        let phase = aris.session.phase
        return ArisVNotch.halo(indicator: phase.indicator, speaking: phase == .speaking, error: phase == .failed)
    }

    private var showsGlyph: Bool {
        ArisNotchHeaderLayout.showsGlyph(showsStar: showsStar, voiceOrWork: aris.session.phase.glyphMode != .orb)
    }

    private var showsStar: Bool {
        ArisNotchHeaderLayout.showsStar(claudePage: coordinator.currentView == .claude, showingNotice: showingNotice)
    }

    /// Close: the answer goes, a voice still reading it stops (a
    /// delivered answer stays in 기록), and the notch closes.
    private func close() {
        withAnimation(ArisGlass.resize) { aris.dismissAnswer() }
        vm.close()
    }

    private var width: CGFloat {
        ArisNotchHeaderLayout.usesSessionsWidth(claudePage: coordinator.currentView == .claude, showingNotice: showingNotice)
            ? ArisGlass.claudeWidth : ArisGlass.contentWidth
    }
    /// Shelf, Claude and settings in the room right of the camera housing, on the band's grid: the last slot ends
    /// where Stop does, 14 points from the body's edge (a 23-point slot's 11-point glyph is 6 further in).
    private var placeMetrics: ArisNotchHeaderLayout.Places {
        ArisNotchHeaderLayout.places(count: ArisNotchHeaderLayout.placeCount, headerWidth: width + 2 * ArisGlass.inset, housing: vm.closedNotchSize.width + 8,
                                     textInset: ArisVNotch.slotTrailing + (ArisNotchHeaderLayout.slot - ArisNotchHeaderLayout.glyph) / 2)
    }

    private func places(_ metrics: ArisNotchHeaderLayout.Places) -> some View {
        HStack(spacing: metrics.spacing) {
            // The slots end `metrics.trailing` from the body's edge; the band's face adds its own 14.
            place(.shelf, symbol: "tray.full", help: ArisShelfWords.name(), size: metrics.slot)
            place(.claude, symbol: "chevron.left.forwardslash.chevron.right", help: ArisUIWords.text("코딩 세션", "Coding sessions"), size: metrics.slot,
                  badge: !claude.approvals.isEmpty)
            Button { ArisStepAside.showSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    .frame(width: metrics.slot, height: metrics.slot).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(ArisUIWords.text("설정", "Settings"))
        }
        .fixedSize()
        .padding(.trailing, metrics.trailing - ArisVNotch.slotTrailing)
    }

    private func place(_ view: NotchViews, symbol: String, help: String, size: CGFloat, badge: Bool = false) -> some View {
        let current = coordinator.currentView == view
        return Button { withAnimation(ArisGlass.resize) { coordinator.currentView = current ? .home : view } } label: {
            // Both weights always there, crossfaded: swapping the font weight replaced the symbol mid-resize, and
            // the new glyph trailed its circle instead of moving with it.
            ZStack {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4)).opacity(current ? 0 : 1)
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ArisGlass.text).opacity(current ? 1 : 0)
            }
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(current ? 0.1 : 0)))
                .overlay(alignment: .topTrailing) {
                    if badge { Circle().fill(.orange).frame(width: 6, height: 6).offset(x: -2, y: 2) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The stop: a 23-point circle, white 10% (16% on hover, 24% pressed), an 8-point rounded square, and "esc" 6 to
/// its left on hover, coming in over 80 ms from 3 points left at 98%.
struct ArisStopButton: View {
    let action: () -> Void
    @State private var hovering = false

    /// The tip's opacity and transform: 80 ms, CSS `ease`.
    static let tipMotion = ArisHoverTip.motion

    var body: some View {
        if ArisSiriLookNow.on {
            // The siri look: Siri's round glass button, Aris's stop square in it.
            ArisSiriLookRoundButton(size: ArisSiriLookBand.size(band: ArisNotchHeader.height), help: ArisUIWords.text("그만 (esc)", "Stop (esc)"), action: action) {
                RoundedRectangle(cornerRadius: 1.8, style: .continuous).frame(width: 9, height: 9)
            }
        } else {
            plain
        }
    }

    private var plain: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                .fill(.white.opacity(hovering ? 1 : 0.9))
                .frame(width: 8, height: 8)
                .frame(width: 23, height: 23)
                .contentShape(Circle())
        }
        .buttonStyle(ArisStopStyle(hovering: hovering))
        .overlay(alignment: .trailing) {
            ArisHoverTip(text: "esc")
                .scaleEffect(hovering ? 1 : 0.98)
                .offset(x: -29 - (hovering ? 0 : 3))
                .opacity(hovering ? 1 : 0)
                .animation(Self.tipMotion, value: hovering)
                .allowsHitTesting(false)
        }
        .arisNotchHover($hovering)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help(ArisUIWords.text("그만 (esc)", "Stop (esc)"))
    }
}

/// The stop's circle: 10%, 16% on hover, 24% while pressed, over 140 ms.
private struct ArisStopStyle: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.24 : hovering ? 0.16 : 0.10)))
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// "Close" on an answer: a pill, white 15% (30% on hover), 11 pt medium.
struct ArisCloseAnswerButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        if ArisSiriLookNow.on {
            // The siri look: Siri's round glass ✕ where Aris has the word.
            ArisSiriLookRoundButton(symbol: "xmark", size: ArisSiriLookBand.size(band: ArisNotchHeader.height), action: action)
                .help(ArisUIWords.text("답 닫고 노치 접기 · 왼쪽 기록에서 다시 볼 수 있어요", "Close the answer and fold the notch · it stays in History on the left"))
        } else {
            plain
        }
    }

    private var plain: some View {
        Button(action: action) {
            Text(ArisUIWords.close)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 23)
                .background(Capsule().fill(.white.opacity(hovering ? 0.3 : 0.15)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(ArisUIWords.text("답 닫고 노치 접기 · 왼쪽 기록에서 다시 볼 수 있어요", "Close the answer and fold the notch · it stays in History on the left"))
    }
}
