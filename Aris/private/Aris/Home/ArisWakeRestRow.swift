//
//  ArisWakeRestRow.swift
//  Aris
//
//  “다른 앱이 마이크를 쓰는 중이라 이름 듣기는 쉬는 중”: when the notch is opened while the wake word rests
//  (ArisWakeRest), one quiet line says why, so calling “아리스” into a closed microphone is never a puzzle. Drawn as
//  the mute notice is (white 8 %, 26 tall, 11.5-point semibold) with a struck microphone; it is simply there or not,
//  with no motion of its own, and holds no place while the wake word listens or a turn is up.
//

import SwiftUI

struct ArisWakeRestRow: View {
    @ObservedObject private var rest = ArisWakeRestLive.shared
    /// A turn or an answer is up.
    var hidden = false

    static let height: CGFloat = 26
    private static let symbolSize: CGFloat = 10.5
    private static let textSize: CGFloat = 11.5
    private static let gap: CGFloat = 6
    private static let inset: CGFloat = 10

    var body: some View {
        if !hidden, let words = rest.words {
            HStack(spacing: Self.gap) {
                Image(systemName: ArisWakeRest.symbol).font(.system(size: Self.symbolSize, weight: .semibold))
                Text(words).font(.system(size: Self.textSize, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, Self.inset).frame(height: Self.height)
            .background(Capsule().fill(.white.opacity(0.08)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(words)
            .allowsHitTesting(false)
            // On the text line, as the tags under an answer are.
            .padding(.horizontal, ArisActivityTag.rowInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
