//
//  ArisNotchPreview.swift
//  Aris
//
//  Mockup C's stage at the top of every page: a strip of desktop with the menu bar, the notch as the page's settings
//  make it (ArisNotchPreviewPlan), Aris's star beside it, and a line under it. It reacts as settings change, then
//  rests: the waveform plays a couple of seconds and stops, the spoken line lights word by word once, the circle draws
//  once. The star is its baked sprites on a layer (the art the window is given), so at rest nothing here runs.
//

import SwiftUI

/// The characters the window draws (the app's baked sprites; a stand-in where there are none).
struct ArisSettingsArt {
    var star: (CGFloat) -> AnyView = { size in
        AnyView(Image(systemName: "star.fill").font(.system(size: size * 0.8)).foregroundStyle(Color(arisHex: 0xefdb8e)).frame(width: size, height: size))
    }
    /// Aris's face in a mood ("default", "working"), live (the 팀원 page's 미리보기 strip).
    var aris: (String, CGFloat) -> AnyView = { _, size in
        AnyView(Image(systemName: "star.fill").font(.system(size: size * 0.8)).foregroundStyle(Color(arisHex: 0xefdb8e)).frame(width: size, height: size))
    }
    /// A teammate's face; `still` holds its rest pose (picker tiles, roster rows).
    var face: (ArisCharacterLook, CGFloat, Bool) -> AnyView = { look, size, _ in
        AnyView(Circle().fill(Color(arisHexString: look.colorHex ?? "#41C4FF") ?? .blue).frame(width: size * 0.8, height: size * 0.8).frame(width: size, height: size))
    }
}

private struct ArtKey: EnvironmentKey { static let defaultValue = ArisSettingsArt() }

extension EnvironmentValues {
    var arisSettingsArt: ArisSettingsArt {
        get { self[ArtKey.self] }
        set { self[ArtKey.self] = newValue }
    }
}

struct ArisNotchPreview: View {
    @Environment(\.arisSettingsArt) private var art
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let plan: ArisNotchPreviewPlan
    /// Rises to play the stage again (들어 보기).
    var replay = 0

    @State private var current: ArisNotchPreviewPlan?
    @State private var hovering = false

    /// What is on screen: the plan as it animates toward a new one.
    private var shown: ArisNotchPreviewPlan { current ?? plan }
    /// AI 서비스's who notch spans the stage: the star has no room beside it.
    private var isWho: Bool { if case .who = plan.content { return true }; return false }

    private var stageHeight: CGFloat { CGFloat(plan.stageHeight) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let open = hovering && plan.opensOnHover
            let notchWidth = open ? 440 : shown.width
            let starLeft = ArisNotchPreviewPlan.starX(stageWidth: width, notchWidth: shown.width)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(arisHex: 0x18191d), Color(arisHex: 0x16171a)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.white.opacity(0.04)).frame(height: 24)
                    .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.04)).frame(height: 1) }
                Text(w("미리보기")).font(.system(size: 10, weight: .semibold)).tracking(0.2).foregroundStyle(.white.opacity(0.38))
                    .offset(x: 14, y: 5)
                if case .window(let circle) = shown.content {
                    ArisPreviewWindow(circle: circle, replay: replay).frame(width: width)
                }
                ArisPreviewNotch(plan: shown, open: open, replay: replay)
                    .frame(width: notchWidth, height: open ? 96 : shown.height, alignment: .center)
                    .offset(x: (width - notchWidth) / 2)
                art.star(20)
                    .frame(width: 20, height: 20)
                    .offset(x: starLeft, y: 5)
                    .opacity(open || isWho ? 0 : 1)
                    .animation(.easeOut(duration: 0.18), value: open)
                Text(w(shown.caption)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1).frame(width: width).offset(y: stageHeight - 14 - 16)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.18), value: shown.caption)
            }
            .frame(width: width, height: stageHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .onHover { inside in hovering = inside }
        }
        .frame(height: stageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(arisHex: 0xdfe2e8, palette.dark ? 0.07 : 0), lineWidth: 1))
        .shadow(color: .black.opacity(palette.dark ? 0 : 0.2), radius: 3, y: 1)
        .onAppear { current = plan }
        .onChange(of: plan) { old, next in
            let curve = ArisNotchPreviewPlan.motion(from: old.width, to: next.width) == .close ? ArisSettingsMotion.close : ArisSettingsMotion.open
            withAnimation(ArisSettingsMotion.reduced ? .easeOut(duration: 0.15) : curve) { current = next }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(w("노치 미리보기: \(w(plan.caption))"))
    }
}

/// The black notch: bottom corners 13 closed, 31 open; a soft drop shadow; what the page puts inside.
private struct ArisPreviewNotch: View {
    @Environment(\.arisWords) private var w
    let plan: ArisNotchPreviewPlan
    let open: Bool
    let replay: Int

    var body: some View {
        let radius = open || plan.wide ? 31.0 : 13.0
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        ZStack {
            shape.fill(.black)
            switch plan.content {
            case .wave: ArisPreviewWave(replay: replay)
            // The line Aris reads out, word by word in the page's wording.
            case .words(let words): ArisPreviewWords(words: w(words.joined(separator: " ")).split(separator: " ").map(String.init), replay: replay)
            case .skillAnswer(let tag, let line): ArisPreviewSkillAnswer(tag: w(tag), line: w(line))
            case .who(let names): ArisPreviewWho(names: names)
            default: EmptyView()
            }
            if plan.opensOnHover {
                Text(w("열린 노치")).font(.system(size: 13)).foregroundStyle(.white.opacity(0.78)).opacity(open ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: open)
            }
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(radius > 13 ? 0.28 : 0.25), radius: radius > 13 ? 6 : 3, y: radius > 13 ? 5 : 2)
        .animation(open ? ArisSettingsMotion.open : ArisSettingsMotion.close, value: open)
    }
}

/// AI 서비스: who thinks, listens and speaks, on one line 17 above the notch's bottom edge (13/500, names at .94, the
/// dots between at .24).
private struct ArisPreviewWho: View {
    let names: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                if index > 0 { Text("·").foregroundStyle(.white.opacity(0.24)) }
                Text(name).foregroundStyle(.white.opacity(0.94)).contentTransition(.opacity)
            }
        }
        .font(.system(size: 13, weight: .medium)).lineLimit(1).fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 17)
        .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.18), value: names)
    }
}

/// An answer that followed a skill: the tag (the notch's own, ArisSkillTag), then its first line.
private struct ArisPreviewSkillAnswer: View {
    let tag: String
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArisSkillTag(title: tag)
            Text(line).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.95)).lineLimit(1)
        }
        .padding(.horizontal, 18).padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The listening bars: a burst of voice, then still.
private struct ArisPreviewWave: View {
    let replay: Int
    @State private var bars = ArisNotchPreviewWave.rest

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { n in
                let bar = bars[n]
                RoundedRectangle(cornerRadius: 2).fill(Color(white: bar.grey / 255)).frame(width: 2.5, height: bar.height)
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: ArisNotchPreviewWave.tick), value: bars)
        .task(id: replay) {
            guard !ArisSettingsMotion.reduced else { return }
            for tick in 0..<ArisNotchPreviewWave.burstTicks {
                bars = ArisNotchPreviewWave.bars(tick: tick)
                try? await Task.sleep(for: .milliseconds(58))
                if Task.isCancelled { return }
            }
            bars = ArisNotchPreviewWave.rest
        }
    }
}

/// The spoken line, each word lighting from .38 to .97 as it is said, once.
private struct ArisPreviewWords: View {
    @Environment(\.arisSettingsStill) private var still
    let words: [String]
    let replay: Int
    @State private var lit: Int?
    @Environment(\.arisSettingsSpeed) private var speed

    var body: some View {
        ArisFlow(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word).font(.system(size: 15)).foregroundStyle(.white.opacity(index < (lit ?? (still ? 3 : 0)) ? 0.97 : 0.38))
                    .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.18), value: lit)
            }
        }
        .fixedSize()
        .padding(.horizontal, 22).padding(.vertical, 10)
        .task(id: "\(replay)-\(speed)") {
            guard !still else { return }
            lit = 0
            guard !ArisSettingsMotion.reduced else { lit = words.count; return }
            for count in 1...max(words.count, 1) {
                try? await Task.sleep(for: .seconds(ArisNotchPreviewPlan.wordInterval(speed: speed)))
                if Task.isCancelled { return }
                lit = count
            }
        }
    }
}

private struct SpeedKey: EnvironmentKey { static let defaultValue = 1.0 }

extension EnvironmentValues {
    /// Aris's speaking speed, for the preview's spoken line.
    var arisSettingsSpeed: Double {
        get { self[SpeedKey.self] }
        set { self[SpeedKey.self] = newValue }
    }
}

/// A window under the notch, and the circle drawn round part of it.
private struct ArisPreviewWindow: View {
    @Environment(\.arisSettingsStill) private var still
    let circle: Bool
    let replay: Int
    @State private var drawn: CGFloat?

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach([120.0, 160, 90], id: \.self) { w in RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.14)).frame(width: w, height: 6) }
                    }
                    .padding(.leading, 12).padding(.top, 14)
                }
                .frame(width: 220, height: 62)
                .padding(.top, 38)
            if circle {
                ArisInkLoop().trim(from: 0, to: drawn ?? (still ? 1 : 0))
                    .stroke(Color(red: 205 / 255, green: 225 / 255, blue: 1).opacity(0.9), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .shadow(color: Color(red: 120 / 255, green: 170 / 255, blue: 1).opacity(0.6), radius: 4)
                    .frame(width: 260, height: 90)
                    .padding(.top, 28)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: "\(circle)-\(replay)") {
            guard !still else { return }
            drawn = 0
            guard circle else { return }
            if ArisSettingsMotion.reduced { drawn = 1; return }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(ArisSettingsMotion.house(0.9)) { drawn = 1 }
        }
    }
}

/// A hand-drawn loop around the window's middle line.
private struct ArisInkLoop: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 260, sy = rect.height / 90
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(150, 14))
        path.addCurve(to: p(222, 48), control1: p(190, 16), control2: p(228, 28))
        path.addCurve(to: p(112, 76), control1: p(216, 70), control2: p(160, 80))
        path.addCurve(to: p(36, 38), control1: p(64, 72), control2: p(30, 58))
        path.addCurve(to: p(140, 12), control1: p(42, 18), control2: p(90, 8))
        return path
    }
}
