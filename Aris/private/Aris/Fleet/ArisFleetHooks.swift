//
//  ArisFleetHooks.swift
//  Aris
//
//  A Claude Code (or Codex, Gemini CLI) hook event as the fleet takes it (ArisFleetEvent): its plain fields, the
//  permission it asks from the hook's own structured fields (tool name, the command or file or address, a fingerprint
//  of the exact request), the terminal its headers named as a first guess at the host. Foundation only (tested).
//

import Foundation

extension ClaudeHookEvent {
    func fleetEvent(at now: Date) -> ArisFleetEvent {
        ArisFleetEvent(name: name, session: sessionId, cwd: cwd, tool: ArisFleetTool(agent: agent), toolName: toolName,
                       notification: notificationType, lastMessage: lastMessage, prompt: prompt,
                       permission: name == "PermissionRequest" ? fleetPermission : nil, terminal: terminal.map(Self.reach), at: now)
    }

    /// What a PermissionRequest asks, from its structured fields only: its whole input (ArisFleetPermission.make).
    var fleetPermission: ArisFleetPermission {
        let kind: ArisFleetPermission.Kind
        switch approvalKind {
        case .question: kind = .question
        case .plan: kind = .plan
        case .tool: kind = .tool
        }
        return ArisFleetPermission.make(tool: toolName ?? "Tool", input: toolInput, kind: kind)
    }

    static func reach(_ terminal: TerminalRef) -> ArisFleetReach {
        switch terminal {
        case .warp: return ArisFleetReach(kind: .warp, guessed: true)
        case .iterm: return ArisFleetReach(kind: .iterm, guessed: true)
        case .app(let bundle):
            switch bundle {
            case "com.apple.Terminal": return ArisFleetReach(kind: .terminal, guessed: true)
            case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.google.antigravity", "com.exafunction.windsurf":
                return ArisFleetReach(kind: .editorTerminal, app: bundle.split(separator: ".").last.map(String.init), guessed: true)
            default: return ArisFleetReach(kind: .window, app: bundle.split(separator: ".").last.map(String.init), guessed: true)
            }
        }
    }
}

extension ClaudeApproval {
    /// The fingerprint of the exact request this card holds (the same as the event's: ArisFleetPermission.fingerprint).
    var fleetFingerprint: String {
        ArisFleetPermission.make(tool: toolName, input: (toolInput as? [String: Any]) ?? [:], kind: .tool).fingerprint
    }

}
