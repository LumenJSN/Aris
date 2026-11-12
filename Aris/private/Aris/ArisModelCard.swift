//
//  ArisModelCard.swift
//  Aris
//
//  ③ B on screen (mockups/audit-3-whisper.html): the offer and the progress cards hanging under the closed notch in
//  the open notch's dress (a black body, the #18191C card inside, radius 26), the right ear's mini bar and percent at
//  rest, a check when it's in (the ear is fixed for the camera, so no 준비 끝 text; a tap opens the progress card), and the first listen's 음성 인식 준비 중 while Apple's model installs. No
//  dots; the only loops are the waiting line's text shimmer and the prep line's.
//

import SwiftUI

struct ArisModelLayer: View {
    @ObservedObject private var downloads = ArisModelDownloader.shared
    @ObservedObject private var agent = ArisAgentMonitor.shared

    /// The star's seat in the band (the ear's mark mirrors it on the right).
    let seat: CGRect?
    let mode: ArisStarBand.Mode?
    let closed: Bool
    let bandHeight: CGFloat
    /// The jobs' pill has a line: it owns the space under the notch (ArisUnderNotch).
    var pillShown = false
    /// A drag is over the notch: no offer shows (it is kept for later).
    var busy = false
    @ObservedObject private var aris = ArisController.shared
    @ObservedObject private var guide = ArisOnboardingGuide.shared
    @ObservedObject private var settings = ArisSettingsWindow.shared

    /// Who draws under the notch now: the card only when nothing else does (it waits), the prep line after the pill
    /// and the agent chip.
    private var owner: ArisUnderNotch? {
        ArisUnderNotch.owner(pill: pillShown, agentChip: ArisAgentLayer.chipWanted(link: agent.link, hovered: agent.hovered, mode: mode),
                             prep: closed && mode == .turn && downloads.appleInstalling,
                             offer: closed && (downloads.cardOpen || (downloads.offering && ArisModelOfferQuiet.mayShow(
                                 dragging: busy, turn: aris.session.phase != .idle, card: aris.session.question != nil, onboarding: guide.showing,
                                 settings: settings.visible))))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if closed, mode == .home, let seat,
                   let text = downloads.state.earText ?? (downloads.loadTrouble != nil ? ArisModelOffer.troubleEar : nil) {
                    // Right-aligned to the right ear's mark slot (the star's seat mirrored), growing inward.
                    ArisModelEar(state: downloads.state, text: text)
                        .onTapGesture { downloads.openCard() }
                        .frame(width: Self.earRoom, alignment: .trailing)
                        .position(x: proxy.size.width - seat.midX + ArisBand.markCenter - Self.edgeInset - Self.earRoom / 2, y: bandHeight / 2)
                        .transition(.opacity)
                }
                Group {
                    if owner == .offer {
                        ArisModelPanel(downloads: downloads)
                            .transition(.modifier(active: Entry(on: false), identity: Entry(on: true)))
                    } else if owner == .prep {
                        ArisModelPrep().transition(.opacity)
                    }
                }
                .padding(.top, bandHeight + 6)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(ArisGlass.opening, value: owner)
        .animation(.easeOut(duration: 0.18), value: downloads.state.earText)
    }

    /// Room the ear's content may take, from the slot's outer edge inward.
    private static let earRoom: CGFloat = 80
    /// Off the band's edge, as the star sits off the left one, but never under the camera: about 44 points of room.
    private static let edgeInset: CGFloat = 4

    private struct Entry: ViewModifier {
        let on: Bool
        func body(content: Content) -> some View {
            content.opacity(on ? 1 : 0).scaleEffect(on ? 1 : 0.985, anchor: .top).offset(y: on ? 0 : -4)
        }
    }
}

/// The right ear at rest: a 14 × 3 bar and the percent (대기, 멈춤), or the check once it's in.
private struct ArisModelEar: View {
    let state: ArisModelDownload
    let text: String

    var body: some View {
        // The ear is fixed (camera clipping): about 44 points of room, so a 14-point bar, and the check alone at the end.
        HStack(spacing: 5) {
            if state == .done {
                ArisModelCheck(size: 14)
            } else {
                Capsule().fill(.white.opacity(0.14)).frame(width: 14, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.85)).frame(width: 14 * state.fraction, height: 3)
                    }
                    .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.5), value: state.fraction)
                Text(verbatim: text)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize()
            }
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ArisModelOffer.earLabel(text)))
        .accessibilityAddTraits(.isButton)
    }
}

/// The notch's body with one card: the offer, or the download's progress.
private struct ArisModelPanel: View {
    @ObservedObject var downloads: ArisModelDownloader

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if downloads.offering {
                offer
            } else if downloads.state == .idle, let model = downloads.loadTrouble {
                title(ArisModelOffer.troubleTitle(model))
                para(ArisModelOffer.troubleLine)
                secondary(ArisModelOffer.close) { downloads.hideCard() }.padding(.top, 12)
            } else {
                progress
            }
        }
        .padding(.horizontal, ArisModelOffer.cardInset)
        .padding(.vertical, 14)
        .frame(width: ArisModelOffer.cardWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(red: 24 / 255, green: 25 / 255, blue: 28 / 255))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.05), lineWidth: 1)))
        .padding(12)
        .background(UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 31, bottomTrailingRadius: 31,
                                           topTrailingRadius: 14, style: .continuous).fill(.black))
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: 0) {
            title(ArisModelOffer.title())
            para(ArisModelOffer.body)
            HStack(spacing: ArisModelOffer.choiceGap) {
                ForEach(ArisSpeechModel.allCases, id: \.self) { m in
                    Button { downloads.choose(m) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: ArisModelOffer.choice(m)).font(Font(ArisFont.system(12.5, weight: 600)))
                            Text(verbatim: ArisModelOffer.cost(m)).font(.system(size: ArisModelOffer.costFontSize)).foregroundStyle(.white.opacity(0.62))
                        }
                        .foregroundStyle(.white.opacity(downloads.model == m ? 0.95 : 0.78))
                        .padding(.horizontal, ArisModelOffer.choiceInset).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(downloads.model == m ? 0.13 : 0.06))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(downloads.model == m ? 0.22 : 0.06), lineWidth: 1)))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(downloads.model == m ? .isSelected : [])
                }
            }
            .padding(.top, 12)
            HStack(spacing: 8) {
                primary(ArisModelOffer.accept) { downloads.accept() }
                secondary(ArisModelOffer.notNow) { downloads.later() }
                Spacer(minLength: 0)
                Text(verbatim: ArisModelOffer.wifiOnly).font(.system(size: 11)).foregroundStyle(.white.opacity(0.43))
            }
            .padding(.top, 12)
        }
    }

    private var progress: some View {
        let state = downloads.state, done = state == .done
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                if done { ArisModelCheck(size: 16) }
                title(ArisModelOffer.progressTitle(downloads.model, state: state))
            }
            para(ArisModelOffer.progressBody(done: done))
            let paused = { if case .running = state { return false }; return !done }()
            Capsule().fill(.white.opacity(0.1)).frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule()
                            .fill(paused ? AnyShapeStyle(.white.opacity(0.35))
                                  : AnyShapeStyle(LinearGradient(colors: [Color(red: 159 / 255, green: 208 / 255, blue: 1).opacity(0.75), .white.opacity(0.95)],
                                                                 startPoint: .leading, endPoint: .trailing)))
                            .frame(width: g.size.width * state.fraction)
                            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.5), value: state.fraction)
                    }
                }
                .padding(.top, 12)
            HStack {
                Text(verbatim: state.numbers(downloads.model))
                Spacer(minLength: 8)
                Text(verbatim: state.status(remaining: downloads.remaining))
                    .modifier(WaitingText(on: { if case .waiting = state { return true }; return false }()))
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.white.opacity(0.43))
            .padding(.top, 6)
            HStack(spacing: 8) {
                if done {
                    primary(ArisModelOffer.close) { downloads.closeDone() }
                } else if state.retries {
                    primary(ArisModelOffer.retry) { downloads.retryNow() }
                    secondary(ArisModelOffer.cancel) { downloads.cancel() }
                    secondary(ArisModelOffer.hide) { downloads.hideCard() }
                } else {
                    secondary({ if case .paused = state { return ArisModelOffer.resume }; return ArisModelOffer.pause }()) { downloads.togglePause() }
                    secondary(ArisModelOffer.cancel) { downloads.cancel() }
                    secondary(ArisModelOffer.hide) { downloads.hideCard() }
                }
            }
            .padding(.top, 12)
        }
    }

    private func title(_ s: String) -> some View {
        Text(verbatim: s).font(Font(ArisFont.system(13, weight: 600))).foregroundStyle(.white.opacity(0.95)).padding(.bottom, 4)
    }

    private func para(_ s: String) -> some View {
        Text(verbatim: s).font(.system(size: 12.5)).lineSpacing(3).foregroundStyle(.white.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The mockup's Allow capsule: 30 tall, rgba(17,18,21,.85) with a .22 ring, 13 / 600.
    private func primary(_ s: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: s).font(Font(ArisFont.system(13, weight: 600))).foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 14).frame(height: 30)
                .background(Capsule().fill(Color(red: 17 / 255, green: 18 / 255, blue: 21 / 255).opacity(0.85))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// The mockup's .sec: 30 tall, radius 14, a .08 ring, 12.5 / 500 at .78.
    private func secondary(_ s: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: s).font(Font(ArisFont.system(12.5, weight: 500))).foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 12).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private struct WaitingText: ViewModifier {
        let on: Bool
        func body(content: Content) -> some View {
            if on { content.modifier(ArisProcessingShimmer(on: true)) } else { content }
        }
    }
}

/// The first listen while Apple's model installs: the line shimmers, its note stays still.
private struct ArisModelPrep: View {
    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: ArisModelOffer.prepLine).font(Font(ArisFont.system(12, weight: 600))).modifier(ArisProcessingShimmer(on: true))
            Text(verbatim: ArisModelOffer.prepNote).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
        }
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Capsule(style: .continuous).fill(LinearGradient(colors: [Color(red: 32 / 255, green: 32 / 255, blue: 35 / 255).opacity(0.965),
                                                                            Color(red: 19 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.98)],
                                                                   startPoint: .top, endPoint: .bottom))
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1)))
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 6)
    }
}

/// The green check (the mockup's .okc), landing once.
private struct ArisModelCheck: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.55, weight: .black))
            .foregroundStyle(Color(red: 6 / 255, green: 32 / 255, blue: 15 / 255))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(red: 80 / 255, green: 200 / 255, blue: 120 / 255).opacity(0.95)))
            .scaleEffect(landed || reduceMotion ? 1 : 0.4)
            .opacity(landed || reduceMotion ? 1 : 0)
            .onAppear { withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.46)) { landed = true } }
    }
}

