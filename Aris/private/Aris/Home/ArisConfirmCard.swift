//
//  ArisConfirmCard.swift
//  Aris
//
//  Before the AI acts: exactly what would happen, as a confirmation card in the result slot under your words:
//  #18191C, radius 26, 4 in from each side, padding 12 0, as tall as its content up to
//  min(440, the answer budget) and then scrolling (nothing is cut with a line limit). The action's name, its details
//  as label / value rows, then 취소 and the dark-glass 허용 in a footer under the scroller, 12 from the right: only the
//  title and details scroll, so a long card (a lesson's thirteen steps, second VM run) never hides its own buttons
//  under its text. It comes in over 0.3 s ease-out from 4 points below. Yes or no also by
//  voice or the Y / N keys (while the pointer is on the card). When a value was cut ("… (+81자)"), 전체 보기 shows
//  every line uncut. A message the user dictated has the countdown mode instead (ArisConfirmCard+Countdown).
//

import SwiftUI

struct ArisConfirmCard: View {
    let question: ArisConfirmation
    /// The answer's budget here; the card stops at the smaller of it and 440.
    var budget: CGFloat = ArisConfirmCard.maxHeight
    /// 전체 보기: the details with nothing cut (ArisConfirmation.full).
    @State private var expanded = false
    /// The owner's ②A: the values as they changed them (보내기 waits until each reads as aris-tools must read it).
    @ObservedObject private var editor = ArisCardEditor.shared
    /// The yes button is at rest until the card has been still for a moment (ArisCardHold): a click before counts for nothing.
    @ObservedObject private var still = ArisCardStill.shared
    /// A card taller than its room takes no pressed yes until its end has been on screen (ArisCardRead).
    @ObservedObject private var reader = ArisCardReadLive.shared
    /// Whether the card hears a spoken answer now, said beside its buttons (ArisCardHearing).
    @ObservedObject private var ear = ArisCardEar.shared
    /// A dictated message's countdown: when it began (ArisController.countdownStarted), nil while Aris still says it.
    var countdownStarted: Date?
    /// Whether its "취소" can be heard (no microphone: the same card waits for a press).
    @ObservedObject var mic = ArisCountdownMic.shared

    static let maxHeight: CGFloat = 440
    static let cornerRadius: CGFloat = 26
    static let background = Color(red: 0x18 / 255, green: 0x19 / 255, blue: 0x1C / 255)
    /// Outer margin 0 4 (width 100% − 8), padding 12 0.
    static let sideInset: CGFloat = 4
    static let verticalPadding: CGFloat = 12
    /// The footer's lane at the card's bottom (취소 and 허용), and 허용's distance from the right.
    static let allowLane: CGFloat = 40
    static let allowTrailing: CGFloat = 12
    static let buttonHeight: CGFloat = 30
    /// The yes button while it can't be pressed (a value that doesn't read, a card not read to its end), and the one
    /// ease that brings it to full strength.
    static let restOpacity: Double = 0.4
    /// The yes button during its short click hold (ArisCardHold): clearly not ready (eighth VM run, item 2: at 0.75
    /// with its glass it read as a ready button, cap8/T1-pair.jpg). Its glass is not drawn, only an outline like the
    /// no button's, its label is at half strength, and the hold's line fills under it (ArisHoldSweep); the glass and
    /// the full label come in with one ease when the hold is over. Nothing blinks or pulses.
    static let heldOpacity: Double = 0.5
    static let heldOutline: Double = 0.16
    static let wakeEase: Animation = .easeOut(duration: 0.25)
    /// The held button's ease to ready: as long as the hold's `wake`, so it ends as the hold does.
    static let holdEase: Animation = .easeOut(duration: ArisCardHold.wake)
    /// The entrance: 0.3 s ease-out from 4 points below.
    static let entry: AnyTransition = .opacity.combined(with: .offset(y: 4)).animation(.easeOut(duration: ArisCardHold.entry))

    var body: some View {
        // The automatic check's stopped card has its own face (ArisStoppedCard).
        // Its title is the agent's own sentence, in the request's language and never translated here: its labels follow it
        // (eleventh VM run: "Was about to / Do it anyway / Don't" under a Korean title).
        if question.stopped { ArisStoppedCard(question: question, budget: budget, english: ArisConfirmReply.isEnglish(question)) } else if question.countdown { countdownCard } else { confirmCard }
    }

    /// The card is drawn in English, buttons and all: the request it answers is English (ArisCardEnglish), or the
    /// agent wrote it in English already.
    private var english: Bool {
        ArisCardEnglish.isEnglish(request: ArisController.shared.session.heard) || ArisConfirmReply.isEnglish(question)
    }

    /// The footer under the scroller: its lane and the padding below it.
    static var footerHeight: CGFloat { allowLane + verticalPadding }

    /// The room the scrolling title and details get: the card's own room (at most 440) less the footer and the top
    /// padding, never below one row.
    static func scrollBudget(_ budget: CGFloat) -> CGFloat {
        max(min(maxHeight, budget) - footerHeight - verticalPadding, 44)
    }

    private var confirmCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArisFadingScroll(budget: Self.scrollBudget(budget), refresh: question.id,
                             onScroll: { ArisCardReadLive.shared.scrolled(card: question.id, offset: $0, visible: $1, content: $2) }) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    details
                }
                .padding(.top, Self.verticalPadding)
            }
            buttons
                .padding(.bottom, Self.verticalPadding)
        }
        .cardSurface()
        .cardStill(question.id)
    }

    var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 100 / 255, green: 160 / 255, blue: 1).opacity(0.9))
                .frame(width: 18, height: 18)
            Text(question.countdown && !question.action ? ArisCountdownCopy.title
                 : (question.countdown ? countdownEnglish : english) ? ArisCardEnglish.title(question.title) : question.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder private var details: some View {
        if question.fields.isEmpty { plainDetails } else { editableDetails }
    }

    /// The owner's ②A: why it asks (when it says), then the values as rows they can change (ArisEditableRows).
    private var editableDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let note = ArisCardEdit.note(question) {
                Text(english ? ArisCardEnglish.detail(note, title: question.title) : note).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }
            ArisEditableRows(question: question, english: english)
        }
        .padding(EdgeInsets(top: 0, leading: 14, bottom: 6, trailing: 14))
    }

    private var plainDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            // An English card: the agent's Korean details are put into English whole (a desktop card's first line is
            // what is done, the lines after it the user's own text), then cut into rows.
            let text = expanded ? question.full ?? question.detail : question.detail
            let rows = Self.rows(english ? ArisCardEnglish.detail(text, title: question.title) : text, title: question.title)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if let label = row.label {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.38)).fixedSize()
                        Spacer(minLength: 0)
                        Text(row.value).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.88))
                            .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 9)
                } else {
                    Text(row.value).font(.system(size: 12.5)).lineSpacing(6).foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
                if index < rows.count - 1 { Rectangle().fill(.white.opacity(0.05)).frame(height: 1) }
            }
            if question.full != nil {
                Button { expanded.toggle() } label: {
                    Text(ArisConfirmWords.whole(expanded: expanded, english: english)).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.38))
                        .padding(.top, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(EdgeInsets(top: 2, leading: 14, bottom: 12, trailing: 14))
    }

    /// The footer, outside the scroller: 취소 and 허용, always on screen.
    private var buttons: some View {
        HStack(spacing: 8) {
            notTakenNote(english: english)
            // A click that wasn't taken says so first; otherwise whether the card listens or waits for a click.
            if !notTaken, let hearing = ear.state.hearing(card: question.id) { ArisCardHearingNote(hearing: hearing, english: english) }
            Spacer(minLength: 0)
            Button { ArisController.shared.answerQuestion(false) } label: {
                Text(ArisConfirmWords.cancel(question.allow, english: english)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.38))
                    .padding(.horizontal, 14).frame(height: Self.buttonHeight)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(ArisConfirmWords.noHelp(english: english))
            allow
        }
        .padding(.horizontal, Self.allowTrailing)
        .frame(height: Self.allowLane)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.05)).frame(height: 1) }
    }

    private var allow: some View {
        // Every value reads as it must, and the card's end has been on screen (ArisCardRead).
        let ready = (question.fields.isEmpty || ArisCardEdit.allAccepted(question.fields, editor.values(for: question))) && read
        return Button { ArisController.shared.answerQuestion(true) } label: {
            allowLabel
                .background(HeldGlass(held: held))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .opacity(!ready ? Self.restOpacity : held ? Self.heldOpacity : 1)
        .overlay { if ready && held { ArisHoldSweep(duration: holdLeft) } }
        .animation(Self.holdEase, value: held)
        .animation(Self.wakeEase, value: read)
        .help(read ? ArisConfirmWords.yesHelp(english: english) : ArisCardRead.hint(english: english))
    }

    /// The card's end has been on screen: at once when it fits its room, after a scroll to its end when it does not.
    var read: Bool { reader.readCard == question.id }

    /// A click on yes doesn't count yet: the card was just put up, or just moved or grew.
    var held: Bool { still.ready != question.id }

    /// What is left of that hold, for its line under the button.
    var holdLeft: Double { still.remaining(card: question.id) }

    /// A click on yes came during the hold and wasn't taken: said beside the buttons for a moment, in one calm fade.
    var notTaken: Bool { still.refused == question.id }

    @ViewBuilder func notTakenNote(english: Bool) -> some View {
        if notTaken {
            Text(ArisConfirmWords.notYet(english: english))
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.animation(.easeOut(duration: 0.2)))
        }
    }

    /// The yes button's ground: the dark glass when a click counts; during the hold only an outline, like the no
    /// button's, so a held button never reads as ready.
    struct HeldGlass: View {
        let held: Bool

        var body: some View {
            ZStack {
                ArisDarkGlassButton().opacity(held ? 0 : 1)
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(held ? ArisConfirmCard.heldOutline / ArisConfirmCard.heldOpacity : 0), lineWidth: 1)
            }
        }
    }

    private var allowLabel: some View {
        Text(ArisConfirmWords.allow(question.allow, sends: question.fields.contains { $0.role == .recipient }, english: english)).font(.system(size: 13, weight: .semibold)).tracking(0.13).foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 18).frame(height: Self.buttonHeight)
    }

    /// The card's surface: #18191C, radius 26, 4 in from each side; with `keys`, the keys are its while the pointer is on it.
    struct Surface: ViewModifier {
        var keys = true

        func body(content: Content) -> some View {
            content
                .background(RoundedRectangle(cornerRadius: ArisConfirmCard.cornerRadius, style: .continuous).fill(ArisConfirmCard.background))
                .clipShape(RoundedRectangle(cornerRadius: ArisConfirmCard.cornerRadius, style: .continuous))
                .padding(.horizontal, ArisConfirmCard.sideInset)
                .onHover { if keys { KeyboardFocus.arm($0) } }
                .onDisappear { if keys { KeyboardFocus.arm(false) } }
        }
    }

    /// "받는 사람: 엄마" lines become label / value rows; anything else stays a line of text, and so does a to-do's or a
    /// note's own words with a colon in them (ArisCardEnglish.keepsLineWhole).
    static func rows(_ detail: String, title: String = "") -> [(label: String?, value: String)] {
        detail.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            if ArisCardEnglish.keepsLineWhole(String(line), title: title) { return (nil, String(line)) }
            let parts = line.split(separator: ":", maxSplits: 1)
            // An address is one value, never a "https" label over "//example.com" (eleventh VM run).
            guard parts.count == 2, parts[0].count <= 14, !parts[0].contains("/"), !parts[1].hasPrefix("//") else { return (nil, String(line)) }
            return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
        }
    }
}

extension View {
    func cardSurface(keys: Bool = true) -> some View { modifier(ArisConfirmCard.Surface(keys: keys)) }
}
