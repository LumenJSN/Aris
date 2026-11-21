// jv-hands: the capability registry, its one gate entry and the MCP face (arisCore2). The old path is the oracle: every
// decision through ArisCapabilityGate is compared with the decision the old code made for the same call, and every
// capability that replaces a built-in tool is shown refusing what the old flags and hook refused. Fakes and scratch
// folders only: no process of the user's is started, nothing of ~/.config/aris is read.
import Foundation

private let handsTools = "/Users/me/.config/aris/aris-tools"

func runHandsTests() {
    handsInventoryTests()
    handsBookTests()
    handsEffectTests()
    handsAPIGateTests()
    handsHandOffTests()
    handsClaudeFaceTests()
    handsFailClosedTests()
    handsLocalTests()
    handsServerTests()
    handsInitTests()
    handsLaunchTests()
    handsMeasureTests()
}

private func handsFolder(_ name: String) -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hands-\(name)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return folder
}

// MARK: - The inventory, checked against the gates themselves

private func handsInventoryTests() {
    // Every command aris-tools dispatches has a row (its main.swift's `case "…"` lines).
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../ArisTools/main.swift")
    let text = (try? String(contentsOf: source, encoding: .utf8)) ?? ""
    let dispatch = text.components(separatedBy: "switch arguments.first {").last ?? ""
    let cases = Set(dispatch.split(separator: "\n").compactMap { line -> [String]? in
        guard line.hasPrefix("case \"") else { return nil }
        return line.dropFirst(5).components(separatedBy: ":").first?.components(separatedBy: " where").first?
            .split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
    }.joined())
    let commands = Set(ArisCapabilities.commands)
    check(cases.count > 55 && cases.isSubset(of: commands), "hands inventory: every command aris-tools dispatches has a row (\(cases.subtracting(commands).sorted()))")
    check(commands.subtracting(cases).isSubset(of: ["turn-gate", "sealed-gate", "--version"]), "hands inventory: no row names a command aris-tools doesn't take")
    check(ArisCapabilities.inventory.count >= 90, "hands inventory: \(ArisCapabilities.inventory.count) rows (commands and subcommands)")

    for row in ArisCapabilities.inventory where row.path != .none && row.path != .refused {
        let rest = row.example
        let line = ArisAPICatalog.command(tools: handsTools, argv: rest)
        let name = rest.joined(separator: " ")
        let careful = ArisTurnGate.verdict(tool: "Bash", command: line, tools: handsTools, tainted: false, careful: true, resolve: { _ in ["93.184.216.34"] })
        switch row.path {
        case .actionTool:
            check(ArisHandOff.isWrite(rest), "hands inventory: \(name) is handed to /action-tool")
        case .messageTool:
            check(ArisTurnGate.isAgentMessage(rest) && !ArisHandOff.names(rest), "hands inventory: \(name) goes to /message-tool")
        case .readJudge:
            if case .judge = careful { check(true, "") } else { check(false, "hands inventory: \(name) is judged on a careful turn (\(careful))") }
        case .hook:
            let runs: Bool
            switch careful { case .allow, .allowMarking: runs = true; default: runs = false }
            check(runs && !ArisHandOff.names(rest), "hands inventory: \(name) runs in aris-tools behind the hook alone (\(careful))")
        default:
            check(!ArisHandOff.names(rest), "hands inventory: \(name) reaches its own route, not /action-tool")
        }
        let classified = ArisClaudeDriver.bringsInOutside(ArisAgentStream.ToolCall(name: "Bash", command: line), tools: handsTools, handsOff: true)
        switch row.prints {
        case .clean: check(ArisTurnGate.bringsNothingIn(rest) && !classified, "hands inventory: \(name) prints nothing others wrote")
        case .fixedWords: check((ArisHandOff.answersInFixedWords(rest) || ArisTurnGate.isAgentMessage(rest)) && !classified, "hands inventory: \(name) is answered in fixed words")
        case .ownNames: check(ArisHandOff.bringsNothingIn(rest) && !ArisHandOff.answersInFixedWords(rest) && !classified, "hands inventory: \(name) prints only its own names")
        case .outsideText: check(classified, "hands inventory: \(name) brings outside text in")
        case .markedByRoute: check(!classified, "hands inventory: \(name) is marked by its route, not the classifier")
        }
    }
    check(ArisCapabilities.inventory.filter { $0.runs == .inProcess }.map { $0.command.joined(separator: " ") } == ["memory", "recall", "recall --tainted", "shelf"],
          "hands inventory: memory, recall and shelf run in process")
    check(ArisCapabilities.capability(["weather", "Seoul", "--set-home", "x"])?.path == .actionTool && ArisCapabilities.capability(["maps", "search", "x", "--json"])?.path == .readJudge
          && ArisCapabilities.capability(["recall", "x", "--tainted"])?.prints == .outsideText && ArisCapabilities.capability(["todo", "add", "x"])?.command == ["todo", "add"],
          "hands inventory: a call falls under its longest row, flags included")
}

// MARK: - The book

private func handsBookTests() {
    let names = ArisCapabilityBook.all.map(\.name)
    check(Set(names).count == names.count && names.allSatisfy { $0.range(of: #"^[a-zA-Z0-9_-]{1,64}$"#, options: .regularExpression) != nil },
          "hands book: every tool name is unique and a valid tool name")
    check(Set(ArisCapabilityBook.all.map(\.id)).count == names.count, "hands book: every id is unique")
    check(ArisAPICatalog.entries.map(\.function.name) == ArisCapabilities.functions.map(\.function.name)
          && ArisCapabilityBook.arisTools.map(\.name) == ArisCapabilities.functions.map(\.function.name),
          "hands book: the API brains' functions and the book's aris-tools section are the one list, in order")
    check(Array(ArisCapabilityBook.core2.map(\.id)) == ["shell.run", "file.read", "file.write", "file.edit", "file.search", "web.fetch", "web.search"],
          "hands book: the capabilities that replace a provider's built-in tools")
    // Every typed function's sample call names a row of the inventory.
    let samples: [String: [String: Any]] = ["timer": ["minutes": 25], "music": ["action": "play"], "volume": ["level": "40"], "open_app": ["name": "Figma"],
        "weather": ["place": "Seoul"], "todo_add": ["item": "우유"], "remind": ["text": "약"], "add_event": ["title": "회의", "start": "2026-11-19 15:00"],
        "list_events": ["from": "2026-12-01"], "send_message": ["to": "엄마", "text": "곧 도착"], "save_note": ["markdown": "# a"], "remember": ["fact": "라떼"],
        "stock": ["symbol": "AAPL"], "file_read": ["path": "/Users/me/a.txt"], "file_rename": ["path": "/Users/me/a", "name": "b"],
        "desktop_click": ["ref": "@s1:e3"], "aside_task": ["brief": "항공권"], "claude_sessions": [:], "recall": ["query": "보고서"]]
    for (name, arguments) in samples {
        let argv = ArisCapabilityBook.entry(named: name)?.argv(arguments)
        check(argv.flatMap(ArisCapabilities.capability) != nil, "hands book: \(name)'s call has an inventory row")
    }
}

// MARK: - Effect classes

private func handsEffectTests() {
    let shell = { (command: String) in ArisCore2.shellEffect(command, tools: handsTools) }
    check(shell("ls -la ~/Desktop") == .observe && shell("grep -r x .") == .observe, "hands effect: a looking command observes")
    // vmfix4: a repository's own settings can make any git command run a program, so git asks (vmfix4-script-tests).
    check(shell("git status") == .changePermanent, "hands effect: git status asks")
    check(shell("mkdir ~/x") == .changeReversible && shell("rm ~/a.txt") == .changePermanent && shell("find . -delete") == .changePermanent && shell("python3 x.py") == .changePermanent, "hands effect: changes by what can be taken back")
    check(shell("curl https://x") == .outward && shell("git push") == .outward && shell("ls && curl x") == .outward, "hands effect: what reaches others is outward")
    check(shell("sudo ls") == .never && shell("cat ~/.config/aris/claude-hook-token") == .never && shell("cat ~/.ssh/id_rsa") == .never
          && shell("ls $(rm x)") == .never && shell("echo x > ~/a.txt") == .never, "hands effect: the never-list, and a line that can't be read part by part")
    check(shell("\(handsTools) timer 25") == .changeReversible && shell("\(handsTools) memory") == .observe && shell("\(handsTools) message 엄마 hi") == .outward,
          "hands effect: an aris-tools line is as strong as its row")
    let home = handsFolder("effect")
    let existing = home.appendingPathComponent("a.txt").path
    FileManager.default.createFile(atPath: existing, contents: Data("x".utf8))
    let file = { (path: String, writing: Bool, edit: Bool) in ArisCore2.fileEffect(path, writing: writing, edit: edit, home: home.path) }
    // Decision 4: an overwrite whose copy the undo store can keep is reversible; one it can't keep is permanent.
    let free = ArisUndoStore.freeBytes
    ArisUndoStore.freeBytes = { _ in 0 }
    let noRoom = file(existing, true, false)
    ArisUndoStore.freeBytes = free
    check(file(existing, false, false) == .observe && file(existing, true, false) == .changeReversible && noRoom == .changePermanent
          && file(home.appendingPathComponent("new.txt").path, true, false) == .changeReversible && file(existing, true, true) == .changeReversible,
          "hands effect: file.write by whether the target exists and its copy can be kept; an edit keeps its old text")
    check(file(home.path + "/.ssh/id_rsa", false, false) == .never && file(home.path + "/.config/aris/claude-hook-token", false, false) == .never
          && file(home.path + "/.config/aris/aris/memory.sqlite", false, false) == .never && file(home.path + "/.config/aris/aris/home.json", false, false) == .observe
          && file("relative.txt", false, false) == .never, "hands effect: keys, tokens and Aris's records are never touched; its own folder may be read")
    for row in ArisCapabilities.inventory {
        check(row.kind == .reads ? row.effectClass == .observe : row.effectClass != .observe, "hands effect: \(row.command.joined(separator: " ")) declares its class")
    }
    check(ArisCapabilityBook.entry(named: "send_message")?.effect(["to": "엄마", "text": "x"]) == .outward
          && ArisCapabilityBook.entry(named: "timer")?.effect(["minutes": 5]) == .changeReversible
          && ArisCapabilityBook.entry(named: "aris")?.effect(["args": ["activity", "log", "x"]]) == .never
          && ArisCapabilityBook.entry(named: "aris")?.effect(["args": ["nonsense"]]) == .changePermanent,
          "hands effect: a typed call's class comes from its row; a call no row names is treated as permanent")
    check(ArisEffectClass.strongest([.observe, .outward, .changeReversible]) == .outward && ArisEffectClass.strongest([]) == .observe, "hands effect: the strongest part wins")
}

// MARK: - The API brain: the gate entry against the old sequence

private func describe(_ decision: ArisAPIGateDecision) -> String {
    switch decision {
    case .allow(let audit): return "allow \(audit)"
    case .deny(let audit, let reason): return "deny \(audit) \(reason)"
    case .read(let ask, _, let audit): return "read \(ask.id) \(ask.title) \(ask.detail) \(audit)"
    case .ask(let ask, let pending, let remember, let audit): return "ask \(ask.id) \(ask.title) \(ask.detail) \(ask.countdown) \(remember ?? "-") \(pending.covered) \(audit)"
    }
}

/// The driver's own steps before jv-hands (ArisAPIDriver.request at ce0683cd), the oracle.
private func oldAPIDecision(_ argv: [String], gate: ArisAPIGate, sealed: Bool, handsFree: Bool, scopes: Set<ArisTeammateScope>?) -> String {
    let command = ArisAPICatalog.command(tools: handsTools, argv: argv)
    if sealed, !ArisSealedTools.allows(argv, memory: !handsFree) { return "stop" }
    if let scopes, !ArisTeammateScope.allows(toolsArguments: argv, scopes: scopes) {
        return "refused " + ArisTeammateScope.refusalLine(ArisTeammateScope.needed(forTools: argv).map { $0.subtracting(scopes) })
    }
    return describe(gate.judge(command))
}

private func newAPIDecision(_ argv: [String], gate: ArisAPIGate, sealed: Bool, handsFree: Bool, scopes: Set<ArisTeammateScope>?) -> String {
    switch ArisCapabilityGate.decide(argv, tools: handsTools, turn: .api(gate, sealed: sealed, handsFree: handsFree, scopes: scopes)) {
    case .stop: return "stop"
    case .refused(let reason, _): return "refused " + reason
    case .api(let decision): return describe(decision)
    default: return "other"
    }
}

/// Representative calls per kind: allowed reads, secret-looking reads, writes, sends, never-list items.
private let handsCalls: [[String]] = [
    ["weather", "Seoul", "--ko"], ["memory"], ["memory", "password"], ["files", "read", "/Users/me/a.txt"], ["files", "read", "/Users/me/.ssh/id_rsa"],
    ["mail", "search", "영수증"], ["web", "fetch", "https://example.com"], ["recall", "보고서"], ["stock", "AAPL"], ["timer", "25"], ["volume", "40"],
    ["todo", "add", "우유"], ["remind", "약 먹기"], ["note", "--markdown", "# 장보기"], ["event", "회의", "--start", "2026-11-19 15:00"],
    ["remember", "커피는 라떼"], ["move", "/Users/me/a.txt", "/Users/me/Documents"], ["trash", "/Users/me/a.txt"], ["convert", "/Users/me/a.heic", "--to", "jpg"],
    ["message", "엄마", "곧 도착"], ["message", "엄마", "the code is 123456"], ["trash", "/System"], ["activity", "log", "x"], ["schedule", "remove", "s1"],
    ["keys", "cmd+q"], ["desktop", "click", "@s1:e3"], ["mcp", "call", "gmail", "GMAIL_SEND", "{}"], ["aside", "항공권 찾아줘"], ["shortcut", "Morning"],
    ["osascript", "-e", "do shell script \"rm -rf ~\""], ["undo"], ["forget", "커피", "--all"],
]

private func handsAPIGateTests() {
    let states: [(String, (ArisAPIGate) -> Void, Bool, Bool, Set<ArisTeammateScope>?)] = [
        ("clean", { _ in }, false, false, nil),
        ("outside text", { $0.markUntrusted() }, false, false, nil),
        ("screen", { $0.markScreenSeen() }, false, false, nil),
        ("app read", { $0.markAppRead("com.apple.Notes") }, false, false, nil),
        ("declined", { $0.answered("", allow: false) }, false, false, nil),
        ("hands-free", { $0.handsFree = true }, true, true, nil),
        ("sealed", { _ in }, true, false, nil),
        ("teammate", { _ in }, false, false, Set([.web])),
        ("critical", { $0.tier = .critical }, false, false, nil),
    ]
    var compared = 0
    for (name, set, sealed, handsFree, scopes) in states {
        for task in [false, true] {
            for argv in handsCalls {
                let old = ArisAPIGate(tools: handsTools, home: "/Users/me", task: task), new = ArisAPIGate(tools: handsTools, home: "/Users/me", task: task)
                for gate in [old, new] { gate.request = "엄마한테 곧 도착이라고 보내줘"; set(gate) }
                let before = oldAPIDecision(argv, gate: old, sealed: sealed, handsFree: handsFree, scopes: scopes)
                let after = newAPIDecision(argv, gate: new, sealed: sealed, handsFree: handsFree, scopes: scopes)
                check(before == after && old.taint == new.taint, "hands API gate: \(argv.joined(separator: " ")) on a \(name)\(task ? " job" : "") turn: \(after)")
                compared += 1
            }
        }
    }
    check(compared == states.count * 2 * handsCalls.count, "hands API gate: \(compared) calls decided as before")
    // The driver itself, through the entry: a sealed process's call off its list stops, a teammate's is refused.
    let sealedDriver = ArisAPIDriver(profile: nil, tools: handsTools, sealed: true)
    _ = sealedDriver.ask("x", tier: .quick)
    let stop = sealedDriver.read(##"{"type":"tool_request","id":"c1","name":"save_note","arguments":"{\"markdown\":\"# a\"}","round":1}"##)
    check(stop.contains { if case .abort = $0 { return true }; return false } || stop.isEmpty, "hands API gate: the sealed driver still stops off its list")
}

// MARK: - A handed-off write: the entry against ArisActionGate.decide

private final class HandsTurn: ArisMessageTurn {
    var request = "우유 할 일에 넣어줘"
    var isTask = false
    var taint = ArisTaint.none
    var handsFree = false
    var critical = false
    var scopes: Set<ArisTeammateScope>? = nil
    func stillSendable() -> Bool { true }
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) { answer(.no) }
    func audit(_ fields: [String: String]) {}
}

private func handsHandOffTests() {
    func text(_ decision: ArisActionGate.Decision) -> String { "\(decision)" }
    var compared = 0
    for taint in [ArisTaint.none, .outsideText, .screenSeen] {
        for (handsFree, task, declined, always) in [(false, false, false, false), (true, false, false, false), (false, true, false, false), (false, false, true, false), (false, false, false, true)] {
            for argv in handsCalls {
                let turn = HandsTurn()
                turn.taint = taint; turn.handsFree = handsFree; turn.isTask = task
                let old = ArisActionGate.decide(argv, turn: turn, tools: handsTools, home: "/Users/me", declined: declined, alwaysAsks: always)
                let new = ArisCapabilityGate.handOff(argv, turn: turn, tools: handsTools, home: "/Users/me", declined: declined, alwaysAsks: always)
                check(old.decision == new.decision && old.audit == new.audit, "hands hand-off: \(argv.joined(separator: " ")) (\(taint), hands-free \(handsFree), job \(task)): \(text(new.decision))")
                compared += 1
            }
        }
    }
    check(compared == 3 * 5 * handsCalls.count, "hands hand-off: \(compared) handed-off calls decided as before")
}

// MARK: - The MCP face's calls against the hook on the Bash line the model would have written

private struct HandsHookState {
    let name: String
    let marked: Bool
    let careful: Bool
    let folder: Bool
}

private func handsHookEnvironment(_ state: HandsHookState) -> (environment: [String: String], folder: URL?) {
    var environment: [String: String] = [:]
    var folder: URL?
    if state.folder {
        folder = handsFolder("hook")
        if state.marked { ArisTurnGate.mark(folder) }
        environment[ArisTurnGate.stateKey] = folder!.path
    }
    if state.careful { environment[ArisReadGate.carefulKey] = "1" }
    return (environment, folder)
}

private func handsClaudeFaceTests() {
    // Each: the tool and its arguments, and the line a model would have typed for its Bash (its own quoting).
    let calls: [(String, [String: Any], String)] = [
        ("timer", ["minutes": 25], "\(handsTools) timer 25"),
        ("weather", ["place": "Seoul", "language": "ko"], "\(handsTools) weather Seoul --ko"),
        ("stock", ["symbol": "AAPL"], "\(handsTools) stock \"AAPL\""),
        ("todo_add", ["item": "우유 사기"], "\(handsTools) todo add \"우유 사기\""),
        ("send_message", ["to": "엄마", "text": "곧 도착"], "\(handsTools) message 엄마 '곧 도착'"),
        ("save_note", ["markdown": "# 장보기\n- [ ] 우유"], "\(handsTools) note --markdown '# 장보기\n- [ ] 우유'"),
        ("file_read", ["path": "/Users/me/보고서.pdf"], "\(handsTools) files read '/Users/me/보고서.pdf'"),
        ("recall", ["query": "보고서"], "\(handsTools) recall 보고서"),
        ("file_move", ["path": "/Users/me/a.txt", "folder": "/Users/me/Documents"], "\(handsTools) move /Users/me/a.txt /Users/me/Documents"),
        ("desktop_click", ["ref": "@s1abc:e3"], "\(handsTools) desktop click @s1abc:e3"),
        ("desktop_type", ["ref": "@s1abc:e4", "text": "안녕\n두 줄"], "\(handsTools) desktop type @s1abc:e4 --stdin <<'EOF'\n안녕\n두 줄\nEOF"),
        ("claude_session_send", ["session": "aris", "text": "/unslop"], "\(handsTools) session send aris /unslop"),
        ("aris", ["args": ["memory", "커피"]], "\(handsTools) memory 커피"),
        ("aris", ["args": ["todo"]], "\(handsTools) todo"),
        ("aris", ["args": ["activity", "log", "x"]], "\(handsTools) activity log x"),
        ("aris", ["args": ["screen", "--pid", "1"]], "\(handsTools) screen --pid 1"),
        ("aris", ["args": ["web", "fetch", "http://127.0.0.1/x"]], "\(handsTools) web fetch http://127.0.0.1/x"),
    ]
    let states = [HandsHookState(name: "clean", marked: false, careful: false, folder: true), HandsHookState(name: "after a read", marked: true, careful: false, folder: true),
                  HandsHookState(name: "a job", marked: false, careful: true, folder: true), HandsHookState(name: "no folder", marked: false, careful: false, folder: false)]
    for (allowed, judgeName) in [(true, "judge yes"), (false, "judge no")] {
        let judge = { (_: ArisReadCall) -> ArisReadVerdict in allowed ? .ok : .blocked(.other) }
        for state in states {
            for (name, arguments, typed) in calls {
                let a = handsHookEnvironment(state), b = handsHookEnvironment(state)
                guard let call = ArisHandsFace.call(function: name, input: arguments, tools: handsTools), let entry = ArisCapabilityBook.entry(named: name) else {
                    check(false, "hands face: \(name) reads as a call"); continue
                }
                let input = (try? JSONSerialization.data(withJSONObject: ["tool_name": "Bash", "tool_input": ["command": typed]])) ?? Data()
                let old = ArisTurnGate.run(input: input, tools: handsTools, environment: a.environment, judge: judge, resolve: { _ in ["127.0.0.1"] })
                let verdict = ArisTodayTrust(judge: judge).decide(ArisTrustCall(entry: entry, arguments: arguments, effect: entry.effect(arguments), argv: call.argv,
                                                                               stdin: call.stdin, environment: b.environment, tools: handsTools))
                let oldSaid = old.code == 0 ? "run" : "refuse \(old.reason ?? "")"
                let newSaid: String
                switch verdict { case .run: newSaid = "run"; case .refuse(let why): newSaid = "refuse \(why)"; default: newSaid = "\(verdict)" }
                check(oldSaid == newSaid && ArisTurnGate.isMarked(a.folder) == ArisTurnGate.isMarked(b.folder),
                      "hands face: \(name) on a \(state.name) turn (\(judgeName)) as its Bash line: \(newSaid)")
                // The taint classifier reads the call as that Bash line.
                let shell = ArisHandsFace.asShell(ArisMCPServerWire.clientName(name), input: arguments, tools: handsTools)
                check(ArisClaudeDriver.bringsInOutside(ArisAgentStream.ToolCall(name: shell.name, command: shell.command), tools: handsTools, handsOff: true)
                      == ArisClaudeDriver.bringsInOutside(ArisAgentStream.ToolCall(name: "Bash", command: typed), tools: handsTools, handsOff: true),
                      "hands face: \(name)'s taint as its Bash line's")
            }
        }
    }
    check(ArisHandsFace.call(function: "timer", input: ["minutes": 9_999], tools: handsTools) == nil
          && ArisHandsFace.call(function: "nonsense", input: [:], tools: handsTools) == nil
          && ArisHandsFace.call(function: "desktop_type", input: ["ref": "@s1:e1"], tools: handsTools) == nil,
          "hands face: arguments off the schema, an unknown tool and a desktop type with no text aren't calls")
    let heredoc = ArisCapabilityGate.shellLine(["desktop", "type", "@s1:e1", "--stdin"], stdin: "a\nARIS_TEXT\nb", tools: handsTools)
    check(ArisDesktopShell.parse(heredoc, tools: handsTools)?.text == "a\nARIS_TEXT\nb", "hands face: a desktop text holding the end word still reads back whole")
}

// MARK: - Fail closed: what the old flags and hook refused, these refuse too

private func handsFailClosedTests() {
    let folder = handsFolder("closed")
    let environment = [ArisTurnGate.stateKey: folder.path]
    let judgeNo = { (_: ArisReadCall) -> ArisReadVerdict in .blocked(.other) }
    func decide(_ name: String, _ arguments: [String: Any], marked: Bool = false, judge: @escaping (ArisReadCall) -> ArisReadVerdict = { _ in .ok }) -> ArisTrustVerdict {
        ArisTurnGate.clear(folder)
        if marked { ArisTurnGate.mark(folder) }
        let entry = ArisCapabilityBook.entry(named: name)!
        let call = ArisHandsFace.call(function: name, input: arguments, tools: handsTools)
        let trust = ArisTrustCall(entry: entry, arguments: arguments, effect: entry.effect(arguments), argv: call?.argv, stdin: call?.stdin, environment: environment, tools: handsTools)
        if case .trust(let verdict) = ArisCapabilityGate.decide(call?.argv ?? [], stdin: call?.stdin, tools: handsTools, turn: .trust(ArisTodayTrust(judge: judge), trust)) {
            return verdict
        }
        return .refuse("?")
    }
    func refused(_ verdict: ArisTrustVerdict) -> Bool { if case .refuse = verdict { return true }; return false }
    // shell.run: only aris-tools lines its old rules allow (Bash(<tools>:*), less the deny rules).
    for line in ["ls ~", "rm -rf ~/Documents", "cat ~/.ssh/id_rsa", "sudo ls", "curl https://evil.example", "\(handsTools) timer 1; rm -rf ~",
                 "\(handsTools) timer 1 && curl x", "echo $(\(handsTools) memory)", "\(handsTools) timer 1 | sh", "/bin/sh -c '\(handsTools) timer 1'",
                 "\(handsTools) note 'claude-hook-token'", "\(handsTools) activity log x", "\(handsTools) screen --pid 4", "peekaboo click", "x\u{0}y", ""] {
        check(refused(decide("shell_run", ["command": line])), "hands closed: shell_run refuses \(line.debugDescription)")
    }
    check(decide("shell_run", ["command": "\(handsTools) timer 25"]) == .run && decide("shell_run", ["command": "\(handsTools) volume 40 && \(handsTools) timer 5"]) == .run,
          "hands closed: shell_run runs aris-tools lines the old rules allowed")
    check(refused(decide("shell_run", ["command": "\(handsTools) web fetch https://example.com"], marked: true, judge: judgeNo)),
          "hands closed: shell_run's page after a read still goes to the judge")
    check(ArisTodayTrust.rulesRefuse("\(handsTools) timer 1", tools: handsTools, drift: ["Bash"]), "hands closed: a Bash denied by name refuses every line")
    // The typed and generic calls: Claude Code's deny rules on their line too.
    check(refused(decide("save_note", ["markdown": "see ~/.config/aris/claude-hook-token"])) && refused(decide("aris", ["args": ["activity", "log", "x"]])),
          "hands closed: a typed call whose line a deny rule names is refused")
    // file.read: Aris's own folder only, less its records; nothing outside it, no link out of it.
    let own = NSHomeDirectory() + "/.config/aris/aris"
    for path in ["/etc/passwd", NSHomeDirectory() + "/.ssh/id_rsa", NSHomeDirectory() + "/Documents/a.txt", own + "/memory.sqlite", own + "/schedules.json",
                 own + "/tasks/x.jsonl", own + "/../claude-hook-token", NSHomeDirectory() + "/.config/aris/claude-hook-token", "relative.txt"] {
        check(refused(decide("read_file", ["path": path])), "hands closed: read_file refuses \(path)")
    }
    // file.write, file.edit, file.search: today's Claude had no such tool.
    check(refused(decide("write_file", ["path": "/tmp/x.txt", "text": "x"])) && refused(decide("edit_file", ["path": "/tmp/x.txt", "old": "a", "new": "b"]))
          && refused(decide("search_files", ["in": "/tmp", "pattern": "*.txt"])), "hands closed: writing, editing and searching files wait for the trust policy")
    // web: the hook's own rules (a local address never; after a read, the judge).
    check(refused(decide("web_fetch", ["url": "http://127.0.0.1:23351/ask"])) && refused(decide("web_fetch", ["url": "http://localhost/"])),
          "hands closed: web_fetch never reaches a local address")
    check(refused(decide("web_fetch", ["url": "https://example.com"], marked: true, judge: judgeNo))
          && refused(decide("web_search", ["query": "x"], marked: true, judge: judgeNo)), "hands closed: after a read the judge decides the web")
    check(decide("web_search", ["query": "서울 날씨"]) == .run, "hands closed: a search on a clean turn runs, as WebSearch did")
    // The never-list holds whatever the policy says.
    struct Yes: ArisTrustDeciding { func decide(_ call: ArisTrustCall) -> ArisTrustVerdict { .run } }
    let entry = ArisCapabilityBook.entry(named: "shell_run")!
    let never = ArisTrustCall(entry: entry, arguments: ["command": "sudo rm -rf /"], effect: entry.effect(["command": "sudo rm -rf /"]), argv: nil, stdin: nil,
                              environment: [:], tools: handsTools)
    if case .trust(let verdict) = ArisCapabilityGate.decide([], tools: handsTools, turn: .trust(Yes(), never)) {
        check(refused(verdict), "hands closed: the never-list holds under any policy")
    } else { check(false, "hands closed: the never-list holds under any policy") }
}

// MARK: - Aris's own reads in process

private func handsLocalTests() {
    let folder = handsFolder("local")
    let store = ArisMemoryStore.at(folder)
    _ = store.remember(ArisMemoryCandidate(kind: .preference, subject: "", text: "커피는 라떼", confidence: 1), source: .tool, turnAt: Date(), approved: true)
    let none: ([String: String]) -> Set<ArisTeammateScope>? = { _ in nil }
    let memory = ArisCapabilityLocal.run(["memory"], environment: [:], folder: folder, home: folder.path, scopes: none)
    check(memory?.status == 0 && memory?.stdout.contains("라떼") == true && memory?.stderr == "", "hands local: memory is read in process")
    check(ArisCapabilityLocal.run(["memory", "녹차"], environment: [:], folder: folder, home: folder.path, scopes: none)?.text(cap: 6_000) == "(nothing remembered yet)",
          "hands local: nothing matching says so, as aris-tools prints it")
    check(ArisCapabilityLocal.run(["recall", "--bogus"], environment: [:], folder: folder, home: folder.path, scopes: none)?.status == 1,
          "hands local: a recall aris-tools can't read fails as it does")
    check(ArisCapabilityLocal.run(["shelf"], environment: [:], folder: folder, home: folder.path, scopes: none)?.text(cap: 6_000) == "The shelf is empty.",
          "hands local: the shelf, read in process")
    let sealed = ArisCapabilityLocal.run(["memory"], environment: [ArisSealedTools.environmentKey: "1", ArisSealedTools.handsFreeKey: "1"], folder: folder, home: folder.path, scopes: none)
    check(sealed?.status == 1 && sealed?.stderr == (ArisSealedTools.refusal(environment: [ArisSealedTools.environmentKey: "1", ArisSealedTools.handsFreeKey: "1"], arguments: ["memory"]) ?? "x") + "\n",
          "hands local: a hands-free process's memory is refused with aris-tools' own line")
    // A teammate's job: what aris-tools would refuse (by its scopes) is refused here with the same line, the rest runs.
    for argv in [["memory"], ["recall", "x"], ["shelf"]] {
        let none = Set<ArisTeammateScope>()
        let said = ArisCapabilityLocal.run(argv, environment: [:], folder: folder, home: folder.path, scopes: { _ in none })
        let expected = ArisTeammateScope.refusal(scopes: none, arguments: argv)
        check(expected.map { said?.status == 1 && said?.stderr == $0 + "\n" } ?? (said?.status == 0), "hands local: a teammate's \(argv[0]) is refused exactly when aris-tools refuses it")
    }
    check(ArisCapabilityLocal.run(["timer", "5"], environment: [:], folder: folder, home: folder.path, scopes: none) == nil
          && !ArisCapabilityLocal.handles(["todo"]) && ArisCapabilityLocal.handles(["recall", "x", "--tainted"]), "hands local: only the registry's in-process rows run here")
    check(ArisCapabilityLocal.Output(status: 1, stdout: "out\n", stderr: "").text(cap: 99) == "out" && ArisCapabilityLocal.Output(status: 1, stdout: "o", stderr: " bad \n").text(cap: 99) == "bad"
          && ArisCapabilityLocal.Output.printed(String(repeating: "x", count: 10)).text(cap: 4) == "xxxx", "hands local: read back as an aris-tools child's output is")
    // The API brain's helper runs such a call in process and never starts aris-tools for it.
    let started = NSLock()
    nonisolated(unsafe) var spawned = 0
    let helper = ArisAPIHelper(profile: ArisAPIProfile(id: "ollama", quick: "m", strong: "m", baseURL: nil, vision: nil, tools: nil), tools: "/x/aris-tools",
                               send: { _ in }, key: { _ in nil }, run: { _, _, done in started.withLock { spawned += 1 }; done(0, "spawned") },
                               local: { argv in argv.first == "memory" ? .printed("in process") : nil })
    _ = helper
    check(spawned == 0, "hands local: building the helper starts nothing")
}

// MARK: - The shim's server

private func handsServerTests() {
    let lock = NSLock()
    nonisolated(unsafe) var lines: [[String: Any]] = []
    nonisolated(unsafe) var ran: [[String]] = []
    let folder = handsFolder("server")
    let server = ArisHandsServer(tools: handsTools, environment: [ArisTurnGate.stateKey: folder.path],
                                 write: { data in lock.withLock { lines.append(jsonLine(data)) } }, judge: { _ in .ok },
                                 run: { _, argv, _, _, _, _ in
                                     lock.withLock { ran.append(argv) }
                                     if argv.first == "desktop", argv.dropFirst().first != "wait" { return ArisCapabilityLocal.Output(status: ArisSlowCalls.waitingStatus, stdout: "", stderr: "still under way: run desktop wait 0123456789abcdef") }
                                     if argv.first == "mail" { return .printed("from: 은행\n새 카드") }
                                     return .printed("done")
                                 },
                                 local: { argv, _ in argv.first == "memory" ? .printed("커피는 라떼") : nil }, mayRun: { true })
    server.receive(Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#.utf8))
    server.receive(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
    server.receive(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8))
    let listed = lock.withLock { ((lines.last?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? [] }
    check((lock.withLock { (lines.first?["result"] as? [String: Any])?["protocolVersion"] as? String }) == "2025-06-18" && listed == ArisCapabilityBook.all.map(\.name),
          "hands server: initialize answers the client's version; tools/list is the whole book")
    let timer = server.answer(name: "timer", input: ["minutes": 25])
    check(!timer.isError && timer.text == "done" && lock.withLock { ran.last } == ["timer", "25"] && timer.content == nil, "hands server: a timer runs as aris-tools timer 25")
    let memory = server.answer(name: "aris", input: ["args": ["memory"]])
    check(memory.text == "커피는 라떼" && lock.withLock { ran.last } == ["timer", "25"] && memory.content?.kind == "aris", "hands server: a memory read runs in process, marked as content")
    let mail = server.answer(name: "aris", input: ["args": ["mail", "recent"]])
    check(mail.content == ArisToolResult.Content(kind: "mail", source: "aris-tools mail recent") && mail.meta != nil, "hands server: mail comes back marked as mail")
    let desktop = server.answer(name: "desktop_click", input: ["ref": "@s1:e3"])
    check(lock.withLock { ran.suffix(2) } == [["desktop", "click", "@s1:e3"], ["desktop", "wait", "0123456789abcdef"]] && desktop.text == "done",
          "hands server: a call that hands back an id is collected here")
    let shell = server.answer(name: "shell_run", input: ["command": "rm -rf ~"])
    check(shell.isError && shell.text == ArisTodayTrust.shellRefusal, "hands server: a general shell line is refused with a clear message")
    check(server.answer(name: "timer", input: ["minutes": "x"]).isError, "hands server: arguments off the schema run nothing")
    let refusedOrigin = ArisHandsServer(tools: handsTools, environment: [:], write: { _ in }, judge: { _ in .ok }, run: { _, _, _, _, _, _ in .printed("ran") },
                                        local: { _, _ in nil }, mayRun: { false })
    check(refusedOrigin.answer(name: "timer", input: ["minutes": 5]).text == ArisOrigin.refusedLine, "hands server: the start check looked at again, as the hook does")
    server.receive(Data(#"{"jsonrpc":"2.0","id":9,"method":"nope"}"#.utf8))
    check(lock.withLock { (lines.last?["error"] as? [String: Any])?["code"] as? Int } == -32601, "hands server: an unknown method is an error")
    let shown = ArisHandsServer.shown(ArisCapabilityLocal.Output(status: 2, stdout: "a", stderr: "b"))
    check(shown.isError && shown.text == "Exit code 2\na\nb", "hands server: a failure shows its status, its output and its complaint")
}

// MARK: - The init check

private func handsInitTests() {
    let names = ArisHandsFace.clientNames
    let server: [Any] = [["name": "aris", "status": "connected"]]
    check(ArisClaudeInit.verdict(listed: names, servers: server, expected: [], mcp: names) == .ok, "hands init: exactly the one server and its tools")
    check(ArisClaudeInit.verdict(listed: names + ["mcp__other__x"], servers: server, expected: [], mcp: names) == .refused
          && ArisClaudeInit.verdict(listed: Array(names.dropFirst()), servers: server, expected: [], mcp: names) == .refused
          && ArisClaudeInit.verdict(listed: names, servers: server + [["name": "x", "status": "connected"]], expected: [], mcp: names) == .refused
          && ArisClaudeInit.verdict(listed: names, servers: [["name": "aris", "status": "failed"]], expected: [], mcp: names) == .refused
          && ArisClaudeInit.verdict(listed: names, servers: [["name": "evil", "status": "connected"]], expected: [], mcp: names) == .refused
          && ArisClaudeInit.verdict(listed: names + [names[0]], servers: server, expected: [], mcp: names) == .refused,
          "hands init: another tool or server, one missing, a failed server or a repeated name stops the process")
    check(ArisClaudeInit.verdict(listed: names + ["Bash"], servers: server, expected: [], mcp: names) == .relaunch(extra: ["Bash"]),
          "hands init: a built-in tool that came back anyway is denied by name in the next process")
    check(ArisClaudeInit.verdict(listed: ["Bash", "Read", "WebFetch", "WebSearch"], servers: [], expected: ["Bash", "Read", "WebFetch", "WebSearch"]) == .ok
          && ArisClaudeInit.verdict(listed: ["Bash", "Read", "WebFetch", "WebSearch"], servers: server, expected: ["Bash", "Read", "WebFetch", "WebSearch"]) == .refused,
          "hands init: with the switch off, no MCP server at all, as before")
}

// MARK: - The launch: byte for byte today's with the switch off

private func handsLaunchTests() {
    let saved = ArisCore2.isOn
    defer { ArisCore2.isOn = saved }
    ArisCore2.isOn = { false }
    let off = ArisClaudeDriver(model: "sonnet", tools: handsTools)
    check(off.hands == nil && off.arguments.contains(#"{"mcpServers":{}}"#) && off.arguments.contains(ArisTurnGate.hookSettings(tools: handsTools))
          && off.arguments.contains("Bash,Read,WebSearch,WebFetch") && !off.arguments.contains { $0.hasPrefix("mcp__") } && off.environment["ENABLE_TOOL_SEARCH"] == nil,
          "hands launch: off, the open Claude starts as today")
    ArisCore2.isOn = { true }
    let on = ArisClaudeDriver(model: "sonnet", tools: handsTools)
    let arguments = on.arguments
    let config = arguments.firstIndex(of: "--mcp-config").map { jsonLine(Data(arguments[$0 + 1].utf8)) } ?? [:]
    let aris = (config["mcpServers"] as? [String: Any])?["aris"] as? [String: Any]
    check(on.hands != nil && aris?["type"] as? String == "stdio" && (aris?["args"] as? [String]) == ["hands-mcp", "--tools", handsTools]
          && arguments.firstIndex(of: "--tools").map { arguments[$0 + 1] } == "" && arguments.contains("--strict-mcp-config")
          && ArisHandsFace.clientNames.allSatisfy(arguments.contains) && !arguments.contains(ArisTurnGate.hookSettings(tools: handsTools))
          && on.environment["ENABLE_TOOL_SEARCH"] == "false" && on.environment[ArisTurnGate.stateKey] != nil,
          "hands launch: on, model-only: no built-in tool, Aris's one stdio server, its tools allowed by name, no hook")
    check(ArisClaudeDriver(model: "sonnet", tools: handsTools, sealed: true).hands == nil && ArisClaudeDriver(model: "sonnet", tools: handsTools, handsFree: true).hands == nil
          && ArisClaudeDriver(model: "sonnet", tools: handsTools, scopes: Set([.web])).hands == nil, "hands launch: never the sealed, hands-free or a teammate's Claude")
    // observe reads a face call as its built-in form: a mail read marks the thread, a timer doesn't.
    let initLine = String(decoding: try! JSONSerialization.data(withJSONObject: ["type": "system", "subtype": "init", "tools": ArisHandsFace.clientNames,
                                                                                   "mcp_servers": [["name": "aris", "status": "connected"]]]), as: UTF8.self)
    _ = on.read(initLine)
    _ = on.ask("x", tier: .quick)
    _ = on.read(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"mcp__aris__timer","input":{"minutes":5}}]}}"#)
    let cleanAfterTimer = on.taint == .none
    _ = on.read(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"mcp__aris__aris","input":{"args":["mail","recent"]}}]}}"#)
    check(cleanAfterTimer && on.taint == .outsideText, "hands launch: the classifier reads a face call as its Bash line")
    let prompt = ArisHandsPrompt.system(task: false), old = ArisAgentPrompt.system(tools: handsTools, task: false, reads: true)
    print("hands prompt: open Claude (shell) \(old.count) characters, arisCore2 (tool schemas) \(prompt.count)")
    check(!prompt.contains("the only shell command you can run"), "hands launch: the model-only prompt teaches no shell")
}

// MARK: - The per-call saving

private func handsMeasureTests() {
    let folder = handsFolder("measure")
    let none: ([String: String]) -> Set<ArisTeammateScope>? = { _ in nil }
    let rounds = 50
    var start = Date()
    for _ in 0..<rounds { _ = ArisCapabilityLocal.run(["memory"], environment: [:], folder: folder, home: folder.path, scopes: none) }
    let local = Date().timeIntervalSince(start) / Double(rounds)
    // The floor of a child process: /usr/bin/true through the same runner the shim uses for aris-tools.
    start = Date()
    for _ in 0..<rounds { _ = ArisHandsServer.runTools("/usr/bin/true", [], nil, [:], 10) { _ in } }
    let child = Date().timeIntervalSince(start) / Double(rounds)
    print(String(format: "hands measure: a memory read in process %.2f ms; the least a child process costs %.2f ms", local * 1_000, child * 1_000))
    check(local < child, "hands measure: in process is cheaper than the cheapest child")
}
