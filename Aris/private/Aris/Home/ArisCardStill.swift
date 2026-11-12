//
//  ArisCardStill.swift
//  Aris
//
//  The confirm card's hold, live (ArisCardHold): told when a card is put up and when its view's frame changes, asked
//  by the controller whether a click on yes counts, and watched by the card so its yes button is drawn at rest until
//  the hold is over and at full strength after (one ease, when the card has been still; never a blink or a pulse).
//

import SwiftUI

@MainActor
final class ArisCardStill: ObservableObject {
    static let shared = ArisCardStill()

    private(set) var hold = ArisCardHold()
    /// The card whose yes a click may give now; nil while a card's hold is still on.
    @Published private(set) var ready: String?
    private var wake: Task<Void, Never>?

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// A card was put up (also the same card again).
    func shown(_ id: String) { apply(hold.shown(id, at: Self.now)) }

    /// The session's card changed or went.
    func follow(_ id: String?) { apply(hold.following(id, at: Self.now)) }

    /// The card's view was laid out here.
    func framed(card id: String, _ frame: CGRect) { apply(hold.framed(card: id, frame, at: Self.now)) }

    func clickCounts(card id: String) -> Bool { hold.clickCounts(card: id, at: Self.now) }

    private func apply(_ next: ArisCardHold) {
        guard next != hold else { return }
        hold = next
        if ready != nil { ready = nil }
        wake?.cancel()
        guard let card = next.card, let readyAt = next.readyAt else { return }
        wake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, readyAt - Self.now) + 0.02))
            guard !Task.isCancelled, let self, self.hold.clickCounts(card: card, at: Self.now) else { return }
            self.ready = card
        }
    }
}

extension View {
    /// Reports the card's frame to its hold: a card that moved or grew takes no click-yes for a moment.
    func cardStill(_ id: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ArisCardStill.shared.framed(card: id, $0) }
    }
}
