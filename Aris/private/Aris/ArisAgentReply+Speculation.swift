//
//  ArisAgentReply+Speculation.swift
//  Aris
//
//  How each of aris-agent's replies counts for a speculative request (ArisHeldStream, ArisEndpointDriver): `inert`
//  replies change nothing, `output` would be seen or heard (held until the turn commits), `action` may have done
//  something (a step started, a card is up, a window is being worked in, a job was launched): the turn commits at once.
//
//  A status line is an action unless it is one of the helper's own notes from before any brain runs, which tell of
//  nothing done: "알아보는 중" (ArisThinking.lookingStatus, said at once) and whom the turn went to (ArisTurnFallback's
//  "Claude 한도 → GPT (Codex)", ArisImageRouting's "화면은 Claude가 봐요"). Those are output. Every other status the helper
//  sends means something started and the line alone can't say it has no side effects: a brain's tool call
//  (ArisAgentStatus.forCommand / forTool: "웹 검색 중" and "메시지 준비 중" alike), Aside working, a card's automatic
//  check, an auto-approval, a refusal, a teammate or a job, a learned shortcut or saved steps replaying. They stay action.
//

import Foundation

extension ArisAgentReply {
    var speculationKind: ArisReplyKind {
        switch self {
        case .status(let status):
            return Self.isPlainStatus(status) ? .output : .action
        case .delta, .answer, .failure:
            return .output
        case .turn, .untrusted, .skill, .refusedJobs, .shownOnly, .helperAnswers:
            return .inert
        case .confirm, .operating, .launched, .work, .file, .stepFailed, .savedSteps:
            return .action
        }
    }

    /// The helper's notes before a brain runs (the same words as ArisImageRouting's statuses; a test holds them equal).
    private static let handOverNotes: Set<String> = ["화면은 Claude가 봐요", "화면은 GPT가 봐요", "동그라미는 GPT가 봐요", "화면을 본 대화라 GPT가 이어서 답해요"]

    /// Another brain took the turn (ArisTurnFallback.status, for every pair of brains).
    private static let fallbackNotes: Set<String> = Set(ArisBrain.allCases.flatMap { from in
        ArisBrain.allCases.flatMap { to in ["\(from.title) 없음 → \(to.title)", "\(from.title) 한도 → \(to.title)"] }
    })

    /// A status that tells of nothing done (see the top of the file).
    static func isPlainStatus(_ status: String) -> Bool {
        ArisThinking.saysAtOnce(status) || handOverNotes.contains(status) || fallbackNotes.contains(status)
    }
}
