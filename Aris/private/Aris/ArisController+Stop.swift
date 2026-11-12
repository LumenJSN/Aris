//
//  ArisController+Stop.swift
//  Aris
//
//  A press on a working tag stops its work (the owner, 2026-11-11: "태그를 누르면 취소"), through the stop that already
//  exists: the turn's own stop (the header's stop button, Esc), a waiting card's 취소, a job's cancel in the agent. What
//  is new is what the notch says afterwards (ArisStopLine): what the activity record holds as done, and that the rest
//  was stopped, never "취소" for something that already happened. The step cut off loses its tag; it is never ticked.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// The agent ends the brain a moment after the stream drops; the record is read after that.
    private static let recordSettle: Duration = .milliseconds(300)

    /// A press on the turn's running tag.
    func stopFromTag() {
        // A card is up: the same as its 취소.
        if session.question != nil { return answerQuestion(false) }
        guard session.phase == .thinking else { return cancel() }
        let before = session
        let since = ArisTagClock.shared.times.turnBegan ?? Date()
        let english = ArisSpeech.language(of: before.heard) != "ko-KR"
        let cut = ArisStopLine.cut(before)
        log.notice("stopped from the tag (\(cut.finished.count, privacy: .public) steps finished)")
        cancel()
        // At once, with what the app itself knows; the record's part follows when it has something to add.
        let first = before.stopped(ArisStopLine.line(record: [], cut: cut, english: english))
        session = first
        Task { [weak self] in
            try? await Task.sleep(for: Self.recordSettle)
            let record = await ArisAgentClient.activity(today: true).map { ArisStopLine.mine($0, since: since) }
            // Only while the stop line is still what the notch shows: a new turn is never written over.
            guard let self, self.session == first else { return }
            let told = before.stopped(ArisStopLine.line(record: record, cut: cut, english: english))
            if told != first { self.session = told }
        }
    }

    /// A press on a running job's tag: the job's own cancel (its waiting card is declined and its AI stops), then its
    /// row says what it had done by then.
    func stopJobFromTag(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), !job.isFinished else { return }
        let cut = ArisStopLine.jobCut(job.state)
        let english = ArisSpeech.language(of: job.title) != "ko-KR"
        log.notice("a job stopped from its tag")
        cancelJob(id)
        let note = { (record: [String]?) in
            ArisTagClock.shared.note(ArisStopLine.line(record: record, cut: cut, english: english), for: id, among: self.jobs.map(\.id))
        }
        note([])
        Task {
            try? await Task.sleep(for: Self.recordSettle)
            note(await ArisAgentClient.activity(today: true).map { ArisStopLine.job($0, title: job.title, since: job.created) })
        }
    }
}
