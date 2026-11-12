//
//  ArisTeamRouting+Direct.swift
//  Aris
//
//  A request that calls a teammate by name at its start ("큐에이봇, 17 곱하기 23은?", "페이지야 …", "탐한테 …") goes to
//  that teammate, decided here in the app on every brain, never left to a model (BUG-25b): the settings page promises
//  "이름을 부르면 그 팀원이 일을 맡아요". Claude Code still goes through the brain, which gives it a project folder.
//

import Foundation

extension ArisTeamRouting {
    /// The job for the teammate `text` calls, the user's words as said; nil when it calls none (or Claude Code).
    static func directJob(_ text: String, teammates: [ArisTeammate]) -> ArisJobSpec? {
        guard let mate = addressee(in: text, teammates: teammates), mate.id != ArisTeammate.claudeCodeId else { return nil }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ArisJobSpec(title: ArisHandoff.title(of: words), prompt: words, assignee: .teammate(mate.id), cwd: nil, appHint: nil)
    }
}
