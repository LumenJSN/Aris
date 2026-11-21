//
//  ArisCardHearingNote.swift
//  Aris
//
//  The confirm card's small line beside its buttons: "듣는 중" with a microphone while the card listens for a yes or
//  no, "지금은 듣지 않아요. 눌러서 답해 주세요." when only a click, Y or N answers (ArisCardHearing). It comes and goes in
//  one calm fade; nothing blinks or pulses.
//

import SwiftUI

/// What the card on screen was last told about its microphone (ArisController.cardWait tells it).
@MainActor
final class ArisCardEar: ObservableObject {
    static let shared = ArisCardEar()

    @Published private(set) var state = ArisCardEarState()

    func set(_ hearing: ArisCardHearing, card id: String) { state = state.setting(hearing, card: id) }

    func clear(card id: String) { state = state.clearing(card: id) }
}

/// Whether Y and N reach the card right now (KeyboardFocus tells it): the note names the keys only while they do.
@MainActor
final class ArisCardKeyReach: ObservableObject {
    static let shared = ArisCardKeyReach()

    @Published private(set) var reaches = false
    private var state = ArisCardKeyReachState()
    private var ends: DispatchWorkItem?

    func update(now: Double, _ change: (inout ArisCardKeyReachState) -> Void) {
        change(&state)
        ends?.cancel()
        ends = nil
        reaches = state.reaches(at: now)
        // The tap's window runs out with the card still up: the note stops naming the keys at that moment.
        guard let end = state.tapEnds(), end > now else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.update(now: end) { _ in } }
        }
        ends = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (end - now), execute: item)
    }
}

struct ArisCardHearingNote: View {
    let hearing: ArisCardHearing
    let english: Bool
    @ObservedObject private var keys = ArisCardKeyReach.shared

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: hearing.hears ? "mic.fill" : "mic.slash")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(hearing.hears ? Color(red: 100 / 255, green: 160 / 255, blue: 1).opacity(0.9) : .white.opacity(0.38))
            Text(ArisCardHearing.words(hearing, english: english, keys: keys.reaches))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(hearing.hears ? 0.72 : 0.5))
                .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeOut(duration: 0.2), value: hearing)
        .transition(.opacity.animation(.easeOut(duration: 0.2)))
        .accessibilityElement(children: .combine)
    }
}
