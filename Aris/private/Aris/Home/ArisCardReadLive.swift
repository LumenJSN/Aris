//
//  ArisCardReadLive.swift
//  Aris
//
//  ArisCardRead, live: told which card is up and how far its scroller has shown it, asked by the controller whether a
//  pressed yes counts, and watched by the card so its yes button is at rest until the card's end has been on screen.
//  Only the moment a card becomes read (or unread again) is published, so scrolling re-draws nothing.
//

import SwiftUI

@MainActor
final class ArisCardReadLive: ObservableObject {
    static let shared = ArisCardReadLive()

    private(set) var read = ArisCardRead()
    /// The card whose pressed yes counts now; nil while the card up has not been read to its end.
    @Published private(set) var readCard: String?

    /// The session's card changed or went.
    func follow(_ id: String?) { apply(read.following(id)) }

    /// A card was put up (also the same card again).
    func shown(_ id: String) { apply(read.shown(id)) }

    /// The card's scroller moved or was laid out.
    func scrolled(card id: String, offset: CGFloat, visible: CGFloat, content: CGFloat) {
        apply(read.scrolled(card: id, offset: offset, visible: visible, content: content))
    }

    func yesCounts(card id: String) -> Bool { read.yesCounts(card: id) }

    private func apply(_ next: ArisCardRead) {
        guard next != read else { return }
        read = next
        let now = next.card.flatMap { next.yesCounts(card: $0) ? $0 : nil }
        if now != readCard { readCard = now }
    }
}
