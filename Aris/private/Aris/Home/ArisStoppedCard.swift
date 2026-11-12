//
//  ArisStoppedCard.swift
//  Aris
//
//  The automatic check stopped an action (aris-agent's ArisAutoMode; mockup 1-D): the confirm card's own surface and
//  rows (ArisConfirmCard: #18191C, radius 26, the 40-point button lane), a warning mark in place of the shield, the one
//  sentence ("시키지 않은 일이라 멈췄어요."), then what was about to happen: its name in the gate's own words on one row,
//  and its text (which may be anyone's words) as one quoted, cut block that is never read as rows. Two buttons:
//  그래도 하기, drawn as the card's quiet 취소 is, and 하지 않기 on the dark glass with ↩ beside it, the default. 하지 않기
//  (↩, N, esc) settles the card into one line (ArisStoppedEnd, drawn by ArisCountdownEndCard); 그래도 하기 (a click after
//  the card has been still a moment, or Y) runs nothing: the action's own confirm card comes next. Like any card's yes,
//  그래도 하기 counts only once the card's end has been on screen (ArisCardRead): the card tells the reader how far its
//  scroller has shown it, and the button stays at rest and disabled until then. Also the quiet
//  "확인함" mark beside a receipt or a 한 일 row the check let run (ArisCheckedMark). Nothing here moves once it is up.
//  The words are ArisStoppedCopy's.
//

import SwiftUI

struct ArisStoppedCard: View {
    let question: ArisConfirmation
    var budget: CGFloat = ArisConfirmCard.maxHeight
    var english = false
    /// 그래도 하기 takes no click until the card has been still for a moment, as any card's yes (ArisCardHold).
    @ObservedObject private var still = ArisCardStill.shared
    /// 그래도 하기 takes no press until the card's end has been on screen, as any card's yes (ArisCardRead).
    @ObservedObject private var reader = ArisCardReadLive.shared

    static let warning = Color(red: 240 / 255, green: 185 / 255, blue: 90 / 255).opacity(0.95)
    static let keyHint = "↩"
    /// The most lines of the action's own text the card shows.
    static let quoteLines = 6

    var body: some View {
        ArisFadingScroll(budget: min(ArisConfirmCard.maxHeight, budget),
                         onScroll: { ArisCardReadLive.shared.scrolled(card: question.id, offset: $0, visible: $1, content: $2) }) {
            VStack(alignment: .leading, spacing: 0) {
                header
                rows
                buttons
            }
            .padding(.vertical, ArisConfirmCard.verticalPadding)
        }
        .cardSurface()
        .cardStill(question.id)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Self.warning)
                .frame(width: 18, height: 18)
            Text(question.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    /// The one row Aris itself says (the label and the gate's fixed name for the action), then the action's own text as
    /// one quoted block behind a bar: never read as rows (a line "Aris: …" in it is only text), and cut after
    /// `quoteLines` lines (그래도 하기 brings up the action's own card, which shows all of it).
    private var rows: some View {
        let quote = ArisStoppedCopy.quoted(of: question)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ArisStoppedCopy.aboutTo(english: english)).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.38)).fixedSize()
                Spacer(minLength: 0)
                Text(verbatim: ArisStoppedCopy.action(of: question)).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.trailing).lineLimit(2)
            }
            .padding(.vertical, 9)
            if !quote.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous).fill(.white.opacity(0.16)).frame(width: 2)
                    Text(verbatim: quote).font(.system(size: 12.5)).lineSpacing(4).foregroundStyle(.white.opacity(0.72))
                        .lineLimit(Self.quoteLines).truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 2, leading: 14, bottom: 12, trailing: 14))
    }

    /// The card's end has been on screen: at once when it fits its room, after a scroll to its end when it does not.
    private var read: Bool { reader.readCard == question.id }

    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button { ArisController.shared.answerQuestion(true) } label: {
                Text(ArisStoppedCopy.anyway(english: english)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.38))
                    .padding(.horizontal, 14).frame(height: ArisConfirmCard.buttonHeight)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(ArisPressStyle())
            .disabled(!read)
            .opacity(read && still.ready == question.id ? 1 : ArisConfirmCard.restOpacity)
            .animation(ArisConfirmCard.wakeEase, value: still.ready == question.id)
            .animation(ArisConfirmCard.wakeEase, value: read)
            .help(read ? ArisConfirmWords.yesHelp(english: english) : ArisCardRead.hint(english: english))
            Button { ArisController.shared.answerQuestion(false) } label: {
                HStack(spacing: 7) {
                    Text(ArisStoppedCopy.skip(english: english)).font(.system(size: 13, weight: .semibold)).tracking(0.13).foregroundStyle(.white.opacity(0.95))
                    Text(Self.keyHint).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.12)))
                }
                .padding(.horizontal, 18).frame(height: ArisConfirmCard.buttonHeight)
                .background(ArisDarkGlassButton())
                .contentShape(Rectangle())
            }
            .buttonStyle(ArisPressStyle())
            .help(ArisConfirmWords.noHelp(english: english))
        }
        .padding(.horizontal, ArisConfirmCard.allowTrailing)
        .frame(height: ArisConfirmCard.allowLane)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.05)).frame(height: 1) }
    }
}

/// "확인함": the automatic check let this run. A small shield and the word, quiet beside the receipt or the row.
struct ArisCheckedMark: View {
    var english = false

    static let height: CGFloat = 28

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 9.5))
            Text(verbatim: ArisStoppedCopy.checked(english: english)).font(.system(size: 11))
        }
        .foregroundStyle(.white.opacity(0.43))
        .padding(.horizontal, 4)
        .frame(height: Self.height)
        .fixedSize()
        .help(ArisStoppedCopy.checkedHelp(english: english))
    }
}
