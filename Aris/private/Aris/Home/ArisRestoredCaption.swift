//
//  ArisRestoredCaption.swift
//  Aris
//
//  The small line over a turn put back from the 기록 tab (ArisHistoryRestore): "기록 · 어제 오후 3:42", so a past
//  answer is never taken for a new one. In the side notch's own heading style (the day separator: 10.5 / 600,
//  tracked 0.01em, white .42), on the notch's text line. It shows only while that very turn is what the notch shows.
//

import SwiftUI

struct ArisRestoredCaption: View {
    @ObservedObject private var aris = ArisController.shared

    var body: some View {
        if let restored = aris.restored, restored.isOn(aris.session) {
            Text(verbatim: ArisHistoryRestore.caption(restored.date))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.1)
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .arisTextBacking()
                .padding(.horizontal, ArisGlass.textInset)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
    }
}
