//
//  ArisFleet.swift
//  Shared/Core (app, aris-agent, tests)
//
//  Every coding-agent session on this Mac as one record (ARCHITECTURE Part 3, F2): Claude Code, Codex and Gemini CLI,
//  as the app's hook server hears them (Codex and Gemini through agent-hook.sh) and as Claude Code's own list of its
//  live sessions shows them (`claude agents --json`, read by the helper). What is known per tool:
//   · Claude Code: every hook (start, prompt, tools, permission, notification, stop, failure, end); pid, start time,
//     title and background from its list; the exact host (tmux, screen, WezTerm, kitty, iTerm2, Terminal, Warp, an
//     editor's terminal, the Claude app, an editor panel, a background session) from its process.
//   · Codex: SessionStart, UserPromptSubmit, Pre/PostToolUse, PermissionRequest and Stop (no SessionEnd, no pid, no
//     list): state, folder, last tool, last message. It answers its own permissions in its terminal; Aris can't type
//     into it.
//   · Gemini CLI: its hooks mapped to Claude's names, the same as Codex otherwise.
//  A session's own words (its last message, its listed title) are model-written: they are kept apart (ArisFleetText)
//  and never go into the conversation's context unless `fleet.status` is asked for. Pure.
//

import Foundation

enum ArisFleetTool: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude", codex, gemini

    /// The tool as a person names it.
    var name: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        }
    }

    /// From the hook's agent name ("claude", "codex", "gemini"); anything else is Claude Code, as the hook server reads it.
    init(agent: String) { self = ArisFleetTool(rawValue: agent.lowercased()) ?? .claudeCode }
}

enum ArisFleetState: String, Codable, Sendable {
    case working
    /// It asked the user something (a question, a plan to approve, a dialog).
    case waitingInput = "waiting-input"
    /// It waits for the user's answer to a permission request.
    case waitingPermission = "waiting-permission"
    /// Its turn is over (or it never started one): waiting for the next prompt.
    case idle
    /// Its turn ended on an error.
    case failed
    /// The session ended, or went away.
    case gone

    /// It needs the user: a question, a permission, or its turn failed.
    var needsUser: Bool { self == .waitingInput || self == .waitingPermission || self == .failed }
    var isLive: Bool { self != .gone }
}

/// Who started a session.
enum ArisFleetStarter: String, Codable, Sendable {
    /// The user, in a terminal or an editor.
    case user
    /// Aris, as its Claude Code teammate (a job the owner asked for).
    case arisTeammate = "aris-teammate"
    /// Aris, as one of its own background tasks (not populated yet: those run in Aris's own folder, which the fleet leaves out).
    case arisTask = "aris-task"
}

/// How a session can be reached to type into it (ArisSessionHost, as the helper classified its process; or the terminal
/// its hooks named, when the helper hasn't looked).
struct ArisFleetReach: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case tmux, screen, wezterm, kitty, iterm, terminal, warp
        case editorTerminal = "editor-terminal"
        case window, claudeApp = "claude-app"
        case editorPanel = "editor-panel"
        case background, unsupported, unknown
    }

    let kind: Kind
    /// The app it lives in, as a person names it ("VS Code", "Ghostty").
    var app: String? = nil
    /// Only the terminal the hooks named was seen, not the process: a guess until the helper looks.
    var guessed = false

    /// Aris can type into it (the send checks the exact place again before any key).
    var reachable: Bool {
        switch kind {
        case .editorPanel, .background, .unsupported: return false
        case .unknown: return false
        default: return true
        }
    }

    /// The place is found exactly (a pane, a window id, a tty) rather than by a window's title.
    var exact: Bool { [.tmux, .screen, .wezterm, .kitty, .iterm, .terminal].contains(kind) }

    var name: String {
        switch kind {
        case .tmux: return "tmux"
        case .screen: return "screen"
        case .wezterm: return "WezTerm"
        case .kitty: return "kitty"
        case .iterm: return "iTerm2"
        case .terminal: return "Terminal"
        case .warp: return "Warp"
        case .editorTerminal: return (app ?? "editor") + " terminal"
        case .window: return app ?? "terminal window"
        case .claudeApp: return "Claude app"
        case .editorPanel: return (app ?? "editor") + " Claude Code panel"
        case .background: return "background session"
        case .unsupported: return app ?? "unknown app"
        case .unknown: return "unknown"
        }
    }

    /// Why it can't be reached, and what would make it reachable; nil when it can.
    func unreachable(english: Bool) -> String? {
        switch kind {
        case .editorPanel:
            return english ? "it runs in \(name), which Aris can't type into. Run it in a terminal (or the editor's own terminal, or tmux) to reach it."
                : "\(app ?? "에디터")의 Claude Code 패널에서 돌고 있어서 Aris가 입력할 수 없어요. 터미널(에디터 안 터미널이나 tmux도 돼요)에서 열면 보낼 수 있어요."
        case .background:
            return english ? "it is a background session with no input box. Open it with `claude attach` to reach it."
                : "백그라운드 세션이라 입력창이 없어요. 터미널에서 claude attach로 열면 보낼 수 있어요."
        case .unsupported:
            return english ? "it runs in \(app ?? "an app") that Aris can't type into. Run it in a terminal or tmux to reach it."
                : "\(app ?? "알 수 없는 앱")에서 돌고 있어서 입력할 수 없어요. 터미널이나 tmux에서 열면 보낼 수 있어요."
        case .unknown:
            return english ? "Aris doesn't know where it runs (its process wasn't found)."
                : "어디에서 돌고 있는지 찾지 못했어요(프로세스가 안 보여요)."
        default:
            return nil
        }
    }
}

/// Text a session's model wrote (its last message, its listed title): data, never the owner's instruction.
struct ArisFleetText: Equatable, Codable, Sendable {
    let text: String
    /// Where it came from: "Claude Code session in aris-jv-world (its last message)".
    let source: String
}

/// A permission a session waits on, from the hook's own structured fields (never from the session's prose).
/// `shown` is the request's complete input, rendered legibly (every argument, sorted by name, each value whole): the
/// text the owner's allow card shows, and the very text the fingerprint is taken over, so what he sees and what his
/// yes lets through are the same bytes. An input that can't be shown whole and legibly (too long, control or hidden
/// characters, binary) has no `shown`, and Aris never allows it: the owner answers it in the session itself.
struct ArisFleetPermission: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable { case tool, question, plan }
    let tool: String
    /// The call's main argument (the command, the file, the address), for the spoken summary only.
    let detail: String
    let kind: Kind
    /// The request exactly: an answer is applied only to the very request the owner saw.
    let fingerprint: String
    var shown: String? = nil

    /// The longest input shown on a card.
    static let longestShown = 8_000

    /// A permission from the hook's tool name and its whole input.
    static func make(tool: String, input: [String: Any], kind: Kind) -> ArisFleetPermission {
        let main = ["command", "file_path", "path", "url", "pattern"].lazy.compactMap { input[$0] as? String }.first { !$0.isEmpty }
        let shown = render(input)
        return ArisFleetPermission(tool: tool, detail: String((main ?? shown ?? "").prefix(4_000)), kind: kind,
                                   fingerprint: shown.map { fingerprint(tool: tool, shown: $0) } ?? fingerprint(tool: tool, bytes: canonical(input)),
                                   shown: shown)
    }

    /// Every argument as "name: value", sorted by name, each value whole (text as it is; anything else as sorted JSON);
    /// nil when it can't be shown whole and legibly.
    static func render(_ input: [String: Any]) -> String? {
        var lines: [String] = []
        for key in input.keys.sorted() {
            let value: String
            switch input[key] {
            case let text as String: value = text
            case let number as NSNumber:
                value = CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
            case is NSNull: value = "null"
            case let other?:
                guard JSONSerialization.isValidJSONObject([other]),
                      let data = try? JSONSerialization.data(withJSONObject: other, options: [.sortedKeys, .withoutEscapingSlashes]),
                      let text = String(data: data, encoding: .utf8) else { return nil }
                value = text
            case nil: return nil
            }
            lines.append("\(key): \(value)")
        }
        let text = lines.joined(separator: "\n")
        guard text.count <= longestShown, legible(text) else { return nil }
        return text
    }

    /// No control character but line breaks and tabs, no hidden format character (a direction override, a zero width).
    static func legible(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            if scalar == "\n" || scalar == "\t" { return false }
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned: return true
            default: return false
            }
        }
    }

    /// FNV-1a over the tool's name and the shown text: the same in the app and the helper.
    static func fingerprint(tool: String, shown: String) -> String { fingerprint(tool: tool, bytes: Data(shown.utf8)) }

    static func fingerprint(tool: String, bytes: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in Array(tool.utf8) + [0] + Array(bytes) {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    /// The input as canonical JSON (the fingerprint of one that can't be shown).
    static func canonical(_ input: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])) ?? Data()
    }
}

struct ArisFleetSession: Equatable, Codable, Sendable {
    let id: String
    var tool: ArisFleetTool
    /// The short number a person says ("3번"), stable while the session lives.
    var number: Int
    var pid: Int32?
    var folder: String
    var branch: String?
    /// The first thing typed into it (not a slash command), one line: the user's words when the user started it.
    var firstRequest: String?
    /// Claude Code's own name for it (its list): may be written by its model.
    var title: ArisFleetText?
    var state: ArisFleetState
    var lastTool: String?
    var lastMessage: ArisFleetText?
    var pending: ArisFleetPermission?
    var startedAt: Date
    var lastActive: Date
    var starter: ArisFleetStarter
    var reach: ArisFleetReach
    /// Heard by the hooks at least once (else known only from the list).
    var heard = false
    /// Seen in Claude Code's own list at least once (then missing from a whole list means it is over).
    var listed = false
    /// When it went (gone sessions are kept a while, so their number isn't handed out at once).
    var goneAt: Date?
    /// A card waits in the notch for its permission (set by the app as it answers): only then can Aris answer it.
    var answerable = false

    /// The folder's own name ("~" for the home folder).
    func project(home: String) -> String {
        let path = (folder as NSString).standardizingPath
        if path == (home as NSString).standardizingPath { return "~" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? String(id.prefix(8)) : name
    }
}

struct ArisFleet: Equatable, Codable, Sendable {
    /// In number order.
    var sessions: [ArisFleetSession] = []

    var live: [ArisFleetSession] { sessions.filter { $0.state.isLive } }
    var needingUser: [ArisFleetSession] { live.filter { $0.state.needsUser } }

    func session(_ id: String) -> ArisFleetSession? { sessions.first { $0.id == id } }
    func numbered(_ number: Int) -> ArisFleetSession? { live.first { $0.number == number } }

    var json: Data { (try? ArisFleet.encoder.encode(self)) ?? Data("{}".utf8) }

    static func decoded(_ data: Data) -> ArisFleet? { try? decoder.decode(ArisFleet.self, from: data) }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
