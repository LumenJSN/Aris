//
//  ArisAgentChip.swift
//  Aris
//
//  The owner's pick ① B (mockups/audit-1-agent-down.html): while aris-agent can't be reached the star dozes beside the
//  camera (ArisMainCharacter); hovering it, or tapping it, shows a chip under the notch: 에이전트 연결 끊김 and
//  다시 시작. Then 다시 시작하는 중 (the text shimmer, the only loop), 다시 연결됐어요 with a check landing once, or
//  아직 연결이 안 돼요 with 다시 시작 again. The hover target is the star's ear only, above the notch's own hover, so
//  hovering the star never opens the notch.
//

import SwiftUI

struct ArisAgentLayer: View {
    @ObservedObject private var agent = ArisAgentMonitor.shared

    /// The star's seat in the band (ArisStarSeats.band, resolved), when the band is drawn.
    let seat: CGRect?
    let mode: ArisStarBand.Mode?
    let bandHeight: CGFloat
    let ear: CGFloat
    /// The jobs' pill has a line: it comes first under the notch (ArisUnderNotch).
    var pillShown = false

    /// The chip would show (the star at rest, down and hovered, or restarting / back).
    static func chipWanted(link: ArisAgentLink, hovered: Bool, mode: ArisStarBand.Mode?) -> Bool {
        mode == .home && ArisAgentLink.chipShows(link, hovered: hovered)
    }

    var body: some View {
        let hot = ArisStarBand.agentHotWidth(mode: mode, dozing: agent.link.dozes, ear: ear)
        let shows = ArisUnderNotch.owner(pill: pillShown, agentChip: Self.chipWanted(link: agent.link, hovered: agent.hovered, mode: mode),
                                         prep: false, offer: false) == .agentChip
        ZStack(alignment: .top) {
            if hot > 0, let seat {
                Color.black.opacity(0.001)
                    .frame(width: hot, height: bandHeight)
                    .contentShape(Rectangle())
                    .position(x: seat.midX, y: bandHeight / 2)
                    .onHover { agent.hover($0) }
                    .onTapGesture { agent.hover(!agent.hovered) }
                    .accessibilityLabel(Text(verbatim: ArisAgentLink.lostWords))
                    .accessibilityAction(named: Text(verbatim: ArisAgentLink.restartWords)) { agent.restart() }
            }
            if shows {
                ArisAgentChip(link: agent.link, restart: agent.restart)
                    .onHover { agent.hover($0) }
                    .padding(.top, bandHeight + 6)
                    .transition(.modifier(active: ChipEntry(on: false), identity: ChipEntry(on: true)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.15), value: shows)
    }

    /// In from 4 points lower at .97, 150 ms ease-out (the mockup's .tipB).
    private struct ChipEntry: ViewModifier {
        let on: Bool
        func body(content: Content) -> some View {
            content.opacity(on ? 1 : 0).scaleEffect(on ? 1 : 0.97, anchor: .top).offset(y: on ? 0 : 4)
        }
    }
}

struct ArisAgentChip: View {
    let link: ArisAgentLink
    let restart: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if link == .back { ArisAgentOK() }
            Text(verbatim: link.chipText)
                .font(Font(ArisFont.system(11.5, weight: 560)))
                .modifier(ChipText(link: link))
                .fixedSize()
            if link.offersRestart {
                Button(action: restart) {
                    Text(verbatim: ArisAgentLink.restartWords)
                        .font(Font(ArisFont.system(11.5, weight: 600)))
                        .tracking(0.115)
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 10)
                        .frame(height: 23)
                        .background(Capsule(style: .continuous).fill(.white.opacity(0.15)))
                        .contentShape(Capsule())
                }
                .buttonStyle(ArisChipPress())
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, link.offersRestart ? 6 : 11)
        .frame(height: 26)
        .background(
            Capsule(style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 32 / 255, green: 32 / 255, blue: 35 / 255).opacity(0.965),
                                              Color(red: 19 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.98)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 6)
        .animation(.easeOut(duration: 0.18), value: link)
    }

    /// The restarting line shimmers (the one moving thing); the rest is white .78.
    private struct ChipText: ViewModifier {
        let link: ArisAgentLink
        func body(content: Content) -> some View {
            if link == .restarting {
                content.modifier(ArisProcessingShimmer(on: true))
            } else {
                content.foregroundStyle(.white.opacity(link == .back ? 0.9 : 0.78))
            }
        }
    }
}

/// Pressed: .95, 140 ms (the mockup's .pill:active).
private struct ArisChipPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.14), value: configuration.isPressed)
    }
}

/// The green check that lands once (460 ms, the only overshoot), as the mockup's .okmark.
private struct ArisAgentOK: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(Color(red: 6 / 255, green: 32 / 255, blue: 15 / 255))
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color(red: 80 / 255, green: 200 / 255, blue: 120 / 255).opacity(0.95)))
            .scaleEffect(landed || reduceMotion ? 1 : 0.4)
            .opacity(landed || reduceMotion ? 1 : 0)
            .onAppear { withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.46)) { landed = true } }
    }
}
