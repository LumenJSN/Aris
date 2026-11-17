//
//  ArisNoticeQueue.swift
//  Aris
//
//  The notices waiting and the notices up, as values. A notice waits until the moment is right (ArisNoticeGate) and then
//  goes on top; only the newest up is drawn (one pill at a time), the ones under it come back as it goes. It stays until
//  it is closed, acted on or replaced; only a notice with its own showsFor (a deadline, a Claude Code notice) goes by
//  itself (ArisNoticeCenter). A notice with a key replaces the one with the same key, waiting or up, in its place.
//  Foundation only (tested).
//

import Foundation

struct ArisNoticeQueue: Equatable {
    /// Waiting to be shown, oldest first.
    private(set) var pending: [ArisNotice] = []
    /// Up, newest first: the first is the one drawn.
    private(set) var shown: [ArisNotice] = []

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
        return next
    }

    /// What the key stood for is over (the helper answers again): its card goes, waiting or up.
    func withdrawing(key: String) -> ArisNoticeQueue {
        var next = self
        next.shown.removeAll { $0.key == key }
        next.pending.removeAll { $0.key == key }
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
        /// The notch is open (hovered or showing something): a notice never comes up under it.
        var notchOpen = false
        /// An Aris turn, or a conversation listening between turns.
        var turn = false
        /// A dictation runs, or its pill still shows what came of it (the copied words, its error line).
        var dictating = false
    }

    /// The dictation pill shows a dictation or what came of it (not its idle bar or its hover).
    static func dictationBusy(_ phase: ArisDictationPillPhase) -> Bool {
        switch phase {
        case .hidden, .idle, .hover: false
        case .recording, .transcribing, .recovered, .error: true
        }
    }

    /// A notice comes up only at a pause, with the notch closed, no setup, no turn and no dictation: those take
    /// priority, and the notice waits in line for them.
    static func mayShow(_ moment: Moment) -> Bool { moment.pause && !stepsAside(moment) }

    /// The notice already up steps aside (fades out, stays up) while the notch is open, the setup shows, a turn or a
    /// dictation runs, so nothing ever covers them; it comes back as it was.
    static func stepsAside(_ moment: Moment) -> Bool { moment.notchOpen || moment.onboarding || moment.turn || moment.dictating }
}
