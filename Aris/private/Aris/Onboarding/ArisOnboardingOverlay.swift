//
//  ArisOnboardingOverlay.swift
//  Aris
//
//  The full-screen veil on the notch's display (mockups/onboarding2: index.html .screen, css/base.css, scenes.css): a
//  borderless, transparent panel the size of that display only, on every Space and over full-screen apps, at the level
//  ArisOnboardingStage.overlay gives it (26 while it leads; −1 and click-through whenever Aris isn't active, and from the
//  handoff on). On it, as pure functions of the guide's clock: the veil (its stops and vignette), the
//  drifting light, the star (the sunrise, the lockup, the flight with its trail), the wordmark, the kicker and tagline,
//  시작하기, the captions and the name, the mute (bottom-left), 건너뛰기 (bottom-right, from 12 s) and the ✕.
//  Always dark, whatever the system's appearance.
//

import AppKit
import SwiftUI

final class ArisOnboardingOverlayWindow: NSPanel {
    init(screen: NSScreen, guide: ArisOnboardingGuide) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        level = NSWindow.Level(rawValue: ArisOnboardingStage.overlayLevel)
        title = ArisOnboardingCopy.overlayLabel
        contentView = NSHostingView(rootView: ArisOnboardingOverlayView(guide: guide))
        place(on: screen)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Covers exactly this display (the others stay as they are).
    func place(on screen: NSScreen) { setFrame(screen.frame, display: true) }
}

struct ArisOnboardingOverlayView: View {
    @ObservedObject var guide: ArisOnboardingGuide
    /// The offscreen renders pin the clock (nil: the media clock).
    var frozen: Double?

    private var running: Bool { [.intro, .flight, .talk, .handoff].contains(guide.phase) && frozen == nil }

    var body: some View {
        TimelineView(.animation(paused: !running)) { _ in
            let now = frozen ?? ArisOnboardingGuide.now()
            ArisOnboardingScene(guide: guide, now: now)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .opacity(guide.active ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: guide.active)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ArisOnboardingCopy.overlayLabel)
    }
}

/// One frame of the veil's scene.
struct ArisOnboardingScene: View {
    @ObservedObject var guide: ArisOnboardingGuide
    let now: Double

    private typealias Score = ArisOnboardingScore
    private typealias M = ArisOnboardingMotion

    var body: some View {
        let L = guide.layout, veil = guide.veil(at: now), t = guide.storyMs(now)
        let intro = introLayers(t: t, L: L)
        ZStack(alignment: .topLeading) {
            ArisOnboardingVeil().opacity(veil)
            ArisOnboardingAtmos(t: t / 1000).opacity(veil).allowsHitTesting(false)
            tagline(intro.tagline, L: L)
            wordmark(intro.letters, L: L)
            ArisGlassPill(title: ArisOnboardingCopy.start, turning: guide.phase == .intro) { guide.startTapped() }
                .scaleEffect(intro.cta.scale)
                .offset(y: intro.cta.y)
                .opacity(intro.cta.opacity)
                .position(x: L.ctaX + 140, y: L.ctaY + 34)
                .allowsHitTesting(guide.phase == .intro && intro.cta.opacity > 0.6)
                .accessibilityHidden(intro.cta.opacity < 0.6)
            starLayer(t: t)
            ArisOnboardingTalkView(guide: guide, now: now)
            chrome(veil: veil, t: t)
        }
        .frame(width: guide.screenSize.width, height: guide.screenSize.height, alignment: .topLeading)
    }

    // MARK: - The intro's layers (frozen and fading once the star is thrown)

    private struct Intro {
        var tagline: Score.Fade
        var letters: [Score.Letter]
        var cta: Score.Fade
    }

    private func introLayers(t: Double, L: Score.Layout) -> Intro {
        let gone = Intro(tagline: .init(opacity: 0, y: 0, scale: 1), letters: Array(repeating: .init(opacity: 0, blur: 0, dx: 0), count: 4),
                         cta: .init(opacity: 0, y: 0, scale: 1))
        switch guide.phase {
        case .intro:
            let f = Score.frame(at: t, layout: L, reduced: guide.reduced)
            return Intro(tagline: f.tagline, letters: f.letters, cta: f.cta)
        case .flight:
            guard let flight = guide.flight else { return gone }
            let f = Score.frame(at: flight.tc, layout: L, reduced: guide.reduced), dt = (now - flight.start) * 1000
            // 200 ms quick exits; the letters leave right to left, 30 ms apart, blurring (main.js startFlight).
            let e = M.exit(M.span(dt, 0, 200))
            let letters = f.letters.enumerated().map { i, l -> Score.Letter in
                let d = Double(3 - i) * 30, p = M.exit(M.span(dt, d, d + 220))
                return Score.Letter(opacity: l.opacity * (1 - p), blur: 6 * p, dx: -10 * p)
            }
            return Intro(tagline: .init(opacity: f.tagline.opacity * (1 - e), y: f.tagline.y, scale: f.tagline.scale), letters: letters,
                         cta: .init(opacity: f.cta.opacity * (1 - e), y: -7 * e, scale: 1 - 0.02 * e))
        default: return gone
        }
    }

    private func tagline(_ f: Score.Fade, L: Score.Layout) -> some View {
        let w = L.width, size = min(54, max(29, w * 0.042))
        return VStack(spacing: 10) {
            Text(ArisOnboardingCopy.kicker)
                .font(.system(size: 11, weight: .semibold))
                .tracking(3.3)
                .foregroundStyle(Color(.sRGB, red: 1, green: 246 / 255, blue: 226 / 255, opacity: 0.54))
            Text(ArisOnboardingCopy.tagline)
                .font(.system(size: size, weight: .regular))
                .tracking(-0.035 * size)
                .foregroundStyle(.white.opacity(0.92))
        }
        .multilineTextAlignment(.center)
        .frame(width: min(760, w * 0.88))
        .fixedSize(horizontal: false, vertical: true)
        .shadow(color: .black.opacity(0.38), radius: 15, y: 8)
        .scaleEffect(f.scale)
        .opacity(f.opacity)
        .position(x: w / 2, y: L.height / 2 - 72 + f.y)
        .allowsHitTesting(false)
        .accessibilityHidden(f.opacity < 0.5)
    }

    private func wordmark(_ letters: [Score.Letter], L: Score.Layout) -> some View {
        HStack(spacing: 0) {
            ForEach(Array("Aris".enumerated()), id: \.offset) { i, ch in
                let l = letters[i]
                Text(String(ch))
                    .font(.system(size: 76, weight: .semibold))
                    .tracking(-0.045 * 76)
                    .foregroundStyle(Color(.sRGB, red: 246 / 255, green: 246 / 255, blue: 248 / 255, opacity: 1))
                    .blur(radius: l.blur > 0.05 ? l.blur : 0)
                    .offset(x: l.dx)
                    .opacity(l.opacity)
            }
        }
        .fixedSize()
        .frame(height: 76)
        .offset(x: L.wordX, y: L.wordY)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Aris")
        .accessibilityHidden(letters.allSatisfy { $0.opacity < 0.5 })
    }

    // MARK: - The star and its light

    private func starLayer(t: Double) -> some View {
        let state = heroState(t: t)
        return ZStack(alignment: .topLeading) {
            if let hero = state.hero {
                ArisOnboardingHero(hero: hero)
            }
            ArisOnboardingStarlight(glint: state.glint, x: state.hero?.x ?? 0, y: state.hero?.y ?? 0, size: state.size, trail: state.trail)
        }
        .allowsHitTesting(guide.phase == .intro)
    }

    private struct HeroState {
        var hero: Score.Hero?
        var glint: Double = -1
        var size: Double = 0
        var trail: [Score.TrailPoint] = []
    }

    private func heroState(t: Double) -> HeroState {
        let L = guide.layout
        switch guide.phase {
        case .intro:
            let f = Score.frame(at: t, layout: L, reduced: guide.reduced)
            return HeroState(hero: f.hero, glint: f.glint, size: f.size)
        case .flight:
            guard let flight = guide.flight else { return HeroState() }
            let dt = (now - flight.start) * 1000
            if guide.reduced {
                let hero = Score.Hero(x: flight.from.x, y: flight.from.y, scale: 1, opacity: max(0, 1 - dt / 150))
                return HeroState(hero: hero.opacity > 0 ? hero : nil, size: L.vis)
            }
            guard dt < Score.flightTimes.land else { return HeroState() }
            let hero = Score.flight(at: dt, from: flight.from, to: flight.to, screen: guide.screenSize)
            return HeroState(hero: hero, size: L.vis * hero.scale,
                             trail: Score.trail(at: dt, from: flight.from, to: flight.to, screen: guide.screenSize, size: L.vis))
        default:
            return HeroState()
        }
    }

    // MARK: - Mute, 건너뛰기, ✕

    private func chrome(veil: Double, t: Double) -> some View {
        let skip = ArisOnboardingStage.skipShown(phase: guide.phase, elapsedMs: guide.reduced ? t * 6 : t)
        let mute = ArisOnboardingStage.muteShown(phase: guide.phase, veil: veil)
        return ZStack {
            Button { guide.setMuted(!guide.muted) } label: {
                Image(systemName: guide.muted ? "speaker.slash" : "speaker.wave.2")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 28, height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(ArisOverlayChromeStyle(rest: 0.42, hover: 0.85))
            .padding([.leading, .bottom], 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .opacity(mute ? 1 : 0)
            .allowsHitTesting(mute)
            .animation(ArisOBCurve.settle(0.5), value: mute)
            .accessibilityLabel(guide.muted ? ArisOnboardingCopy.unmute : ArisOnboardingCopy.mute)
            .accessibilityHidden(!mute)

            Button { guide.skipTapped() } label: {
                Text(ArisOnboardingCopy.skip).font(.system(size: 11.5, weight: .medium)).padding(4).contentShape(Rectangle())
            }
            .buttonStyle(ArisOverlayChromeStyle(rest: 0.48, hover: 0.9))
            .padding([.trailing, .bottom], 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(skip ? 1 : 0)
            .allowsHitTesting(skip)
            .animation(ArisOBCurve.settle(0.5), value: skip)
            .accessibilityHint(ArisOnboardingCopy.skipHint)
            .accessibilityHidden(!skip)

            if ArisOnboardingStage.exitShown(phase: guide.phase) {
                Button { guide.close(.dismissed) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.06)))
                        .contentShape(Circle())
                }
                .buttonStyle(ArisOverlayChromeStyle(rest: 0.45, hover: 0.85))
                .padding(.top, 52).padding(.trailing, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityLabel(ArisOnboardingCopy.close)
                // The ✕ puts the setup off (ArisOnboarding.closing): the rest comes back the next time Aris is opened.
                .accessibilityHint(ArisOnboardingCopy.laterHint)
            }
        }
    }
}

/// White at a resting opacity, brighter on hover (160 ms).
private struct ArisOverlayChromeStyle: ButtonStyle {
    let rest: Double
    let hover: Double

    func makeBody(configuration: Configuration) -> some View { Label(configuration: configuration, rest: rest, hoverTo: hover) }

    private struct Label: View {
        let configuration: Configuration
        let rest: Double
        let hoverTo: Double
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.white.opacity(hovering || configuration.isPressed ? hoverTo : rest))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.16), value: hovering)
        }
    }
}

// MARK: - The veil and the drifting light

/// The veil's stops (navy near-black, .54 at the top → .94 at the bottom) and its vignette.
struct ArisOnboardingVeil: View {
    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: Color(.sRGB, red: 0, green: 2 / 255, blue: 8 / 255, opacity: 0.54), location: 0),
                                   .init(color: Color(.sRGB, red: 0, green: 3 / 255, blue: 10 / 255, opacity: 0.64), location: 0.24),
                                   .init(color: Color(.sRGB, red: 0, green: 4 / 255, blue: 12 / 255, opacity: 0.77), location: 0.5),
                                   .init(color: Color(.sRGB, red: 0, green: 4 / 255, blue: 14 / 255, opacity: 0.87), location: 0.76),
                                   .init(color: Color(.sRGB, red: 0, green: 3 / 255, blue: 12 / 255, opacity: 0.94), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                RadialGradient(stops: [.init(color: Color(.sRGB, red: 3 / 255, green: 7 / 255, blue: 14 / 255, opacity: 0), location: 0.22),
                                       .init(color: Color(.sRGB, red: 2 / 255, green: 6 / 255, blue: 16 / 255, opacity: 0.025), location: 0.56),
                                       .init(color: Color(.sRGB, red: 1 / 255, green: 5 / 255, blue: 15 / 255, opacity: 0.11), location: 1)],
                               center: UnitPoint(x: 0.5, y: 0.48), startRadius: 0,
                               endRadius: hypot(geo.size.width, geo.size.height) / 2)
            }
        }
        .allowsHitTesting(true)
        .accessibilityHidden(true)
    }
}

/// The lighting as the mockup tunes it for glow D: screen-blended elliptical spots drifting on slow incommensurate
/// periods; 30 frames a second is plenty.
struct ArisOnboardingAtmos: View {
    let t: Double

    private static let indigo = (60.0, 68.0, 126.0), blue = (54.0, 106.0, 179.0), olive = (99.0, 94.0, 61.0)

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, m = max(w, h)
            func color(_ c: (Double, Double, Double), _ a: Double) -> Color { Color(.sRGB, red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, opacity: a) }
            func spot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: (Double, Double, Double), _ a: Double, _ squash: CGFloat) {
                var g = ctx
                g.translateBy(x: x, y: y)
                g.scaleBy(x: 1, y: squash)
                let rect = CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)
                g.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(stops: [.init(color: color(c, a), location: 0), .init(color: color(c, a * 0.44), location: 0.42),
                                                                                    .init(color: color(c, 0), location: 1)]),
                                                                     center: .zero, startRadius: 0, endRadius: r))
            }
            let mixed = (60 + (54 - 60) * 0.38, 68 + (106 - 68) * 0.38, 126 + (179 - 126) * 0.38)
            spot(0.5 * w, -0.15 * h, max(0.82 * w, h), mixed, 0.025 + 0.007 * sin(0.32 * t), 0.48)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: 0.25 * h)),
                     with: .linearGradient(Gradient(stops: [.init(color: Color(.sRGB, red: 90 / 255, green: 140 / 255, blue: 220 / 255, opacity: 0.032), location: 0),
                                                            .init(color: Color(.sRGB, red: 70 / 255, green: 115 / 255, blue: 205 / 255, opacity: 0.014), location: 0.64),
                                                            .init(color: .clear, location: 1)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: 0.25 * h)))
            spot(w * (0.31 + 0.02 * sin(0.19 * t)), 0.49 * h, 0.62 * m, Self.indigo, 0.04 + 0.01 * sin(0.43 * t), 0.78)
            spot(0.76 * w, 1.05 * h, 0.58 * m, Self.blue, 0.021, 0.56)
            spot(0.03 * w, 0.98 * h, 0.46 * m, Self.olive, 0.01, 0.68)
        }
        .blendMode(.screen)
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

// MARK: - The star

/// The live star at its 96-pt box, moved by the score: scale, on-screen defocus, squash and stretch along its path.
struct ArisOnboardingHero: View {
    let hero: ArisOnboardingScore.Hero

    var body: some View {
        let anchor: UnitPoint = hero.anchor == .bottom ? .bottom : hero.anchor == .top ? .top : .center
        ArisOnboardingStar(size: ArisOnboardingScore.base, interactive: true)
            // CSS filters run in the element's own space: divided by the scale, the defocus is constant on screen.
            .blur(radius: hero.blur > 0.05 ? hero.blur / max(hero.scale, 0.01) : 0)
            .rotationEffect(.radians(-hero.angle))
            .scaleEffect(x: hero.sx, y: hero.sy, anchor: anchor)
            .rotationEffect(.radians(hero.angle))
            .scaleEffect(hero.scale)
            .opacity(hero.opacity)
            .position(x: hero.x, y: hero.y)
            .accessibilityHidden(true)
    }
}

/// The star's light (glow D "글린트"): one small four-point glint on the top tip — a 2.5-pt core and two tapered
/// hairlines (22 and 15 at the peak) scaled by sin(πp) and turning 0 → 15° over its 700 ms, white, not gold; and, when
/// it's thrown, a tapered ribbon of its last 170 ms like a shooting star, warm at the head, gone at the tail.
struct ArisOnboardingStarlight: View {
    let glint: Double
    let x: Double
    let y: Double
    let size: Double
    let trail: [ArisOnboardingScore.TrailPoint]

    var body: some View {
        Canvas { ctx, _ in
            ctx.blendMode = .plusLighter
            drawTrail(&ctx)
            if glint > 0 && glint < 1 { drawGlint(&ctx) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawGlint(_ ctx: inout GraphicsContext) {
        let e = sin(Double.pi * glint), angle = 15 * Double.pi / 180 * glint
        var g = ctx
        g.translateBy(x: x - size * 0.02, y: y - size * 0.5)
        g.rotate(by: .radians(angle))
        let r = 2.5 + 3 * e
        g.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
               with: .radialGradient(Gradient(colors: [.white.opacity(0.95 * e), .white.opacity(0)]), center: .zero, startRadius: 0, endRadius: r))
        func ray(_ dx: Double, _ dy: Double, _ length: Double, _ width: Double) {
            var p = Path()
            p.move(to: CGPoint(x: -dy * width, y: dx * width))
            p.addLine(to: CGPoint(x: dx * length, y: dy * length))
            p.addLine(to: CGPoint(x: dy * width, y: -dx * width))
            p.closeSubpath()
            g.fill(p, with: .linearGradient(Gradient(colors: [.white.opacity(0.9 * e), .white.opacity(0)]), startPoint: .zero,
                                            endPoint: CGPoint(x: dx * length, y: dy * length)))
        }
        ray(0, -1, 22 * e, 1.1)
        ray(0, 1, 22 * e, 1.1)
        ray(-1, 0, 15 * e, 0.9)
        ray(1, 0, 15 * e, 0.9)
    }

    private func drawTrail(_ ctx: inout GraphicsContext) {
        guard trail.count >= 3 else { return }
        let n = trail.count - 1
        var left: [CGPoint] = [], right: [CGPoint] = []
        for (i, p) in trail.enumerated() {
            let a = trail[max(0, i - 1)], b = trail[min(n, i + 1)]
            var nx = -(b.y - a.y), ny = b.x - a.x
            let length = max(hypot(nx, ny), 1e-6)
            nx /= length
            ny /= length
            let hw = p.size * 0.2 * (1 - Double(i) / Double(n))
            left.append(CGPoint(x: p.x + nx * hw, y: p.y + ny * hw))
            right.append(CGPoint(x: p.x - nx * hw, y: p.y - ny * hw))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        let head = trail[0], tail = trail[n]
        ctx.fill(path, with: .linearGradient(Gradient(stops: [.init(color: Color(.sRGB, red: 1, green: 246 / 255, blue: 222 / 255, opacity: 0.5), location: 0),
                                                             .init(color: Color(.sRGB, red: 239 / 255, green: 219 / 255, blue: 142 / 255, opacity: 0.22), location: 0.35),
                                                             .init(color: Color(.sRGB, red: 239 / 255, green: 219 / 255, blue: 142 / 255, opacity: 0), location: 1)]),
                                             startPoint: CGPoint(x: head.x, y: head.y), endPoint: CGPoint(x: tail.x, y: tail.y)))
    }
}
