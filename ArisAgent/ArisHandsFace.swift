//
//  ArisHandsFace.swift
//  aris-agent
//
//  The registry's MCP face (ARCHITECTURE 3.4 and Part 2): the provider's whole tool surface with the helper switch
//  `arisCore2` on (Settings › 할 수 있는 일 › 컴퓨터 제어 › 실험 기능, sent by the app: ArisHelperSwitches; off by
//  default, and then nothing here is used: the
//  launch flags, the hook and the init check are today's, byte for byte).
//
//  With it on, the open Claude (not the sealed or hands-free one, not a teammate's job) runs model-only: no built-in
//  tool at all (`--tools ""`) and exactly one MCP server, `aris`, a stdio server Claude Code starts as its own child,
//  `aris-agent hands-mcp --tools <aris-tools>` (ArisHandsShim), so it has Claude's environment and sits in its process
//  tree as Claude's Bash calls did. It lists every entry of ArisCapabilityBook (the typed aris-tools functions, the
//  generic `aris`, shell/file/web) as mcp__aris__<name>. No hook process starts for a call: the shim asks the trust
//  policy (ArisTrustDeciding; until jv-trust's lands, ArisTodayTrust gives today's open-Claude answer: an aris-tools call
//  is judged by the turn gate as the very shell line it is, with the hook's own input, folder and read judge), then
//  runs it: aris-tools with those words (a write still hands itself to POST /action-tool, a message to /message-tool,
//  computer use to /desktop-tool: the same cards and audit lines) or the helper capability itself.
//  · The taint classifier and the after-a-read backstop read a call of the face as the built-in call it stands for
//    (ArisClaudeDriver.observe: `asShell`): an aris-tools function as its Bash line, shell_run as Bash, web_fetch as
//    WebFetch, web_search as WebSearch, file_read as Read.
//  · Results that are content carry their source in `_meta` (ArisToolResult.Content), not prose.
//  · The init line must show this one server, connected, exactly its tool names and no built-in tool (ArisClaudeInit).
//  Codex keeps its shell and its own approval flow: an MCP call of Codex's would skip that flow, so it gets no face yet.
//

import Foundation

enum ArisHandsFace {
    /// The helper mode Claude Code starts the server as.
    static let mode = "hands-mcp"

    /// The entries the face serves: the whole book.
    static var entries: [ArisCapabilityEntry] { ArisCapabilityBook.all }

    static var tools: [ArisMCPServerWire.Tool] {
        entries.map { ArisMCPServerWire.Tool(name: $0.name, description: $0.description, inputSchema: $0.parameters) }
    }

    /// The tools' names as Claude Code lists them (its init line, its allow rules).
    static var clientNames: [String] { entries.map { ArisMCPServerWire.clientName($0.name) } }

    /// Whether a Claude gets the face: the open one only, never a teammate's job (its scopes are enforced per call by
    /// the shell's rules), and only with `arisCore2` on.
    static func applies(sealed: Bool, scopes: Set<ArisTeammateScope>?) -> Bool { !sealed && scopes == nil && ArisCore2.isOn() }

    /// How long one call may take: a Bash call's limit (ArisClaudeDriver.bashLimit), as aris-tools' own limits apply inside.
    static let callLimit: TimeInterval = ArisClaudeDriver.bashLimit

    /// `--mcp-config`: the one stdio server, started by Claude Code as its own child (so it has Claude's environment
    /// and sits in its process tree, where aris-tools' calls to the agent's routes must come from).
    static func config(agent: String, tools: String) -> String {
        let server: [String: Any] = ["type": "stdio", "command": agent, "args": [mode, "--tools", tools], "timeout": Int(callLimit * 1_000)]
        let data = (try? JSONSerialization.data(withJSONObject: ["mcpServers": [ArisMCPServerWire.serverName: server]], options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// What Claude Code is told besides the flags: the server's tools are never deferred behind a search tool (they
    /// must be in the init line by name, and the model must see them).
    static let environment = ["ENABLE_TOOL_SEARCH": "false"]

    /// A call of the face: its entry, and for an aris-tools entry its words, the text on its stdin (a desktop type)
    /// and the Bash line the gates read; nil for a name of no tool here or arguments that aren't what its schema says.
    static func call(function name: String, input: [String: Any], tools: String)
        -> (entry: ArisCapabilityEntry, argv: [String]?, stdin: String?, line: String?)? {
        guard let entry = ArisCapabilityBook.entry(named: name) else { return nil }
        guard case .arisTools(_, let makeStdin) = entry.run else { return (entry, nil, nil, nil) }
        guard let argv = entry.argv(input) else { return nil }
        // A desktop type's text goes on stdin, never in argv (as the API brain's helper sends it).
        var stdin: String?
        if argv.first == "desktop", argv.last == "--stdin" {
            guard let text = makeStdin?(input), text.utf8.count <= 131_072, !text.contains("\0") else { return nil }
            stdin = text
        }
        return (entry, argv, stdin, ArisCapabilityGate.shellLine(argv, stdin: stdin, tools: tools))
    }

    /// The tool call as the Claude driver's taint classifier and backstop read it: the built-in call it stands for (a
    /// call that can't be read as one is left as it came, which they count as outside text and refuse after a read).
    static func asShell(_ name: String, input: [String: Any], tools: String) -> (name: String, command: String?, input: [String: Any]) {
        guard let function = ArisMCPServerWire.function(clientName: name), let found = call(function: function, input: input, tools: tools) else {
            return (name, input["command"] as? String, input)
        }
        if let line = found.line { return ("Bash", line, ["command": line]) }
        let text = { (key: String) in ArisAPICatalog.text(input[key]) ?? "" }
        switch found.entry.id {
        case "shell.run": return ("Bash", text("command"), ["command": text("command")])
        case "web.fetch": return ("WebFetch", nil, ["url": text("url"), "prompt": ""])
        case "web.search": return ("WebSearch", nil, ["query": text("query")])
        case "file.read": return ("Read", nil, ["file_path": (text("path") as NSString).expandingTildeInPath])
        default: return (name, nil, input)
        }
    }

    /// Whether Claude Code's own rules for the open Claude would refuse the Bash line (its --disallowedTools patterns
    /// for aris-tools: `Bash(<tools> <words>:*)`), so the face refuses the same call.
    static func refusedByRules(_ argv: [String], refused: [String] = ArisClaudeDriver.openRefused) -> Bool {
        let said = argv.joined(separator: " ")
        return refused.contains { said == $0 || said.hasPrefix($0 + " ") }
    }

    static let rulesRefusal = "Refused: Aris's rules don't let this conversation run that."
}
