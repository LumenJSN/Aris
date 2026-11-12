//
//  ArisSealedTools.swift
//  aris-tools (also built into aris-agent)
//
//  What the sealed Claude may run (R2 = a): the turns that saw the user's screen, and hands-free ones. aris-tools
//  subcommands that reach nothing outside the Mac, plus (the owner, 2026-11-06: screen turns get the same tools) the reads
//  of the user's own apps and the connected services; its hook sends every read, and its web search and fetch, to the read
//  judge first (ArisReadGate), and the services go through the agent's one gate; a maps lookup (--json) is such a judged
//  read, and for the sealed Claude of a screen turn so are the weather, a stock, Canvas and the brief (they put words
//  in a URL, so never unjudged, and never for agy's relay or a hands-free turn). No Maps opened, no links, reminders,
//  clipboard, screen, selection or memory, and none of the ungated brain's refused actions. The agent gives Claude Code these as exact allow rules, and sets ARIS_SEALED=1 for the process, so
//  aris-tools itself refuses anything else too, checking every argument. What writes, sends or opens something is not
//  on the list: the sealed Claude of a screen turn hands each such call to the agent's gate (ArisHandOff), which judges
//  it as Codex's and asks the user on a card; nothing of it runs in the sealed process. Pure, so the tests run it.
//

import CryptoKit
import Foundation

enum ArisSealedTools {
    static let environmentKey = "ARIS_SEALED"

    /// The read-only and fixed forms: exactly these words, nothing more (an exact rule each). Not `memory`: a sealed
    /// turn saw the screen or was heard hands-free, and the user's memories don't go to either.
    static let bare: [[String]] = [
        ["activity"], ["activity", "--today"], ["schedule", "list"], ["todo"], ["calendars"], ["shortcuts"],
        ["calendar"], ["music", "play"], ["music", "pause"], ["music", "next"], ["music", "previous"],
        ["timer", "pomodoro"], ["timer", "stop"],
    ]

    /// Subcommands that take arguments (a prefix rule each); `allows` checks each one's arguments.
    static let withArguments: [[String]] = [["timer"], ["volume"], ["window"], ["windows"], ["tile"], ["new"], ["app"], ["folder"]]

    /// The only folders `folder` opens (revealed in Finder, never opened as a path).
    static let folders = ["Desktop", "Downloads", "Documents"]

    /// Set for the hands-free sealed Claude: the user's memories are never read on a hands-free turn (every brain alike).
    static let handsFreeKey = "ARIS_SEALED_HANDS_FREE"

    /// Set for the sealed Claude alone (the owner, 2026-11-08): `message <to> <text>` is on its list, and aris-tools hands it to
    /// the agent (POST /message-tool), which shows the user their plain card (never a countdown) and refuses it after outside
    /// text. Never for agy's relay, the turn gate's clean reads or the sealed API brain: they share `allows` without it.
    static let messageKey = "ARIS_SEALED_MESSAGES"

    /// Claude Code's allow rules for the absolute aris-tools path: the list, the reads of the user's apps (each read verb,
    /// bare and with words) and the services. `memory`: his memories too (a screen turn's, never a hands-free one's).
    /// `messages`: the sealed Claude's `message` too (messageKey). `handOff`: and every write aris-tools hands to the
    /// agent for it (ArisHandOff.sealedKey): never run in its own process.
    static func allowRules(tools: String, memory: Bool = false, messages: Bool = false, handOff: Bool = false) -> [String] {
        let reads = ArisLocalReadPolicy.forms.keys.sorted().flatMap { command in
            (ArisLocalReadPolicy.forms[command] ?? []).sorted().flatMap { verb in ["Bash(\(tools) \(command) \(verb))", "Bash(\(tools) \(command) \(verb):*)"] }
        }
        return bare.map { "Bash(\(tools) \($0.joined(separator: " ")))" }
            + withArguments.map { "Bash(\(tools) \($0.joined(separator: " ")):*)" }
            + reads + ["Bash(\(tools) mcp list)", "Bash(\(tools) mcp list:*)", "Bash(\(tools) mcp call:*)", "Bash(\(tools) mcp wait:*)"]
            + desktopVerbs.sorted().map { "Bash(\(tools) desktop \($0):*)" }
            + ["Bash(\(tools) skill list)", "Bash(\(tools) skill read:*)", "Bash(\(tools) skill run:*)", "Bash(\(tools) skill wait:*)", "Bash(\(tools) aside:*)"]
            + ["Bash(\(tools) maps search:*)", "Bash(\(tools) maps directions:*)"]
            + (memory ? ["Bash(\(tools) memory)", "Bash(\(tools) memory:*)", "Bash(\(tools) recall)", "Bash(\(tools) recall:*)"] : [])
            + (messages ? ["Bash(\(tools) message:*)"] : [])
            + (handOff ? ArisHandOff.forms.map { "Bash(\(tools) \($0.joined(separator: " ")):*)" } + ["Bash(\(tools) undo)"]
                + outsideReads.flatMap { ["Bash(\(tools) \($0))", "Bash(\(tools) \($0):*)"] } : [])
    }

    /// The reads that reach a service outside the Mac (ArisTurnGate.isOutsideRead): on the sealed Claude's list of a
    /// screen turn since its hook puts each to the read judge first, as its web searches are (audit gate-1: "오늘 날씨
    /// 어때?" was answered "화면을 보는 중에는 못 해요").
    static let outsideReads = ["weather", "stock", "currency", "canvas", "brief"]

    /// Whether `arguments` (after the program name) are one of the sealed forms, each argument as documented.
    /// `memory`: `memory [words]` too. `messages`: the sealed Claude's `message <to> <text>` (messageKey).
    /// `handOff`: the sealed Claude's writes too (ArisHandOff.sealedKey): aris-tools hands each to the agent's gate and
    /// never runs it there. Without it (the default: agy's relay, the sealed API brain, a hands-free turn) the list is
    /// what it always was.
    static func allows(_ arguments: [String], memory: Bool = false, messages: Bool = false, handOff: Bool = false) -> Bool {
        guard !arguments.isEmpty, arguments.allSatisfy(isPlain) else { return false }
        if bare.contains(arguments) { return true }
        if messages, ArisTurnGate.isAgentMessage(arguments) { return true }
        if handOff, ArisHandOff.isWrite(arguments) { return true }
        // The weather, a stock, Canvas, the brief: reads the hook's judge checks first (never for agy's relay or a hands-free turn).
        if handOff, ArisTurnGate.isOutsideRead(arguments), arguments.count <= 12, arguments.allSatisfy({ $0.count <= 200 }) { return true }
        if memory, ArisReadGate.isMemoryRead(arguments) || ArisWorkRecallWords.parse(arguments) != nil { return true }
        // The user's own apps, read only (the hook asks the judge first).
        if ArisLocalReadPolicy.isRead(arguments) { return true }
        let rest = Array(arguments.dropFirst())
        switch arguments[0] {
        case "timer": return timerForm(rest)
        case "volume": return rest.count == 1 && (["up", "down", "mute", "unmute"].contains(rest[0]) || number(rest[0], in: 0...100))
        case "window": return !rest.isEmpty && ["left", "right", "full", "center", "maximize"].contains(rest[0]) && appName(Array(rest.dropFirst()), optional: true)
        case "windows": return appName(rest, optional: true)
        case "tile": return withFlag("--grid", in: rest, value: isGrid).map { appName($0, optional: false, commas: true) } ?? false
        case "new": return withFlag("--count", in: rest, value: { number($0, in: 1...9) }).map { appName($0, optional: false) } ?? false
        case "app": return appName(rest, optional: false)
        case "folder": return rest.count == 1 && folderName(rest[0]) != nil
        case "mcp": return mcpForm(rest)
        case "desktop": return desktopForm(rest)
        case "skill": return skillForm(rest)
        // Website work for Aside: the agent's one gate asks the user on every sealed turn (the screen, hands-free).
        case "aside": return !rest.isEmpty && rest.joined(separator: " ").count <= 4_000
        // A maps lookup (--json, nothing opens): a read, the hook asks the judge first (QA BUG-1). Never Maps opened.
        case "maps": return ArisReadGate.isMapsLookup(arguments)
        default: return false
        }
    }

    /// `skill list`, `skill read <name> [file]` or `skill run <name> scripts/<file> [arguments…]`: the agent reads only
    /// inside the skill and asks the user before a script runs (and never on a turn that saw the screen).
    static func skillForm(_ rest: [String]) -> Bool {
        let name = #"^[a-z0-9][a-z0-9-]{0,63}$"#, file = #"^[A-Za-z0-9_][A-Za-z0-9_./-]{0,199}$"#
        func fits(_ word: String, _ pattern: String) -> Bool { word.range(of: pattern, options: .regularExpression) != nil && !word.contains("..") }
        switch rest.first {
        case "list": return rest.count == 1
        case "wait": return rest.count == 2 && fits(rest[1], #"^[0-9a-f]{16}$"#)
        case "read": return (rest.count == 2 || rest.count == 3) && fits(rest[1], name) && (rest.count == 2 || fits(rest[2], file))
        case "run":
            return rest.count >= 3 && rest.count <= 23 && fits(rest[1], name) && fits(rest[2], file) && rest[2].hasPrefix("scripts/")
                && rest.dropFirst(3).allSatisfy { $0.count <= 2_000 }
        default: return false
        }
    }

    /// `mcp list [service]` or `mcp call <service> <tool> [<json object> | key=value …]`: names as the agent takes them,
    /// at most one JSON object (it was single-quoted), each pair a key, =, then a value.
    private static func mcpForm(_ rest: [String]) -> Bool {
        let service = #"^[a-z0-9][a-z0-9_-]{0,31}$"#, tool = #"^[A-Za-z0-9_.\-/]{1,128}$"#
        func fits(_ word: String, _ pattern: String) -> Bool { word.range(of: pattern, options: .regularExpression) != nil }
        switch rest.first {
        case "list": return rest.count == 1 || (rest.count == 2 && fits(rest[1], service))
        // Collecting a call that outlasted one command (the agent's ArisSlowCalls): only its id.
        case "wait": return rest.count == 2 && fits(rest[1], #"^[0-9a-f]{16}$"#)
        case "call":
            guard rest.count >= 3, fits(rest[1], service), fits(rest[2], tool) else { return false }
            let values = Array(rest.dropFirst(3))
            if values.isEmpty { return true }
            if values.count == 1, values[0].hasPrefix("{"), values[0].hasSuffix("}") { return values[0].count <= 64 * 1_024 }
            return values.count <= 40 && values.allSatisfy { fits($0, #"^[A-Za-z0-9_]{1,64}=.*$"#) }
        default: return false
        }
    }

    /// Computer use's verbs (ArisDesktopWords): the agent's desktop engine reads every word again and gates each call
    /// (reads judged on a careful turn, actions on the user's card), whichever brain sent it.
    static let desktopVerbs: Set<String> = ["see", "snapshot", "menu", "dialog", "window", "list-windows", "app", "dock", "click", "click-at",
                                            "type", "set-value", "press", "scroll", "drag", "batch", "wait"]

    /// `desktop <verb> …`: a known verb and at most 20 plain words (the engine checks each flag and value).
    private static func desktopForm(_ rest: [String]) -> Bool {
        guard let verb = rest.first, desktopVerbs.contains(verb), rest.count <= 21 else { return false }
        // Collecting a slow call: only its id (security review LOW 8, as `mcp wait`).
        if verb == "wait" { return rest.count == 2 && rest[1].range(of: #"^[0-9a-f]{16}$"#, options: .regularExpression) != nil }
        return rest.allSatisfy { $0.count <= 400 }
    }

    /// `timer <minutes> [--focus]`: whole or decimal minutes, up to a day.
    private static func timerForm(_ rest: [String]) -> Bool {
        let words = rest.last == "--focus" ? Array(rest.dropLast()) : rest
        guard words.count == 1, let minutes = Double(words[0]), words[0].allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return false }
        return minutes > 0 && minutes <= 24 * 60
    }

    private static func number(_ word: String, in range: ClosedRange<Int>) -> Bool {
        word.allSatisfy { $0.isASCII && $0.isNumber } && Int(word).map(range.contains) == true
    }

    /// "2x2": rows and columns 1…9.
    private static func isGrid(_ word: String) -> Bool {
        let parts = word.lowercased().split(separator: "x", omittingEmptySubsequences: false).map(String.init)
        return parts.count == 2 && parts.allSatisfy { number($0, in: 1...9) }
    }

    /// The words without `flag` and its value (at most once, value checked); nil when the flag or its value is wrong,
    /// or any other flag is there.
    private static func withFlag(_ flag: String, in words: [String], value: (String) -> Bool) -> [String]? {
        var rest = words
        if let index = rest.firstIndex(of: flag) {
            guard index + 1 < rest.count, value(rest[index + 1]) else { return nil }
            rest.removeSubrange(index...(index + 1))
            guard !rest.contains(flag) else { return nil }
        }
        return rest
    }

    /// An app's name: plain words, no "/", none starting with "-" (no flags), at most 60 characters. `commas`: a list
    /// of apps ("Safari,Notes").
    private static func appName(_ words: [String], optional: Bool, commas: Bool = false) -> Bool {
        if words.isEmpty { return optional }
        let name = words.joined(separator: " ")
        let names = commas ? name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } : [name]
        return name.count <= 60 && !names.isEmpty && names.allSatisfy { !$0.isEmpty && !$0.hasPrefix("-") && !$0.contains("/") }
            && words.allSatisfy { !$0.hasPrefix("-") }
    }

    /// "Downloads" or "~/Downloads" (one of `folders`) → its name; nil for anything else.
    static func folderName(_ word: String) -> String? {
        let name = word.hasPrefix("~/") ? String(word.dropFirst(2)) : word
        return folders.contains(name) ? name : nil
    }

    /// The real folder behind an allowed name in `home`: resolved with realpath, a directory, and not a bundle or
    /// package. Nil otherwise.
    static func folderURL(_ word: String, home: String) -> URL? {
        guard let name = folderName(word) else { return nil }
        let path = (home as NSString).appendingPathComponent(name)
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        let url = URL(fileURLWithPath: String(cString: real), isDirectory: true)
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
              values.isDirectory == true, values.isPackage != true, url.pathExtension.isEmpty else { return nil }
        return url
    }

    /// aris-tools' own check: under ARIS_SEALED=1, the message refusing anything outside the list; nil to go ahead.
    static func refusal(environment: [String: String], arguments: [String]) -> String? {
        guard environment[environmentKey] == "1",
              !allows(arguments, memory: environment[handsFreeKey] != "1", messages: environment[messageKey] == "1",
                      handOff: environment[ArisHandOff.sealedKey] == "1" && environment[handsFreeKey] != "1") else { return nil }
        return "aris-tools: \(arguments.first ?? "this") isn't available in this conversation (only its own short list is)"
    }

    /// Set for Antigravity (no per-turn gate): aris-tools then refuses to read the user's messages, mail, notes and Obsidian
    /// itself, on top of agy's deny rules (ArisLocalReadPolicy.privateReads). agy asks Aris to read them (ArisAgyRelay).
    static let ungatedKey = "ARIS_UNGATED"
    static let ungatedLine = "Refused: don't read these yourself. Reply with only an ```aris-run block naming the command, and Aris reads it for you."

    /// Under ARIS_UNGATED=1, the refusal for a private read; nil to go ahead.
    /// Said for any command that names computer use's runtime (Peekaboo, its folders): only the agent runs it (I11).
    static let runtimeRefusal = "Refused: only Aris's agent runs computer use's tools. Use `aris-tools desktop …`."

    static func ungatedRefusal(environment: [String: String], arguments: [String]) -> String? {
        // Every brain's aris-tools, agy's open one included: no argument that is a path into computer use's runtime or
        // Peekaboo's store (I11). Text that only names Peekaboo (a note, a typed message) is fine.
        if arguments.contains(where: ArisProtectedPlaces.namesRuntimePlace) { return runtimeRefusal }
        // `mcp` too (I6): agy reaches the connected services only through Aris's relay, never from a process with a web search.
        // `desktop` too: agy works in apps only through the relay, whose gate is the desktop engine's.
        // File changes too (move, rename, a new folder, a conversion): agy can't tell when outside text came in, so its
        // own aris-tools refuses them and its relay runs them behind the user's card (ArisFileRelay).
        // An agy job hands website work to Aside as exactly `aside "<brief>"` (the agent's route cards every such call).
        if environment[ungatedKey] == "1", arguments.first == "aside" { return arguments.count == 2 ? nil : ungatedLine }
        guard environment[ungatedKey] == "1", let first = arguments.first,
              ArisLocalReadPolicy.privateReads.contains(first) || ["mcp", "skill", "desktop", "move", "rename"].contains(first)
                || ArisConvertWords.verbs.contains(first)
                || arguments.starts(with: ["folder", "new"]) else { return nil }
        return ungatedLine
    }

    /// The subcommand aris-tools runs as the sealed Claude's PreToolUse hook: it reads the hook's JSON on stdin and
    /// exits 2 (block, before the call runs) unless the call is a Bash command `permits` allows, or a read (one of
    /// The user's apps, the web) the read judge allowed; then it exits 0 and says nothing (never "allow": the permission
    /// rules still decide). Never on the sealed allow list.
    static let hookFlag = "sealed-gate"
    /// Seconds Claude Code gives the hook (it may wait for the read judge).
    static let hookTimeout = ArisReadGate.hookTimeout

    /// The sealed Claude's settings (`--settings`, with `--setting-sources ""` so no user settings load): one
    /// PreToolUse hook on every tool that asks aris-tools before anything runs. Anything but a clean yes blocks
    /// (`|| exit 2`), so a missing or broken aris-tools fails closed.
    static func hookSettings(tools: String) -> String {
        let quoted = "'" + tools.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = "\(quoted) \(hookFlag) || exit 2"
        let settings: [String: Any] = ["disableAllHooks": false,
                                       "hooks": ["PreToolUse": [["matcher": "*", "hooks": [["type": "command", "command": command,
                                                                                         "timeout": hookTimeout]]]]]]
        let data = (try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    enum HookVerdict: Equatable {
        case allow
        /// A read: the read judge decides.
        case judge(ArisReadCall)
        case block
    }

    /// The hook's answer for one PreToolUse input: a Bash call `permits` allows goes (a read of the user's apps or, off a
    /// hands-free turn, his memories, to the judge first), the web tools go to the judge (a WebFetch only to an address
    /// that resolves to public addresses), anything else is blocked.
    static func hookVerdict(input: Data, tools: String, handsFree: Bool = false, messages: Bool = false, handOff: Bool = false,
                            resolve: (String) -> [String]? = ArisWebFetch.liveResolve) -> HookVerdict {
        guard let object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any], let name = object["tool_name"] as? String else { return .block }
        let toolInput = object["tool_input"] as? [String: Any] ?? [:]
        if ArisReadGate.fetchAllowed(tool: name, input: toolInput, resolve: resolve) == false { return .block }
        if let call = ArisReadGate.call(webTool: name, input: toolInput) { return .judge(call) }
        if name == "Bash", let command = toolInput["command"] as? String,
           ArisProtectedPlaces.executesComputerRuntime(ArisDesktopShell.commandLine(command, tools: tools)) { return .block }
        // A desktop call with its text on stdin (a quoted heredoc, the one form the shell never expands): the agent's
        // desktop engine gates it.
        if name == "Bash", let command = toolInput["command"] as? String, command.contains("\n"),
           let line = ArisDesktopShell.parse(command, tools: tools), line.text != nil {
            return allows(["desktop"] + line.words) ? .allow : .block
        }
        guard name == "Bash", let command = toolInput["command"] as? String,
              permits(command: command, tools: tools, memory: !handsFree, messages: messages, handOff: handOff && !handsFree),
              let rest = words(command).map({ Array($0.dropFirst()) }) else { return .block }
        return ArisReadGate.isJudgedRead(rest) || ArisTurnGate.isOutsideRead(rest) ? .judge(ArisReadGate.call(arisTools: rest)) : .allow
    }

    /// Commands that are never the sealed list, refused by Claude Code before they run (on top of the exact allow
    /// rules and the hook): shells, env changes (an `ARIS_SEALED=` prefix or `env -u` is a different command and so denied
    /// anyway), network and script tools, and anything naming a secret folder.
    static let deniedShapes: [String] = [
        "Bash(env:*)", "Bash(export:*)", "Bash(unset:*)", "Bash(ARIS_SEALED=*)", "Bash(*=*)",
        "Bash(sh:*)", "Bash(bash:*)", "Bash(zsh:*)", "Bash(eval:*)", "Bash(exec:*)", "Bash(source:*)",
        "Bash(curl:*)", "Bash(wget:*)", "Bash(nc:*)", "Bash(ssh:*)", "Bash(scp:*)", "Bash(python3:*)", "Bash(python:*)",
        "Bash(perl:*)", "Bash(ruby:*)", "Bash(node:*)", "Bash(osascript:*)", "Bash(open:*)", "Bash(cat:*)",
        // Claude Code lets read-only commands (echo, ls…) through even in "dontAsk" (seen in the canary run).
        "Bash(echo:*)", "Bash(printf:*)", "Bash(ls:*)", "Bash(pwd:*)", "Bash(find:*)", "Bash(grep:*)", "Bash(head:*)",
        "Bash(tail:*)", "Bash(less:*)", "Bash(file:*)", "Bash(stat:*)", "Bash(which:*)", "Bash(mdfind:*)", "Bash(defaults:*)",
        "Bash(*.ssh*)", "Bash(*.gnupg*)", "Bash(*.aws*)", "Bash(*.codex*)", "Bash(*.claude*)", "Bash(*Keychains*)",
        "Bash(*claude-hook-token*)", "Bash(*-key*)",
    ]

    /// Whether a shell command line is exactly `<tools> <allowed subcommand>`: words and "double-quoted words" only,
    /// with no character the shell would treat specially (no ; & | $ ` < > ( ) { } \ ' * ? or newline).
    static func permits(command: String, tools: String, memory: Bool = false, messages: Bool = false, handOff: Bool = false) -> Bool {
        if ArisProtectedPlaces.executesComputerRuntime(ArisDesktopShell.commandLine(command, tools: tools)) { return false }
        // The one multi-line form: a desktop type, set-value or dialog input with its text in a quoted heredoc (ArisDesktopShell).
        if command.contains("\n") {
            guard let line = ArisDesktopShell.parse(command, tools: tools), line.text != nil else { return false }
            return allows(["desktop"] + line.words, memory: memory)
        }
        guard let words = words(command), words.first == tools else { return false }
        return allows(Array(words.dropFirst()), memory: memory, messages: messages, handOff: handOff)
    }

    private static let special = Set(";&|$`<>(){}\\'*?![]#\n\r\t")

    private enum Scan { case gap, word, quoted, single, closed }

    /// The shell words of a command line made only of plain words and "quoted words"; nil for anything else (a quote
    /// opens only at a word's start and must end it).
    private static func words(_ command: String) -> [String]? {
        var words: [String] = [], current = "", scan = Scan.gap
        for character in command {
            // Inside '…' the shell expands nothing: any character but ' and a line break is taken as it is.
            // Any line break or control character, by scalar ("\r\n" is one Character): never a plain word (C1).
            if character.unicodeScalars.contains(where: { ArisCommandPolicy.isLineBreak($0) || CharacterSet.controlCharacters.contains($0) }) { return nil }
            if scan == .single {
                if character == "'" { scan = .closed } else { current.append(character) }
                continue
            }
            if scan == .gap, character == "'" { scan = .single; current = ""; continue }
            guard !special.contains(character) else { return nil }
            switch (scan, character) {
            case (.gap, " "): continue
            case (.gap, "\""): scan = .quoted; current = ""
            case (.gap, _): scan = .word; current = String(character)
            case (.word, " "), (.closed, " "): words.append(current); scan = .gap
            case (.word, "\""), (.closed, _): return nil
            case (.word, _): current.append(character)
            case (.quoted, "\""): scan = .closed
            case (.quoted, _): current.append(character)
            case (.single, _): break
            }
        }
        switch scan {
        case .quoted, .single: return nil
        case .word, .closed: words.append(current)
        case .gap: break
        }
        return words
    }

    /// No control characters in an argument.
    private static func isPlain(_ argument: String) -> Bool {
        !argument.isEmpty && argument.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}

/// A desktop command as a shell line: plain words (`<tools> desktop click @s1abc:e3`), or a type, set-value or dialog input whose
/// text comes on stdin through a quoted heredoc, the one form whose body the shell never expands:
///
///     <tools> desktop type @s1abc:e3 --stdin <<'ARIS'
///     <the text, any number of lines>
///     ARIS
///
/// Anything else (a pipe, a chain, an unquoted heredoc, words after the end line) isn't one.
enum ArisDesktopShell {
    struct Line: Equatable {
        let words: [String]
        let text: String?
    }

    /// The command as a desktop call; nil when it isn't exactly one.
    static func parse(_ command: String, tools: String) -> Line? { parse(command, tools: Optional(tools)) }

    /// `tools` nil: any program's path as the first word (the audit's view of a line, whose tools path it doesn't know).
    private static func parse(_ command: String, tools: String?) -> Line? {
        let named = { (words: [String]) in tools.map { words[0] == $0 } ?? true }
        if let words = ArisCommandPolicy.words(command) {
            // Every word as the shell passes it: no control character or line break, even inside quotes (C1).
            guard words.count >= 2, named(words), words[1] == "desktop", words.allSatisfy(isPlain) else { return nil }
            return Line(words: Array(words.dropFirst(2)), text: nil)
        }
        // Split by scalar, never by Character ("\r\n" is one Character): the head is everything before the first LF.
        let scalars = Array(command.unicodeScalars)
        guard let newline = scalars.firstIndex(of: "\n") else { return nil }
        let head = String(String.UnicodeScalarView(scalars[..<newline]))
        guard !ArisCommandPolicy.hasLineBreak(head), let marker = head.range(of: " <<'"), head.hasSuffix("'") else { return nil }
        let delimiter = String(head[marker.upperBound..<head.index(before: head.endIndex)])
        guard delimiter.range(of: #"^[A-Z_]{1,16}$"#, options: .regularExpression) != nil,
              let words = ArisCommandPolicy.words(String(head[..<marker.lowerBound])), words.allSatisfy(isPlain),
              words.count >= 4, named(words), words[1] == "desktop", words.last == "--stdin",
              ["type", "set-value", "batch"].contains(words[2]) || words[2...3] == ["dialog", "input"] else { return nil }
        var body = Array(scalars[(newline + 1)...])
        if body.last == "\n" { body.removeLast() }
        // A CR anywhere in the body could end a line where zsh doesn't: refused.
        guard !body.contains("\r") else { return nil }
        let lines = String(String.UnicodeScalarView(body)).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let last = lines.last, last == delimiter else { return nil }
        let text = lines.dropLast().joined(separator: "\n")
        // The end line is the first line that is exactly the delimiter: one earlier would end the heredoc there.
        guard !lines.dropLast().contains(delimiter) else { return nil }
        return Line(words: Array(words.dropFirst(2)), text: text)
    }

    /// The command inside `zsh -lc '…'`, read exactly as the gate reads it (ArisCommandPolicy.unwrap, which takes both
    /// '"'"' and POSIX '\'' quoting): the audit line never shows a shape the gate didn't see (QA live on b9c766bc).
    static func auditUnwrap(_ command: String) -> String { ArisCommandPolicy.unwrap(command) }

    /// What the shell runs of the line: a desktop heredoc's first line (its body is text it never runs), else all of it.
    static func commandLine(_ command: String, tools: String) -> String {
        guard parse(command, tools: tools)?.text != nil,
              let head = command.unicodeScalars.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first else { return command }
        return String(String.UnicodeScalarView(head))
    }

    /// A word as the shell passes it on: not empty, no control character, no line break of any kind (C1).
    static func isPlain(_ word: String) -> Bool {
        !word.isEmpty && !word.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || ArisCommandPolicy.isLineBreak($0) }
    }

    /// The command as actions.log keeps it: a desktop heredoc's body (the text typed, maybe a private message) is
    /// replaced by its length and SHA-256; any other command is kept as it is. Codex's `zsh -lc '…'` wrapper is read
    /// through (security review I13).
    static func audited(_ command: String) -> String {
        let inner = auditUnwrap(command)
        guard let line = parse(inner, tools: nil), let text = line.text,
              let head = inner.unicodeScalars.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first else { return command }
        let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(String.UnicodeScalarView(head)) + " ‹text: \(text.count) characters, sha256 \(digest)›"
    }

    /// The words after `desktop`, for a shell line that is one desktop call.
    static func words(_ command: String, tools: String) -> [String]? { parse(command, tools: tools)?.words }
}
