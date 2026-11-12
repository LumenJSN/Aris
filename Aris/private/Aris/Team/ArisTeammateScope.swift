//
//  ArisTeammateScope.swift
//  Aris (also built into aris-agent and aris-tools)
//
//  What a teammate may use (the 팀원 page's 쓸 수 있는 것): files, the web, websites through Aside, apps, reading mail
//  and messages, sending, the calendar and reminders, the terminal. A teammate's job runs with its scopes in ARIS_TEAMMATE_SCOPES, set by the
//  agent from the stored teammate (never from a request), and every gate reads them: the risk gate (Codex, the API
//  brain), the open and sealed Claude's PreToolUse hooks, and aris-tools itself (every brain, agy included). A command
//  outside them is refused, not asked. Risky steps inside them still ask with a card as ever. Pure.
//  A refusal is never a dead end for the user (audit team-8): it names the switch that is off and tells the brain to tell
//  him he can turn it on for this teammate in 설정 › 팀원 (missingLine).
//

import Foundation

enum ArisTeammateScope: String, CaseIterable, Codable, Sendable {
    case files, web, aside, apps, mail, send, calendar, terminal

    /// The variable the agent sets for a teammate's job: the scopes' raw values, comma separated ("" is none at all).
    static let environmentKey = "ARIS_TEAMMATE_SCOPES"
    /// Set beside it by the agent alone: this process is a teammate's job, so a missing scope variable means nothing is
    /// allowed (fail closed), never everything.
    static let jobKey = "ARIS_TEAMMATE_JOB"

    /// The variables for `scopes` (sorted, so the same set always reads the same).
    static func environment(_ scopes: Set<ArisTeammateScope>) -> [String: String] {
        [environmentKey: scopes.map(\.rawValue).sorted().joined(separator: ","), jobKey: "1"]
    }

    /// The scopes a process runs under; nil when it isn't a teammate's job (no limit). A teammate's job whose variable is
    /// missing or unreadable may use nothing (fail closed).
    static func current(_ environment: [String: String]) -> Set<ArisTeammateScope>? {
        guard environment[jobKey] != nil || environment[environmentKey] != nil else { return nil }
        return environment[environmentKey].flatMap(parse) ?? []
    }

    /// "files,web" → the set; nil when any part isn't a scope.
    static func parse(_ raw: String) -> Set<ArisTeammateScope>? {
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let scopes = parts.compactMap(ArisTeammateScope.init(rawValue:))
        return scopes.count == parts.count ? Set(scopes) : nil
    }

    /// Stored lists: known values only, each once, in the page's order.
    static func canonical(_ raw: [String]) -> [String] {
        allCases.map(\.rawValue).filter(raw.contains)
    }

    static func isAll(_ scopes: Set<ArisTeammateScope>) -> Bool { scopes == Set(allCases) }

    /// Stored scopes from a list written before `aside` had its own switch (`version` 1, d46a95cb): every other scope on
    /// meant everything, so it gets `aside` too (N6; otherwise an agy teammate would quietly answer in words only). Any
    /// other list, or one written since (version 2), is kept as it is.
    static func migrated(_ raw: [String], version: Int) -> [String] {
        guard version < 2, Set(raw) == Set(allCases.filter { $0 != .aside }.map(\.rawValue)) else { return raw }
        return allCases.map(\.rawValue)
    }

    /// The switches the 팀원 page shows for a teammate on `brain` (N4): a Claude teammate has no terminal switch, since
    /// the open Claude's turn gate runs no command but aris-tools whatever it says (ArisTeamCopy.terminalOnClaude says so).
    static func shown(brain: String) -> [ArisTeammateScope] {
        brain == "claude" ? allCases.filter { $0 != .terminal } : allCases
    }

    // MARK: - aris-tools

    /// What an aris-tools subcommand needs: `[]` nothing (a timer, the volume, music, opening an app or a window, the
    /// board, Aris's own memory; undo here, though aris-tools then wants the scope of what it undoes: ArisUndo.scope);
    /// nil a subcommand not known here (refused under any limit).
    static func needed(forTools arguments: [String]) -> Set<ArisTeammateScope>? {
        guard let first = arguments.first else { return [] }
        switch first {
        case "find", "open", "folder", "rename", "move", "trash", "convert", "merge", "split", "compress", "files", "finder",
             "note", "notes", "obsidian", "shelf":
            return [.files]
        case "web", "weather", "stock", "currency", "maps", "canvas", "brief", "link", "tab":
            return [.web]
        case "aside":
            return [.aside]
        case "desktop", "keys", "type", "screen", "selection", "clipboard", "shortcut", "shortcuts":
            return [.apps]
        case "messages", "mail":
            return [.mail]
        case "message":
            return [.send]
        case "mcp":
            // The connected services read and send.
            return [.mail, .send]
        case "event", "calendars", "use-calendar", "calendar", "remind", "todo", "schedule":
            return [.calendar]
        case "skill":
            // The user's own skills, switched on by them: listing and reading one is a read, and every script run asks on a
            // card of its own in the agent (ArisSkillTool). Not the terminal's: a Claude teammate has no such switch
            // (shown(brain:)), so skills would be locked to the other brains (audit team-9).
            return []
        case "timer", "music", "volume", "app", "window", "windows", "tile", "new", "board", "activity", "undo", "remember", "forget", "memory", "recall":
            return []
        default:
            return nil
        }
    }

    /// Whether `scopes` allow this aris-tools call.
    static func allows(toolsArguments arguments: [String], scopes: Set<ArisTeammateScope>) -> Bool {
        needed(forTools: arguments).map { $0.isSubset(of: scopes) } ?? false
    }

    /// aris-tools' own check (every brain): in a teammate's job, the refusal for a call outside its scopes; nil to go ahead.
    static func refusal(environment: [String: String], arguments: [String]) -> String? {
        refusal(scopes: current(environment), arguments: arguments)
    }

    static func refusal(scopes: Set<ArisTeammateScope>?, arguments: [String]) -> String? {
        guard let scopes, !allows(toolsArguments: arguments, scopes: scopes) else { return nil }
        return refusalLine(needed(forTools: arguments).map { $0.subtracting(scopes) })
    }

    /// The scopes a process works under, from both channels (re-review 2): the variables, which a brain with the terminal
    /// could clear, and the job file the agent keeps for the brain's process (ArisTeammateJobFile), which no environment
    /// trick removes. Either one makes it a teammate's job; both: only what both allow. Nil: not a teammate's job.
    static func effective(environment: [String: String], jobFile: ArisTeammateJobFile.Found) -> Set<ArisTeammateScope>? {
        let fromEnvironment = current(environment)
        switch jobFile {
        case .none: return fromEnvironment
        case .scopes(let filed): return fromEnvironment.map { $0.intersection(filed) } ?? filed
        }
    }

    /// Said to the brain: the teammate isn't allowed this, so it doesn't try another way. When a switch on the 팀원 page
    /// would allow it, the brain is told to say which one and where the user turns it on (never a flat "I can't").
    static func refusalLine(_ missing: Set<ArisTeammateScope>?) -> String {
        guard let missing, !missing.isEmpty else {
            return "Refused: this teammate isn't allowed this (the user set what it may use on the 팀원 page). Don't try another way; say what you couldn't do."
        }
        let what = allCases.filter(missing.contains).map { "“\($0.englishTitle)”" }.joined(separator: ", ")
        return "Refused: this teammate isn't allowed \(what) (the user set what it may use on the 팀원 page). Don't try another way. "
            + "Finish what you can without it, then tell the user exactly this, in their language: \(missingLine(missing))"
    }

    /// What the user is told when a teammate's job needed a switch that is off: which one, and where to turn it on.
    static func missingLine(_ missing: Set<ArisTeammateScope>) -> String {
        let names = allCases.filter(missing.contains).map { "‘\($0.koreanTitle)’" }.joined(separator: ", ")
        return "이 팀원은 \(names) 권한이 꺼져 있어서 그 부분은 하지 못했어요. 설정 › 팀원 › 쓸 수 있는 것에서 켜면 다시 맡길 수 있어요."
    }

    /// The 팀원 page's word for it (the user's cards are Korean).
    var koreanTitle: String {
        switch self {
        case .files: "파일"
        case .web: "웹"
        case .aside: "웹사이트 조작 (Aside)"
        case .apps: "앱 조작"
        case .mail: "메일 · 메시지 읽기"
        case .send: "보내기"
        case .calendar: "캘린더 · 미리 알림"
        case .terminal: "터미널"
        }
    }

    /// What a teammate may use, in the page's order and words ("파일, 캘린더 · 미리 알림"; "없음" for nothing).
    static func summary(_ scopes: Set<ArisTeammateScope>) -> String {
        let shown = allCases.filter(scopes.contains).map(\.koreanTitle)
        return shown.isEmpty ? "없음" : shown.joined(separator: ", ")
    }

    var englishTitle: String {
        switch self {
        case .files: "files"
        case .web: "the web"
        case .aside: "websites through Aside"
        case .apps: "using apps"
        case .mail: "reading mail and messages"
        case .send: "sending messages and mail"
        case .calendar: "the calendar and reminders"
        case .terminal: "the terminal"
        }
    }

    // MARK: - Hooks (the open and the sealed Claude)

    /// A Claude PreToolUse hook's check, before its own: in a teammate's job (`scopes`: effective(…), nil for any other), the refusal for a web tool without `web`, a
    /// Read without files or the terminal, or an aris-tools command outside the scopes (every command of a chain); nil to
    /// go on to the hook's own rules. `words`: how a command line splits into calls (ArisCommandPolicy, which this file
    /// can't see).
    /// `desktop`: a desktop call's words after `desktop` (ArisDesktopShell, a heredoc's typed text included, which the
    /// shell never runs), nil for any other line.
    static func hookRefusal(input: Data, tools: String, scopes: Set<ArisTeammateScope>?,
                            words: (String) -> [[String]]?, desktop: (String) -> [String]? = { _ in nil }) -> String? {
        guard let scopes else { return nil }
        guard let object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any], let tool = object["tool_name"] as? String else {
            return refusalLine(nil)
        }
        switch tool {
        case "WebSearch", "WebFetch":
            return scopes.contains(.web) ? nil : refusalLine([.web])
        case "Read":
            return scopes.contains(.files) || scopes.contains(.terminal) ? nil : refusalLine([.files])
        case "Bash":
            guard let command = (object["tool_input"] as? [String: Any])?["command"] as? String else { return refusalLine(nil) }
            // One desktop call with its text in a heredoc (the only way to type): its command line is what runs.
            if let arguments = desktop(command) {
                let head = command.unicodeScalars.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
                    .map { String(String.UnicodeScalarView($0)) } ?? ""
                guard !mentionsEnvironment(head) else { return refusalLine(nil) }
                let call = ["desktop"] + arguments
                return allows(toolsArguments: call, scopes: scopes) ? nil : refusalLine(needed(forTools: call).map { $0.subtracting(scopes) })
            }
            guard let calls = words(command), !touchesEnvironment(command, calls: calls, tools: tools) else { return refusalLine(nil) }
            for call in calls {
                guard call.first == tools else { return scopes.contains(.terminal) ? nil : refusalLine([.terminal]) }
                let rest = Array(call.dropFirst())
                if !allows(toolsArguments: rest, scopes: scopes) { return refusalLine(needed(forTools: rest).map { $0.subtracting(scopes) }) }
            }
            return nil
        default:
            return refusalLine(nil)
        }
    }

    /// `command` reads or changes the environment: either scope variable named anywhere, or (unless every call is an
    /// aris-tools call, whose words are data it is handed, never run by the shell) mentionsEnvironment (bug hunt F9).
    static func touchesEnvironment(_ command: String, calls: [[String]]?, tools: String) -> Bool {
        if command.contains(environmentKey) || command.contains(jobKey) { return true }
        if let calls, !calls.isEmpty, calls.allSatisfy({ $0.first == tools }) { return false }
        return mentionsEnvironment(command)
    }

    /// A command that reads or changes the environment (env, unset, export, either scope variable, or a script that clears
    /// it: os.environ, %ENV / $ENV, ENV.clear, process.env, putenv): never a teammate's.
    static func mentionsEnvironment(_ command: String) -> Bool {
        command.contains(environmentKey) || command.contains(jobKey)
            || command.range(of: #"(?<![\w./-])(?:[\w./-]*/)?(env|unset|export|setenv|unsetenv|putenv|clearenv)(?![\w-])"#, options: .regularExpression) != nil
            || command.range(of: #"os\.environ|[%$]ENV\b|\bENV\s*(\.|\[|=)|process\.env|getenv|\benviron\b"#, options: .regularExpression) != nil
    }

    // MARK: - The risk gate (Codex, the API brain)

    /// What a shell command needs: an aris-tools call's scopes, a plain read (ls, cat…) files, anything else the
    /// terminal. `words`: the command's calls, nil when it isn't one plain chain.
    static func needed(shell words: [[String]]?, tools: String, readsOnly: Bool) -> Set<ArisTeammateScope>? {
        guard let words, !words.isEmpty, words.allSatisfy({ $0.first == tools }) else { return readsOnly ? [.files] : [.terminal] }
        var all = Set<ArisTeammateScope>()
        for call in words {
            guard let needed = needed(forTools: Array(call.dropFirst())) else { return nil }
            all.formUnion(needed)
        }
        return all
    }

    /// Whether a shell command fits `scopes` (a plain read fits files or the terminal).
    static func allowsShell(words: [[String]]?, tools: String, readsOnly: Bool, scopes: Set<ArisTeammateScope>) -> Bool {
        guard let needed = needed(shell: words, tools: tools, readsOnly: readsOnly) else { return false }
        if needed == [.files], readsOnly, words?.first?.first != tools { return scopes.contains(.files) || scopes.contains(.terminal) }
        return needed.isSubset(of: scopes)
    }

    /// A tool from a server: computer use is apps, Aside websites; Notion is a connected service like any other, so it
    /// needs what `aris-tools mcp` needs (reading and sending: N18, the same through Codex as through aris-tools); any
    /// server Aris doesn't know (a ChatGPT app, a new connector) needs every scope, since what it reads or sends can't be told.
    static func needed(server: String) -> Set<ArisTeammateScope> {
        switch server {
        case "cua_repl", "unified-computer-use": [.apps]
        case "aris_aside": [.aside]
        case "aris_notion": needed(forTools: ["mcp"]) ?? Set(allCases)
        default: Set(allCases)
        }
    }
}

/// The second channel for a teammate's scopes (re-review 2): when the agent starts a teammate's brain it writes
/// ~/.config/aris/aris/teammate-jobs/<pid> (0600 in a 0700 folder) with the process's start time and its scopes, and
/// removes it when the process ends. aris-tools walks its own parent chain: a process below a brain with a job file is
/// that teammate's, whatever its environment says; a file that can't be read allows nothing. It also names the teammate
/// (its id), which is who the job is for aris-tools (its schedules, its undo), never ARIS_TEAMMATE. Kept here (plain
/// POSIX) because the agent, aris-tools and the tests all build it.
enum ArisTeammateJobFile {
    enum Found: Equatable {
        case none
        case scopes(Set<ArisTeammateScope>)
    }

    /// A job file's scopes and the teammate it names (nil: none, an older file, or an id that isn't one).
    struct Job: Equatable {
        let found: Found
        let teammate: String?
    }

    private struct Record: Codable {
        let started: Double
        let scopes: String
        var teammate: String?
    }

    /// A teammate id as the agent stores them (lowercase letters, digits, dashes), else nil.
    static func teammateId(_ id: String?) -> String? {
        guard let id, id.range(of: #"^[a-z0-9][a-z0-9-]{0,31}$"#, options: .regularExpression) != nil else { return nil }
        return id
    }

    static func folder(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/aris/aris/teammate-jobs")
    }

    static func file(home: String, pid: Int32) -> URL {
        folder(home: home).appendingPathComponent(String(pid))
    }

    /// Writes the job file for the brain's process `pid` (started at `started`); false when it couldn't (the agent then
    /// doesn't run the job).
    @discardableResult
    static func write(pid: Int32, started: Double, scopes: Set<ArisTeammateScope>, teammate: String? = nil, home: String) -> Bool {
        let folder = folder(home: home)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else { return false }
        chmod(folder.path, 0o700)
        let record = Record(started: started, scopes: scopes.map(\.rawValue).sorted().joined(separator: ","), teammate: teammate)
        guard let data = try? JSONEncoder().encode(record) else { return false }
        let target = file(home: home, pid: pid)
        unlink(target.path)
        let descriptor = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
            return true
        } catch {
            unlink(target.path)
            return false
        }
    }

    static func remove(pid: Int32, home: String) {
        unlink(file(home: home, pid: pid).path)
    }

    /// Every job file goes (the agent starting: no brain of its outlived it).
    static func sweep(home: String) {
        let folder = folder(home: home)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where Int32(name) != nil {
            unlink(folder.appendingPathComponent(name).path)
        }
    }

    /// The scopes of the nearest of `ancestors` (pid, start time) that has a job file for that very process; a file that
    /// is there but can't be read, isn't the user's private file, or names no known scopes allows nothing.
    static func lookup(ancestors: [(pid: Int32, started: Double?)], home: String) -> Found {
        lookupJob(ancestors: ancestors, home: home).found
    }

    /// The nearest job file's scopes (as `lookup`) and the teammate it names.
    static func lookupJob(ancestors: [(pid: Int32, started: Double?)], home: String) -> Job {
        for ancestor in ancestors {
            let path = file(home: home, pid: ancestor.pid).path
            var info = stat()
            guard lstat(path, &info) == 0 else { continue }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_mode & 0o077 == 0,
                  let data = FileManager.default.contents(atPath: path), let record = try? JSONDecoder().decode(Record.self, from: data) else {
                return Job(found: .scopes([]), teammate: nil)
            }
            // Another process now has that pid: not the job (its file is stale).
            guard let started = ancestor.started, abs(record.started - started) < 0.001 else { continue }
            return Job(found: .scopes(ArisTeammateScope.parse(record.scopes) ?? []), teammate: teammateId(record.teammate))
        }
        return Job(found: .none, teammate: nil)
    }

    /// This process and its parents (at most 32), each with its start time.
    static func ancestors(of pid: Int32 = getpid()) -> [(pid: Int32, started: Double?)] {
        var chain: [(pid: Int32, started: Double?)] = []
        var current = pid
        for _ in 0..<32 {
            guard current > 1 else { break }
            chain.append((current, startTime(of: current)))
            guard let up = parent(of: current), up != current else { break }
            current = up
        }
        return chain
    }

    static func startTime(of pid: Int32) -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        return Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
    }

    private static func parent(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        return info.kp_eproc.e_ppid
    }
}
