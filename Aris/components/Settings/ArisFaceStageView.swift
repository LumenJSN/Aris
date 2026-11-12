//
//  ArisFaceStageView.swift
//  Aris
//
//  The 팀원 page's 미리보기 strip (the owner's "Settings A", mockups/face/sa.html): Aris's face at rest beside the camera,
//  listening as the band widens to 270 × 32 (lifted 1.5 pt, the four bars on the far side), and working in the pill
//  under the notch (the line shimmering), in turn every 2.2 s (자동) or held on one (ArisFaceStage). The face hops
//  between seats on the house curve; a new face drops in. 모션 줄이기 or Reduce Motion: 자동 holds rest, no hop, no bars,
//  no shimmer. The face is the window's art: Aris's baked sprites, live.
//

import SwiftUI

struct ArisFaceStageView: View {
    @Environment(\.arisSettingsArt) private var art
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsStill) private var still
    @AppStorage(ArisFace.key, store: ArisFace.store) private var arisFace = ""
    @State private var pin = ArisFaceStage.Pin.auto
    @State private var tick = 0
    @State private var hop = false
    /// Drawn offscreen in one mode (the design renders).
    var shownMode: ArisFaceStage.Mode?

    private static let height: CGFloat = 150
    private var reduced: Bool { ArisSettingsMotion.reduced }
    private var mode: ArisFaceStage.Mode { shownMode ?? ArisFaceStage.mode(pin: pin, tick: tick, reduced: reduced) }

    var body: some View {
        GeometryReader { proxy in
            let mid = proxy.size.width / 2
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(arisHex: 0x18191d), Color(arisHex: 0x16171a)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.white.opacity(0.04)).frame(height: 24)
                    .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.04)).frame(height: 1) }
                Text(ArisTeamCopy.faceStagePreview).font(.system(size: 10, weight: .semibold)).tracking(0.2).foregroundStyle(.white.opacity(0.38))
                    .offset(x: 14, y: 5)
                ArisFaceStagePill(working: mode == .work, reduced: reduced || still)
                    .offset(x: mid - 105, y: 40)
                band.offset(x: mid - ArisFaceStage.notchWidth(mode) / 2)
                face.offset(seat(mid: mid))
                Text(ArisFaceStage.caption(mode)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1).frame(width: proxy.size.width).offset(y: Self.height - 14 - 16)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.18), value: mode)
                pins.offset(x: proxy.size.width - 10 - Self.pinsWidth, y: 30)
            }
            .frame(width: proxy.size.width, height: Self.height, alignment: .topLeading)
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(arisHex: 0xdfe2e8, palette.dark ? 0.07 : 0), lineWidth: 1))
        .shadow(color: .black.opacity(palette.dark ? 0 : 0.2), radius: 3, y: 1)
        .task(id: pin) { await cycle() }
        .onChange(of: mode) { _, _ in hopOnce() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ArisTeamCopy.faceStageLabel(ArisFaceStage.caption(mode)))
    }

    // MARK: pieces

    /// The camera's band: closed 150 × 29, widened to 270 × 32 with the listening rim and bars.
    private var band: some View {
        let listening = mode == .listen
        let radius = ArisFaceStage.notchRadius(mode)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        return shape.fill(.black)
            .overlay(alignment: .trailing) {
                ArisFaceStageBars(on: listening && !reduced && !still).padding(.trailing, 14).opacity(listening ? 1 : 0)
                    .animation(.easeOut(duration: 0.18).delay(listening ? 0.16 : 0), value: listening)
            }
            .overlay(shape.stroke(Color(red: 235 / 255, green: 245 / 255, blue: 1).opacity(listening ? 0.22 : 0), lineWidth: 0.9))
            .shadow(color: Color(red: 90 / 255, green: 170 / 255, blue: 1).opacity(listening ? 0.32 : 0), radius: 8, y: 3)
            .frame(width: ArisFaceStage.notchWidth(mode), height: ArisFaceStage.notchHeight(mode))
            .animation(listening ? ArisSettingsMotion.open : ArisSettingsMotion.close, value: listening)
    }

    private var face: some View {
        let size: CGFloat = mode == .work ? 22 : 20
        // A new face: the old one drops out, the new one lands on the land curve.
        return ZStack {
            art.aris(mode == .work ? "working" : "default", size)
                .frame(width: size, height: size)
                .id(arisFace)
                .transition(reduced || still ? .opacity : .asymmetric(insertion: .scale(scale: 0.7).combined(with: .opacity).combined(with: .offset(y: -10)),
                                                                         removal: .scale(scale: 0.6).combined(with: .opacity).combined(with: .offset(y: 6))))
        }
        .animation(reduced ? .easeOut(duration: 0.15) : .timingCurve(0.34, 1.56, 0.64, 1, duration: 0.46), value: arisFace)
        .offset(y: hop ? -12 : 0)
            .offset(y: mode == .listen && !reduced ? -1.5 : 0)
    }

    /// The face's seat: beside the camera at rest, at the widened band's near end listening, in the pill's slot working.
    private func seat(mid: CGFloat) -> CGSize {
        switch mode {
        case .rest: CGSize(width: mid + 83, height: 2)
        case .listen: CGSize(width: mid - 123, height: 4.5)
        case .work: CGSize(width: mid - 98, height: 44)
        }
    }

    private static let pinsWidth: CGFloat = 250

    /// 자동 · 쉴 때 · 들을 때 · 일할 때, the window's glass control drawn dark at .86.
    private var pins: some View {
        ArisGlassSegmented(options: ArisFaceStage.Pin.allCases.map { ArisSettingOption(id: $0.rawValue, title: $0.title) }, selected: pin.rawValue,
                           label: ArisTeamCopy.faceStagePreview) { id in
            withAnimation(reduced ? nil : ArisSettingsMotion.house(0.42)) { pin = ArisFaceStage.Pin(rawValue: id) ?? .auto }
        }
            .environment(\.colorScheme, .dark)
            .scaleEffect(0.86, anchor: .topTrailing)
            .frame(width: Self.pinsWidth, alignment: .trailing)
    }

    // MARK: motion

    /// 자동 steps every 2.2 s while the page shows (and not at all under 모션 줄이기); a pin holds its mode.
    private func cycle() async {
        tick = 0
        guard pin == .auto, !still, !reduced else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(ArisFaceStage.interval))
            guard !Task.isCancelled else { return }
            withAnimation(ArisSettingsMotion.house(0.42)) { tick += 1 }
        }
    }

    /// Between seats: up 12 and down again over 420 ms (ArisStarHop's length).
    private func hopOnce() {
        guard !reduced, !still else { return }
        withAnimation(.easeOut(duration: 0.19)) { hop = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(190))
            withAnimation(.easeIn(duration: 0.23)) { hop = false }
        }
    }
}

/// The four listening bars, 2.5 wide, a new height every 58 ms while on (ArisNotchPreviewWave's levels); flat when off.
private struct ArisFaceStageBars: View {
    let on: Bool

    var body: some View {
        if on {
            TimelineView(.periodic(from: .now, by: ArisNotchPreviewWave.tick)) { context in
                bars(ArisNotchPreviewWave.bars(tick: Int(context.date.timeIntervalSinceReferenceDate / ArisNotchPreviewWave.tick)).map(\.height))
            }
        } else {
            bars([2, 2, 2, 2])
        }
    }

    private func bars(_ heights: [Double]) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { n in
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.9)).frame(width: 2.5, height: heights[n])
            }
        }
        .frame(height: 18)
    }
}

/// The working pill under the notch: 210 × 30, r15, the dictation pill's dark glass; its line shimmering (a 2.4 s sweep;
/// still at .78 under 모션 줄이기). In on the open curve, out on the close one.
private struct ArisFaceStagePill: View {
    let working: Bool
    let reduced: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        ZStack(alignment: .leading) {
            shape.fill(LinearGradient(colors: [Color(red: 22 / 255, green: 22 / 255, blue: 27 / 255).opacity(0.96),
                                               Color(red: 12 / 255, green: 12 / 255, blue: 15 / 255).opacity(0.96)], startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.4), radius: 9, y: 6)
            line.padding(.leading, 36)
        }
        .frame(width: 210, height: 30)
        .opacity(working ? 1 : 0)
        .scaleEffect(working ? 1 : 0.965)
        .offset(y: working ? 0 : -6)
        .animation(working ? ArisSettingsMotion.open : ArisSettingsMotion.close, value: working)
    }

    @ViewBuilder
    private var line: some View {
        let text = Text(ArisFaceStage.workLine).font(.system(size: 11.5, weight: .semibold)).tracking(-0.1)
        if reduced || !working {
            text.foregroundStyle(.white.opacity(0.78))
        } else {
            TimelineView(.animation) { context in
                // 0 → 1 over the first half of 2.4 s, then held: the light crosses once a cycle, as the mockup's sweep.
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 1.2
                let head = min(1, t) * 1.6 - 0.3
                let at = { (x: Double) in min(1, max(0, x)) }
                text.foregroundStyle(LinearGradient(stops: [.init(color: .white.opacity(0.45), location: at(head - 0.15)),
                                                            .init(color: .white, location: at(head)),
                                                            .init(color: .white.opacity(0.45), location: at(head + 0.15))],
                                                    startPoint: .leading, endPoint: .trailing))
            }
        }
    }
}
