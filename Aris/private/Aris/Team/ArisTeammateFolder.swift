//
//  ArisTeammateFolder.swift
//  Aris
//
//  Where Claude Code opens when the job names no folder (audit imp-2: "Claude Code한테 이 버그 고치라고 해" used to fail
//  with "Claude Code를 열 폴더가 아니에요"). The folder the user's most recent Claude Code session works in is proposed
//  instead. Aris chose it, not the user, so that launch is never sent as vouched by their turn: the agent's launch card
//  always asks, with the folder on it. With no session to go by, the job says how to name a folder. Pure.
//

import Foundation

enum ArisTeammateFolder {
    /// A Claude session as the notch knows it (ClaudeStore).
    struct Session: Equatable {
        let cwd: String
        let lastEvent: Date
        let agent: String
    }

    /// The folder to propose: the most recently active Claude Code session's, when it is a folder inside `home` (never
    /// `home` itself or ~/Library; the agent checks it again, resolved, before any card). Nil when there is none.
    static func proposed(_ sessions: [Session], home: String) -> String? {
        let root = (home as NSString).standardizingPath
        return sessions.filter { $0.agent == "claude" }.sorted { $0.lastEvent > $1.lastEvent }
            .map { ($0.cwd as NSString).standardizingPath }
            .first { $0.hasPrefix(root + "/") && $0 != root + "/Library" && !$0.hasPrefix(root + "/Library/") }
    }

    /// Whether a job's folder is missing ("" or spaces).
    static func isMissing(_ cwd: String?) -> Bool {
        (cwd ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The job's row while the launch card asks about the proposed folder.
    static func proposingStep(_ folder: String, home: String, korean: Bool) -> String {
        let shown = folder.hasPrefix(home + "/") ? "~" + folder.dropFirst(home.count) : folder
        return korean ? "폴더를 말씀 안 하셔서 최근에 쓰신 \(shown)에서 열지 여쭤봐요" : "No folder was named: asking to open in your recent \(shown)"
    }

    /// Said when no folder was named and none can be proposed.
    static func noFolder(korean: Bool) -> String {
        korean
            ? "Claude Code를 어느 폴더에서 열지 몰라서 열지 못했어요. ‘~/Projects/내앱 폴더에서 …’처럼 폴더를 같이 말해 주세요."
            : "I couldn't open Claude Code because I don't know which folder to use. Name the project folder with the request, like “in ~/Projects/myapp, …”."
    }
}
