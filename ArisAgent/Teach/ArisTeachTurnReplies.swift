//
//  ArisTeachTurnReplies.swift
//  aris-agent
//
//  What a replay streams to the app when one of its steps ran and failed with steps left (ArisTeachTurn's go-on
//  question). Seventh VM run, item 2: the failure sentence came first, and the app took it for the answer starting, so
//  the "Doing “랩 메모”" tag was ticked as finished; it was marked "!" only after Stop or Continue, when the run's end
//  marked it (ArisTeachRunEnd.marksTagFailed). Now the tag is marked failed first, while the step's tag is still the
//  running one, so it never shows a tick for a run with a failed step. Pure.
//

import Foundation

enum ArisTeachTurnReplies {
    /// The step at `index` failed (why: the app layer's words) and steps are left: its tag is marked failed, then the
    /// sentence saying so. The go-on card comes after these.
    static func failed(_ procedure: ArisTeachProcedure, at index: Int, why: String, english: Bool) -> [ArisAgentReply] {
        [.stepFailed(nil), .delta(ArisTeachCopy.failedLine(procedure, at: index, why: why, english: english) + "\n")]
    }
}
