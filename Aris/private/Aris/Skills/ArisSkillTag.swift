//
//  ArisSkillTag.swift
//  Aris
//
//  The small tag over an answer that followed one of the user's skills ("회의록 정리 스킬 사용 중"), in the notch and in the
//  settings page's preview.
//

import SwiftUI

/// "회의록 정리 스킬 사용 중": a quiet capsule over the answer.
struct ArisSkillTag: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars").font(.system(size: 10.5, weight: .semibold))
            Text(title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 10).frame(height: 26)
        .background(Capsule().fill(.white.opacity(0.08)))
        .accessibilityLabel(title)
    }
}
