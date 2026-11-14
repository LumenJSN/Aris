//
//  ArisConfirmCard.swift
//  Aris
//
//  Before the AI acts: exactly what would happen, as a confirmation card in the result slot under your words:
//  #18191C, radius 26, 4 in from each side, padding 12 0, as tall as its content up to
//  min(440, the answer budget) and then scrolling (nothing is cut with a line limit). The action's name, its details
//  as label / value rows, then 취소; the dark-glass 허용 floats over the card's bottom 40 points, 12 from the right, so
//  it stays in reach while the details scroll. It comes in over 0.3 s ease-out from 4 points below. Yes or no also by
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
    /// A dictated message's countdown: when it began (ArisController.countdownStarted), nil while Aris still says it.
    var countdownStarted: Date?

    static let maxHeight: CGFloat = 440
    static let cornerRadius: CGFloat = 26
    static let background = Color(red: 0x18 / 255, green: 0x19 / 255, blue: 0x1C / 255)
    /// Outer margin 0 4 (width 100% − 8), padding 12 0.
    static let sideInset: CGFloat = 4
    static let verticalPadding: CGFloat = 12
    /// The floating 허용's lane at the card's bottom, and its distance from the right.
    static let allowLane: CGFloat = 40
    static let allowTrailing: CGFloat = 12
    static let buttonHeight: CGFloat = 30
    /// The yes button while a click on it doesn't count yet, and the one ease that brings it to full strength.
    static let restOpacity: Double = 0.4
    static let wakeEase: Animation = .easeOut(duration: 0.25)
    /// The entrance: 0.3 s ease-out from 4 points below.
    static let entry: AnyTransition = .opacity.combined(with: .offset(y: 4)).animation(.easeOut(duration: 0.3))

    var body: some View {
        // The automatic check's stopped card has its own face (ArisStoppedCard).
        if question.stopped { ArisStoppedCard(question: question, budget: budget, english: english) } else if question.countdown { countdownCard } else { confirmCard }
    }

    /// The card is drawn in English, buttons and all: the request it answers is English (ArisCardEnglish), or the
    /// agent wrote it in English already.
    private var english: Bool {
        ArisCardEnglish.isEnglish(request: ArisController.shared.session.heard) || ArisConfirmReply.isEnglish(question)
    }

    private var confirmCard: some View {
        ArisFadingScroll(budget: min(Self.maxHeight, budget), refresh: question.id,
                         onScroll: { ArisCardReadLive.shared.scrolled(card: question.id, offset: $0, visible: $1, content: $2) }) {
            VStack(alignment: .leading, spacing: 0) {
                header
                details
                buttons
            }
            .padding(.vertical, Self.verticalPadding)
        }
        .overlay(alignment: .bottomTrailing) {
            allow
                .padding(.trailing, Self.allowTrailing)
                .padding(.bottom, Self.verticalPadding + (Self.allowLane - Self.buttonHeight) / 2)
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
            Text(question.countdown ? ArisCountdownCopy.title : english ? ArisCardEnglish.title(question.title) : question.title)
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
            let rows = Self.rows(english ? ArisCardEnglish.detail(text, title: question.title) : text)
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

    /// 취소, and room for the floating 허용 beside it.
    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button { ArisController.shared.answerQuestion(false) } label: {
                Text(ArisConfirmWords.cancel(english: english)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.38))
                    .padding(.horizontal, 14).frame(height: Self.buttonHeight)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(ArisConfirmWords.noHelp(english: english))
            allowLabel.hidden()
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
                .background(ArisDarkGlassButton())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .opacity(ready && !held ? 1 : Self.restOpacity)
        .animation(Self.wakeEase, value: held)
        .animation(Self.wakeEase, value: read)
        .help(read ? ArisConfirmWords.yesHelp(english: english) : ArisCardRead.hint(english: english))
    }

    /// The card's end has been on screen: at once when it fits its room, after a scroll to its end when it does not.
    var read: Bool { reader.readCard == question.id }

    /// A click on yes doesn't count yet: the card was just put up, or just moved or grew.
    var held: Bool { still.ready != question.id }

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

    /// "받는 사람: 엄마" lines become label / value rows; anything else stays a line of text.
    static func rows(_ detail: String) -> [(label: String?, value: String)] {
        detail.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].count <= 14, !parts[0].contains("/") else { return (nil, String(line)) }
            return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
        }
    }
}

extension View {
    func cardSurface(keys: Bool = true) -> some View { modifier(ArisConfirmCard.Surface(keys: keys)) }
}
