//
//  ArisTeammateScope+Gate.swift
//  aris-agent
//
//  A teammate's scopes as the agent's gates read them: whether an action the risk gate judges (Codex, the API brain)
//  is one the teammate may take, and the Claude Code deny rules for a teammate's Claude. Outside the scopes means
//  refused (`.never`), never a card.
//

import Foundation

extension ArisTeammateScope {
    /// Every aris-tools subcommand the scope table knows (the Claude deny rules name each one a teammate may not run).
    static let knownSubcommands = ["find", "open", "folder", "rename", "move", "trash", "convert", "merge", "split", "compress", "files",
                                   "finder", "note", "notes", "obsidian", "web", "weather", "stock", "currency", "maps", "canvas", "brief", "link", "tab", "aside",
                                   "desktop", "keys", "type", "screen", "selection", "clipboard", "shortcut", "shortcuts", "message",
                                   "messages", "mail", "mcp", "event", "calendars", "use-calendar", "calendar", "remind", "todo", "schedule",
                                   "skill", "shelf"]

    /// Plain reading commands: files, or the terminal.
    private static let reading: Set<String> = ["ls", "cat", "head", "tail", "wc", "file", "stat", "find", "mdfind", "mdls", "grep", "rg",
                                               "du", "df", "nl", "sed"]
    /// Commands that read no file at all: any teammate may run them (Codex runs them without asking).
    private static let harmless: Set<String> = ["pwd", "date", "cal", "echo", "which", "uname", "whoami", "sw_vers", "cd", "true"]
    /// Flags that make a reading command run a program or write a file.
    private static let findActions: Set<String> = ["-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprint0", "-fprintf", "-fls"]

    /// What a line of plain reads needs (bug hunt 2026-11-08, F3 and F7): `[]` when it reads no file (date, echo, cd…),
    /// `[.files]` when it reads files; nil when it isn't only reads (a program named by a path, a flag that runs or
    /// writes, a `sed` that isn't `-n` with a print, a pipe into anything else). Pieces chained with `&&`, `;` or `|`.
    static func readsNeed(_ command: String) -> Set<ArisTeammateScope>? {
        guard let pipes = pipeline(command) else { return nil }
        var needs = Set<ArisTeammateScope>()
        for part in pipes {
            guard let pieces = ArisCommandPolicy.segments(part) else { return nil }
            for piece in pieces {
                guard let words = ArisCommandPolicy.words(piece), let first = words.first else { return nil }
                let arguments = Array(words.dropFirst())
                if harmless.contains(first) { continue }
                guard reading.contains(first), plainRead(first, arguments) else { return nil }
                needs.insert(.files)
            }
        }
        return needs
    }

    /// `command` split at single `|` outside quotes; nil for `||`, a backslash, or an empty side.
    private static func pipeline(_ command: String) -> [String]? {
        var parts: [String] = [], part = "", quote: Character?
        let characters = Array(command)
        for (index, character) in characters.enumerated() {
            if let open = quote {
                if character == open { quote = nil }
                part.append(character)
            } else if character == "'" || character == "\"" {
                quote = character
                part.append(character)
            } else if character == "\\" {
                return nil
            } else if character == "|" {
                if index + 1 < characters.count, characters[index + 1] == "|" { return nil }
                if index > 0, characters[index - 1] == "|" { return nil }
                parts.append(part)
                part = ""
            } else {
                part.append(character)
            }
        }
        parts.append(part)
        let trimmed = parts.map { $0.trimmingCharacters(in: .whitespaces) }
        return trimmed.contains(where: \.isEmpty) ? nil : trimmed
    }

    /// A reading command whose arguments neither run a program nor write: no find action, no rg preprocessor or zip
    /// search, no `file -C`, and `sed` only as `-n` with print scripts (`12p`, `1,120p`, `$p`).
    private static func plainRead(_ command: String, _ arguments: [String]) -> Bool {
        switch command {
        case "find": return !arguments.contains(where: findActions.contains)
        case "rg": return !arguments.contains { $0.hasPrefix("--pre") || $0.hasPrefix("--hostname-bin") || $0.hasPrefix("--search-zip")
            || ($0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("z")) }
        case "file": return !arguments.contains { $0.hasPrefix("--compile") || ($0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("C")) }
        case "sed":
            guard arguments.first == "-n", arguments.count >= 2 else { return false }
            return arguments[1].range(of: #"^(\d+|\$)(,(\d+|\$))?p$"#, options: .regularExpression) != nil
                && !arguments.dropFirst(2).contains { $0.hasPrefix("-") }
        default: return true
        }
    }

    /// A command's aris-tools calls, nil when it isn't a plain chain of words.
    static func calls(_ command: String) -> [[String]]? {
        guard let pieces = ArisCommandPolicy.segments(ArisCommandPolicy.unwrap(command)) else { return nil }
        let words = pieces.map(ArisCommandPolicy.words)
        guard words.allSatisfy({ $0?.isEmpty == false }) else { return nil }
        return words.compactMap { $0 }
    }

    /// Whether the teammate with `scopes` may take `action` at all (the risk gate then judges it as ever).
    static func permits(_ action: ArisAction, scopes: Set<ArisTeammateScope>, tools: String) -> Bool {
        switch action {
        case .shell(let raw):
            let command = ArisCommandPolicy.unwrap(raw)
            // One desktop call with its text in a heredoc (the only way to type, bug hunt F2): its first line is what runs.
            if let desktop = ArisDesktopShell.parse(command, tools: tools) {
                return !mentionsEnvironment(ArisDesktopShell.commandLine(command, tools: tools))
                    && allows(toolsArguments: ["desktop"] + desktop.words, scopes: scopes)
            }
            // Never a command that reads or changes the environment (the scope variables above all).
            if touchesEnvironment(command, calls: calls(command), tools: tools) { return false }
            // Plain reads (Codex runs its own without asking): files or the terminal; nothing for those that read no file.
            if let needs = readsNeed(command) { return needs.isEmpty || scopes.contains(.files) || scopes.contains(.terminal) }
            return allowsShell(words: calls(command), tools: tools, readsOnly: false, scopes: scopes)
        case .fileChange: return scopes.contains(.files)
        case .mcp(let server, _): return needed(server: server).isSubset(of: scopes)
        case .computerUse: return scopes.contains(.apps)
        case .browserTask: return scopes.contains(.aside)
        }
    }

    /// The switches `action` needs and the teammate lacks, for the line the user reads when the gate stops it (audit
    /// team-8). Empty when it fits, or when no switch would allow it (a command that touches the environment, an
    /// aris-tools command the table doesn't know).
    static func missing(for action: ArisAction, scopes: Set<ArisTeammateScope>, tools: String) -> Set<ArisTeammateScope> {
        guard !permits(action, scopes: scopes, tools: tools) else { return [] }
        switch action {
        case .shell(let raw):
            let command = ArisCommandPolicy.unwrap(raw)
            if let desktop = ArisDesktopShell.parse(command, tools: tools) {
                guard !mentionsEnvironment(ArisDesktopShell.commandLine(command, tools: tools)) else { return [] }
                return (needed(forTools: ["desktop"] + desktop.words) ?? []).subtracting(scopes)
            }
            if touchesEnvironment(command, calls: calls(command), tools: tools) { return [] }
            if readsNeed(command) != nil { return [.files] }
            return (needed(shell: calls(command), tools: tools, readsOnly: false) ?? []).subtracting(scopes)
        case .fileChange: return [.files]
        case .mcp(let server, _): return needed(server: server).subtracting(scopes)
        case .computerUse: return [.apps]
        case .browserTask: return [.aside]
        }
    }

    /// The deny rules for a teammate's Claude: every aris-tools subcommand outside its scopes, the web tools without
    /// `web`, Read without files (on top of the hook, aris-tools' own refusal, and the tools left out of its list).
    static func claudeDenied(_ scopes: Set<ArisTeammateScope>, tools: String) -> [String] {
        let commands = knownSubcommands.filter { !allows(toolsArguments: [$0], scopes: scopes) }.map { "Bash(\(tools) \($0):*)" }
        return commands + (scopes.contains(.web) ? [] : ["WebSearch", "WebFetch"]) + (scopes.contains(.files) ? [] : ["Read"])
    }

    /// The tools a teammate's Claude is given at all (`--tools`, and what its init line must list): Bash, Read with
    /// files, the web tools with web.
    static func claudeTools(_ scopes: Set<ArisTeammateScope>?, sealed: Bool) -> [String] {
        let base = sealed ? ["Bash", "WebSearch", "WebFetch"] : ["Bash", "Read", "WebSearch", "WebFetch"]
        guard let scopes else { return base }
        return base.filter { tool in
            switch tool {
            case "Read": scopes.contains(.files)
            case "WebSearch", "WebFetch": scopes.contains(.web)
            default: true
            }
        }
    }
}
