//
//  ArisDelegationLine.swift
//  Aris
//
//  What Aris says when the conversation hands work out. The brain says one natural sentence of what it is starting
//  before its jobs block ("네, 세 군데 비교해 보고 알려 드릴게요."), which streams to the voice at once; the stock line
//  (ArisHandoffLine, "도우미 1이 맡았어요") is then only shown, unless it tells something the brain couldn't know: a
//  teammate whose brain isn't set up, a job kept in the turn, or no sentence at all. Then it is said as before.
//  Also the line the helper ends a task with when the conversation cancelled it (`aris-tools task cancel`), which the
//  app takes as a cancel, not a failure. Foundation only.
//

import Foundation

enum ArisDelegationLine {
    /// The brain's words before its jobs block, without <say> marks; "" when the block came alone.
    static func brainSentence(_ answer: String) -> String {
        guard let block = ArisDispatch.jobsBlockRange(in: answer) else { return "" }
        let before = String(answer[..<block.lowerBound])
        let plain = before.replacingOccurrences(of: #"(?i)</?say>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A sentence that promises to pay or order is not kept or shown: the stock line stands alone (ArisPaymentBoundary).
        return ArisPaymentBoundary.promisesPayment(plain) ? "" : plain
    }

    /// What is said after the brain's sentence (nil: nothing more) and what the notch shows and the history keeps.
    static func after(brainSaid: String, handed: String, plain: Bool) -> (spoken: String?, shown: String) {
        guard !brainSaid.isEmpty else { return (handed, handed) }
        return (plain ? nil : handed, brainSaid + "\n" + handed)
    }
}

/// A job's end the helper reports as cancelled (POST /cancel's or the conversation's `task cancel`), or one refused
/// at its start because it was cancelled first: a cancel, never said as a failure.
enum ArisJobCancelLine {
    static let lines: Set<String> = ["cancelled", "이 작업은 취소됐어요."]

    static func isCancel(_ message: String) -> Bool { lines.contains(message.trimmingCharacters(in: .whitespacesAndNewlines)) }
}
