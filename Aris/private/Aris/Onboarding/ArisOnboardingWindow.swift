//
//  ArisOnboardingWindow.swift
//  Aris
//
//  Aris's setup window after the intro (mockups/onboarding2/css/window.css, js/appwin.js): 1080 × 710 where the
//  display has room for it (ArisOnboardingStage.fit: narrower and shorter on a small display, never off its edge),
//  radius 20, light or dark with the app's theme. The progress rail at the top (ArisSetupRail), the pages in two 50%
//  columns, the 128-pt glow strip at the bottom, 뒤로 bottom-left (72 × 38 r11). Its entrance is a prepared handoff:
//  the content scales 1.3 → 1 over 920 ms (.16, 1, .3, 1) while the window fades in over 220 ms; pages cross-fade in
//  .3 s; it leaves in 240 ms. For E's rules, also a dim ✕ (top right) and 나중에 할게요 (bottom right).
//  An ordinary window (level 0) except while it rides over the lifting veil, so macOS's alerts and System Settings
//  always come above it.
//

import AppKit
import SwiftUI

final class ArisOnboardingSetupWindow: NSWindow {
    /// `fit`: its size and place on the display that shows it (ArisOnboardingStage.fit(in: that display's visible frame)).
    init(guide: ArisOnboardingGuide, fit: ArisOnboardingStage.Fit, placed: Bool) {
        super.init(contentRect: CGRect(origin: .zero, size: fit.size), styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        title = ArisOnboardingCopy.windowTitle
        collectionBehavior = [.moveToActiveSpace]
        let host = NSHostingView(rootView: ArisSetupRoot(guide: guide))
        host.wantsLayer = true
        host.layer?.cornerRadius = 20
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        contentView = host
        // Centred between the menu bar and the Dock; with no display to measure, wherever macOS centres it.
        if placed { setFrameOrigin(fit.origin) } else { center() }
    }

    /// The display changed under it: the new size and place.
    func apply(_ fit: ArisOnboardingStage.Fit) {
        setFrame(CGRect(origin: fit.origin, size: fit.size), display: true)
        invalidateShadow()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// In over 220 ms ease-out (the content's own 920 ms scale runs in SwiftUI); over the veil while it lifts.
    func present(handingOff: Bool, reduced: Bool, activate: Bool) {
        level = NSWindow.Level(rawValue: ArisOnboardingStage.windowLevel(handingOff: handingOff))
        alphaValue = 0
        if activate {
            makeKeyAndOrderFront(nil)
            bringForward()
        } else {
            // A quiet resume: in front of the other apps' windows, without taking the keyboard from them.
            orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? 0.15 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.invalidateShadow() }
    }

    /// In front of every app's windows, with the keyboard. macOS may refuse a plain activation when another app is in
    /// front (a launch from a terminal, the app that was active before a system prompt): the window is ordered in
    /// front regardless and Aris activated over the others.
    func bringForward() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Out in 240 ms ease-out (ArisOnboardingStage.windowOut): quicker than it came, so the notch that opens next is
    /// what the eye lands on.
    func dismiss(reduced: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? ArisOnboardingStage.windowOutReduced : ArisOnboardingStage.windowOut
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 0
        }
    }
}

struct ArisSetupRoot: View {
    @ObservedObject var guide: ArisOnboardingGuide
    /// Settings' 라이트 / 다크 / 자동 (Defaults stores the string as is).
    @AppStorage("arisSettingsTheme") private var theme = "auto"
    @Environment(\.colorScheme) private var systemScheme

    private var scheme: ColorScheme { theme == "light" ? .light : theme == "dark" ? .dark : systemScheme }

    var body: some View {
        ArisSetupContent(guide: guide, palette: ArisSetupPalette(dark: scheme == .dark))
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
    }
}

struct ArisSetupContent: View {
    @ObservedObject var guide: ArisOnboardingGuide
    let palette: ArisSetupPalette
    @Environment(\.arisOnboardingStill) private var settled
    @State private var entered = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(palette.background)
            if let model = guide.model {
                ArisSetupPages(guide: guide, model: model, palette: palette)
                    .scaleEffect(entered || settled || guide.reduced ? 1 : 1.3)
            }
            LinearGradient(stops: palette.glow, startPoint: .bottom, endPoint: .top)
                .frame(height: 128)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            if let model = guide.model { ArisSetupRail(guide: guide, model: model, palette: palette) }
            chrome
        }
        .frame(width: guide.fit.layout.width, height: guide.fit.layout.height)
        .foregroundStyle(palette.fg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.windowLine, lineWidth: 0.5))
        // A display too small for even the smallest layout draws the whole window smaller.
        .scaleEffect(guide.fit.scale, anchor: .topLeading)
        .frame(width: guide.fit.size.width, height: guide.fit.size.height, alignment: .topLeading)
        .onAppear {
            guard !entered else { return }
            withAnimation(guide.reduced ? nil : ArisOBCurve.handoff) { entered = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ArisOnboardingCopy.windowTitle)
    }

    @ViewBuilder
    private var chrome: some View {
        let backShown = guide.model?.flow.backShown ?? false
        ZStack {
            if backShown {
                Button(ArisOnboardingCopy.back) { guide.back() }
                    .buttonStyle(ArisBackButtonStyle(palette: palette))
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                    .padding([.leading, .bottom], 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.opacity)
            }
            if guide.phase == .setup || guide.phase == .handoff {
                Button(ArisOnboardingCopy.later) { guide.close(.later) }
                    .buttonStyle(ArisQuietButtonStyle(palette: palette, size: 13, weight: .medium))
                    .padding(.trailing, 28).padding(.bottom, 30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .accessibilityHint(ArisOnboardingCopy.laterHint)
            }
            Button { guide.close(.dismissed) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(palette.back))
                    .contentShape(Circle())
            }
            .buttonStyle(ArisQuietButtonStyle(palette: palette, size: 10, weight: .bold))
            // Never the keyboard's: with macOS's keyboard navigation on, the × (top right) was the window's first key
            // view, and a stray Space closed the whole setup for good (third VM run, new install, bug 3). It takes a
            // click (and VoiceOver's press); the keys start at the page's own buttons.
            .focusable(false)
            .padding(.top, 48).padding(.trailing, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .accessibilityLabel(ArisOnboardingCopy.close)
            // The × puts the setup off (ArisOnboarding.closing): the rest comes back the next time Aris is opened.
            .accessibilityHint(ArisOnboardingCopy.laterHint)
        }
        .animation(ArisOBCurve.card, value: backShown)
    }
}

/// The pages, cross-fading .3 s.
struct ArisSetupPages: View {
    @ObservedObject var guide: ArisOnboardingGuide
    @ObservedObject var model: ArisOnboardingModel
    let palette: ArisSetupPalette

    var body: some View {
        ZStack {
            switch guide.page {
            case .permissions: ArisPermissionsPage(guide: guide, model: model, palette: palette).transition(.opacity)
            case .ask: ArisTryPage(guide: guide, model: model, palette: palette).transition(.opacity)
            case .brain: ArisBrainPage(guide: guide, palette: palette).transition(.opacity)
            case .wake: ArisWakePage(guide: guide, palette: palette).transition(.opacity)
            case .dictation: ArisDictationPage(guide: guide, palette: palette).transition(.opacity)
            }
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The layout's columns: two 50% columns, both centred; the left one padded 48.
struct ArisSetupColumns<Left: View, Right: View>: View {
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    var body: some View {
        HStack(spacing: 0) {
            left.padding(.horizontal, 48).frame(maxWidth: .infinity)
            right.frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
