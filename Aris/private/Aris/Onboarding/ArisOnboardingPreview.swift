//
//  ArisOnboardingPreview.swift
//  Aris
//
//  The permissions page's preview stage (mockups/onboarding2/js/dialogs.js, css/macos.css: the stage
//  always shows the exact system UI that comes next): a faithful macOS alert and System Settings › 개인정보 보호 및 보안
//  pane, in the onboarding's language and the window's appearance, looped with a cursor pressing the right button.
//  What comes next for real: the mic's own alert (then speech recognition's); Accessibility's and Screen Recording's
//  System Settings lists (no alert: Aris opens the list and docks the drag panel under it). The list is drawn as it
//  really is at that moment: without Aris in it, its + and − under it, and the helper panel docked below with the row
//  to drag; the loop drags that row into the list, where Aris then appears with its switch off, and turns the switch
//  on (VM run 2026-11-11, 2.2: the picture showed Aris already in the list). Aris's icon in the list and the panel is
//  the app's own, the one the real list shows; the alert's is the live star, paused. Reduce Motion: the alert, its
//  button pressed; the list, a still frame of the drag. The picture never leaves the stage empty: which one shows, and
//  the loop's score, are ArisOnboardingPreviewScore's.
//

import SwiftUI

/// The stage: 500 × 400 r16 on the page's right, the preview looping in it.
struct ArisPermissionStage: View {
    let picture: ArisStagePicture
    let palette: ArisSetupPalette
    let reduced: Bool
    /// The offscreen renders pin the loop's time.
    @Environment(\.arisOnboardingPreviewTime) private var frozen
    @State private var start = Date()
    @State private var yes: CGRect = .zero
    @State private var list: CGRect = .zero
    @State private var chip: CGRect = .zero

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.stage)
            switch picture {
            case .preview(let card, let held):
                TimelineView(.animation(paused: reduced || held || frozen != nil)) { context in
                    let score = ArisPreviewScore(kind: .of(card))
                    // Reduce Motion: the list is one still frame of the drag. macOS's own alert is up: this one is still.
                    let still = held ? ArisPreviewScore.alertStill : reduced && score.kind == .settingsOnly ? ArisPreviewScore.dragStill : nil
                    let elapsed = context.date.timeIntervalSince(start) * 1000
                    let t = frozen ?? still ?? elapsed.truncatingRemainder(dividingBy: score.period)
                    // After its first round (or as a still) the picture is simply there: nothing fades it out and in.
                    room(card, t: t, entered: frozen != nil || still != nil || elapsed >= score.period)
                }
                .id(card)
                .transition(.opacity)
                .onAppear { start = Date() }
            case .star:
                ArisOnboardingStar(size: 88, interactive: true, spot: .stage).transition(.opacity)
            }
        }
        // One picture gives way to the next in a short cross-fade, so the stage is not blank between two cards.
        .animation(reduced ? ArisOBCurve.fade : ArisOBCurve.card, value: picture)
        .frame(maxWidth: 500)
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .coordinateSpace(name: "stage")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ArisOnboardingCopy.stageLabel)
    }

    private func room(_ card: ArisPermissionCard, t: Double, entered: Bool) -> some View {
        let score = ArisPreviewScore(kind: .of(card))
        // The list alone is drawn from the score even under Reduce Motion (one still frame of it).
        let scored = !reduced || score.kind == .settingsOnly
        // Aris's row in the list is the second one: where the carried row is dropped, and where its switch is.
        let row = list.minY + ArisMacSettings.rowHeight * 1.5
        let cursor = score.cursor(t, start: CGPoint(x: 400, y: 270), yes: CGPoint(x: yes.minX + yes.width * 0.55, y: yes.minY + yes.height * 0.55),
                                  toggle: CGPoint(x: list.maxX - 24, y: row + 2),
                                  chip: CGPoint(x: chip.minX + 46, y: chip.midY + 2), slot: CGPoint(x: list.minX + 46, y: row + 2))
        return ZStack {
            if score.kind != .alertOnly {
                VStack(spacing: -ArisMacDragPanel.overlap) {
                    ArisMacSettings(card: card, dark: palette.dark, on: score.toggleOn(t), added: score.added(t), listFrame: $list)
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(palette.imageLine, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 15, y: 10)
                    ArisMacDragPanel(dark: palette.dark, chipFrame: $chip)
                }
                .scaleEffect(scored ? score.settingsScale(t, entered: entered) : 1)
                .opacity(scored ? score.settingsOpacity(t, entered: entered) : 0)
                if score.carrying(t) {
                    // The row in the cursor's hand.
                    ArisMacDragPanel.Row(dark: palette.dark, carried: true)
                        .frame(width: 150)
                        .position(x: cursor.point.x + 58, y: cursor.point.y + 6)
                }
            }
            if score.kind != .settingsOnly {
                ArisMacAlert(card: card, dark: palette.dark, pressed: reduced || score.yesDown(t), yesFrame: $yes)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(palette.imageLine, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 15, y: 10)
                    .scaleEffect(0.9231 * (reduced ? 1 : score.alertScale(t, entered: entered)))
                    .opacity(reduced ? 1 : score.alertOpacity(t, entered: entered))
            }
            if scored {
                ArisMacCursor()
                    .scaleEffect(cursor.scale, anchor: .topLeading)
                    .frame(width: 18, height: 26)
                    .position(x: cursor.point.x + 9, y: cursor.point.y + 13)
                    .opacity(cursor.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// macOS's TCC alert as Sequoia draws it: 260 wide, r12, the app icon 64, title 13 semibold, body 11, two 28-high
/// buttons, the default one blue.
struct ArisMacAlert: View {
    let card: ArisPermissionCard
    let dark: Bool
    var pressed = false
    @Binding var yesFrame: CGRect

    var body: some View {
        let mic = card == .mic
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ArisOBColor.hex(0x17171a))
                ArisOnboardingStar(size: 42, paused: true)
            }
            .frame(width: 64, height: 64)
            .padding(.bottom, 10)
            Text(mic ? ArisOnboardingCopy.alertMicTitle : ArisOnboardingCopy.alertScreenTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineSpacing(3)
            Text(mic ? ArisOnboardingCopy.alertMicBody : ArisOnboardingCopy.alertSettingsBody)
                .font(.system(size: 11))
                .lineSpacing(3)
                .foregroundStyle(dark ? .white.opacity(0.74) : .black.opacity(0.78))
                .padding(.top, 6)
            HStack(spacing: 8) {
                button(mic ? ArisOnboardingCopy.alertDontAllow : ArisOnboardingCopy.alertDeny, primary: false)
                button(mic ? ArisOnboardingCopy.alertAllow : ArisOnboardingCopy.alertOpenSettings, primary: true)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { yesFrame = $0 }
            }
            .padding(.top, 16)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(dark ? ArisOBColor.hex(0xf2f2f2) : ArisOBColor.hex(0x111111))
        .padding(EdgeInsets(top: 20, leading: 16, bottom: 16, trailing: 16))
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(dark ? Color(.sRGB, red: 42 / 255, green: 42 / 255, blue: 44 / 255, opacity: 0.97)
                                                                                 : Color(.sRGB, red: 236 / 255, green: 236 / 255, blue: 236 / 255, opacity: 0.97)))
    }

    private func button(_ title: String, primary: Bool) -> some View {
        Text(title)
            .font(.system(size: 13))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(primary ? .white : dark ? ArisOBColor.hex(0xf2f2f2) : ArisOBColor.hex(0x111111))
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(primary ? ArisOBColor.macBlue : dark ? .white.opacity(0.14) : .black.opacity(0.07)))
            .brightness(primary && pressed ? -0.14 : 0)
    }
}

/// System Settings › 개인정보 보호 및 보안 › (the list), compact: 470 × 296, the sidebar 132, another app already on, the
/// list's + and − under it, and Aris with its switch only once it has been added (`added`), as in the real list.
struct ArisMacSettings: View {
    let card: ArisPermissionCard
    let dark: Bool
    var on = false
    var added = true
    @Binding var listFrame: CGRect

    static let rowHeight: CGFloat = 40

    var body: some View {
        let screen = card == .screen
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Circle().fill(ArisOBColor.hex(0xff5f57))
                    Circle().fill(ArisOBColor.hex(0xfebc2e))
                    Circle().fill(ArisOBColor.hex(0x28c840))
                }
                .frame(height: 11)
                .padding(.leading, 4)
                .padding(.bottom, 18)
                ForEach(Array(ArisOnboardingCopy.settingsSidebar.enumerated()), id: \.offset) { i, item in
                    Text(item)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundStyle(i == 2 ? (dark ? .white : ArisOBColor.hex(0x111111)) : (dark ? .white.opacity(0.7) : .black.opacity(0.72)))
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(i == 2 ? (dark ? .white.opacity(0.12) : .black.opacity(0.1)) : .clear))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14).padding(.horizontal, 8)
            .frame(width: 132)
            .frame(maxHeight: .infinity)
            .background(dark ? ArisOBColor.hex(0x1f1f21) : ArisOBColor.hex(0xe9e9ec))
            VStack(alignment: .leading, spacing: 0) {
                Text("‹ " + (screen ? ArisOnboardingCopy.paneScreen : ArisOnboardingCopy.paneAccessibility))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 2).padding(.bottom, 12)
                Text(screen ? ArisOnboardingCopy.paneScreenDesc : ArisOnboardingCopy.paneAccessibilityDesc)
                    .font(.system(size: 11))
                    .lineSpacing(3)
                    .foregroundStyle(dark ? .white.opacity(0.58) : .black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                VStack(spacing: 0) {
                    row(icon: AnyView(RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [ArisOBColor.hex(0xa7a7ad), ArisOBColor.hex(0x8a8a90)], startPoint: .top, endPoint: .bottom))),
                        name: ArisOnboardingCopy.paneOtherApp, on: true, aris: false)
                    if added {
                        hairline
                        // The app's own icon, as the real list shows it.
                        row(icon: AnyView(ArisOwnAppIcon(size: 24)), name: "Aris", on: on, aris: true).transition(.opacity)
                    }
                    hairline
                    // The list's own + and −: the other way to add Aris.
                    HStack(spacing: 12) {
                        Text("+")
                        Rectangle().fill(dark ? .white.opacity(0.12) : .black.opacity(0.12)).frame(width: 0.5, height: 12)
                        Text("−")
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(dark ? .white.opacity(0.55) : .black.opacity(0.5))
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(dark ? .white.opacity(0.05) : .white))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(dark ? .white.opacity(0.1) : .black.opacity(0.12), lineWidth: 0.5))
                // Aris's row leaves the list as the loop starts over (the picture itself stays).
                .animation(.easeOut(duration: 0.15), value: added)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { listFrame = $0 }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(dark ? ArisOBColor.hex(0xeeeeee) : ArisOBColor.hex(0x111111))
        .frame(width: 470, height: 296)
        .background(dark ? ArisOBColor.hex(0x262628) : ArisOBColor.hex(0xfbfbfb))
    }

    private var hairline: some View { Rectangle().fill(dark ? .white.opacity(0.08) : .black.opacity(0.1)).frame(height: 0.5) }

    private func row(icon: AnyView, name: String, on: Bool, aris: Bool) -> some View {
        HStack(spacing: 10) {
            icon.frame(width: 24, height: 24)
            Text(name).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 8)
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? ArisOBColor.macBlue : (dark ? .white.opacity(0.2) : .black.opacity(0.14)))
                Circle().fill(.white).frame(width: 13, height: 13).shadow(color: .black.opacity(0.3), radius: 1, y: 1).padding(1)
            }
            .frame(width: 26, height: 15)
            .animation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.16), value: on)
        }
        .padding(.horizontal, 12)
        .frame(height: Self.rowHeight)
    }
}

/// Aris's helper panel as it docks under System Settings (ArisPermissionGuideView), small: the blue badge with what
/// to do, and the row to drag with the app's own icon.
struct ArisMacDragPanel: View {
    let dark: Bool
    @Binding var chipFrame: CGRect

    /// How far it sits over the bottom of the System Settings window, as the real panel does.
    static let overlap: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(ArisOBColor.blue)
                    Image(systemName: "arrow.down.to.line").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)
                Text(ArisSetupWords.dragShort())
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(dark ? ArisOBColor.hex(0xf3f4f6) : ArisOBColor.hex(0x1e2939))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
            Row(dark: dark)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { chipFrame = $0 }
        }
        .padding(9)
        .frame(width: 300)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(dark ? ArisOBColor.hex(0x2a2a2c) : .white)
                .shadow(color: .black.opacity(0.22), radius: 12, y: 8)
        }
    }

    /// The row to drag: the icon, "Aris", and the hint; `carried`: the copy in the cursor's hand.
    struct Row: View {
        let dark: Bool
        var carried = false

        var body: some View {
            HStack(spacing: 8) {
                ArisOwnAppIcon(size: 22)
                Text("Aris").font(.system(size: 11.5, weight: .medium)).foregroundStyle(dark ? ArisOBColor.hex(0xf9fafb) : ArisOBColor.hex(0x101828))
                Spacer(minLength: 0)
                if !carried {
                    Text(ArisOnboardingCopy.dragHint).font(.system(size: 9)).foregroundStyle(dark ? ArisOBColor.hex(0x6a7282) : ArisOBColor.hex(0x99a1af))
                }
            }
            .padding(EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 9))
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(carried ? (dark ? ArisOBColor.hex(0x3a3a3d) : ArisOBColor.hex(0xf3f4f6)) : (dark ? .white.opacity(0.06) : .black.opacity(0.04))))
            .shadow(color: .black.opacity(carried ? 0.25 : 0), radius: 8, y: 5)
            .opacity(carried ? 0.92 : 1)
        }
    }
}

/// The macOS arrow (18 × 26).
struct ArisMacCursor: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 18
            var p = Path()
            p.move(to: CGPoint(x: 1.5 * s, y: 1.5 * s))
            p.addLine(to: CGPoint(x: 1.5 * s, y: 20.7 * s))
            p.addLine(to: CGPoint(x: 6.1 * s, y: 16.3 * s))
            p.addLine(to: CGPoint(x: 9.1 * s, y: 23.4 * s))
            p.addLine(to: CGPoint(x: 12.4 * s, y: 22 * s))
            p.addLine(to: CGPoint(x: 9.4 * s, y: 15 * s))
            p.addLine(to: CGPoint(x: 15.8 * s, y: 15 * s))
            p.closeSubpath()
            ctx.fill(p, with: .color(.black))
            ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 1.4 * s, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
