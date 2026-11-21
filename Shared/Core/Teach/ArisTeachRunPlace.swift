//
//  ArisTeachRunPlace.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  What a replay's account says about where its text landed (eleventh VM run, T1: "줄 추가, 우유" typed "첫 줄우유", the
//  typing's own result said "it went on the same line … (no new line was started)", and the account was "‘줄 추가’ 다
//  했어요. (2단계)"). A step that begins a line (ArisTeachStep.newLine) whose typing read back as on the same line with
//  what was there did not do what he taught: the account says what happened, never "done". Pure.
//

import Foundation

extension ArisTeachRunEnd {
    /// The typing calls of a run that should have begun a line and read back on a line with other text.
    final class Placed: @unchecked Sendable {
        private let lock = NSLock()
        private var missed = false

        init() {}

        /// One call's result. `beginsLine`: the call carried the line-start mark (ArisApps.NewLine).
        func note(call name: String, beginsLine: Bool, result: ArisMindResult) {
            guard ArisTeachRunEnd.typing.contains(name), beginsLine, !result.isError, result.text.contains(ArisTeachRunEnd.sameLineMark) else { return }
            lock.withLock { missed = true }
        }

        var sameLine: Bool { lock.withLock { missed } }
    }

    /// What app.type's result says when the text shares a line with what was there (ArisApps.TypedPlace.note).
    static let sameLineMark = "no new line was started"

    /// Whether a call carries the line-start mark.
    static func beginsLine(_ arguments: [String: Any]) -> Bool {
        arguments[ArisApps.NewLine.argument] as? String == ArisApps.NewLine.mark
    }

    /// The account of a run whose line-starting text landed on the same line: what was done and what wasn't.
    static func withPlace(_ account: String, procedure: ArisTeachProcedure, outcome: ArisTeachReplay.Outcome, sameLine: Bool, english: Bool) -> String {
        guard sameLine else { return account }
        let note = english ? "The text went on the same line as what was there, not on a new line. Say “undo” to take it back."
                           : "넣은 글이 새 줄이 아니라 있던 글 바로 뒤에 붙었어요. ‘되돌려’ 하면 지워요."
        guard case .done(let steps) = outcome else { return account + "\n" + note }
        return (english ? "I did the \(steps) steps of “\(procedure.name)”, but not as you showed it." : "‘\(procedure.name)’ \(steps)단계를 했는데, 보여 주신 대로는 안 됐어요.")
            + " " + note
    }
}
