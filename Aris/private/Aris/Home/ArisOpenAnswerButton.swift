//
//  ArisOpenAnswerButton.swift
//  Aris
//
//  The owner's pick A (mockups/answer-format.html): "자세히 보기 ›" at the end of an answer taller than the reader limit
//  (ArisAnswerReader), 12 under its last line at 12.5 and white .5 (.78 on hover, 160 ms). It opens the whole answer in
//  the Aris reader.
//

import SwiftUI

struct ArisOpenAnswerButton: View {
    /// Its words; "자세히 보기 ›" unless another line under an answer borrows the button (ArisBrainTrouble's way to Settings).
    var title = ArisUIWords.text("자세히 보기 ›", "Read more ›")
    var help = ArisUIWords.text("답 전체를 읽기 창에서 보기", "Read the whole answer in the reader")
    let action: () -> Void
    @State private var hovering = false

    /// In with the answer's reveal.
    static let entry: AnyTransition = .opacity.animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.42))
    static let height: CGFloat = 18
    /// Above it, on top of the answer's own 8 at the bottom: 12 under the last line.
    static let gap: CGFloat = 4
    /// CSS `ease` over 160 ms.
    private static let hover = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.16)

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(hovering ? 0.78 : 0.5))
                .lineLimit(1)
                .frame(height: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(Self.hover, value: hovering)
        .help(help)
    }
}
