//
//  ArisNoticeQueue.swift
//  Aris
//
//  The cards waiting and the cards up, as values. A card waits until the moment is right (ArisNoticeGate) and then goes
//  on top of the stack; it stays until it is closed, acted on or replaced (no timer takes it away: measured, the only
//  timer there is a watchdog). A card with a key replaces the one with the same key, waiting or up, in its place.
//  Clicking a stack of two or more opens it; closing down to one card closes it again. Foundation only (tested).
//

import Foundation

struct ArisNoticeQueue: Equatable {
    /// Waiting to be shown, oldest first.
    private(set) var pending: [ArisNotice] = []
    /// On screen, newest first: the first is the front card.
    private(set) var shown: [ArisNotice] = []
    /// The stack is opened into a list.
    private(set) var expanded = false

    var front: ArisNotice? { shown.first }

    /// A new card waits for its moment; one with the key of a card already up replaces that card at once (the moment
    /// was right for the first one), one with the key of a waiting card takes its place in the line.
    func posting(_ notice: ArisNotice) -> ArisNoticeQueue {
        var next = self
        if let key = notice.key, let at = shown.firstIndex(where: { $0.key == key }) {
            next.shown[at] = notice
            next.pending.removeAll { $0.key == key }
            return next
        }
        if let key = notice.key, let at = pending.firstIndex(where: { $0.key == key }) {
            next.pending[at] = notice
            return next
        }
        next.pending.append(notice)
        return next
    }

    /// Whether `id` still waits (it was not withdrawn or replaced meanwhile).
    func isWaiting(_ id: UUID) -> Bool { pending.contains { $0.id == id } }

    /// `id`'s moment came: it goes on top. Nothing when it no longer waits.
    func presenting(_ id: UUID) -> ArisNoticeQueue {
        guard let at = pending.firstIndex(where: { $0.id == id }) else { return self }
        var next = self
        let notice = next.pending.remove(at: at)
        next.shown.insert(notice, at: 0)
        return next
    }

    /// Cards that waited too long are dropped from the line.
    func dropping(expiredAt now: Date) -> ArisNoticeQueue {
        var next = self
        next.pending.removeAll { $0.expired(at: now) }
        return next
    }

    /// Closed (its ✕) or acted on.
    func closing(_ id: UUID) -> ArisNoticeQueue {
        var next = self
        next.shown.removeAll { $0.id == id }
        next.pending.removeAll { $0.id == id }
        if next.shown.count < 2 { next.expanded = false }
        return next
    }

    /// What the key stood for is over (the helper answers again): its card goes, waiting or up.
    func withdrawing(key: String) -> ArisNoticeQueue {
        var next = self
        next.shown.removeAll { $0.key == key }
        next.pending.removeAll { $0.key == key }
        if next.shown.count < 2 { next.expanded = false }
        return next
    }

    /// A click on a stack of two or more opens it.
    func expanding() -> ArisNoticeQueue {
        guard shown.count > 1 else { return self }
        var next = self
        next.expanded = true
        return next
    }

    func collapsing() -> ArisNoticeQueue {
        var next = self
        next.expanded = false
        return next
    }

    /// A card's buttons changed (the next of several fixes).
    func replacing(_ notice: ArisNotice) -> ArisNoticeQueue {
        var next = self
        if let at = shown.firstIndex(where: { $0.id == notice.id }) { next.shown[at] = notice }
        return next
    }
}

/// When a waiting card may come up, and the presenter's measured timings.
enum ArisNoticeGate {
    /// Once the moment looks right, it must still be right this much later.
    static let settle: TimeInterval = 0.8
    /// While it isn't, it is looked at again this often.
    static let recheck: TimeInterval = 3

    struct Moment: Equatable {
        /// Aris is idle at a pause: no turn of the user's, no card, nobody talking (ArisController's pause rule).
        var pause = true
        /// The first-run setup is on screen.
        var onboarding = false
        /// The notch is open (hovered or showing something): a card never comes up under it.
        var notchOpen = false
    }

    static func mayShow(_ moment: Moment) -> Bool { moment.pause && !moment.onboarding && !moment.notchOpen }

    /// The cards already up step aside (fade out, stay in the stack) while the notch is open or the setup shows, so
    /// nothing ever covers the notch; they come back as they were.
    static func stepsAside(_ moment: Moment) -> Bool { moment.notchOpen || moment.onboarding }
}
