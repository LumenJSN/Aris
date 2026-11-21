//
//  ArisCapability.swift
//  aris-agent
//
//  The capability registry (ARCHITECTURE 3.4, jv-hands): every aris-tools command and subcommand as data. For each:
//  the words that name it, its arguments, whether it reads or acts, the path the open Claude's call takes through the
//  gates today (its PreToolUse hook only, the hook's read judge, or one of the agent's routes), what it prints (nothing
//  anyone else wrote, the agent's fixed words, only the names it was given, or outside text), and where it runs (in the
//  calling process, or as an aris-tools child). tests/hands-tests.swift checks every row against the gates themselves
//  (ArisTurnGate, ArisHandOff, ArisReadGate, the Claude driver's taint classifier), so a row that drifts from the code
//  fails there. The typed faces (JSON Schema-shaped functions) are ArisCapabilityFunctions; every brain's call is still
//  judged as the same shell command by the one gate (ArisCapabilityGate). API brains and Codex judge every command with
//  ArisAPIGate (Codex's approve path); the `path` column is the open Claude's, the brain with no gate of its own.
//

import Foundation

struct ArisCapability {
    /// Whether it reads or acts (the inventory's plain column; the trust policy reads `effectClass`).
    enum Kind: String { case reads, acts }

    /// The open Claude's path for this call today (its Bash runs aris-tools; Codex and the API brains: ArisAPIGate).
    enum Path: String {
        /// The PreToolUse hook (ArisTurnGate) lets it run in aris-tools; refused after outside text unless it stays local.
        case hook
        /// The hook's read judge on a careful turn (a job, after outside text): reads that could carry words out.
        case readJudge
        /// aris-tools hands it to POST /action-tool (ArisActionGate: Codex's same judgement, the user's card when it asks).
        case actionTool
        /// POST /message-tool (ArisMessageGate).
        case messageTool
        /// POST /desktop-tool (computer use: ArisDesktopGate).
        case desktopTool
        /// POST /mcp-tool (the connected services: ArisMCPPolicy).
        case mcpTool
        case skillTool, asideTool, sessionTool, routineTool
        /// POST /task-tool (the background tasks the conversation handed out: ArisTaskTool).
        case taskTool
        /// Refused before it runs (the agent's own forms).
        case refused
        /// Not a call: the hooks themselves, the version line.
        case none
    }

    enum Prints: String {
        /// Nothing anyone else wrote (a timer, the volume, a window): the turn stays clean.
        case clean
        /// The agent answers its success in fixed words ("done").
        case fixedWords
        /// Only the names the call was given (a move, a rename, a conversion's new names).
        case ownNames
        /// Others' words may come back: the turn holds outside text after it.
        case outsideText
        /// The agent's route marks the conversation itself before outside text comes back (services, desktop, Aside…).
        case markedByRoute
    }

    enum Runs: String {
        /// The calling process runs it with the same code aris-tools runs (ArisCapabilityLocal): no process started.
        case inProcess
        /// An aris-tools child process.
        case tools
    }

    let command: [String]
    let arguments: String
    let kind: Kind
    let path: Path
    let prints: Prints
    var runs: Runs = .tools
    /// What the call does to the world, for the trust policy (ArisEffectClass).
    let effectClass: ArisEffectClass
    /// A representative call (its words after the program), for the tests.
    let example: [String]
}

enum ArisCapabilities {
    private static func row(_ command: String, _ arguments: String, _ kind: ArisCapability.Kind, _ path: ArisCapability.Path,
                            _ prints: ArisCapability.Prints, runs: ArisCapability.Runs = .tools, example: String? = nil,
                            effect: ArisEffectClass = .observe) -> ArisCapability {
        let words = command.split(separator: " ").map(String.init)
        return ArisCapability(command: words, arguments: arguments, kind: kind, path: path, prints: prints, runs: runs,
                              effectClass: effect, example: example.map { ArisCommandPolicy.words($0) ?? [] } ?? words)
    }

    /// Every command and subcommand aris-tools takes (ArisTools/main.swift's dispatch), in its order.
    static let inventory: [ArisCapability] = [
        row("weather", "[place] [--days N] [--ko|--en] [--json]", .reads, .readJudge, .outsideText, example: "weather Seoul --ko"),
        row("weather --set-home", "<city>", .acts, .actionTool, .outsideText, example: "weather --set-home Orlando", effect: .changeReversible),
        row("canvas", "", .reads, .readJudge, .outsideText),
        row("brief", "", .reads, .readJudge, .outsideText),
        row("todo", "(the open items)", .reads, .hook, .outsideText),
        row("todo add", "<item> [--due <when>] [--list <list>] [--note <text>]", .acts, .actionTool, .fixedWords, example: "todo add 우유", effect: .changeReversible),
        row("todo done", "<words naming one item>", .acts, .actionTool, .outsideText, example: "todo done 우유", effect: .changeReversible),
        row("todo edit", "<words> [--due] [--note] [--title]", .acts, .actionTool, .outsideText, example: "todo edit 우유 --due 내일", effect: .changeReversible),
        row("todo remove", "<words naming one item>", .acts, .actionTool, .outsideText, example: "todo remove 우유", effect: .changePermanent),
        row("board", "\"<markdown>\" [--screen here|left|right|main] | --close", .acts, .hook, .outsideText, example: "board '# 표' --screen here", effect: .changeReversible),
        row("timer", "<minutes> [--focus] | pomodoro | stop", .acts, .hook, .clean, example: "timer 25", effect: .changeReversible),
        row("find", "<words>", .reads, .hook, .outsideText, example: "find 세금"),
        row("open", "<path>", .acts, .actionTool, .fixedWords, example: "open /Users/x/a.pdf", effect: .changeReversible),
        row("osascript", "(restart, shut down, log out or sleep: System Events' four scripts)", .acts, .actionTool, .outsideText,
            example: "osascript -e 'tell application \"System Events\" to sleep'", effect: .changePermanent),
        row("remember", "<fact, in the user's words>", .acts, .actionTool, .fixedWords, example: "remember 커피는 라떼", effect: .changeReversible),
        row("forget", "<words> [--all]", .acts, .actionTool, .outsideText, example: "forget 커피", effect: .changePermanent),
        row("memory", "[words]", .reads, .readJudge, .outsideText, runs: .inProcess, example: "memory 커피"),
        row("recall", "[words] [--limit N] | --id E12|L3 | --stats", .reads, .readJudge, .clean, runs: .inProcess, example: "recall 보고서"),
        row("recall --tainted", "[words] | --id E12", .reads, .readJudge, .outsideText, runs: .inProcess, example: "recall 보고서 --tainted"),
        row("window", "left|right|full|center [app]", .acts, .hook, .clean, example: "window left Safari", effect: .changeReversible),
        row("music", "play|pause|next|previous [spotify|music]", .acts, .hook, .clean, example: "music play", effect: .changeReversible),
        row("volume", "0-100|up|down|mute|unmute", .acts, .hook, .clean, example: "volume 40", effect: .changeReversible),
        row("app", "<name>", .acts, .hook, .clean, example: "app Figma", effect: .changeReversible),
        row("link", "<https://…>", .acts, .actionTool, .fixedWords, example: "link https://example.com", effect: .changeReversible),
        row("folder", "Desktop|Downloads|Documents (shown in Finder)", .acts, .hook, .clean, example: "folder Downloads", effect: .changeReversible),
        row("folder", "<another path> (opened)", .acts, .actionTool, .outsideText, example: "folder /Users/x/Projects", effect: .changeReversible),
        row("folder new", "<path>", .acts, .actionTool, .ownNames, example: "folder new '/Users/x/새 폴더'", effect: .changeReversible),
        row("rename", "<path> <new name>", .acts, .actionTool, .ownNames, example: "rename /Users/x/a.txt b.txt", effect: .changeReversible),
        row("shortcut", "<name>", .acts, .actionTool, .outsideText, example: "shortcut 'Morning'", effect: .changePermanent),
        row("shortcuts", "", .reads, .hook, .outsideText),
        row("remind", "<text> [--at \"YYYY-MM-DD HH:MM\"]", .acts, .actionTool, .fixedWords, example: "remind '약 먹기' --at '2026-11-19 09:00'", effect: .changeReversible),
        row("event", "<title> --start \"YYYY-MM-DD HH:MM\" [--minutes N] [--calendar <name>]", .acts, .actionTool, .fixedWords,
            example: "event 회의 --start '2026-11-19 15:00'", effect: .changeReversible),
        row("event find", "--from <day> [--to <day>] | <title> --start <when>", .reads, .actionTool, .outsideText, example: "event find --from 2026-12-01"),
        row("event delete", "--id <id> --title <title> --start <when>", .acts, .actionTool, .outsideText,
            example: "event delete --id X1 --title 회의 --start '2026-11-19 15:00'", effect: .changePermanent),
        row("event change", "--id <id> --title <title> --start <when> [--to <when>] [--rename <title>]", .acts, .actionTool, .outsideText,
            example: "event change --id X1 --title 회의 --start '2026-11-19 15:00' --to '2026-11-19 16:00'", effect: .changeReversible),
        row("calendars", "", .reads, .hook, .outsideText),
        row("use-calendar", "<name>", .acts, .actionTool, .outsideText, example: "use-calendar 회사", effect: .changeReversible),
        row("calendar", "(opens Apple Calendar)", .acts, .hook, .clean, effect: .changeReversible),
        row("selection", "", .reads, .hook, .outsideText),
        row("clipboard", "", .reads, .hook, .outsideText),
        row("clipboard set", "<text>", .acts, .actionTool, .fixedWords, example: "clipboard set 안녕", effect: .changeReversible),
        row("tab", "[--text]", .reads, .hook, .outsideText),
        row("finder", "", .reads, .hook, .outsideText),
        row("shelf", "", .reads, .hook, .outsideText, runs: .inProcess),
        row("screen", "[--image]", .reads, .hook, .outsideText),
        row("windows", "[app]", .reads, .hook, .outsideText),
        row("tile", "<app>[,<app>…] [--grid RxC]", .acts, .hook, .clean, example: "tile Safari --grid 2x2", effect: .changeReversible),
        row("new", "<app> [--count N]", .acts, .hook, .clean, example: "new 'Microsoft Word' --count 4", effect: .changeReversible),
        row("keys", "<cmd+shift+t> [--app X] [--times N]", .acts, .actionTool, .fixedWords, example: "keys cmd+shift+t --app Safari", effect: .changeReversible),
        row("type", "'<text>' [--app X] [--title <window>] [--at end|start] (the desktop engine's `desktop type --focused`)", .acts, .desktopTool,
            .outsideText, example: "type 안녕 --app Notes", effect: .changeReversible),
        row("message", "<name|number|email> <text>", .acts, .messageTool, .fixedWords, example: "message 엄마 '곧 도착'", effect: .outward),
        row("trash", "<path>…", .acts, .actionTool, .fixedWords, example: "trash /Users/x/a.txt", effect: .changeReversible),
        row("move", "<from> <to>", .acts, .actionTool, .ownNames, example: "move /Users/x/a.txt /Users/x/Documents", effect: .changeReversible),
        row("convert", "<file>…|--finder|--shelf|--made [--to …] [--quality N] [--max N|--percent N] [--pages …]", .acts, .actionTool, .ownNames,
            example: "convert /Users/x/a.heic --to jpg", effect: .changeReversible),
        row("merge", "<file>…|--finder|--shelf|--made [--to pdf|mp4|mov|m4a]", .acts, .actionTool, .ownNames, example: "merge /Users/x/a.pdf /Users/x/b.pdf", effect: .changeReversible),
        row("split", "<pdf> [--pages 1-3,5]", .acts, .actionTool, .ownNames, example: "split /Users/x/a.pdf --pages 1-2", effect: .changeReversible),
        row("compress", "<file>… [--quality N] [--max N]", .acts, .actionTool, .ownNames, example: "compress /Users/x/a.jpg --quality 60", effect: .changeReversible),
        row("activity", "[--today] [--json]", .reads, .hook, .outsideText),
        row("activity log", "(the agent's alone)", .acts, .refused, .outsideText, example: "activity log x", effect: .never),
        row("undo", "[--id <uuid>]", .acts, .actionTool, .outsideText, effect: .changeReversible),
        row("schedule add", "--title T --prompt P (--at … | --daily HH:mm | --weekly fri HH:mm | --every 30m)", .acts, .actionTool, .fixedWords,
            example: "schedule add --title 아침 --prompt '날씨 알려줘' --daily 08:00", effect: .changeReversible),
        row("schedule list", "", .reads, .hook, .outsideText),
        row("schedule remove", "<id>", .acts, .actionTool, .outsideText, example: "schedule remove s1", effect: .changePermanent),
        row("note", "<text> | --markdown '<markdown>'", .acts, .actionTool, .fixedWords, example: "note --markdown '# 장보기'", effect: .changeReversible),
        row("mcp list", "[service]", .reads, .mcpTool, .markedByRoute),
        row("mcp call", "<service> <tool> '<json>'", .acts, .mcpTool, .markedByRoute, example: "mcp call gmail GMAIL_SEND '{}'", effect: .outward),
        row("mcp wait", "<id>", .reads, .mcpTool, .markedByRoute, example: "mcp wait 0123456789abcdef"),
        row("desktop", "see|snapshot|find|get|click|type|set-value|press|scroll|drag|window|app|menu|dialog|click-at|batch|wait … (text on stdin: --stdin)",
            .acts, .desktopTool, .markedByRoute, example: "desktop click @s1abc:e3", effect: .changeReversible),
        row("skill list", "", .reads, .skillTool, .markedByRoute),
        row("skill read", "<name> [file]", .reads, .skillTool, .markedByRoute, example: "skill read unslop"),
        row("skill run", "<name> scripts/<file> [args…]", .acts, .skillTool, .markedByRoute, example: "skill run unslop scripts/run.sh", effect: .changePermanent),
        row("routine", "list | add … | remove … | run …", .acts, .routineTool, .markedByRoute, example: "routine list", effect: .changeReversible),
        row("task", "list | status <id> | add <id> … | cancel <id> | pause <id>", .acts, .taskTool, .markedByRoute, example: "task list", effect: .changeReversible),
        row("aside", "\"<brief>\"", .acts, .asideTool, .markedByRoute, example: "aside '항공권 찾아줘'", effect: .outward),
        row("session list", "", .reads, .sessionTool, .markedByRoute),
        row("session send", "<folder or id> <text>", .acts, .sessionTool, .markedByRoute, example: "session send aris '/unslop 해 줘'", effect: .outward),
        row("devin sessions", "[--all]", .reads, .readJudge, .outsideText),
        row("messages recent", "[--with <name>]", .reads, .readJudge, .outsideText, example: "messages recent --with 엄마"),
        row("mail recent", "", .reads, .readJudge, .outsideText),
        row("mail search", "<words>", .reads, .readJudge, .outsideText, example: "mail search 영수증"),
        row("mail reply", "(a draft opened in Mail after the user's card)", .acts, .actionTool, .outsideText, example: "mail reply --id 1 --text 네", effect: .changeReversible),
        row("notes recent", "", .reads, .readJudge, .outsideText),
        row("notes search", "<words>", .reads, .readJudge, .outsideText, example: "notes search 회의"),
        row("files find", "<words> [--kind pdf|image|doc] [--in <folder>]", .reads, .readJudge, .outsideText, example: "files find 계약서 --kind pdf"),
        row("files read", "<path> | --shelf [<name words>] | --finder", .reads, .readJudge, .outsideText, example: "files read /Users/x/a.pdf"),
        row("obsidian search", "<words>", .reads, .readJudge, .outsideText, example: "obsidian search 일기"),
        row("maps directions", "<from> <to> (opens Maps)", .acts, .actionTool, .outsideText, example: "maps directions here 강남역", effect: .changeReversible),
        row("maps search", "<place> (opens Maps)", .acts, .actionTool, .outsideText, example: "maps search 카페", effect: .changeReversible),
        row("maps directions --json", "<from> <to> (a lookup; nothing opens)", .reads, .readJudge, .outsideText, example: "maps directions here 강남역 --json"),
        row("maps search --json", "<place>", .reads, .readJudge, .outsideText, example: "maps search 카페 --json"),
        row("stock", "<symbol|name> [--json]", .reads, .readJudge, .outsideText, example: "stock AAPL"),
        row("currency", "<amount> <FROM> <TO> [--json]", .reads, .readJudge, .outsideText, example: "currency 100 CNY CAD"),
        row("web fetch", "<https://…>", .reads, .readJudge, .outsideText, example: "web fetch https://example.com"),
        row("turn-gate", "(the open Claude's PreToolUse hook)", .reads, .none, .clean),
        row("sealed-gate", "(the sealed Claude's PreToolUse hook)", .reads, .none, .clean),
        row("--version", "", .reads, .none, .clean),
    ]

    /// The top-level commands (the dispatch's cases, the hooks and the version line).
    static var commands: [String] {
        var seen: [String] = []
        for capability in inventory where !seen.contains(capability.command[0]) { seen.append(capability.command[0]) }
        return seen
    }

    /// The row a call falls under: the longest command its words start with (flags anywhere after it for the
    /// `--json`, `--tainted` and `--set-home` forms).
    static func capability(_ argv: [String]) -> ArisCapability? {
        inventory.filter { row in
            let named = row.command.filter { !$0.hasPrefix("--") }, flags = row.command.filter { $0.hasPrefix("--") }
            return !named.isEmpty ? argv.starts(with: named) && flags.allSatisfy(argv.contains) : argv.first == row.command.first
        }.max { $0.command.count < $1.command.count }
    }

    /// Whether the call runs in the calling process (ArisCapabilityLocal), by its row.
    static func runsInProcess(_ argv: [String]) -> Bool { capability(argv)?.runs == .inProcess }
}
