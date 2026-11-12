//
//  ArisMuteNoticeTag.swift
//  Aris
//
//  "음소거 중이라 글로 답할게요": a quiet capsule under the turn, shown for a few seconds the first time the user talks
//  to a muted Aris by voice (ArisMuteNotice), so an answer that arrives without a voice is never a puzzle. Drawn as
//  the skill tag is (white 8%, 26 tall, 11.5-point semibold), with the struck speaker; it comes in as the activity
//  tags do and holds no place while it is down.
//

import SwiftUI

struct ArisMuteNoticeTag: View {
    @ObservedObject private var quiet = ArisQuietLive.shared

    static let height: CGFloat = 26

    var body: some View {
        Group {
            if quiet.noticeUp { tag.transition(ArisActivityTag.entry) }
        }
        // The turn makes room for it on the notch's opening clock.
        .animation(ArisGlass.opening, value: quiet.noticeUp)
    }

    private var tag: some View {
        let words = ArisQuietCopy.notice(english: ArisUIWords.english)
        return HStack(spacing: 6) {
            Image(systemName: "speaker.slash.fill").font(.system(size: 10.5, weight: .semibold))
            Text(words).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 10).frame(height: Self.height)
        .background(Capsule().fill(.white.opacity(0.08)))
        .accessibilityLabel(words)
        .allowsHitTesting(false)
        // On the text line, as the tags under an answer are.
        .padding(.horizontal, ArisActivityTag.rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
