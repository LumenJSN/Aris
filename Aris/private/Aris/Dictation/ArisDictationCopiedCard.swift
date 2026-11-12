//
//  ArisDictationCopiedCard.swift
//  Aris
//
//  Dictation with nowhere to type, under its activity tag (ArisDictationCopy; mockups/dictation-copy B): the words in
//  the prompt card (r24, white .07, 15 pt, 4 between lines, 16 in), folded to three lines with "더 보기" / "접기"
//  (11.5 / 500, white .38, .62 on hover, 6 under the words), and under it on the right the secondary "다시 복사"
//  button (30 high, 14 in, r14, a 1-point white .08 ring, 13 / 600 at white .62, a 13-point copy icon). Pressed, it
//  copies again and reads "복사했어요" with a check in green for 1.5 s. The words scroll inside the budget when opened.
//  No glow, nothing blinks; with Reduce Motion the fold and the label swap without moving.
//

import SwiftUI

struct ArisDictationCopiedCard: View {
    let text: String
    /// The height the card may take (the words scroll past it).
    var budget: CGFloat = .infinity
    /// Puts the words on the clipboard; true when they're there.
    let copy: () -> Bool
    /// The pointer is on the card (the controller keeps it up meanwhile).
    var hovering: (Bool) -> Void = { _ in }
    /// Starts unfolded, or already showing "복사했어요" (the offscreen renders).
    var startsOpen = false
    var startsCopied = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    @State private var fullHeight: CGFloat = 0
    @State private var foldedHeight: CGFloat = 0
    @State private var copied = false
    @State private var copiedReset: Task<Void, Never>?
    @State private var rowHeight: CGFloat = 0

    /// Button row: 30 high, 12 above it.
    private static let rowGap: CGFloat = 12
    private static let okColor = Color(red: 80 / 255, green: 200 / 255, blue: 120 / 255).opacity(0.95)

    private var fold: ArisDictationCopy.Fold {
        ArisDictationCopy.Fold(overflows: fullHeight > foldedHeight + 1, open: open)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            ArisFadingScroll(budget: max(ArisAnswerBudget.minimum, budget - Self.rowGap - rowHeight)) { words }
            HStack {
                Spacer(minLength: 0)
                copyButton
            }
            .padding(.horizontal, 4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover(perform: hovering)
        .onAppear {
            open = startsOpen
            copied = startsCopied
        }
        .onDisappear {
            copiedReset?.cancel()
            hovering(false)
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 6) {
            wordsText
                .lineLimit(fold.lineLimit)
                .truncationMode(.tail)
                // The whole words and three lines of them, measured the same way, decide whether it folds.
                .background(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        wordsText
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                        wordsText
                            .lineLimit(ArisDictationCopy.lineLimit)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { foldedHeight = $0 }
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }
            if let toggle = fold.toggle {
                ArisFoldToggle(label: ArisDictationCopy.label(toggle)) {
                    withAnimation(reduceMotion ? nil : ArisGlass.resize) { open.toggle() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(ArisGlass.promptFill))
    }

    private var wordsText: some View {
        Text(verbatim: text)
            .font(.system(size: ArisDictationCopy.fontSize))
            .lineSpacing(ArisDictationCopy.lineSpacing)
            .foregroundStyle(.white.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copyButton: some View {
        Button(action: copyAgain) {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "square.on.square")
                    .font(.system(size: copied ? 11 : 11.5, weight: copied ? .bold : .medium))
                    .frame(width: 13, height: 13)
                Text(copied ? ArisDictationCopy.done : ArisDictationCopy.again)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.13)
            }
            .foregroundStyle(copied ? Self.okColor : .white.opacity(0.62))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: copied)
        }
        .buttonStyle(ArisCopyPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(copied ? ArisDictationCopy.done : ArisDictationCopy.again)
    }

    private func copyAgain() {
        guard copy() else { return }
        copied = true
        copiedReset?.cancel()
        copiedReset = Task { @MainActor in
            try? await Task.sleep(for: ArisDictationCopy.feedback)
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

/// "더 보기" / "접기" under the folded words: 11.5 / 500 at white .38, .62 while the pointer is on it.
private struct ArisFoldToggle: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(hovering ? 0.62 : 0.38))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The mockup's press: .97 while held, none with Reduce Motion.
private struct ArisCopyPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
    }
}
