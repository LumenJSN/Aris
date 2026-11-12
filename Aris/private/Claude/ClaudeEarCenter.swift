//
//  ClaudeEarCenter.swift
//  Aris
//
//  What sits in the middle of the right ear's ring: the busiest state, and while
//  Claude works, the tool it has in hand.
//

import Foundation

enum EarCenter: Equatable {
    case tool(Tool), waiting, error, done, resting

    enum Tool: Equatable { case terminal, edit, search, agents, thinking }

    /// `state` is what the character in the left ear shows (pending approvals already folded in), so both ears agree.
    static func pick(state: ClaudeState, sessions: [ClaudeSession]) -> EarCenter {
        switch state {
        case .notification: return .waiting
        case .error: return .error
        case .happy: return .done
        case .idle, .sleeping: return .resting
        case .thinking, .typing, .building, .juggling:
            let session = sessions.filter { $0.state == state }.max { $0.lastEvent < $1.lastEvent }
            return .tool(tool(named: session?.steps.last?.tool))
        }
    }

    static func tool(named name: String?) -> Tool {
        switch name {
        case "Bash", "BashOutput", "KillShell": return .terminal
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return .edit
        case "Read", "Grep", "Glob", "LS", "WebSearch", "WebFetch": return .search
        case "Task", "Agent": return .agents
        default: return .thinking
        }
    }
}
