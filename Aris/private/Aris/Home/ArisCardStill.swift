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
    /// The card that shows its "not taken" note: a click on its yes came during the hold (ArisCardHold.refused).
    @Published private(set) var refused: String?
    private var wake: Task<Void, Never>?
    /// Waits for the frames a change of the card is drawn in (ArisCardHold.drawn).
    private var frames: Task<Void, Never>?
    private var noteEnd: Task<Void, Never>?
    private var pressMonitor: Any?

    /// Every press in Aris's own windows is timed where it goes down, so a click-yes is held to that moment and not
    /// to when its button's action runs (ArisCardHold.clickCounts).
    init() {
        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.pressed(at: event.timestamp) }
            return event
        }
    }

    func pressed(at time: Double) { hold = hold.pressed(at: time) }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// A card was put up (also the same card again).
    func shown(_ id: String) { apply(hold.shown(id, at: Self.now)) }

    /// The session's card changed or went.
    func follow(_ id: String?) { apply(hold.following(id, at: Self.now)) }

    /// The card's view was laid out here.
    func framed(card id: String, _ frame: CGRect) { apply(hold.framed(card: id, frame, at: Self.now)) }

    /// The card's view came in (its fade-in starts): it is held from when it is fully drawn.
    func entering(card id: String) { apply(hold.entering(card: id, at: Self.now)) }

    func clickCounts(card id: String) -> Bool { hold.clickCounts(card: id, at: Self.now) }

    /// A click on card `id`'s yes came during the hold and was not taken: the card says so, calmly, for a moment. The
    /// press itself is dropped (never applied later), and the hold goes on as it was.
    func refusedClick(card id: String) {
        hold = hold.refused(card: id, at: Self.now)
        guard hold.noteUntil(card: id) != nil else { return }
        refused = id
        waitForNoteEnd(id)
    }

    /// Takes the note away when its time is over; when the hold started again meanwhile (the card moved), after that one.
    private func waitForNoteEnd(_ id: String) {
        noteEnd?.cancel()
        guard let until = hold.noteUntil(card: id) else { return }
        noteEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, until - Self.now) + 0.02))
            guard !Task.isCancelled, let self, self.refused == id else { return }
            if self.hold.noteShows(card: id, at: Self.now) { return self.waitForNoteEnd(id) }
            self.refused = nil
        }
    }

    /// What is left of card `id`'s hold now (0 for another card).
    func remaining(card id: String) -> Double { hold.card == id ? hold.remaining(at: Self.now) : 0 }

    /// `drawn`: the change is the card's frames having gone by; any other change is not on the screen yet, and the hold
    /// waits for its frames before it counts (ninth VM run, item 4: a card that came whole as the notch grew took a
    /// press 0.95 s after its button was first seen).
    private func apply(_ next: ArisCardHold, drawn: Bool = false) {
        guard next != hold else { return }
        let next = drawn ? next : next.undrawn()
        hold = next
        frames?.cancel()
        if next.awaitsDraw, let card = next.card {
            // Each frame is waited for on the main actor, one after another: a main thread too busy to draw is also
            // too busy to count them.
            frames = Task { [weak self] in
                for _ in 0..<ArisCardHold.drawFrames {
                    try? await Task.sleep(for: .seconds(ArisCardHold.frame))
                    if Task.isCancelled { return }
                }
                guard let self, self.hold.card == card else { return }
                self.apply(self.hold.drawn(card: card, at: Self.now), drawn: true)
            }
        }
        if ready != nil { ready = nil }
        // Another card's note is not this card's.
        if let refused, refused != next.card {
            self.refused = nil
            noteEnd?.cancel()
        }
        wake?.cancel()
        // The button's ease to ready starts `wake` before the hold is over and ends with it: it looks ready when a
        // click starts to count, not a moment after (eleventh VM run, item 9).
        guard let card = next.card, let readyAt = next.readyAt, let wakesAt = next.wakesAt else { return }
        wake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, wakesAt - Self.now)))
            guard !Task.isCancelled, let self, self.hold.card == card, self.hold.readyAt == readyAt else { return }
            self.ready = card
        }
    }
}

/// The held yes button's line: under its label, filling once from the left over what is left of the hold, so a held
/// button reads as "a moment" and never as disabled (seventh VM run, item 3). It fills once and stops: no repeat.
struct ArisHoldSweep: View {
    let duration: Double
    @State private var filled = false

    var body: some View {
        GeometryReader { box in
            Capsule().fill(.white.opacity(0.6))
                .frame(width: filled ? box.size.width : 0, height: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.linear(duration: max(duration, 0.05))) { filled = true } }
    }
}

extension View {
    /// Reports the card's frame to its hold: a card that moved or grew takes no click-yes for a moment. And when the
    /// card's view comes in: it is held from when its fade-in is over (ArisCardHold.entering).
    func cardStill(_ id: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ArisCardStill.shared.framed(card: id, $0) }
            .onAppear { ArisCardStill.shared.entering(card: id) }
    }
}
