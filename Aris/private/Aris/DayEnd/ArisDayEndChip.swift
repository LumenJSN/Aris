//
//  ArisDayEndChip.swift
//  Aris
//
//  The chip that offers the day-end summary (ArisDayEnd) under the closed notch, in the agent chip's dress
//  (ArisAgentChip: a 26-point capsule of dark glass, 11.5 / 560 at .78, and one 23-point button that presses to .97):
//  "오늘 정리 · 한 일 12 · 확인 대기 2 · 내일 4" and 보기. Nothing on it moves. ArisDayEndLayer decides when it hangs.
//

import SwiftUI

/// The capsule itself: the counts, and 보기.
struct ArisDayEndChip: View {
    let text: String
    var english = ArisUILanguage.english
    let show: () -> Void

    static let height: CGFloat = 26
    static let buttonHeight: CGFloat = 23

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: text)
                .font(Font(ArisFont.system(11.5, weight: 560)))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize()
            Button(action: show) {
                Text(verbatim: ArisDayEndCopy.show(english: english))
                    .font(Font(ArisFont.system(11.5, weight: 600)))
                    .tracking(0.115)
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 10)
                    .frame(height: Self.buttonHeight)
                    .background(Capsule(style: .continuous).fill(.white.opacity(0.15)))
                    .contentShape(Capsule())
            }
            .buttonStyle(ArisPressStyle())
            .help(ArisDayEndCopy.chipHelp(english: english))
        }
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .frame(height: Self.height)
        .background(
            Capsule(style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 32 / 255, green: 32 / 255, blue: 35 / 255).opacity(0.965),
                                              Color(red: 19 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.98)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 6)
    }
}
