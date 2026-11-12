//
//  ArisOnboardingPermissions.swift
//  Aris
//
//  The permissions page (mockups/onboarding2/js/perms.js, css/window.css): the heading, three cards (radius 16, a
//  1-point light border, 16 inside, a faint shadow, all .3 s ease-in-out, 12 apart), the open one with why and its 허용
//  (the glass rect) and 나중에 (the microphone's also says macOS asks twice, for speech recognition too, and Screen
//  Recording's that macOS asks once more after its switch and why: ArisFirstCapture, with what follows if that second
//  question isn't allowed); a card turned on says so with a check (it grows 0 → 24 over 350 ms from +50 ms, then
//  fades in over 250 ms from +350 ms) and its sound; 계속 fades in once the mic and Accessibility are on or every card
//  is decided. On the right, the stage previews the system UI that comes next (ArisStagePicture: it keeps a picture
//  up while macOS's own prompt or System Settings is in front, never empty). 허용 asks macOS for real
//  (ArisOnboardingSystem); the star in the notch works while macOS's window is up.

import SwiftUI

struct ArisPermissionsPage: View {
    @ObservedObject var guide: ArisOnboardingGuide
    @ObservedObject var model: ArisOnboardingModel
    let palette: ArisSetupPalette
    /// What the install lacks (ArisPrerequisites), read as the page comes on screen; a still picture of the page
    /// reads nothing of this Mac and shows none.
    @State private var lacking: [ArisPrerequisites.Missing] = []
    @Environment(\.arisOnboardingStill) private var still

    var body: some View {
        let flow = model.flow
        ArisSetupColumns {
            VStack(alignment: .leading, spacing: 0) {
                Text(ArisOnboardingCopy.permsTitle)
                    .font(.system(size: 24))
                    .lineSpacing(8)
                    .foregroundStyle(palette.fg)
                    .accessibilityAddTraits(.isHeader)
                // What this install lacks is said before anything is asked for (an Aris.app with no helper, an older macOS).
                ForEach(lacking, id: \.self) { missing in
                    Text(ArisPrerequisites.full(missing, english: ArisOnboardingCopy.language != "ko"))
                        .font(.system(size: 14))
                        .lineSpacing(6)
                        .foregroundStyle(palette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
                VStack(spacing: 12) {
                    ForEach(ArisPermissionCard.allCases, id: \.self) { card in
                        ArisPermissionCardView(card: card, state: model.state(card), palette: palette, reduced: guide.reduced,
                                               note: card == .screen ? model.captureNote.map { ArisSetupWords.captureNote($0) } : nil,
                                               allow: { guide.allow(card) }, later: { guide.later(card) })
                    }
                }
                .padding(.top, 32)
                ArisGlassRect(title: ArisOnboardingCopy.continueLabel) { guide.next() }
                    .padding(.top, 32)
                    .opacity(flow.continueShown(granted: model.grants) ? 1 : 0)
                    .allowsHitTesting(flow.continueShown(granted: model.grants))
                    .accessibilityHidden(!flow.continueShown(granted: model.grants))
                    .animation(ArisOBCurve.card, value: flow.continueShown(granted: model.grants))
            }
            .frame(maxWidth: 600, minHeight: 304, alignment: .topLeading)
            .padding(.top, 64).padding(.bottom, 32)
        } right: {
            // The picture is drawn as designed and shrunk with its column on a narrow window, so nothing in it is cut.
            let stage = ArisOnboardingStage.stageSize
            let scale = ArisOnboardingStage.stageScale(column: ArisOnboardingStage.columnWidth(layout: guide.fit.layout.width))
            ArisPermissionStage(picture: ArisStagePicture.of(active: flow.active, waiting: flow.waiting), palette: palette, reduced: guide.reduced)
                .frame(width: stage.width, height: stage.height)
                .scaleEffect(scale)
                .frame(width: stage.width * scale, height: stage.height * scale)
        }
        .onChange(of: model.flow.waiting) { _, waiting in
            if waiting.isEmpty { guide.starWorking = false }
        }
        .onAppear { if !still { lacking = ArisPrerequisites.current() } }
    }
}

struct ArisPermissionCardView: View {
    let card: ArisPermissionCard
    let state: ArisCardState
    let palette: ArisSetupPalette
    let reduced: Bool
    /// One more line about what macOS does on this card (Screen Recording's second question); shown open and once on.
    var note: String?
    let allow: () -> Void
    let later: () -> Void

    private var open: Bool { state == .active || state == .waiting }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .lineSpacing(6)
            .foregroundStyle(palette.t2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state == .granted ? ArisOnboardingCopy.cardDone(card) : ArisOnboardingCopy.cardTitle(card))
                .font(.system(size: 16))
                .lineSpacing(8)
                .foregroundStyle(palette.t1)
                .padding(.trailing, 32)
                .fixedSize(horizontal: false, vertical: true)
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    Text(ArisOnboardingCopy.cardWhy(card))
                        .font(.system(size: 14))
                        .lineSpacing(6)
                        .foregroundStyle(palette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    if card == .mic {
                        // The card's 허용 brings two of macOS's prompts: said here, so the page's count is true.
                        Text(ArisOnboardingCopy.micSpeech)
                            .font(.system(size: 14))
                            .lineSpacing(6)
                            .foregroundStyle(palette.t2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    if let note { line(note) }
                    HStack {
                        ArisGlassRect(title: ArisOnboardingCopy.allow, action: allow)
                            .disabled(state == .waiting)
                        Spacer()
                        Button(ArisOnboardingCopy.notNow, action: later)
                            .buttonStyle(ArisQuietButtonStyle(palette: palette))
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if state == .granted, let note {
                // On, with macOS's second question still to come, or not allowed: said under "… is on."
                line(note).padding(.trailing, 32).transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { badge }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.card)
                .shadow(color: palette.dark ? .clear : .black.opacity(0.05), radius: 1, y: 1)
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.cardLine, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(reduced ? ArisOBCurve.fade : ArisOBCurve.card, value: state)
        .animation(reduced ? ArisOBCurve.fade : ArisOBCurve.card, value: note)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ArisOnboardingCopy.cardTitle(card))
        .accessibilityValue(state == .granted ? ArisOnboardingCopy.cardDone(card) : state == .later ? ArisOnboardingCopy.putOff
                            : state == .waiting ? ArisOnboardingCopy.waiting : "")
    }

    @ViewBuilder
    private var badge: some View {
        if state == .granted {
            ArisCheck(reduced: reduced).padding([.top, .trailing], 16)
        } else if state == .later {
            Text(ArisOnboardingCopy.putOff)
                .font(.system(size: 12))
                .foregroundStyle(palette.t2)
                .padding(.top, 18).padding(.trailing, 16)
        }
    }
}

/// The check: a 24-pt blue circle, its width growing 0 → 24 over 350 ms (.4, 0, .2, 1) from +50 ms, faded and
/// scaled .7 → 1 over 250 ms from +350 ms.
struct ArisCheck: View {
    let reduced: Bool
    @Environment(\.arisOnboardingStill) private var still
    @State private var grown = false
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle().fill(ArisOBColor.blue)
            Path { p in
                p.move(to: CGPoint(x: 7.2, y: 12.3))
                p.addLine(to: CGPoint(x: 10.4, y: 15.4))
                p.addLine(to: CGPoint(x: 16.8, y: 8.6))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 24, height: 24)
        .scaleEffect(shown || still ? 1 : 0.7)
        .opacity(shown || still ? 1 : 0)
        .frame(width: grown || still ? 24 : 0, height: 24, alignment: .leading)
        .clipped()
        .onAppear {
            withAnimation(reduced ? nil : ArisOBCurve.checkGrow.delay(0.05)) { grown = true }
            withAnimation(reduced ? ArisOBCurve.fade : ArisOBCurve.settle(0.25).delay(0.35)) { shown = true }
        }
        .accessibilityHidden(true)
    }
}
