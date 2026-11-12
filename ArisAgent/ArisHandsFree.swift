//
//  ArisHandsFree.swift
//  aris-agent
//
//  A hands-free turn (security review C1): the app heard it in an open conversation, with no key and no wake word, so
//  the words could be anyone's (a video, a call, the next room). Plain reads, answers, local undoable actions and job
//  dispatch go as usual. What would act for the user on their word alone doesn't:
//  - no vouch, so a Claude Code launch always shows its card;
//  - no standing permissions or remembered yeses (computer use's app grants included);
//  - no request coverage: an outbound or destructive action is asked, never auto or a countdown.
//

import Foundation

enum ArisHandsFree {
    /// aris-tools commands that delete, send or undo, beyond ArisRiskPolicy.asksAfterOutsideText's outbound and
    /// read-back writes.
    private static let destructive: [[String]] = [["trash"], ["message"], ["mail"], ["todo", "remove"], ["todo", "done"],
                                                   ["schedule", "remove"], ["forget"], ["undo"], ["osascript"]]
    /// MCP tool names that send, delete or share.
    private static let destructiveWords = ["send", "delete", "remove", "trash", "share", "post", "publish", "invite", "forward", "reply"]

    /// The gate's risk for a hands-free turn: an outbound or destructive action asks.
    static func risk(_ risk: ArisRisk, of action: ArisAction, tools: String) -> ArisRisk {
        guard risk == .auto || risk == .countdown, asks(action, tools: tools) else { return risk }
        return .confirm
    }

    /// Whether `action` sends, deletes or can't be read (any of it asks on a hands-free turn).
    static func asks(_ action: ArisAction, tools: String) -> Bool {
        if ArisRiskPolicy.asksAfterOutsideText(action, tools: tools, conversions: false) { return true }
        switch action {
        case .shell(let command):
            guard let pieces = ArisCommandPolicy.segments(command) else { return true }
            return pieces.contains { piece in
                guard let words = ArisCommandPolicy.words(piece) else { return true }
                guard words.first == tools else { return false }
                let rest = Array(words.dropFirst())
                // A read of the user's apps is a read (`mail recent`), even though a `mail` send would ask.
                if ArisLocalReadPolicy.isRead(rest) { return false }
                // A note with lists takes the screen and presses keys in Notes: the user says yes first.
                if rest.first == "note", rest.contains("--markdown") || rest.contains("--checklist") { return true }
                return destructive.contains { rest.starts(with: $0) }
            }
        case .mcp(_, let tool):
            let name = tool.lowercased()
            return destructiveWords.contains { name.contains($0) }
        case .browserTask, .computerUse: return true
        case .fileChange: return false
        }
    }

    /// Whether the turn may vouch for a Claude Code launch.
    static func vouches(_ vouches: Bool, handsFree: Bool) -> Bool { vouches && !handsFree }

    /// What a hands-free turn on a restricted brain says when asked to send, delete or reach outside (the user's wording).
    static let askAgainLine = "보내기·지우기 같은 건 ⌥Space로 다시 말해 주면 할게요."

    /// The brain profile a hands-free turn or job runs on (the owner: every feature on every brain): Codex as itself (its
    /// gate asks); Claude as the sealed, hands-free Claude (no web or files, only the sealed aris-tools list, every
    /// outbound or destructive command refused but a message, which is the user's plain card); Antigravity as the sealed agy (no tools at all; Aris runs the sealed
    /// list's commands and the reads for it: ArisAgyRelay).
    static func profile(_ requested: ArisBrain) -> (brain: ArisBrain, sealed: Bool) {
        switch requested {
        case .codex: return (.codex, false)
        // An API brain: its own sealed process (the sealed functions only, ARIS_SEALED, every call through its gate).
        case .claude, .antigravity, .api: return (requested, true)
        }
    }

    /// A learned shortcut replays its commands without the AI or the gate's questions: never for a hands-free or
    /// untrusted turn.
    static func mayReplayShortcut(untrusted: Bool, handsFree: Bool) -> Bool { !untrusted && !handsFree }
}
