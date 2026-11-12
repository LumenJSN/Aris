//
//  ArisPanel.swift
//  Aris
//
//  The cards a turn sometimes needs, in the notch's look: dictation (your words, struck through where they're tidied;
//  with 다시 복사 when there was nowhere to type them and they were copied), the morning brief's tiles and wake-word
//  training. The confirmation before the AI acts, a dictated message's countdown among them, sits in the turn's result
//  slot (ArisConfirmCard), under your words.
//

import SwiftUI

struct ArisPanel: View {
    @ObservedObject private var aris = ArisController.shared
    @ObservedObject private var dictationState = ArisDictationState.shared
    /// How tall the words may grow before they scroll.
    var budget: CGFloat = ArisAnswerBudget.widgetMax

    /// The activity tag above the words, with its gap: what the panel spends where a turn has its prompt.
    static let tagRow: CGFloat = 28 + 12

    /// The prompt card above and the hint line below the words, measured: the words' budget leaves room for them.
    @State private var promptHeight: CGFloat = 0
    @State private var hintHeight: CGFloat = 0

    private var session: ArisSession { aris.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
            if let why = dictationState.refusal { ArisDictationRefusalTag(why: why) }
        }
        .animation(ArisGlass.resize, value: dictationState.refusal)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let training = aris.training {
                trainingSteps(training)
            } else if let brief = aris.brief, aris.briefTilesShown {
                briefTiles(brief)
            } else if let question = session.question {
                ArisConfirmCard(question: question, budget: budget, countdownStarted: aris.countdownStarted)
            } else {
                turn
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(ArisGlass.resize, value: session)
        .animation(ArisGlass.resize, value: aris.training)
    }

    /// Training "아리스": what to say, and a dot per time you've said it.
    private func trainingSteps(_ training: ArisController.Training) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Train “아리스”")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ArisOrb.glow)
            Text(training.message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
            HStack(spacing: 8) {
                ForEach(0..<ArisWakeModel.recordingsNeeded, id: \.self) { index in
                    Circle()
                        .fill(index < training.count ? ArisOrb.glow : Color.white.opacity(0.18))
                        .frame(width: 9, height: 9)
                }
                Text("\(training.count)/\(ArisWakeModel.recordingsNeeded)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The morning brief: a greeting, then weather, the next event and the soonest deadline as tiles.
    private func briefTiles(_ brief: ArisBrief) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(brief.greeting)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ArisOrb.glow)
                .lineLimit(1)
            HStack(spacing: 8) {
                ForEach(Array(brief.tiles.enumerated()), id: \.offset) { _, tile in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tile.label).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                        Text(tile.big)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(tile.urgent ? Self.dueColor : .white)
                        Text(tile.detail).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ArisSideStyle.pill(RoundedRectangle(cornerRadius: ArisGlass.pillRadius, style: .continuous)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A deadline today.
    private static let dueColor = Color(red: 1, green: 0.55, blue: 0.35)

    private var turn: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsQuestionAbove {
                ArisPromptPill(text: session.heard)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { promptHeight = $0 }
            }
            ArisActivityTag(label: status, done: aris.dictation == .typed, failed: session.phase == .failed)
                .padding(.horizontal, ArisActivityTag.rowInset)
                .transition(ArisActivityTag.entry)
            if copiedDictation {
                // Nowhere to type: the words, folded to three lines, with 다시 복사 (ArisDictationCopy).
                ArisDictationCopiedCard(text: words, budget: wordsBudget, copy: { dictationState.copy(words) },
                                        hovering: { dictationState.cardHovered = $0 })
            } else {
                // One scroller from the start: as tall as the words up to the budget, then it scrolls.
                ArisFadingScroll(budget: wordsBudget) { wordsText }
            }
            if showsHint {
                Text(dictationState.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 16)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hintHeight = $0 }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Dictated words are yours, so they sit in the prompt card; an answer is plain type.
    private var wordsText: some View {
        wordsLine
            .font(.system(size: 15))
            .lineSpacing(aris.dictation == nil ? 4.5 : 4)
            .foregroundStyle(.white.opacity(answering && aris.dictation == nil ? 0.95 : 0.9))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(aris.dictation == nil ? EdgeInsets(top: 4, leading: 14, bottom: 8, trailing: 14) : EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            .background {
                if aris.dictation != nil {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(aris.dictation == .listening ? ArisGlass.promptFillActive : ArisGlass.promptFill)
                }
            }
    }

    /// While dictation is cleaned up, the dropped words are struck through.
    private var wordsLine: Text {
        guard case .cleaning(let marked) = aris.dictation else { return Text(words) }
        var line = AttributedString()
        for (index, word) in marked.enumerated() {
            var piece = AttributedString((index == 0 ? "" : " ") + word.text)
            if !word.kept {
                piece.strikethroughStyle = .single
                piece.foregroundColor = .white.opacity(0.3)
            }
            line += piece
        }
        return Text(line)
    }

    private var answering: Bool {
        session.phase == .speaking || session.phase == .failed || session.phase == .idle
    }

    private var showsQuestionAbove: Bool { answering && !session.heard.isEmpty }

    private var showsHint: Bool { aris.dictation == .listening }

    private var copiedDictation: Bool { aris.dictation == .typed && dictationState.copied }

    /// The budget less the prompt card and the hint line while they show (each with its 12-point gap), never
    /// under 120.
    private var wordsBudget: CGFloat {
        let above = showsQuestionAbove ? promptHeight + 12 : 0
        let below = showsHint ? hintHeight + 12 : 0
        return max(ArisAnswerBudget.minimum, budget - above - below)
    }

    /// A new right-⌥ press while the last words are still going in (bug hunt 11-06 #3).
    private static let stillTyping = ArisUIWords.text("아직 넣는 중 · 다 넣으면 바로 받아써요", "Still typing that in · dictation starts as soon as it's done")

    private var status: String {
        switch aris.dictation {
        case .listening: return aris.dictationQueue.waiting ? Self.stillTyping : ArisUIWords.text("받아쓰는 중", "Dictating")
        case .cleaning: return aris.dictationQueue.waiting ? Self.stillTyping : ArisUIWords.text("정리하는 중", "Tidying up")
        case .typed: return dictationState.typedStatus
        case nil: break
        }
        switch session.phase {
        case .listening:
            if aris.followingUp { return ArisUIWords.text("더 필요한 거 있어요? · 그냥 기다려도 돼요", "Anything else? · or just wait") }
            return aris.handsFree ? ArisUIWords.text("듣고 있어요 · 다 말하면 잠깐 멈추세요", "Listening · pause when you're done") : ArisUIWords.text("듣고 있어요", "Listening")
        case .thinking: return session.status.isEmpty ? ArisUIWords.thinking : session.status
        case .speaking:
            if let title = aris.announcing { return ArisUIWords.text("\(title) 알림", "\(title)") }
            return session.question == nil ? ArisUIWords.text("말하는 중", "Speaking") : ArisUIWords.text("확인이 필요해요 · 응 / 아니", "Needs your OK · yes / no")
        // Nothing heard isn't a problem: the line says it (QA BUG-30).
        case .failed: return ArisTranscript.isNotHeard(session.reply) ? "Aris" : ArisUIWords.text("문제가 생겼어요", "Something went wrong")
        case .idle: return "Aris"
        }
    }

    /// Your words while listening and thinking; Aris's once it answers.
    private var words: String {
        switch session.phase {
        case .listening:
            if session.heard.isEmpty, aris.dictation != nil { return ArisUIWords.text("말씀하세요…", "Go ahead…") }
            if session.heard.isEmpty { return aris.followingUp ? ArisUIWords.text("더 필요한 거 있어요?", "Anything else?") : ArisUIWords.text("듣고 있어요…", "Listening…") }
            return session.heard
        case .thinking: return session.heard
        case .speaking, .failed, .idle: return session.reply
        }
    }
}

/// The dark liquid-glass button: a faint diagonal sheen, a lit bottom edge, a soft inner shadow at the top, a
/// cool hairline and radius 12.
/// A right-⌥ press Aris couldn't take just now (the AI is working, a card waits for an answer): why, for a moment,
/// as a settled tag under the turn. A press is never ignored without a sign (audit voice-9).
struct ArisDictationRefusalTag: View {
    let why: String

    var body: some View {
        ArisActivityTag(label: why, failed: true)
            .allowsHitTesting(false)
            .padding(.horizontal, ArisGlass.textInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(ArisActivityTag.entry)
    }
}

struct ArisDarkGlassButton: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        shape
            .fill(LinearGradient(stops: [
                .init(color: Color(red: 140 / 255, green: 150 / 255, blue: 170 / 255).opacity(0.08), location: 0),
                .init(color: .white.opacity(0.15), location: 0.5),
                .init(color: Color(red: 140 / 255, green: 150 / 255, blue: 170 / 255).opacity(0.08), location: 1),
            ], startPoint: .topTrailing, endPoint: .bottomLeading))
            .overlay(shape.strokeBorder(Color(red: 150 / 255, green: 170 / 255, blue: 200 / 255).opacity(0.25), lineWidth: 0.5))
            .overlay(shape.inset(by: 0.5).stroke(LinearGradient(colors: [.black.opacity(0.6), .clear, .white.opacity(0.3)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 2)
    }
}
