//
//  ArisOnboardingTryPage.swift
//  Aris
//
//  눌러서 말하기 (the owner's picks 1-A and 4-A, 2026-11-11; the mockup's "누른 채 바로 말하기"): the shortcut's practice and
//  the first request on one page, with no quiz. Aris's own talk shortcut as configured (KeyboardShortcuts) is drawn as
//  keycaps that light while it is really held (ArisController.keyHeld), and holding it, or this page's button, which
//  presses the same key, listens for real. The request under the keys ("3분 타이머 맞춰 줘") lights word by word as it
//  is heard; the real notch answers and shows the running timer; then 계속 shows and the page moves on by itself
//  (ArisSetupTry decides when the request was really done; the guide moves on). Where Aris can't hear, the page says
//  why in the notch's own sentence and the request can be sent typed. 아니요, 키를 바꿀게요 opens Settings at the talk key.
//  Drawn with the try pages' own parts (ArisTrySingle, ArisTryTile, ArisOnboardingKeycap).
//

import SwiftUI

struct ArisTryPage: View {
    @ObservedObject var guide: ArisOnboardingGuide
    @ObservedObject var model: ArisOnboardingModel
    let palette: ArisSetupPalette
    @ObservedObject private var aris = ArisController.shared
    /// This page's button is held down (it holds the talk key).
    @State private var holding = false
    @State private var changedKey = false
    /// The notch's sentence from a press that could not start listening; gone once one does.
    @State private var lastFailure: String?
    @State private var hasMicrophone = true
    @State private var typed = ""
    @Environment(\.arisOnboardingStill) private var still
    /// The offscreen renders say what Aris can hear.
    @Environment(\.arisTryHearing) private var pinned

    private typealias Try = ArisSetupTry
    private var line: String { Try.line(english: ArisSetupWords.english) }
    private var words: [String] { line.split(separator: " ").map(String.init) }
    private var done: Bool { guide.askAnswered }
    private var hearing: Try.Hearing {
        pinned ?? Try.hearing(micGranted: model.granted(.mic), hasMicrophone: hasMicrophone, lastFailure: lastFailure)
    }

    var body: some View {
        let keys = model.actions.talkKeys(), text = keys.joined(separator: " ")
        let lit = Try.lit(words: words.count, heard: aris.session.heard, listening: aris.session.phase == .listening, done: done)
        ArisTrySingle(title: ArisSetupWords.tryTitle(text), palette: palette) {
            ArisTryTile(question: ArisSetupWords.tryHow(), palette: palette, spread: true) {
                VStack(spacing: Self.wellGap) {
                    HStack(spacing: 12) {
                        ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                            ArisOnboardingKeycap(symbol: key, lit: aris.keyHeld || holding, palette: palette)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ArisOnboardingCopy.keysLabel(text))
                    request(lit: lit)
                    if let sentence = Try.sentence(hearing, english: ArisSetupWords.english), !done {
                        typing(sentence).transition(.opacity)
                    }
                }
            } actions: {
                Button(ArisOnboardingCopy.shortcutChange) {
                    // Straight to the talk key's row (it opened on whatever page was last seen).
                    ArisSettingsNav.shared.go(ArisSettingsCaption.talkKey.page, anchor: ArisSettingsCaption.talkKey.anchor)
                    ArisSettingsWindow.shared.show()
                    changedKey = true
                }
                .buttonStyle(ArisQuietButtonStyle(palette: palette, weight: .regular))
                Spacer(minLength: 0)
                if !done {
                    Button(ArisOnboardingCopy.skip) { guide.next() }
                        .buttonStyle(ArisQuietButtonStyle(palette: palette, weight: .regular))
                }
                button
            }
            note
        }
        .animation(.easeOut(duration: 0.16), value: lit)
        .animation(guide.reduced ? ArisOBCurve.fade : ArisOBCurve.card, value: hearing)
        .onChange(of: aris.session.phase) { _, phase in
            // A start that works clears what the last one said; one that fails is kept, with typing offered.
            if phase == .listening { lastFailure = nil }
            if let failure = Try.failure(failed: phase == .failed, reply: aris.session.reply) { lastFailure = failure }
        }
        .onAppear {
            if typed.isEmpty { typed = line }
            if !still { hasMicrophone = ArisMicChoice.hasMicrophone() }
        }
    }

    /// Between the keys, the request and the typed row inside the well.
    private static let wellGap: CGFloat = 14

    /// The request, lit word by word as Aris hears it; whole once it is done.
    private func request(lit: Int) -> some View {
        (words.indices.reduce(Text("“")) { text, i in
            text + Text((i == 0 ? "" : " ") + words[i]).foregroundColor(i < lit ? palette.t1 : palette.t2)
        } + Text("”").foregroundColor(done ? palette.t1 : palette.t2))
            .font(.system(size: 18))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Why Aris can't hear, in the notch's own sentence, and the same request to send typed.
    private func typing(_ sentence: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sentence)
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(palette.t2)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                // A still picture draws the field as its words (ImageRenderer can't draw AppKit's field editor).
                if still {
                    Text(typed.isEmpty ? line : typed).foregroundStyle(palette.t1).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(line, text: $typed)
                        .textFieldStyle(.plain)
                        .foregroundStyle(palette.t1)
                        .onSubmit(send)
                        .accessibilityLabel(ArisSetupWords.tryFieldLabel())
                }
            }
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.tileLine, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var button: some View {
        switch Try.button(done: done, hearing: hearing) {
        case .next:
            ArisGlassRect(title: ArisOnboardingCopy.continueLabel) { guide.next() }
        case .send:
            ArisGlassRect(title: ArisSetupWords.trySend()) { send() }
        case .hold:
            ArisGlassRect(title: ArisOnboardingCopy.askHold, held: holding) {}
                .simultaneousGesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !holding else { return }
                        holding = true
                        aris.keyDown()
                    }
                    .onEnded { _ in
                        holding = false
                        aris.keyUp()
                    })
        }
    }

    /// One quiet line under the tile: what letting go does, where the key is changed, that it worked, or to try the
    /// line as it is.
    private var note: some View {
        let note = Try.note(done: done, lastOutcome: guide.tryOutcome, changedKey: changedKey, hearing: hearing)
        return Text(note.map { ArisSetupWords.tryNote($0) } ?? " ")
            .font(.system(size: 13))
            .foregroundStyle(palette.t2)
            .frame(minHeight: 20, alignment: .leading)
            .padding(.top, 12).padding(.horizontal, 4)
            .accessibilityHidden(note == nil)
    }

    /// What is typed goes to Aris as a request typed into the notch does: on this page, a practice turn.
    private func send() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        aris.submitTyped(text)
    }
}

private struct ArisTryHearingKey: EnvironmentKey {
    static let defaultValue: ArisSetupTry.Hearing? = nil
}

extension EnvironmentValues {
    /// The offscreen renders pin what Aris can hear on the try page (a still picture reads nothing of this Mac).
    var arisTryHearing: ArisSetupTry.Hearing? {
        get { self[ArisTryHearingKey.self] }
        set { self[ArisTryHearingKey.self] = newValue }
    }
}
