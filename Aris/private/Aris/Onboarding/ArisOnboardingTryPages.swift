//
//  ArisOnboardingTryPages.swift
//  Aris
//
//  The "try it" pages' parts (mockups/onboarding2/js/pages.js) and the dictation page, each doing the real thing:
//  - the tile, the single column and the keycap that 눌러서 말하기 (ArisTryPage), AI 고르기 and 아리스라고 부르기 draw with;
//  - 받아쓰기: Aris's dictation key held, or this page's button (a real hands-free dictation into the note on the
//    right); the note shows what was heard with the fillers struck, then what Aris typed; under it, one line brings in
//    the model that makes dictation more accurate (ArisModelLineView).
//

import SwiftUI

/// The try-it card: r28, .75 border, p20, gap 20 (its question, the well, the actions at the end).
struct ArisTryTile<Well: View, Actions: View>: View {
    let question: String
    let palette: ArisSetupPalette
    /// The actions lay themselves out across the row (one at the left, the rest at the right) instead of all at the right.
    var spread = false
    @ViewBuilder let well: Well
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(question)
                .font(.system(size: 16, weight: .medium))
                .lineSpacing(8)
                .foregroundStyle(palette.t4)
                .fixedSize(horizontal: false, vertical: true)
            well
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.well))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.wellLine, lineWidth: 1))
            HStack(spacing: 16) {
                if !spread { Spacer(minLength: 0) }
                actions
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(palette.tile)
                .shadow(color: palette.dark ? .black.opacity(0.82) : Color(.sRGB, red: 15 / 255, green: 23 / 255, blue: 42 / 255, opacity: 0.05),
                        radius: palette.dark ? 32 : 14, y: palette.dark ? 24 : 10)
            RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(palette.tileLine, lineWidth: 0.75)
        }
    }
}

/// Single-column page content: max 480, centred, the heading text-xl above the tile.
struct ArisTrySingle<Content: View>: View {
    let title: String
    let palette: ArisSetupPalette
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 20))
                .lineSpacing(12.5)
                .foregroundStyle(palette.t1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: 480, minHeight: 304)
        .padding(.top, 64).padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A Mac keycap: 100 × 84 (Space 212), r12, the symbol at 20 top-left, the name at 11 bottom-right; blue-100 while held.
struct ArisOnboardingKeycap: View {
    let symbol: String
    let lit: Bool
    let palette: ArisSetupPalette

    private var wide: Bool { symbol == "Space" }

    var body: some View {
        let name = ArisOnboardingCopy.keyName(symbol)
        VStack(alignment: .leading, spacing: 0) {
            Text(wide ? " " : symbol).font(.system(size: 20)).foregroundStyle(palette.keyInk)
            Spacer(minLength: 0)
            Text(name).font(.system(size: 11)).foregroundStyle(palette.keySub).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .frame(width: wide ? 212 : 100, height: 84)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(lit ? palette.keyOn : palette.key))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(lit ? palette.keyOnLine : palette.keyLine, lineWidth: 1))
        .shadow(color: lit ? .clear : palette.keyLine, radius: 0, y: 1)
        .animation(.easeOut(duration: 0.12), value: lit)
    }
}

// MARK: - 받아쓰기

struct ArisDictationPage: View {
    @ObservedObject var guide: ArisOnboardingGuide
    let palette: ArisSetupPalette
    @ObservedObject private var aris = ArisController.shared
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.arisOnboardingStill) private var still

    private var listening: Bool { aris.dictation == .listening }

    var body: some View {
        ArisSetupColumns {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(ArisOnboardingCopy.dictateTitle)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(palette.t1)
                        .padding(.bottom, 16)
                        .accessibilityAddTraits(.isHeader)
                    // The dictation key by the name of the key that is set (ArisDictationKeyName), never a fixed one.
                    Text(ArisSetupWords.dictateLead())
                        .font(.system(size: 18))
                        .lineSpacing(10)
                        .foregroundStyle(palette.lead)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 24)
                HStack(spacing: 16) {
                    ArisGlassRect(title: ArisOnboardingCopy.finish) { guide.next() }
                    Button(ArisOnboardingCopy.skip) { guide.next() }
                        .buttonStyle(ArisQuietButtonStyle(palette: palette))
                }
            }
            // min-h 400 with border-box: 304 inside the 64 / 32 padding; justify-between.
            .frame(maxWidth: 480, minHeight: 304, maxHeight: 304, alignment: .topLeading)
            .padding(.top, 64).padding(.bottom, 32)
        } right: {
            practice
        }
    }

    /// The practice note: r24, #F5F5F7, a real field Aris types into.
    private var practice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ArisOnboardingCopy.note)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.t2)
                .padding(.bottom, 12)
            ZStack(alignment: .topLeading) {
                if still {
                    Text(text).font(.system(size: 18)).lineSpacing(10).foregroundStyle(palette.t1).padding(.leading, 5)
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                } else {
                    TextEditor(text: $text)
                        .font(.system(size: 18))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(palette.t1)
                        .focused($focused)
                        // The mockup's .text (min-height 84): a TextEditor takes all the height it's offered, which ran
                        // the card past the window's top under the rail (QA BUG-29); fixed, the card is its content's
                        // height, centred in its column as the mockup's col-r is.
                        .frame(height: 84)
                        .accessibilityLabel(ArisOnboardingCopy.note)
                }
                if case .cleaning(let words) = aris.dictation {
                    words.indices.reduce(Text("")) { line, i in
                        line + Text((i == 0 ? "" : " ") + words[i].text)
                            .foregroundColor(words[i].kept ? palette.t1 : palette.t2)
                            .strikethrough(!words[i].kept)
                    }
                    .font(.system(size: 18))
                    .lineSpacing(10)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            Text(ArisOnboardingCopy.noteHint)
                .font(.system(size: 12))
                .foregroundStyle(palette.t2)
                .padding(.top, 14).padding(.bottom, 16)
            if let failure = ArisListenStart.shownOnPage(failed: aris.session.phase == .failed, reply: aris.session.reply, listening: listening) {
                // Why the dictation couldn't start, in the notch's own sentence (no microphone, the model still loading):
                // the button used to flip back with no word.
                Text(failure)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(palette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
            ArisGlassRect(title: listening ? ArisOnboardingCopy.dictateStop : ArisOnboardingCopy.dictateStart) {
                if listening {
                    aris.finishDictation()
                } else {
                    focused = true
                    // A real hands-free dictation, typed where the caret is: this note.
                    aris.startDictation()
                    aris.lockDictation()
                }
            }
            // The model for more accurate dictation is offered here, where dictation is being tried (the owner's pick 9-A).
            ArisModelLineView(palette: palette, reduced: guide.reduced)
        }
        .padding(24)
        .frame(maxWidth: 440, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.practice))
        .animation(.easeOut(duration: 0.26), value: aris.dictation)
    }
}
