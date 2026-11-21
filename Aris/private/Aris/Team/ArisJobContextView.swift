//
//  ArisJobContextView.swift
//  Aris
//
//  A job as the brain's context and the history see it (out of ArisController+Team.swift, so it is tested).
//

import Foundation

extension ArisJob {
    /// The history and context view of this job.
    var backgroundTask: ArisBackgroundTask {
        let view: ArisBackgroundTask.State
        switch state {
        // Aris's own record of the job, in plain states (twelfth VM run, A4: the brain made up states from loose words).
        case .queued: view = .working("not started yet")
        case .running(let step): view = .working(step.isEmpty ? "" : "running; last step: " + step)
        case .awaitingApproval: view = .working("waiting for the owner's answer on a card")
        case .done(let answer): view = .done(answer)
        case .failed(let message): view = .failed(message)
        case .cancelled: view = .failed("cancelled before it finished")
        }
        return ArisBackgroundTask(id: id, title: title, state: view)
    }

    var isFinished: Bool {
        switch state {
        case .queued, .running, .awaitingApproval: return false
        case .done, .failed, .cancelled: return true
        }
    }
}
