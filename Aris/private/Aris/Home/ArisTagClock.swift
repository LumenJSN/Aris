//
//  ArisTagClock.swift
//  Aris
//
//  Keeps, for the open notch's tags, what only time can tell: when each running tag of the turn began (ArisTagTimes,
//  read off the session each time it changes, so a notch that was closed while Aris worked still shows the right
//  clock when it opens), and what became of a job the user stopped from its tag (the line its row then shows, ArisStopLine).
//  Started once at launch; it changes nothing in the turn.
//

import Combine
import Foundation

@MainActor
final class ArisTagClock: ObservableObject {
    static let shared = ArisTagClock()

    /// When each running tag began, and when the turn began working.
    @Published private(set) var times = ArisTagTimes()
    /// Jobs stopped from their tags: what each had done by then, for its row.
    @Published private(set) var stopNotes: [UUID: String] = [:]
    private var watching: AnyCancellable?

    /// Follows the session from here on (called at launch, and again by the first view that needs the clock).
    func start() {
        guard watching == nil else { return }
        watching = ArisController.shared.$session.sink { [weak self] session in self?.see(session) }
    }

    private func see(_ session: ArisSession) {
        let next = times.seeing(session, at: Date())
        if next != times { times = next }
    }

    /// `line`: what the stopped job had done. Notes of jobs no longer listed are let go.
    func note(_ line: String, for job: UUID, among listed: [UUID]) {
        let kept = stopNotes.filter { listed.contains($0.key) }
        stopNotes = kept.merging([job: line]) { _, new in new }
    }
}
