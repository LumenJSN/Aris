//
//  ArisTurnGate.swift
//  aris-tools (also built into aris-agent)
//
//  The open Claude's gate (it has no risk gate of its own): a PreToolUse hook, `aris-tools turn-gate`, asked before
//  every tool call. Once the conversation has taken in outside text from a command (the user's messages, mail or notes, the
//  screen, the clipboard: any aris-tools call that isn't clean), every read (the web, another of the user's apps, the
//  weather, a stock, Canvas) first passes the read judge (ArisReadGate, the owner's ruling of 2026-11-06: reads are free,
//  execution still asks), and every aris-tools command that could carry what was read off the Mac or change something
//  goes to the agent's gate, which asks the user on a card (ArisHandOff, `message`): never run here, and no longer refused
//  for the rest of the conversation (audit gate-3: after one weather question a message, an event and the next weather
//  question were all refused). What is neither a read nor a handed-off call is still refused. A background job's reads
//  are judged from the first one. The mark is a file in the driver's private temp folder
//  (ARIS_TURN_STATE), written before the read runs; the agent removes it when the conversation starts over. A read
//  whose mark can't be written, a line that can't be read word by word, and any tool it doesn't know are refused.
//  Pure apart from the mark, so the tests run it with a fake hook harness.
//

import CryptoKit
import Foundation

enum ArisTurnGate {
    static let hookFlag = "turn-gate"
    /// The folder (0700, the driver's own) that holds the mark.
    static let stateKey = "ARIS_TURN_STATE"
    static let markName = "outside-text"
    /// Seconds Claude Code gives the hook (it may wait for the read judge).
    static let hookTimeout = ArisReadGate.hookTimeout

    /// aris-tools commands whose output carries nothing others wrote (arguments checked as ArisSealedTools does).
    static let cleanCommands: Set<String> = ["timer", "volume", "music", "window", "tile", "new", "app", "folder", "calendar"]

    /// A clean aris-tools call: nothing anyone else wrote comes back.
    static func isClean(_ rest: [String]) -> Bool {
        guard let first = rest.first else { return false }
        return cleanCommands.contains(first) && ArisSealedTools.allows(rest)
    }

    /// A call whose answer carries nothing anyone else wrote, so it doesn't make the turn outside text: a clean call, or
    /// a well-formed file tool (`move`, `rename`, `folder new`, and the conversions: `convert`, `merge`, `split`,
    /// `compress`), which prints only the names the brain passed (a conversion's new names are made from them). Only
    /// for marking: after outside text these are still refused (they aren't clean and don't stay local).
    static func bringsNothingIn(_ rest: [String]) -> Bool {
        if isClean(rest) || ArisConvertWords.parse(rest) != nil { return true }
        // The plain `recall` prints Aris's own wording of its record: clean episodes, and lessons (which any turn the user
        // asked may have taught, marked when it read outside content: the owner's ruling); `--tainted` prints the tainted
        // episodes themselves and is outside text (ArisWorkRecallWords).
        if ArisWorkRecallWords.isCleanForm(rest) { return true }
        let plain = { (word: String) in
            !word.isEmpty && !word.hasPrefix("-") && word.count <= 1_024 && !word.contains("\0") && !ArisCommandPolicy.hasLineBreak(word)
        }
        switch rest.first {
        case "move", "rename": return rest.count == 3 && rest.dropFirst().allSatisfy(plain)
        case "folder": return rest.count == 3 && rest[1] == "new" && plain(rest[2])
        default: return false
        }
    }

    /// The open Claude's message (`message <to> <text…>`): the agent decides and sends it, and says back only fixed
    /// words and the recipient the brain gave (ArisMessageGate.reported), so it brings nothing in. Only this brain's.
    static func isAgentMessage(_ rest: [String]) -> Bool {
        rest.count >= 3 && rest[0] == "message" && !rest[1].isEmpty && !rest[1].hasPrefix("-") && rest[1].count <= 200
            && !ArisCommandPolicy.hasLineBreak(rest[1])
    }

    /// Reads that stay on the Mac and write nothing (besides the local app reads), each exactly as written: a bare
    /// `tab` (its title and address, never `tab --text`), a bare `clipboard` and `todo`. Never `memory`: the user's
    /// memories aren't read once outside text came in.
    private static let localReads: [[String]] = [["screen"], ["selection"], ["tab"], ["finder"], ["windows"], ["calendars"], ["shortcuts"],
                                                 ["activity"], ["activity", "--today"], ["schedule", "list"], ["clipboard"], ["todo"], ["shelf"]]

    /// Reads that reach a service outside the Mac with words of the request (the weather for a place, a stock's price,
    /// Canvas, the brief). Free on a clean turn; once outside text came in (or in a job) the read judge checks each
    /// against the user's own words first, like a web search: what was read can't ride out in a place's name (audit gate-3:
    /// they used to be refused for the rest of the conversation). Saving the home place is a write, not one of these.
    static func isOutsideRead(_ rest: [String]) -> Bool {
        guard let first = rest.first, ["weather", "stock", "currency", "canvas", "brief"].contains(first) else { return false }
        return !rest.contains("--set-home")
    }

    /// What may still run here once outside text came in: clean calls, reads that stay on the Mac and the board (shown
    /// on this Mac, nothing sent). A read that reaches outside is judged first (isOutsideRead), and what changes, sends
    /// or opens something goes to the agent's gate (ArisHandOff, `message`). Anything else is refused.
    static func staysLocal(_ rest: [String]) -> Bool {
        guard let first = rest.first else { return true }
        if isClean(rest) || ArisLocalReadPolicy.isRead(rest) || localReads.contains(rest) { return true }
        if first == "find" { return rest.count > 1 && !rest.dropFirst().contains { $0.hasPrefix("-") } }
        // The connected services: aris-tools only hands the call to the agent's one gate, which knows this conversation read
        // outside text (then every call, a read included, shows the user a card).
        if first == "mcp" { return true }
        // A skill: reading it stays on the Mac, and a script waits for the user's card at the agent.
        if first == "skill" { return true }
        // The user's routines: aris-tools only hands the words to the agent, which asks them on a card before one is saved or
        // removed, and marks the conversation itself when it hands AI-worded steps back (ArisRoutineRoutes).
        if first == "routine" { return true }
        // Website work for Aside: the agent's one gate knows this conversation read outside text (then the user's card).
        if first == "aside" { return true }
        return first == "board"
    }

    enum Verdict: Equatable {
        case allow
        /// Allowed, and outside text comes in with it: the mark is written first.
        case allowMarking
        case deny(String)
        /// A read on a careful turn: the read judge decides (`marks`: the mark is written first).
        case judge(ArisReadCall, marks: Bool)
    }

    /// The answer for one tool call. `tainted`: the mark is there. `careful`: a background job, whose every read is
    /// judged. `input`: the tool's own input (a web tool's query or address, for the judge).
    /// `resolve`: the address check's resolver (a WebFetch or `web fetch` address must resolve to public addresses only).
    static func verdict(tool: String, command: String?, tools: String, tainted: Bool, careful: Bool = false, input: [String: Any] = [:],
                        resolve: (String) -> [String]? = ArisWebFetch.liveResolve) -> Verdict {
        switch tool {
        case "WebFetch", "WebSearch":
            // Never a local or internal address, whatever the turn (security review I2).
            if ArisReadGate.fetchAllowed(tool: tool, input: input, resolve: resolve) == false { return .deny(localRefusal) }
            guard let call = ArisReadGate.call(webTool: tool, input: input) else { return .deny(unreadable) }
            // On a careful turn (a job, or after a read) the judge first, and a job's first web call marks it; an
            // ordinary web search on a clean turn neither waits nor marks ("search the news, then add a to-do": R1).
            if tainted { return .judge(call, marks: false) }
            return careful ? .judge(call, marks: true) : .allow
        case "Read":
            return .allowMarking
        case "Bash":
            guard let command else { return .deny(unreadable) }
            return bash(command, tools: tools, tainted: tainted, careful: careful, resolve: resolve)
        default:
            return .deny("Refused: \(tool) isn't one of Aris's tools.")
        }
    }

    static let screenPidRefusal = "Refused: screen reads the app in front; it takes no --pid from here."
    static let localRefusal = "Refused: that address is on an internal or local network (or doesn't resolve). Aris fetches public pages only."
    static let sendRefusal = "Refused: this conversation has read outside content, so nothing that could carry it off the Mac or change things runs until it starts over. Say in a few words that you can't now."
    static let unreadable = "Refused: run one plain aris-tools command at a time (no pipes, substitutions or redirects)."
    static let oneLine = "Refused: give it as one plain command on one line, with no line break or control character inside the quotes (write \\n for a new line in a note)."

    private static func bash(_ command: String, tools: String, tainted: Bool, careful: Bool, resolve: (String) -> [String]?) -> Verdict {
        // Computer use's runtime is the agent's alone, on every brain (I11).
        if ArisProtectedPlaces.executesComputerRuntime(ArisDesktopShell.commandLine(command, tools: tools)) { return .deny(ArisSealedTools.runtimeRefusal) }
        // One desktop call, alone (its text on stdin included): the agent's desktop engine gates it for every brain, marks
        // the app it reads, and knows what this conversation read (then every action shows the user a card).
        if let line = ArisDesktopShell.parse(command, tools: tools) {
            return ArisSealedTools.allows(["desktop"] + line.words) ? .allow : .deny(unreadable)
        }
        guard let pieces = ArisCommandPolicy.segments(command) else { return .deny(unreadable) }
        var marked = tainted, marks = false
        var reads: [[String]] = []
        for piece in pieces {
            guard let words = ArisCommandPolicy.words(piece), words.first == tools else { return .deny(unreadable) }
            let rest = Array(words.dropFirst())
            // The activity log is written for the notch app by aris-agent alone (QA BUG-18).
            if rest.first == "activity", rest.dropFirst().first == "log" { return .deny("Refused: the activity log isn't written from here.") }
            // `screen --pid` is aris-agent's own, for its look with Aris in front (security review 3, L1).
            if rest.first == "screen", rest.contains("--pid") { return .deny(screenPidRefusal) }
            // aris-tools has no mail send: only the read forms of `mail` ever run.
            // A reply's draft is handed to the agent's gate below (ArisHandOff, ArisMailReplyCard).
            if rest.first == "mail", !ArisLocalReadPolicy.isRead(rest), !ArisHandOff.names(rest) { return .deny("Refused: mail is read only here.") }
            // A service call runs alone, and the agent's gate marks the conversation itself before the service is reached
            // (so it judges the call by the taint as it was: M8).
            if rest.first == "mcp" || rest.first == "skill" || rest.first == "aside" || rest.first == "routine" {
                guard pieces.count == 1 else { return .deny(unreadable) }
                continue
            }
            // A message runs alone, so nothing rides along on its card (or its countdown). aris-tools hands it to the
            // agent, which after a read shows the user's plain card, never the countdown (ArisMessageGate.card).
            if rest.first == "message" {
                guard pieces.count == 1 else { return .deny(unreadable) }
                continue
            }
            // `type` hands its text to the agent's desktop engine (`desktop type --focused`), which gates it as every desktop
            // call is gated (the user's card with the exact text, the taint it knows): alone, like a desktop call.
            if rest.first == "type" {
                guard pieces.count == 1 else { return .deny(unreadable) }
                return .allow
            }
            // A write, a send or something opened (ArisHandOff): aris-tools hands it to the agent, whose gate judges it
            // as Codex's same command, knowing what this conversation read (after outside text: the user's card). It runs
            // alone, so nothing rides along on its card. Its answer may carry others' words (an event's title, what an
            // undo put back): the mark first, then.
            if ArisHandOff.names(rest) {
                guard pieces.count == 1 else { return .deny(unreadable) }
                // Alone but not one plain call (a real line break inside a note's quotes): said as that, so it is fixed
                // rather than given up on.
                guard ArisHandOff.isWrite(rest) else { return .deny(oneLine) }
                return tainted || ArisHandOff.bringsNothingIn(rest) ? .allow : .allowMarking
            }
            // Aris's own record of its work (`recall`, ArisWorkRecallWords): the plain form brings nothing in and is judged
            // like the user's memories once outside text came in (or in a job); `--tainted` is outside text from here on.
            if ArisWorkRecallWords.isRecall(rest) {
                guard let recall = ArisWorkRecallWords.parse(rest) else { return .deny("Refused: " + ArisWorkRecallWords.usage) }
                if marked || careful { reads.append(rest) }
                if recall.tainted { marked = true; marks = true }
                continue
            }
            // A page (aris-tools web fetch, public addresses only), the user's memories or a maps lookup (--json, nothing
            // opens: QA BUG-1): reads, judged on a careful turn, and outside text after.
            if let web = ArisReadGate.web(rest) {
                guard web.tool == "web fetch", ArisWebFetch.allows(web.arguments, resolve: resolve) != nil else { return .deny(localRefusal) }
            }
            if ArisReadGate.web(rest) != nil || ArisReadGate.isMemoryRead(rest) || ArisReadGate.isMapsLookup(rest) {
                if marked || careful { reads.append(rest) }
                marked = true
                marks = true
                continue
            }
            // The weather, a stock, Canvas, the brief: after outside text (or in a job) the judge reads the call first.
            if isOutsideRead(rest) {
                if marked || careful { reads.append(rest) }
                marked = true
                marks = true
                continue
            }
            if marked, !staysLocal(rest) { return .deny(sendRefusal) }
            // Another of the user's apps after outside text (or in a job): the judge reads it first.
            if marked || careful, ArisReadGate.isAppRead(rest) { reads.append(rest) }
            if !rest.isEmpty, !bringsNothingIn(rest), !isAgentMessage(rest) { marked = true; marks = true }
        }
        if !reads.isEmpty {
            let call = reads.count == 1 ? ArisReadGate.web(reads[0]) ?? ArisReadGate.call(arisTools: reads[0])
                : ArisReadCall(tool: "aris-tools", arguments: reads.map { $0.joined(separator: " ") }.joined(separator: " ; "))
            return .judge(call, marks: marks && !tainted)
        }
        return marks && !tainted ? .allowMarking : .allow
    }

    // MARK: - The hook

    /// The open Claude's settings: one PreToolUse hook on every tool; anything but a clean yes blocks (`|| exit 2`).
    static func hookSettings(tools: String) -> String {
        let quoted = "'" + tools.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let settings: [String: Any] = ["disableAllHooks": false,
                                       "hooks": ["PreToolUse": [["matcher": "*", "hooks": [["type": "command", "command": "\(quoted) \(hookFlag) || exit 2",
                                                                                         "timeout": hookTimeout]]]]]]
        let data = (try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The hook: reads Claude Code's PreToolUse JSON, answers with an exit code (0 go on, 2 block) and the reason for
    /// a block. No state folder means no mark can be kept: treated as already marked (fail closed). `judge`: the read
    /// judge (aris-tools asks the agent); the default can't decide, so it blocks.
    static func run(input: Data, tools: String, environment: [String: String],
                    judge: (ArisReadCall) -> ArisReadVerdict = { _ in .blocked(.undecided) },
                    resolve: (String) -> [String]? = ArisWebFetch.liveResolve) -> (code: Int32, reason: String?) {
        guard let object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any], let tool = object["tool_name"] as? String else {
            return (2, unreadable)
        }
        let toolInput = object["tool_input"] as? [String: Any] ?? [:]
        let command = toolInput["command"] as? String
        let folder = environment[stateKey].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
        let tainted = isMarked(folder)
        let careful = environment[ArisReadGate.carefulKey] == "1"
        let marked = { () -> Bool in
            // Already counted as after a read (no folder): nothing to write. Otherwise the mark first: a read that
            // couldn't be marked doesn't run.
            tainted || mark(folder)
        }
        switch verdict(tool: tool, command: command, tools: tools, tainted: tainted, careful: careful, input: toolInput, resolve: resolve) {
        case .allow: return (0, nil)
        case .allowMarking:
            return marked() ? (0, nil) : (2, couldntMark)
        case .deny(let reason): return (2, reason)
        case .judge(let call, let marks):
            if marks, !marked() { return (2, couldntMark) }
            let verdict = judge(call)
            return verdict.allowed ? (0, nil) : (2, ArisReadGate.refusal(verdict.why ?? .other))
        }
    }

    static let couldntMark = "Refused: Aris couldn't note this read, so it doesn't run."

    /// The driver's private folder for the mark: a new 0700 folder in the temp folder; nil if it can't be made.
    static func makeFolder() -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-turn-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return folder
        } catch {
            return nil
        }
    }

    /// Whether calls count as after a read: the mark is there, or there is no folder to keep it in (none named, or
    /// gone: fail closed).
    static func isMarked(_ folder: URL?) -> Bool {
        guard let folder else { return true }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else { return true }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(markName).path)
    }

    /// Writes the mark; false when it couldn't be written.
    @discardableResult
    static func mark(_ folder: URL?) -> Bool {
        guard let folder else { return false }
        return FileManager.default.createFile(atPath: folder.appendingPathComponent(markName).path, contents: Data(),
                                              attributes: [.posixPermissions: 0o600])
    }

    /// The conversation starts over: the folder is there again (0700) and the mark is gone.
    static func clear(_ folder: URL?) {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(markName))
    }
}

/// A one-shot pass for one message (security review M1): aris-tools sends `message <to> <text>` where it ran only when
/// the agent minted a pass for exactly that recipient and text moments before: the user's yes (or their countdown's end) to
/// Codex's or the API brain's card, their changed card, or the agent's own send for the open Claude. Anything else that
/// runs aris-tools (a skill's script, a service's or Aside's child) sends nothing. A 0600 file in Aris's own folder,
/// named by a SHA-256 of the message, claimed by renaming it away and gone after one use or `lifetime` seconds. It
/// lives here because this file is built into both aris-tools and aris-agent.
enum ArisMessagePass {
    static let lifetime: TimeInterval = 120
    /// The tests' folder; nil for Aris's own.
    nonisolated(unsafe) static var folderOverride: URL?

    static func folder() -> URL {
        folderOverride ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/aris/aris/message-passes")
    }

    /// Named by the message's composed (NFC) form, so the pass minted from the user's words is the one found for the argv
    /// aris-tools got, however a launcher in between spelled its Hangul (audit nfd-argv-1).
    static func name(to: String, text: String) -> String {
        SHA256.hash(data: Data((to + "\u{0}" + text).precomposedStringWithCanonicalMapping.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The message in one aris-tools argv (`message <to> <text…>`), as aris-tools reads it.
    static func message(_ argv: [String]) -> (to: String, text: String)? {
        guard argv.count >= 3, argv[0] == "message" else { return nil }
        return (argv[1], argv.dropFirst(2).joined(separator: " "))
    }

    /// What a pass for `aris-tools osascript -e '<restart, shut down, log out or sleep>'` is named by (no recipient is
    /// ever called this): aris-tools runs such a script only with the pass the gate minted on the user's yes, so nothing
    /// else that runs aris-tools can restart the Mac.
    static let powerName = "\u{1}power"

    /// What a pass for `aris-tools remember <fact>` is named by (no recipient is ever called this): the gate let that
    /// very call run, on the user's yes to its 기억하기 card or because the fact is their own words this turn (ArisRiskPolicy:
    /// memory is never anyone else's to approve). aris-tools then writes it as reviewed by them: the write gate lets it
    /// off the override and standing families, never the leak or credential ones (eighth VM pass: "앞으로 나를 솔이라고
    /// 불러" was held for review right after 허용).
    static let memoryName = "\u{2}remember"

    /// Passes for every message in a shell command the gate let run (each `<tools> message …` piece), and for a
    /// restart, shut down, log out or sleep sent through aris-tools.
    static func mint(command: String, tools: String) {
        for piece in ArisCommandPolicy.segments(command) ?? [command] {
            guard let words = ArisCommandPolicy.words(piece), words.first == tools else { continue }
            mint(argv: Array(words.dropFirst()))
        }
    }

    /// A pass for one aris-tools argv, when it is a message, one of the four power scripts or a memory write.
    static func mint(argv: [String]) {
        if let message = message(argv) { mint(to: message.to, text: message.text) }
        if let script = ArisCommandPolicy.powerScript(argv) { mint(to: powerName, text: script) }
        if let fact = memory(argv) { mint(to: memoryName, text: fact) }
    }

    /// The fact of one `remember <fact…>` argv, as aris-tools reads it; nil for anything else (or no fact).
    static func memory(_ argv: [String]) -> String? {
        guard argv.count >= 2, argv[0] == "remember" else { return nil }
        let fact = argv.dropFirst().joined(separator: " ")
        return fact.isEmpty ? nil : fact
    }

    @discardableResult
    static func mint(to: String, text: String, now: Date = Date()) -> Bool {
        let folder = folder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = folder.appendingPathComponent(".pass-\(UUID().uuidString)")
        let expiry = String(now.addingTimeInterval(lifetime).timeIntervalSince1970)
        guard FileManager.default.createFile(atPath: temporary.path, contents: Data(expiry.utf8), attributes: [.posixPermissions: 0o600]) else { return false }
        guard rename(temporary.path, folder.appendingPathComponent(name(to: to, text: text)).path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            return false
        }
        return true
    }

    /// Uses the pass for exactly this message: true once, while it is fresh (a link, or anything but Aris's own regular
    /// file, is none).
    static func consume(to: String, text: String, now: Date = Date()) -> Bool {
        let folder = folder()
        let pass = folder.appendingPathComponent(name(to: to, text: text))
        let claimed = folder.appendingPathComponent(".used-\(UUID().uuidString)")
        guard rename(pass.path, claimed.path) == 0 else { return false }
        defer { try? FileManager.default.removeItem(at: claimed) }
        var info = stat()
        guard lstat(claimed.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              let data = FileManager.default.contents(atPath: claimed.path),
              let expiry = Double(String(decoding: data, as: UTF8.self)) else { return false }
        let left = expiry - now.timeIntervalSince1970
        return left > 0 && left <= lifetime + 5
    }
}

/// How aris-tools' file conversions (`convert`, `merge`, `split`, `compress`) are read, the same way by aris-tools and
/// by every gate (the turn gate, the risk gate, agy's relay, the API brain's functions). It lives here because this
/// file is built into both aris-tools and aris-agent. Pure: words in, a reading out.
enum ArisConvertWords {
    static let verbs: Set<String> = ["convert", "merge", "split", "compress"]
    /// At most this many files in one call.
    static let mostFiles = 50
    /// A video or sound job (or one a selector picks) may take this long before aris-tools stops it (nothing is left
    /// behind); any other this long. Each caller waits a little longer (the runner, the API helper, agy's relay).
    static let mediaLimit: TimeInterval = 180
    static let quickLimit: TimeInterval = 25
    /// A caller's own deadline (seconds since 1970), when it is sooner than the budget: aris-tools ends before it.
    static let deadlineKey = "ARIS_CONVERT_DEADLINE"
    /// Set for a background job's AI process: no selector (nobody picked files for it).
    static let taskKey = "ARIS_TASK"

    /// The whole call's time.
    static func budget(_ words: [String]) -> TimeInterval { isLong(words) ? mediaLimit : quickLimit }

    static func deadline(_ words: [String], environment: [String: String] = [:], now: Date = Date()) -> Date {
        let own = now.addingTimeInterval(budget(words))
        guard let given = environment[deadlineKey].flatMap(Double.init) else { return own }
        return min(own, Date(timeIntervalSince1970: given))
    }

    static func deadline(_ call: Call) -> Date {
        now().addingTimeInterval(call.selector != nil || isMedia(call) ? mediaLimit : quickLimit)
    }

    private static func now() -> Date { Date() }
    /// What AVFoundation reads: video and sound files (lowercased extensions).
    static let videoTypes: Set<String> = ["mov", "mp4", "m4v"]
    static let audioTypes: Set<String> = ["m4a", "mp3", "wav", "aiff", "aif", "caf", "aac"]

    /// Files aris-tools picks itself (and never names back to the brain): the Finder selection, or the notch shelf.
    enum Selector: String, Equatable { case finder = "--finder", shelf = "--shelf" }

    struct Call: Equatable {
        let verb: String
        let paths: [String]
        /// Each flag once, with its value (`--to` → `png`).
        let options: [String: String]
        /// Instead of paths: the files aris-tools picks itself.
        var selector: Selector? = nil
    }

    /// The flags each verb takes, every one with a value.
    static func flags(_ verb: String) -> Set<String> {
        switch verb {
        case "convert": return ["--to", "--quality", "--max", "--percent", "--pages"]
        case "merge": return ["--to"]
        case "split": return ["--pages"]
        case "compress": return ["--quality", "--max"]
        default: return []
        }
    }

    /// One well-formed call (the words after aris-tools): its verb, its files (one for `split`, two or more for
    /// `merge`, up to mostFiles) and its flags; nil for anything else. Every word is plain (not empty, no line break or
    /// control character, at most 1,024 characters), a file never starts with "-", and a flag comes once, with a value.
    static func parse(_ words: [String]) -> Call? {
        guard let verb = words.first, verbs.contains(verb), words.count <= 2 * mostFiles + 12,
              words.allSatisfy({ !$0.isEmpty && $0.count <= 1_024 && !ArisCommandPolicy.hasLineBreak($0)
                                 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else { return nil }
        let known = flags(verb)
        var paths: [String] = [], options: [String: String] = [:], selector: Selector?
        var index = 1
        while index < words.count {
            let word = words[index]
            if let picked = Selector(rawValue: word) {
                guard selector == nil else { return nil }
                selector = picked
                index += 1
            } else if word.hasPrefix("-") {
                guard known.contains(word), options[word] == nil, index + 1 < words.count, !words[index + 1].hasPrefix("-") else { return nil }
                options[word] = words[index + 1]
                index += 2
            } else {
                paths.append(word)
                index += 1
            }
        }
        if let selector { return paths.isEmpty ? Call(verb: verb, paths: [], options: options, selector: selector) : nil }
        switch verb {
        case "split": guard paths.count == 1 else { return nil }
        case "merge": guard (2...mostFiles).contains(paths.count) else { return nil }
        default: guard (1...mostFiles).contains(paths.count) else { return nil }
        }
        return Call(verb: verb, paths: paths, options: options)
    }

    /// A call that may take minutes: a video or sound file in it or made, or files aris-tools picks (they may be).
    static func isLong(_ words: [String]) -> Bool {
        guard let call = parse(words) else { return false }
        return call.selector != nil || isMedia(call)
    }

    /// A video or sound file named in it, or made by it.
    static func isMedia(_ call: Call) -> Bool {
        let media = videoTypes.union(audioTypes)
        return ["mp4", "mov", "m4a"].contains(call.options["--to"]?.lowercased() ?? "")
            || call.paths.contains { media.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    /// The same for one shell command line (`<tools> convert …`), as a brain runs it.
    static func isLong(command: String, tools: String) -> Bool {
        guard let words = ArisCommandPolicy.words(command), words.first == tools else { return false }
        return isLong(Array(words.dropFirst()))
    }
}

/// The files on the notch shelf and the app in front when the user asked, kept by aris-agent for `--shelf` and `--finder`
/// (the sandboxed app sends them with each question): `~/.config/aris/aris/shelf.json`, 0600 in Aris's 0700 folder,
/// written at every question (an emptied shelf clears it). Never put in a brain's context: a file's name is anyone's
/// words. Absolute paths without control characters only, at most ArisConvertWords.mostFiles; stale after 30 minutes.
enum ArisShelfFiles {
    struct State: Equatable {
        let shelf: [String]
        /// The bundle id of the app in front when the user asked.
        let front: String?
        let at: Date
    }

    static let staleAfter: TimeInterval = 30 * 60

    static func file(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/aris/aris/shelf.json")
    }

    static func usable(_ paths: [String]) -> [String] {
        Array(paths.filter { $0.hasPrefix("/") && $0.count <= 1_024 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
            .prefix(ArisConvertWords.mostFiles))
    }

    /// Replaced whole (written beside it, then renamed over it); best effort.
    static func save(_ paths: [String], front: String?, home: String, now: Date = Date()) {
        let target = file(home: home), folder = target.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var object: [String: Any] = ["shelf": usable(paths), "at": now.timeIntervalSince1970]
        if let front, front.count <= 255 { object["front"] = front }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let temporary = folder.appendingPathComponent(".shelf-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
        if rename(temporary.path, target.path) != 0 { try? FileManager.default.removeItem(at: temporary) }
    }

    /// What was kept at the last question, unless it is stale (or not the user's own regular file).
    static func state(home: String, now: Date = Date()) -> State? {
        let target = file(home: home)
        guard let values = try? target.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]), values.isSymbolicLink != true,
              values.isRegularFile == true, let data = try? Data(contentsOf: target),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let at = (object["at"] as? NSNumber)?.doubleValue else { return nil }
        let date = Date(timeIntervalSince1970: at)
        guard now.timeIntervalSince(date) < staleAfter, date.timeIntervalSince(now) < 60 else { return nil }
        return State(shelf: usable(object["shelf"] as? [String] ?? []), front: object["front"] as? String, at: date)
    }

    static func load(home: String, now: Date = Date()) -> [String] { state(home: home, now: now)?.shelf ?? [] }
    static func front(home: String, now: Date = Date()) -> String? { state(home: home, now: now)?.front }
}

/// What `aris-tools message` prints, in fixed words with the brain's own recipient and nothing Messages said (audit
/// tools-1: "sent" was printed on the script ending, while Messages showed "Not Delivered"). "sent" only for a message
/// seen as sent in Messages' own database; a failure and an unchecked send each lead with words the brain can't pass on
/// as success. It lives here, like ArisMessagePass, because this file is built into both aris-tools and aris-agent
/// (ArisMessageGate.reported reads these lines back).
enum ArisMessageResult {
    static func sent(_ to: String) -> String { "sent to \(to)" }
    /// A number that isn't on iMessage, reached through the iPhone's text messages.
    static func sentAsText(_ to: String) -> String { "sent to \(to) as a text message (not iMessage)" }

    static let notSentLead = "NOT SENT:"
    static func notSent(_ to: String) -> String {
        "\(notSentLead) Messages shows the message to \(to) as not delivered, so it wasn't sent. They may not use iMessage, and this Mac may not be " +
            "set up to send text messages through an iPhone. Tell the user it wasn't sent."
    }

    static let notConfirmedLead = "NOT CONFIRMED:"
    /// Why a send isn't known to have gone out: Messages doesn't show it as sent yet; its database can't be read
    /// (no Full Disk Access); or the send was cut off at its time limit.
    enum Unconfirmed {
        case notShown, unreadable, tookTooLong
    }

    static func notConfirmed(_ to: String, _ why: Unconfirmed) -> String {
        let what: String
        switch why {
        case .notShown: what = "Messages took the message for \(to) but doesn't show it as sent yet."
        case .unreadable: what = "Messages took the message for \(to), but Aris couldn't check that it went out (Aris needs Full Disk Access to see Messages' history)."
        case .tookTooLong: what = "Sending to \(to) took too long, so it isn't known whether the message went out."
        }
        return "\(notConfirmedLead) \(what) Don't send it again and don't say it was sent: tell the user it was handed to Messages and to check there."
    }

    /// Aris may not control Messages (macOS's Automation permission).
    static let notAllowed = "\(notSentLead) Aris isn't allowed to control Messages: it is turned on in System Settings > Privacy & Security > Automation. Nothing was sent."
    /// Any other failure before Messages took the message.
    static let failed = "\(notSentLead) Messages couldn't send it. Nothing was sent."

    /// Messages has no account to send from, or doesn't know the person on it (AppleScript's "can't get" errors).
    static let noAccount = "\(notSentLead) Messages has no account signed in that can send this (or it can't reach that person). Nothing was sent. " +
        "Tell the user to open Messages and check it is signed in."
}

/// The aris-tools calls a Claude never runs in its own process (the owner: no feature locked to one brain; audit gate-2,
/// gate-3, gate-1). The Claudes have no risk gate of their own, so what writes, sends, deletes or opens something used
/// to be refused to them outright ("GPT한테 물어봐"). Now aris-tools, inside a Claude's process, hands each such call to
/// the agent (POST /action-tool, as `message` goes to /message-tool), which judges it exactly as Codex's same command
/// is judged (ArisActionGate: ArisAPIGate.judge), shows the user's card when that says to ask, and runs it itself. Inside a
/// Claude's process these never run where they were called: the hand-off is the only door. It lives here because this
/// file is built into both aris-tools and aris-agent. Pure: words in, an answer out.
enum ArisHandOff {
    /// Set for the sealed Claude alone (a turn that saw the screen), as ArisSealedTools.messageKey is for `message`: its
    /// hook and aris-tools then take the forms below and hand them over. Never for a hands-free turn (the owner: nothing is
    /// sent, deleted or changed on words anyone could have said), agy's relay or the sealed API brain.
    static let sealedKey = "ARIS_SEALED_HANDOFF"

    /// The first words of each handed-off call: what changes, sends, deletes or opens something.
    static let forms: [[String]] = [
        ["todo", "add"], ["todo", "edit"], ["todo", "done"], ["todo", "remove"], ["remind"], ["event"], ["note"], ["remember"], ["forget"],
        ["use-calendar"], ["clipboard", "set"], ["link"], ["shortcut"], ["open"], ["maps"], ["keys"], ["trash"], ["move"], ["rename"],
        ["folder"], ["convert"], ["merge"], ["split"], ["compress"], ["schedule", "add"], ["schedule", "remove"], ["undo"], ["weather", "--set-home"],
        // A reply to a mail, opened in Mail as a draft after the user's card (ArisMailReplyCard); never a send.
        ["mail", "reply"],
        // Restart, shut down, log out or sleep (the four System Events scripts, nothing else): the user's card every time.
        ["osascript"],
    ]

    /// The most words and the longest word one call carries (a conversion names up to 50 files; a note may be long).
    static let mostWords = 2 * ArisConvertWords.mostFiles + 12
    static let longestWord = 20_000

    /// Whether the words (after the program) begin as one of the forms: such a call is never run in a Claude's own
    /// process, well formed or not. A maps lookup (`--json`, nothing opens) is a read, not one of these; nor is a clean
    /// call (`folder Downloads`: one of the three known folders shown in Finder), which runs where it was called.
    static func names(_ words: [String]) -> Bool {
        forms.contains { words.starts(with: $0) } && !ArisReadGate.isMapsLookup(words) && !ArisTurnGate.isClean(words)
    }

    /// One well-formed handed-off call: a form, and every word as a shell passes it on (not empty, no control character
    /// or line break), within the limits.
    static func isWrite(_ words: [String]) -> Bool {
        names(words) && words.count <= mostWords && words.allSatisfy { ArisDesktopShell.isPlain($0) && $0.count <= longestWord }
    }

    /// The forms the agent answers in fixed words of its own when they succeed (ArisActionGate.reported), never with
    /// what aris-tools printed: adding a to-do, a reminder, a note or an event, remembering, a link or a file opened,
    /// keys pressed, the clipboard set, the Trash, a schedule made. So a call that worked brings nothing anyone else
    /// wrote into the conversation, and the next small write still goes at once. One that failed comes back with its
    /// error (which may name a calendar or a list), and the agent marks the conversation then.
    private static let fixedAnswers: [[String]] = [
        ["todo", "add"], ["remind"], ["note"], ["remember"], ["clipboard", "set"], ["link"], ["open"], ["keys"], ["trash"], ["schedule", "add"],
    ]

    /// Whether the agent answers this call's success in fixed words: one of `fixedAnswers`, or a new event (not `event
    /// find`, `delete` or `change`, which print calendar titles).
    static func answersInFixedWords(_ words: [String]) -> Bool {
        guard isWrite(words) else { return false }
        if words.first == "event" { return !["find", "delete", "change"].contains(words.dropFirst().first ?? "") }
        return fixedAnswers.contains { words.starts(with: $0) }
    }

    /// Whether a handed-off call that works brings nothing others wrote into the conversation: one the agent answers
    /// in fixed words, or a file tool that prints only the names it was given (ArisTurnGate.bringsNothingIn). Every
    /// other one's answer may (an event's title, the item a `todo done` matched, what an undo put back, a shortcut's
    /// output, the calendar a name matched), so it counts as outside text.
    static func bringsNothingIn(_ words: [String]) -> Bool {
        isWrite(words) && (ArisTurnGate.bringsNothingIn(words) || answersInFixedWords(words))
    }
}
