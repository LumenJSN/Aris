//
//  ArisDropChipRows.swift
//  Aris
//
//  The chips drawn: a first row of what Aris can do with the dropped files at one press (요약 · 한국어로 번역 · PNG로
//  변환), a second, quieter row of the same with another language or format, and a line when Aris holds back from
//  reading a file, took fewer than were dropped, or a file is gone. The pills are ones the notch already has: the
//  agent chip's (ArisAgentChip: 11.5 / 600 on white 15%) for the first row, the files' name chips' (11.5 on white 8%)
//  for the second; pressed to .95. Nothing here moves on its own, and nothing is drawn when there is nothing to offer.
//

import SwiftUI

struct ArisDropChipRows: View {
    let offer: ArisDropOffer
    /// A line about the last drop or press; it comes before the offer's own.
    var notice: String?
    /// What the user often asks of this kind of file (ArisDropLearned): their own chips, before the built-in ones.
    var learned: [ArisDropLearnedChip] = []
    let press: (ArisDropChip) -> Void
    var pressLearned: (ArisDropLearnedChip) -> Void = { _ in }
    var forget: (ArisDropLearnedChip) -> Void = { _ in }

    /// The rows' measurements, in one place for the user's variants.
    enum Look {
        /// As tall as the files' name chips above, and as far apart.
        static let height: CGFloat = 24
        static let gap: CGFloat = 6
        static let padding: CGFloat = 10
        static let type: CGFloat = 11.5
        static let mainWeight: CGFloat = 600, moreWeight: CGFloat = 400
        static let mainFill = 0.15, moreFill = 0.08
        static let mainInk = 0.95, moreInk = 0.78
        /// A chip that arrives after the drop (a picture's 글자 뽑기) fades in.
        static let enter = 0.15
        /// Pressed: .95 over 140 ms, as the agent chip's pill.
        static let pressed: CGFloat = 0.95
        static let pressTime = 0.14
        /// A learned chip is told from a built-in one by a hairline around the same pill, nothing more.
        static let learnedRim = 0.3
        static let learnedRimWidth: CGFloat = 1
    }

    var body: some View {
        let line = notice ?? offer.caption
        let first = ArisDropRowItem.firstRow(learned: learned, main: offer.main)
        if !first.isEmpty || !offer.more.isEmpty || line != nil {
            VStack(alignment: .leading, spacing: Look.gap) {
                if !first.isEmpty { firstRow(first) }
                if !offer.more.isEmpty { row(offer.more, main: false) }
                if let line {
                    Text(verbatim: line).font(.system(size: Look.type)).foregroundStyle(ArisGlass.secondaryText)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .animation(.easeOut(duration: Look.enter), value: offer)
        }
    }

    /// The first row: his own chips, then the built-in ones.
    private func firstRow(_ items: [ArisDropRowItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Look.gap) {
                ForEach(items) { item in
                    switch item {
                    case .learned(let chip):
                        Button { pressLearned(chip) } label: {
                            pill(chip.label, main: true)
                                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(Look.learnedRim), lineWidth: Look.learnedRimWidth))
                        }
                        .buttonStyle(ArisDropChipPress())
                        .help(ArisDropLearnedWords.help(chip.habit.request, english: ArisUIWords.english))
                        .contextMenu { Button(ArisDropLearnedWords.forget(english: ArisUIWords.english)) { forget(chip) } }
                        .transition(.opacity)
                    case .builtIn(let chip):
                        Button { press(chip) } label: { pill(chip.label, main: true) }
                            .buttonStyle(ArisDropChipPress())
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(height: Look.height)
    }

    private func pill(_ label: String, main: Bool) -> some View {
        Text(verbatim: label)
            .font(Font(ArisFont.system(Look.type, weight: main ? Look.mainWeight : Look.moreWeight)))
            .foregroundStyle(.white.opacity(main ? Look.mainInk : Look.moreInk))
            .padding(.horizontal, Look.padding)
            .frame(height: Look.height)
            .background(Capsule(style: .continuous).fill(.white.opacity(main ? Look.mainFill : Look.moreFill)))
            .contentShape(Capsule())
    }

    private func row(_ chips: [ArisDropChip], main: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Look.gap) {
                ForEach(chips) { chip in
                    Button { press(chip) } label: {
                        Text(verbatim: chip.label)
                            .font(Font(ArisFont.system(Look.type, weight: main ? Look.mainWeight : Look.moreWeight)))
                            .foregroundStyle(.white.opacity(main ? Look.mainInk : Look.moreInk))
                            .padding(.horizontal, Look.padding)
                            .frame(height: Look.height)
                            .background(Capsule(style: .continuous).fill(.white.opacity(main ? Look.mainFill : Look.moreFill)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(ArisDropChipPress())
                    .transition(.opacity)
                }
            }
        }
        .frame(height: Look.height)
    }
}

private struct ArisDropChipPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? ArisDropChipRows.Look.pressed : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: ArisDropChipRows.Look.pressTime), value: configuration.isPressed)
    }
}
