//
//  ClaudeModels.swift
//  Aris
//
//  Pure value types for the Claude Code tab: hook events, session state and
//  the states they map to (what the Claude Code teammate's character shows).
//

import Foundation

enum ClaudeState: String, CaseIterable {
    case idle, thinking, typing, building, juggling, happy, error, notification, sleeping

    /// Higher wins when several sessions are active.
    var priority: Int {
        switch self {
        case .notification: return 8
        case .error: return 7
        case .juggling: return 6
        case .building: return 5
        case .typing: return 4
        case .thinking: return 3
        case .happy: return 2
        case .idle: return 1
        case .sleeping: return 0
        }
    }
}

struct ClaudeHookEvent {
    let name: String
    let sessionId: String
    let cwd: String
    let toolName: String?
    let toolSummary: String?
    let toolInput: [String: Any]
    /// Claude's own suggested permission rules (JSON array), echoed back for "Always allow".
    let permissionSuggestions: Data?
    /// First useful lines of the assistant's final message (Stop events).
    let lastMessage: String?
    /// The end of that message (Stop events), uncut: whether it stops on a question (ArisTeammateCompletion.question).
    let lastMessageEnd: String?
    /// The session's terminal, from the hook's request headers.
    let terminal: TerminalRef?
    /// Notification events only: "permission_prompt", "idle_prompt", ...
    let notificationType: String?
    /// Which coding agent sent it: "claude", or "codex" / "gemini" through agent-hook.sh (the X-Agent header).
    let agent: String
    /// SessionStart only: why the session started ("startup", "resume", "clear", "compact").
    let source: String?

    /// Gemini CLI's hook names for Claude's (Codex already uses Claude's).
    static let geminiEvents = ["BeforeTool": "PreToolUse", "AfterTool": "PostToolUse", "BeforeAgent": "UserPromptSubmit",
                               "AfterAgent": "Stop", "PreCompress": "PreCompact"]
    static let agents: Set = ["claude", "codex", "gemini"]

    /// Builds an event from a decoded hook payload; nil if it lacks the basics.
    init?(json: [String: Any], headers: [String: String] = [:]) {
        guard let raw = json["hook_event_name"] as? String,
              let sessionId = json["session_id"] as? String else { return nil }
        let agent = headers["x-agent"]?.lowercased() ?? "claude"
        self.agent = Self.agents.contains(agent) ? agent : "claude"
        self.name = self.agent == "gemini" ? Self.geminiEvents[raw] ?? raw : raw
        self.sessionId = sessionId
        self.cwd = json["cwd"] as? String ?? ""
        self.toolName = json["tool_name"] as? String
        let input = json["tool_input"] as? [String: Any] ?? [:]
        self.toolInput = input
        self.toolSummary = Self.summary(of: input)
        self.permissionSuggestions = Self.allowRules(in: json["permission_suggestions"])
        self.lastMessage = Self.oneLine(json["last_assistant_message"] as? String)
        self.lastMessageEnd = (json["last_assistant_message"] as? String).map { String($0.suffix(2_000)) }
        self.terminal = TerminalRef(headers: headers)
        self.notificationType = json["notification_type"] as? String
        self.source = json["source"] as? String
    }

    /// Only "always allow" *rules* are echoed back. Claude also suggests session-wide changes
    /// (setMode acceptEdits, addDirectories) that would silently widen what "Always allow" means.
    static func allowRules(in raw: Any?) -> Data? {
        let rules = (raw as? [[String: Any]] ?? []).filter {
            $0["type"] as? String == "addRules" && $0["behavior"] as? String == "allow"
        }
        return rules.isEmpty ? nil : try? JSONSerialization.data(withJSONObject: rules)
    }

    /// First non-empty line, stripped of Markdown markers and capped for a card.
    static func oneLine(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t#*>`-")) }
            .first { !$0.isEmpty }
        return line.map { String($0.prefix(140)) }
    }

    /// One-line preview of what the tool is about to do.
    private static func summary(of input: [String: Any]) -> String? {
        let keys = ["command", "file_path", "path", "url", "pattern", "description", "prompt"]
        for key in keys {
            if let value = input[key] as? String, !value.isEmpty {
                return String(value.prefix(240))
            }
        }
        return nil
    }

    /// File change carried by an Edit/MultiEdit/Write call, if any.
    var edit: ClaudeEdit? {
        guard let path = toolInput["file_path"] as? String else { return nil }
        let file = (path as NSString).lastPathComponent
        func lines(_ value: Any?) -> [String] {
            guard let text = value as? String, !text.isEmpty else { return [] }
            return Array(text.components(separatedBy: "\n").prefix(8))
        }
        switch toolName {
        case "Edit":
            return ClaudeEdit(file: file, path: path, removed: lines(toolInput["old_string"]), added: lines(toolInput["new_string"]))
        case "MultiEdit":
            let first = (toolInput["edits"] as? [[String: Any]])?.first
            return ClaudeEdit(file: file, path: path, removed: lines(first?["old_string"]), added: lines(first?["new_string"]))
        case "Write":
            return ClaudeEdit(file: file, path: path, removed: [], added: lines(toolInput["content"]))
        default:
            return nil
        }
    }

    /// What the user is being asked, derived from the tool being requested.
    var approvalKind: ClaudeApproval.Kind {
        switch toolName {
        case "AskUserQuestion":
            let questions = ClaudeQuestion.parse(toolInput["questions"])
            return questions.isEmpty ? .tool : .question(questions)
        case "ExitPlanMode":
            return .plan(toolInput["plan"] as? String ?? "")
        default:
            return .tool
        }
    }

    /// The state this event puts a session into; nil leaves it unchanged.
    var claudeState: ClaudeState? {
        switch name {
        case "SessionStart": return .idle
        case "UserPromptSubmit": return .thinking
        case "PreToolUse", "PostToolUse":
            switch toolName {
            case "Task", "Agent": return .juggling
            case "Bash": return .building
            default: return .typing
            }
        case "PostToolUseFailure", "StopFailure": return .error
        case "SubagentStart": return .juggling
        case "Stop", "SubagentStop": return .happy
        // "Waiting for your input" after a quiet minute is rest, not a request.
        case "Notification": return notificationType == "idle_prompt" ? .idle : .notification
        case "PermissionRequest": return .notification
        case "PreCompact": return .thinking
        default: return nil
        }
    }
}

/// One tool call in a session's recent activity list.
struct ClaudeStep: Identifiable, Equatable {
    let id = UUID()
    let tool: String
    let done: Bool
}

/// The last file change Claude made, as removed/added lines for the diff panel.
struct ClaudeEdit: Equatable {
    let file: String
    let path: String
    let removed: [String]
    let added: [String]
}

struct ClaudeSession: Identifiable, Equatable {
    let id: String
    let cwd: String
    let state: ClaudeState
    let lastEvent: Date
    var steps: [ClaudeStep] = []
    var edit: ClaudeEdit?
    var lastMessage: String?
    var terminal: TerminalRef?
    /// Share of the context window in use, from the status line.
    var contextPercent: Double?
    /// "claude", "codex" or "gemini" (ClaudeHookEvent.agent).
    var agent = "claude"

    var title: String {
        let name = (cwd as NSString).lastPathComponent
        let folder = name.isEmpty ? String(id.prefix(8)) : name
        switch agent {
        case "codex": return "Codex · \(folder)"
        case "gemini": return "Gemini · \(folder)"
        default: return folder
        }
    }
}

struct ClaudeOption: Equatable, Hashable {
    let label: String
    let detail: String
    /// Optional mockup/code Claude attaches to compare options side by side.
    var preview: String? = nil
}

struct ClaudeQuestion: Equatable, Identifiable {
    var id: String { question }
    let header: String
    let question: String
    let options: [ClaudeOption]
    let multiSelect: Bool

    static func parse(_ raw: Any?) -> [ClaudeQuestion] {
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let question = item["question"] as? String, !question.isEmpty else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> ClaudeOption? in
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                let preview = (option["preview"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(2_000)) }
                return ClaudeOption(label: label, detail: option["description"] as? String ?? "", preview: preview)
            }
            return ClaudeQuestion(
                header: item["header"] as? String ?? "",
                question: question,
                options: options,
                multiSelect: item["multiSelect"] as? Bool ?? false
            )
        }
    }
}

struct ClaudeApproval: Identifiable, Equatable {
    enum Kind: Equatable {
        case tool
        case question([ClaudeQuestion])
        case plan(String)
    }

    let id: UUID
    let sessionId: String
    let cwd: String
    let toolName: String
    let summary: String
    let kind: Kind
    /// Claude's suggested "always allow" rules; nil when it offered none.
    var alwaysRules: Data? = nil
    /// The request's tool_input, to recognise the same call finishing after a terminal answer.
    var toolInput: NSDictionary = [:]
    /// The file change an Edit/Write is asking to make, previewed on the card.
    var edit: ClaudeEdit? = nil

    /// PostToolUse echoes the request's input (plus extras such as `answers`), but no tool_use_id to match on.
    func isFinished(by event: ClaudeHookEvent) -> Bool {
        guard event.sessionId == sessionId, event.toolName == toolName else { return false }
        let finished = event.toolInput as NSDictionary
        return toolInput.allSatisfy { key, value in finished[key].map { (value as AnyObject).isEqual($0) } ?? false }
    }

    var canAlwaysAllow: Bool {
        if case .tool = kind { return alwaysRules != nil }
        return false
    }
}

/// "Done", an error or a plan limit: opens the notch onto the Claude tab for a moment, like an approval.
struct ClaudePeek: Equatable, Identifiable {
    enum Kind: Equatable { case done, error, limit }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    var message: String? = nil
    var sessionId: String? = nil
}

enum ClaudeDecision {
    case allow
    /// Allow, and persist Claude's suggested rules (JSON array of permission update entries).
    case allowAlways(rules: Data)
    case deny
    /// Allow, and hand Claude the user's answers (question text -> chosen label).
    case answer([String: String])
    /// Drop the connection so Claude Code asks in the terminal instead.
    case passthrough

    /// The hook response body for a request carrying `input`; nil means "drop the connection".
    func responseBody(input: [String: Any]) -> Data? {
        let decision: [String: Any]
        switch self {
        case .allow:
            decision = ["behavior": "allow"]
        case .allowAlways(let rules):
            let updates = (try? JSONSerialization.jsonObject(with: rules)) ?? []
            decision = ["behavior": "allow", "updatedPermissions": updates]
        case .deny:
            decision = ["behavior": "deny"]
        case .answer(let answers):
            decision = ["behavior": "allow", "updatedInput": input.merging(["answers": answers]) { _, new in new }]
        case .passthrough:
            return nil
        }
        let payload: [String: Any] = [
            "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }
}
