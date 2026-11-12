//
//  ArisFixButtons.swift
//  Aris
//
//  The button under a failure that fixes it (ArisFix), 12 under the last line on the answer's text line. It is a
//  button, drawn as the notch's other buttons are (ArisFixPill: the 23-point capsule of the header's 닫기 and the
//  agent chip's 다시 시작, white 15%, 30% under the pointer, its words at white .95): as a line of grey text it was
//  lost over a light window (the second VM run). One button does the fix; where asking again pairs with it
//  (ArisFixOffer.again) a second, quieter "다시 해보기" stands beside it. After a press that copied a command the
//  button says so for a moment. The live row (bound to ArisFixModel) is ArisFixButtons, at the end of
//  ArisFixModel.swift.
//

import SwiftUI

/// The row from an offer: no model, so the offscreen render draws the real thing.
struct ArisFixButtonRow: View {
    let offer: ArisFixOffer
    /// Said on the button in place of its words ("복사했어요…").
    var feedback: String?
    var english = false
    var press: () -> Void = {}
    var again: () -> Void = {}

    /// Between the buttons of the row.
    static let between: CGFloat = 8
    /// The second button, against the first.
    static let quiet: Double = 0.7
    /// The row's height (the pill's), and its gap above: 12 under the answer's last line with the answer's own 8.
    static let height = ArisFixPill.height
    static let gap: CGFloat = 4

    var body: some View {
        let words = ArisFixWords.title(offer.fix, english: english)
        HStack(spacing: Self.between) {
            ArisFixPill(title: feedback ?? words + " ›", help: words, action: press)
            if offer.again {
                let more = ArisFixWords.again(english: english)
                ArisFixPill(title: more, help: more, action: again)
                    .opacity(Self.quiet)
            }
        }
    }
}

/// The notch's pill button, for what fixes a failure: 23 high, a capsule at white 15% (30% under the pointer, as the
/// header's 닫기), its words 11.5 semibold at white .95 (the agent chip's 다시 시작); pressed, it dips to .95.
struct ArisFixPill: View {
    let title: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    static let height: CGFloat = 23
    static let fill = 0.15
    static let hoverFill = 0.3

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.115)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: Self.height)
                .background(Capsule(style: .continuous).fill(.white.opacity(hovering ? Self.hoverFill : Self.fill)))
                .contentShape(Capsule())
        }
        .buttonStyle(ArisFixPillPress())
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help)
    }
}

/// Pressed: .95 over 140 ms (the agent chip's button).
private struct ArisFixPillPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.14), value: configuration.isPressed)
    }
}
