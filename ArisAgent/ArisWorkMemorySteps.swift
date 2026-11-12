//
//  ArisWorkMemorySteps.swift
//  aris-agent, aris-tools
//
//  A command the brain ran, as the work memory keeps it (ArisWorkStep): which tool and subcommand, and only the
//  arguments of a few kinds (a file's path, an app's name, an id, a flag's name, who it was for). Everything else in
//  the command is left out here, before anything is stored: a message's text, a note's body, a to-do's words, what
//  was typed or copied, a search's words, a link's address, a service call's parameters. What a command printed never
//  comes here at all.
//  Also Aris's strict list of calls whose answer carries nothing anyone else wrote: the one every brain's episode is
//  held to (ArisWorkTaintRule), whatever that brain's own gate counts as outside text.
//  Foundation only (tested).
//

import Foundation

/// `aris-tools recall …` as words: what the tool reads and what the gates read, one rule.
///   recall [<words…>] [--limit N]      the lessons and past episodes about those words (the latest when none)
///   recall --id E12                    one episode's steps (or L3: one lesson and what it is based on)
///   recall --stats                     what recall saved, in numbers
///   … --tainted                        also what came from turns that read outside text
/// Without --tainted no tainted episode is printed (a lesson, Aris's own wording of what worked, may rest on one and
/// says so: the owner's ruling), so the plain form counts as bringing nothing in; with it the output is outside text to
/// every gate.
enum ArisWorkRecallWords {
    struct Call: Equatable {
        var query = ""
        var limit = defaultLimit
        var episode: Int?
        var lesson: Int?
        var tainted = false
        var stats = false
    }

    static let defaultLimit = 5
    static let mostLimit = 20
    static let usage = "usage: recall [<words>] [--limit N] [--id E12 | --id L3] [--tainted] | recall --stats"

    static func isRecall(_ rest: [String]) -> Bool { rest.first == "recall" }

    /// The call, or nil when the words aren't one exactly (an unknown flag, a number out of range, a control character).
    static func parse(_ rest: [String]) -> Call? {
        guard isRecall(rest), rest.count <= 40 else { return nil }
        var call = Call(), words: [String] = [], index = 1
        while index < rest.count {
            let word = rest[index]
            guard word.count <= 200, !word.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || ArisCommandPolicy.isLineBreak($0) }) else { return nil }
            switch word {
            case "--tainted": call.tainted = true
            case "--stats": call.stats = true
            case "--limit":
                guard index + 1 < rest.count, let limit = Int(rest[index + 1]), (1...mostLimit).contains(limit) else { return nil }
                call.limit = limit
                index += 1
            case "--id":
                guard index + 1 < rest.count, let found = rest[index + 1].range(of: #"^[EeLl]?[0-9]{1,9}$"#, options: .regularExpression) else { return nil }
                let name = String(rest[index + 1][found])
                let number = Int(name.trimmingCharacters(in: .letters)) ?? 0
                if name.lowercased().hasPrefix("l") { call.lesson = number } else { call.episode = number }
                index += 1
            default:
                guard !word.hasPrefix("-") else { return nil }
                words.append(word)
            }
            index += 1
        }
        call.query = words.joined(separator: " ")
        // Numbers, or one thing by its id, or words: never mixed.
        if call.stats, !words.isEmpty || call.episode != nil || call.lesson != nil { return nil }
        if call.episode != nil || call.lesson != nil, !words.isEmpty { return nil }
        return call
    }

    /// The plain form: clean episodes and Aris's lessons are printed (a lesson in Aris's own wording, marked when a
    /// turn that read outside content taught it), never a tainted episode itself.
    static func isCleanForm(_ rest: [String]) -> Bool { parse(rest).map { !$0.tainted } ?? false }

    /// A recall that may print what a tainted turn left (or one that can't be read: fail closed): outside text.
    static func pullsTainted(_ rest: [String]) -> Bool { isRecall(rest) && !isCleanForm(rest) }
}

enum ArisWorkSteps {
    /// A step and whether its call brings nothing in even when it fails (a failed hand-off's error may name a
    /// calendar or a list: then only a success is clean).
    struct Seen: Equatable {
        var step: ArisWorkStep
        var cleanWhenFailed: Bool
    }

    /// The two-word subcommands, by their first word.
    private static let subverbs: [String: Set<String>] = [
        "music": ["play", "pause", "next", "previous"], "timer": ["stop", "pomodoro"], "schedule": ["add", "list", "remove"],
        "todo": ["add", "done", "edit", "remove"], "folder": ["new"], "event": ["find", "delete", "change"], "mcp": ["list", "call", "wait"],
        "skill": ["list", "read", "run", "wait"], "maps": ["search", "directions"], "web": ["fetch", "search"], "clipboard": ["set"],
        "window": ["left", "right", "full", "center", "maximize"], "mail": ["recent", "search", "read", "thread", "reply"],
        "messages": ["recent"], "notes": ["recent", "search"], "obsidian": ["search"], "files": ["find", "read"], "activity": ["log"],
        "volume": ["up", "down", "mute", "unmute"], "routine": ["list", "show", "run", "add", "remove"],
    ]
    /// Commands whose plain words are files and folders.
    private static let pathVerbs: Set<String> = ["move", "rename", "trash", "open", "folder", "folder new", "convert", "merge", "split", "compress", "files read"]
    /// Commands whose plain words are an app's name.
    private static let appVerbs: Set<String> = ["app", "new", "tile", "windows", "window left", "window right", "window full", "window center", "window maximize",
                                                "music play", "music pause", "music next", "music previous"]
    /// Commands whose plain words are small fixed ones (minutes, a level).
    private static let wordVerbs: Set<String> = ["timer", "volume"]
    /// Flags whose value is kept, and as what.
    private static let valueFlags: [String: ArisWorkArg.Kind] = [
        "--app": .app, "--out": .path, "--to": .path, "--into": .path, "--folder": .path, "--dir": .path, "--id": .id, "--list": .name,
        "--calendar": .name, "--with": .name, "--count": .flag, "--grid": .flag, "--format": .flag, "--quality": .flag, "--limit": .flag,
        "--pages": .flag, "--size": .flag, "--max": .flag, "--percent": .flag,
    ]
    /// Flags that take no value.
    private static let bareFlags: Set<String> = ["--focus", "--json", "--today", "--finder", "--shelf", "--markdown", "--all", "--ko", "--en", "--text",
                                                 "--tainted", "--stats", "--stdin", "--daily", "--weekly"]
    private static let smallWord = #"^[A-Za-z0-9.:%x,+-]{1,16}$"#
    private static let programName = #"^[A-Za-z0-9._+-]{1,32}$"#

    /// The steps one shell command line makes (one per chained piece). `tools`: aris-tools' path; `home`: shown as ~.
    static func seen(command raw: String, tools: String, home: String) -> [Seen] {
        let command = ArisCommandPolicy.unwrap(raw)
        // A desktop call (its text may ride on stdin): the verb and the app only, never the text.
        if let line = ArisDesktopShell.parse(command, tools: tools) {
            return [Seen(step: arisStep(["desktop"] + line.words, home: home, clean: false), cleanWhenFailed: false)]
        }
        guard let pieces = ArisCommandPolicy.segments(command) else { return [unreadable] }
        return pieces.map { piece in
            guard let words = ArisCommandPolicy.words(piece), let first = words.first else { return unreadable }
            guard first == tools, words.count > 1 else { return Seen(step: shellStep(words, home: home), cleanWhenFailed: false) }
            let rest = Array(words.dropFirst())
            let always = bringsNothingIn(rest)
            return Seen(step: arisStep(rest, home: home, clean: always || bringsNothingInWhenItWorks(rest)), cleanWhenFailed: always)
        }
    }

    private static let unreadable = Seen(step: ArisWorkStep(tool: "shell", verb: "(unreadable)", args: []), cleanWhenFailed: false)

    /// The brain's own tool (a web search, a file read): its name only, and never clean.
    static func brainTool(_ name: String) -> Seen {
        let fits = name.range(of: programName, options: .regularExpression) != nil
        return Seen(step: ArisWorkStep(tool: "brain", verb: fits ? name : "(tool)", args: []), cleanWhenFailed: false)
    }

    /// Aris's strict list: an aris-tools call (its words after the program) whose answer carries nothing anyone else
    /// wrote, whether it works or not. The turn gate's own list (a timer, the volume, music, a window, an app, a known
    /// folder, the calendar app, a file moved, renamed or converted: they print only what the brain passed) and the
    /// plain `recall`. Every read, every list and every service is off it, on every brain.
    static func bringsNothingIn(_ rest: [String]) -> Bool {
        ArisTurnGate.bringsNothingIn(rest) || ArisWorkRecallWords.isCleanForm(rest)
    }

    /// Calls that bring nothing in only when they work: a write the agent answers in fixed words (a to-do, a reminder,
    /// a note, an event added, a link or a file opened: ArisHandOff), and a message. Their errors may name a calendar,
    /// a list or a contact, so a failed one counts as outside text, as it does for the gate.
    static func bringsNothingInWhenItWorks(_ rest: [String]) -> Bool {
        ArisHandOff.bringsNothingIn(rest) || ArisTurnGate.isAgentMessage(rest)
    }

    /// The step's `clean` once it is known how it went.
    static func settled(_ seen: Seen) -> ArisWorkStep {
        var step = seen.step
        if !step.worked, !seen.cleanWhenFailed { step.clean = false }
        return step
    }

    // MARK: - What is kept of a call

    static func arisStep(_ rest: [String], home: String, clean: Bool) -> ArisWorkStep {
        var verb = rest[0].range(of: programName, options: .regularExpression) != nil ? rest[0] : "(command)"
        var words = Array(rest.dropFirst())
        if let second = words.first, subverbs[verb]?.contains(second) == true {
            verb += " " + second
            words.removeFirst()
        } else if verb == "desktop", let second = words.first, second.range(of: #"^[a-z][a-z-]{1,24}$"#, options: .regularExpression) != nil {
            verb += " " + second
            words.removeFirst()
        }
        return ArisWorkStep(tool: "aris-tools", verb: verb, args: arguments(words, verb: verb, home: home), clean: clean)
    }

    /// Another program: its name, an app it opens (`open -a`) and the paths it names. Never clean.
    private static func shellStep(_ words: [String], home: String) -> ArisWorkStep {
        let name = (words[0] as NSString).lastPathComponent
        let verb = name.range(of: programName, options: .regularExpression) != nil ? name : "(command)"
        var args: [ArisWorkArg] = []
        var index = 1
        while index < words.count {
            let word = words[index]
            if verb == "open", word == "-a", index + 1 < words.count {
                if let app = ArisWorkSafe.arg(.app, words[index + 1]) { args.append(app) }
                index += 1
            } else if word.hasPrefix("/") || word.hasPrefix("~/"), let path = ArisWorkSafe.arg(.path, short(word, home: home)) {
                args.append(path)
            }
            index += 1
        }
        return ArisWorkStep(tool: "shell", verb: verb, args: Array(args.prefix(mostArgs)), clean: false)
    }

    static let mostArgs = 12

    /// The kept arguments of an aris-tools call: flags by name, a kept flag's value, and the plain words only for the
    /// commands whose plain words are paths, apps or small fixed words. A message keeps who it was for, never its text.
    private static func arguments(_ words: [String], verb: String, home: String) -> [ArisWorkArg] {
        var args: [ArisWorkArg] = []
        var index = 0, plain = 0
        while index < words.count {
            let word = words[index]
            if word.hasPrefix("-"), word.count > 1, Double(word) == nil {
                if let flag = ArisWorkSafe.arg(.flag, word), word.range(of: #"^--?[A-Za-z][A-Za-z0-9-]{0,30}$"#, options: .regularExpression) != nil { args.append(flag) }
                if !bareFlags.contains(word), index + 1 < words.count, !words[index + 1].hasPrefix("--") {
                    // The flag's value: kept only for the flags named above, as that kind; any other flag's value is dropped.
                    if let kind = valueFlags[word], let value = kept(words[index + 1], as: kind, home: home) { args.append(value) }
                    index += 1
                }
            } else {
                if pathVerbs.contains(verb) {
                    if let path = ArisWorkSafe.arg(.path, short(word, home: home)) { args.append(path) }
                } else if appVerbs.contains(verb) {
                    if let app = ArisWorkSafe.arg(.app, word), word.count <= 80 { args.append(app) }
                } else if wordVerbs.contains(verb) {
                    if word.range(of: smallWord, options: .regularExpression) != nil, let small = ArisWorkSafe.arg(.flag, word) { args.append(small) }
                } else if verb == "message", plain == 0 {
                    if word.count <= 60, let name = ArisWorkSafe.arg(.name, word) { args.append(name) }
                } else if verb == "mcp call", plain < 2 {
                    if word.range(of: #"^[A-Za-z0-9_.\-/]{1,128}$"#, options: .regularExpression) != nil, let id = ArisWorkSafe.arg(.id, word) { args.append(id) }
                }
                plain += 1
            }
            index += 1
        }
        return Array(args.prefix(mostArgs))
    }

    private static func kept(_ value: String, as kind: ArisWorkArg.Kind, home: String) -> ArisWorkArg? {
        switch kind {
        case .path:
            // `--to png` is a format, `--to ~/Desktop` a place.
            if !value.contains("/"), !value.hasPrefix("~"), value.range(of: smallWord, options: .regularExpression) != nil { return ArisWorkSafe.arg(.flag, value) }
            return ArisWorkSafe.arg(.path, short(value, home: home))
        case .flag:
            return value.range(of: smallWord, options: .regularExpression) != nil ? ArisWorkSafe.arg(.flag, value) : nil
        case .id:
            return ArisWorkSafe.id(value)
        case .app, .name:
            return value.count <= 80 ? ArisWorkSafe.arg(kind, value) : nil
        }
    }

    /// A path with the home folder as ~ (shorter, and it doesn't carry the account's name).
    static func short(_ path: String, home: String) -> String {
        guard home.count > 1 else { return path }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
