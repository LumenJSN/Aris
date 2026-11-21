//
//  ClaudeAttention.swift
//  Aris
//
//  Which Claude Code sessions need the user, and why, in words (the user's report 2026-11-19: the orange dot on the tab's </>
//  stayed and nothing said why). The dot is a card waiting in the notch (a question, a plan, a permission); a session
//  that waits in its own terminal is named too. Hovering the </> says it; the tab puts the asking session in front.
//  Foundation only (tested).
//

import Foundation

enum ClaudeAttention {
    enum Why: Equatable {
        /// A card in the notch: Claude's question, its plan, or a tool it wants to use.
        case question, plan, tool(String)
        /// Asking in its own terminal (a permission or a question shown there).
        case terminal
    }

    struct Need: Equatable {
        let session: String
        let why: Why
    }

    /// The cards first (oldest first, as the tab shows them), then the sessions waiting in their terminal with no card.
    /// `isAris`: the folder is Aris's own claude's (its cards are Aris's).
    static func needs(approvals: [ClaudeApproval], sessions: [String: ClaudeSession], isAris: (String) -> Bool) -> [Need] {
        let cards = approvals.map { approval -> Need in
            let name = isAris(approval.cwd) ? "Aris"
                : sessions[approval.sessionId]?.title ?? folder(approval.cwd, id: approval.sessionId)
            switch approval.kind {
            case .question: return Need(session: name, why: .question)
            case .plan: return Need(session: name, why: .plan)
            case .tool: return Need(session: name, why: .tool(approval.toolName))
            }
        }
        let asking = Set(approvals.map(\.sessionId))
        let waiting = sessions.values
            .filter { $0.state == .notification && !asking.contains($0.id) }
            .sorted { $0.lastEvent < $1.lastEvent }
            .map { Need(session: $0.title, why: .terminal) }
        return cards + waiting
    }

    /// "jdoe: 질문에 답을 기다려요".
    static func line(_ need: Need, english: Bool) -> String {
        let why: String
        switch need.why {
        case .question: why = ArisUIWords.text("질문에 답을 기다려요", "waiting for your answer", english: english)
        case .plan: why = ArisUIWords.text("계획 승인을 기다려요", "waiting for you to approve its plan", english: english)
        case .tool(let tool): why = ArisUIWords.text("\(tool) 허용을 기다려요", "waiting for you to allow \(tool)", english: english)
        case .terminal: why = ArisUIWords.text("터미널에서 기다려요", "waiting in its terminal", english: english)
        }
        return "\(need.session): \(why)"
    }

    /// The tab button's tooltip: its name, then one line per session that needs the user.
    static func help(_ needs: [Need], english: Bool) -> String {
        ([ArisUIWords.text("코딩 세션", "Coding sessions", english: english)] + needs.map { line($0, english: english) })
            .joined(separator: "\n")
    }

    private static func folder(_ cwd: String, id: String) -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? String(id.prefix(8)) : name
    }
}
