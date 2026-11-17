//
//  ArisTeammateFolder.swift
//  Aris
//
//  Where Claude Code opens when the job names no folder (audit imp-2: "Claude Code한테 이 버그 고치라고 해" used to fail
//  with "Claude Code를 열 폴더가 아니에요"). The folder the user's most recent Claude Code session works in is proposed
//  instead, the home folder itself included (the owner, 2026-11-14: his own sessions run in ~, and "클로드 코드한테
//  물어봐… 내 마케팅…" died there); with no session to go by, the home folder. Claude Code runs in auto mode, so his own
//  turn vouches for it there as for a folder he named (no launch card: "클코는 automode 로 항상 돌려"). Pure.
//

import Foundation

enum ArisTeammateFolder {
    /// A Claude session as the notch knows it (ClaudeStore).
    struct Session: Equatable {
        let cwd: String
        let lastEvent: Date
        let agent: String
    }

    /// The folder to propose: the most recently active Claude Code session's, when it is the home folder or a folder
    /// inside it (never ~/Library; the agent checks it again, resolved, before any card); else the home folder.
    static func proposed(_ sessions: [Session], home: String) -> String {
        let root = (home as NSString).standardizingPath
        return sessions.filter { $0.agent == "claude" }.sorted { $0.lastEvent > $1.lastEvent }
            .map { ($0.cwd as NSString).standardizingPath }
            .first { ($0 == root || $0.hasPrefix(root + "/")) && $0 != root + "/Library" && !$0.hasPrefix(root + "/Library/") } ?? root
    }

    /// Whether a job's folder is missing ("" or spaces).
    static func isMissing(_ cwd: String?) -> Bool {
        (cwd ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The job's row while Claude Code opens in the proposed folder.
    static func proposingStep(_ folder: String, home: String, korean: Bool) -> String {
        if (folder as NSString).standardizingPath == (home as NSString).standardizingPath {
            return korean ? "폴더를 말씀 안 하셔서 홈 폴더에서 열어요" : "No folder was named: opening in your home folder"
        }
        let shown = folder.hasPrefix(home + "/") ? "~" + folder.dropFirst(home.count) : folder
        return korean ? "폴더를 말씀 안 하셔서 최근에 쓰신 \(shown)에서 열어요" : "No folder was named: opening in your recent \(shown)"
    }
}
