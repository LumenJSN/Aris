//
//  ArisFleetCommandWords.swift
//  Shared/Core (app, aris-agent, tests)
//
//  What a session asks permission to run, said in a few words to the owner (a spoken notice, the first line of his
//  card), from the hook's structured field (the command). THIS TEXT IS ONLY SPOKEN OR SHOWN TO THE OWNER: no decision
//  is ever taken from it. `fleet.answer` puts the exact command on the owner's card and the app answers only the very
//  request he saw (its fingerprint).
//  It is an allowlist, not a list of tricks: a command gets a friendly label ("running tests", "reading files") only
//  when it is one plain command of an exact known shape (the program, flags from that program's safe set, plain path or
//  pattern arguments; no joiner, no substitution, no redirect, no variable, nothing assigned before it). Everything
//  else is "a command I can't summarise" (the owner can ask to hear it), or, where a dangerous kind is recognised
//  (deleting, sudo, a download run by a shell, pushing, a force flag, a hidden or nested command, a write by redirect,
//  the network, installing), that kind; a line of several commands is "several commands" with its parts by kind, most
//  serious first. The tokenizer reads quotes as a shell does: single quotes inert; double quotes still expand `$(`,
//  backticks and `$`; `<(` and `>(` count outside quotes. (ArisCommandPolicy.segments reads quotes the same way but
//  refuses pipes rather than splitting them, and lives in the helper, out of the app's reach: tests/fleet-tests.swift
//  holds the two together.) Pure.
//

import Foundation

enum ArisFleetCommandWords {
    /// The kinds, most serious first.
    enum Kind: Int, CaseIterable, Comparable {
        case pipeToShell, hidden, sudo, delete, force, push, overwrite, network, install, unknown, commit, build, tests, read

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        func word(korean: Bool) -> String {
            switch self {
            case .pipeToShell: return korean ? "내려받은 걸 셸로 실행" : "running a download in a shell"
            case .hidden: return korean ? "숨은 명령" : "a hidden command"
            case .sudo: return korean ? "관리자 권한(sudo)" : "admin rights (sudo)"
            case .delete: return korean ? "파일 삭제" : "deleting files"
            case .force: return korean ? "강제 옵션" : "a force option"
            case .push: return "git push"
            case .overwrite: return korean ? "파일 덮어쓰기" : "overwriting a file"
            case .network: return korean ? "네트워크 전송" : "a network transfer"
            case .install: return korean ? "설치" : "installing"
            case .unknown: return korean ? "요약할 수 없는 명령" : "a command I can't summarise"
            case .commit: return "git commit"
            case .build: return korean ? "빌드" : "a build"
            case .tests: return korean ? "테스트 실행" : "running tests"
            case .read: return korean ? "파일 보기" : "reading files"
            }
        }
    }

    /// One command of a line, as the tokenizer read it.
    struct Part: Equatable {
        var words: [String] = []
        /// Joined to the one before by a pipe.
        var piped = false
        /// `$(`, a backtick, `<(` or `>(`.
        var substitution = false
        /// `$NAME` or `${…}` outside single quotes.
        var expansion = false
        /// A redirect of any kind, and whether one writes to a file (not `2>&1`, not `/dev/null`).
        var redirect = false
        var writes = false
        /// A word had a quote, an escape or a glob character in it (still a word, but not one of the exact shapes).
        var quoted = false
    }

    /// The line in a few words, serious kinds first. Only for the owner's ears.
    static func summary(_ command: String, korean: Bool) -> String {
        let named = kinds(command).map { $0.word(korean: korean) }.joined(separator: ", ")
        guard tokenize(command).count > 1 else { return named }
        return korean ? "명령 여러 개(\(named))" : "several commands (\(named))"
    }

    /// Every kind in the line, most serious first, each once.
    static func kinds(_ command: String) -> [Kind] {
        let parts = tokenize(command)
        guard !parts.isEmpty else { return [.unknown] }
        var found = Set<Kind>()
        for (index, part) in parts.enumerated() {
            if part.substitution { found.insert(.hidden) }
            if part.writes { found.insert(.overwrite) }
            let danger = dangers(part)
            found.formUnion(danger)
            if part.piped, isInterpreter(program(part.words).first) {
                found.insert(parts[..<index].contains { dangers($0).contains(.network) } ? .pipeToShell : .hidden)
            }
            if let label = friendly(part) {
                found.insert(label)
            } else if danger.isEmpty, !part.substitution, !part.writes {
                found.insert(.unknown)
            }
        }
        return found.sorted()
    }

    // MARK: - Tokenizer

    /// The line's commands: split at ; & && || | and line breaks outside quotes, with what each one holds.
    static func tokenize(_ command: String) -> [Part] {
        let chars = Array(command)
        var parts: [Part] = []
        var part = Part()
        var word = "", inWord = false
        var quote: Character?
        var index = 0
        func endWord() {
            if inWord { part.words.append(word) }
            word = ""
            inWord = false
        }
        func endPart(piped next: Bool) {
            endWord()
            if !part.words.isEmpty || part.substitution || part.redirect { parts.append(part) }
            part = Part()
            part.piped = next
        }
        func at(_ offset: Int) -> Character? { index + offset < chars.count ? chars[index + offset] : nil }
        while index < chars.count {
            let char = chars[index]
            // Single quotes: everything inert until the next one.
            if quote == "'" {
                if char == "'" { quote = nil } else { word.append(char) }
                index += 1
                continue
            }
            if char == "\\" {
                if let next = at(1), !isBreak(next) { word.append(next) }
                inWord = true
                part.quoted = true
                index += 2
                continue
            }
            // Outside single quotes (double quotes included): substitutions and variables still expand.
            if char == "`" { part.substitution = true; index += 1; continue }
            if char == "$" {
                if at(1) == "(" {
                    part.substitution = true
                } else if let next = at(1), next == "{" || next.isLetter || next == "_" || "?!#@*0123456789".contains(next) {
                    part.expansion = true
                }
                word.append(char)
                inWord = true
                index += 1
                continue
            }
            if quote == "\"" {
                if char == "\"" { quote = nil } else { word.append(char) }
                index += 1
                continue
            }
            switch char {
            case "'", "\"":
                quote = char
                inWord = true
                part.quoted = true
            case " ", "\t":
                endWord()
            case "<", ">":
                if at(1) == "(" { part.substitution = true; index += 2; continue }
                endWord()
                part.redirect = true
                var rest = index + 1
                while rest < chars.count, chars[rest] == ">" || chars[rest] == "&" || chars[rest] == " " { rest += 1 }
                var end = rest
                while end < chars.count, chars[end] != " ", !";&|\n".contains(chars[end]) { end += 1 }
                let target = String(chars[rest..<end])
                let toFd = index + 1 < chars.count && chars[index + 1] == "&"
                if char == ">", !toFd, target != "/dev/null" { part.writes = true }
                index = end
                continue
            case ";":
                endPart(piped: false)
            case "&":
                if at(1) == ">" { part.redirect = true; part.writes = true; index += 1; continue }
                if at(1) == "&" { index += 1 }
                endPart(piped: false)
            case "|":
                if at(1) == "|" { index += 1; endPart(piped: false) } else { endPart(piped: true) }
            default:
                if isBreak(char) {
                    endPart(piped: false)
                } else {
                    if "*?[]{}~!#".contains(char) { part.quoted = true }
                    word.append(char)
                    inWord = true
                }
            }
            index += 1
        }
        endPart(piped: false)
        return parts
    }

    private static func isBreak(_ char: Character) -> Bool {
        char.unicodeScalars.contains { "\n\r\u{0B}\u{0C}\u{85}\u{2028}\u{2029}".unicodeScalars.contains($0) }
    }

    // MARK: - Dangerous kinds (named when seen; not seeing one makes nothing friendly)

    /// The words from the program on (assignments and wrappers before it dropped).
    static func program(_ all: [String]) -> [String] {
        var rest = all[...]
        while let first = rest.first, isAssignment(first) || ["env", "command", "time", "nice", "nohup", "exec", "xargs"].contains(first) {
            rest = rest.dropFirst()
        }
        return Array(rest)
    }

    private static func isAssignment(_ word: String) -> Bool {
        word.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) != nil
    }

    private static func isInterpreter(_ word: String?) -> Bool {
        guard let word else { return false }
        return ["sh", "bash", "zsh", "fish", "dash", "ksh", "python", "python3", "node", "ruby", "perl", "osascript", "eval", "source", "."]
            .contains((word as NSString).lastPathComponent)
    }

    static func dangers(_ part: Part) -> Set<Kind> {
        var words = program(part.words)
        var found = Set<Kind>()
        if let first = words.first, first == "sudo" || first == "doas" || first == "su" {
            found.insert(.sudo)
            words = Array(words.dropFirst().drop { $0.hasPrefix("-") })
        }
        if part.words.first.map({ ["xargs", "exec", "eval", "source", "."].contains($0) }) == true { found.insert(.hidden) }
        guard let head = words.first.map({ ($0 as NSString).lastPathComponent.lowercased() }) else { return found }
        let args = words.dropFirst().map { $0.lowercased() }
        if args.contains(where: { $0 == "--force" || $0.hasPrefix("--force-") || $0 == "-f" })
            || (head == "rm" && args.contains { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("f") }) {
            found.insert(.force)
        }
        switch head {
        case "rm", "rmdir", "unlink", "shred", "trash", "srm", "dd", "mkfs", "diskutil": found.insert(.delete)
        case "mv", "cp", "tee", "truncate", "chmod", "chown", "ln": found.insert(.overwrite)
        case "curl", "wget", "scp", "rsync", "ssh", "sftp", "ftp", "nc", "ncat", "telnet", "socat": found.insert(.network)
        case "find":
            if args.contains("-delete") { found.insert(.delete) }
            if args.contains(where: { ["-exec", "-execdir", "-ok", "-okdir"].contains($0) }) { found.insert(.hidden) }
            if args.contains(where: { $0.hasPrefix("-fprint") || $0 == "-fls" }) { found.insert(.overwrite) }
        case "git":
            if args.contains(where: { $0 == "-c" || $0.hasPrefix("--upload-pack") || $0.hasPrefix("--receive-pack") || $0.hasPrefix("--exec") || $0.hasPrefix("--ext-diff") }) {
                found.insert(.hidden)
            }
            if args.contains(where: { $0 == "-o" || $0.hasPrefix("--output") }) { found.insert(.overwrite) }
            switch args.first(where: { !$0.hasPrefix("-") }) ?? "" {
            case "push": found.insert(.push)
            case "clean", "restore", "rm": found.insert(.delete)
            case "reset" where args.contains("--hard"): found.insert(.delete)
            case "checkout" where args.contains("--") || args.contains("."): found.insert(.delete)
            case "commit": found.insert(.commit)
            default: break
            }
        case "rg":
            if args.contains(where: { $0.hasPrefix("--pre") }) { found.insert(.hidden) }
        case "brew", "npm", "pnpm", "yarn", "pip", "pip3", "gem", "cargo", "bun", "npx", "uv":
            let verb = args.first { !$0.hasPrefix("-") } ?? ""
            if ["install", "add", "i", "get", "upgrade", "update"].contains(verb) || head == "npx" { found.insert(.install) }
        default:
            if isInterpreter(head) { found.insert(.hidden) }
        }
        return found
    }

    // MARK: - The allowlist

    /// A plain path or pattern: no option, no glob, no variable.
    private static func plain(_ word: String) -> Bool {
        !word.hasPrefix("-") && word.range(of: #"^[A-Za-z0-9._/+@:,=-]{1,200}$"#, options: .regularExpression) != nil
    }

    /// Whether `args` are only these flags, flags with one plain value, and (when `plainArgs`) plain arguments.
    private static func only(_ args: [String], _ flags: Set<String>, valued: Set<String> = [], plainArgs: Bool = true) -> Bool {
        var index = 0
        while index < args.count {
            let arg = args[index]
            if flags.contains(arg) { index += 1; continue }
            if valued.contains(arg), index + 1 < args.count, plain(args[index + 1]) { index += 2; continue }
            if plainArgs, plain(arg) { index += 1; continue }
            return false
        }
        return true
    }

    /// The friendly label of a command of an exact known shape; nil for any other.
    static func friendly(_ part: Part) -> Kind? {
        let words = part.words
        guard !part.substitution, !part.expansion, !part.redirect, !part.quoted, !part.piped, let head = words.first,
              !isAssignment(head) else { return nil }
        let args = Array(words.dropFirst())
        switch head {
        case "swift":
            let rest = Array(args.dropFirst())
            if args.first == "test", only(rest, ["--parallel", "-v", "--verbose", "--quiet", "-q"], valued: ["--filter", "--skip"], plainArgs: false) { return .tests }
            if args.first == "build", only(rest, ["-v", "--verbose", "--quiet", "-q"], valued: ["-c", "--configuration", "--product", "--target"], plainArgs: false) {
                return .build
            }
            return nil
        case "pytest":
            return only(args, ["-q", "-v", "-vv", "-x", "-s", "--lf", "--ff"]) ? .tests : nil
        case "npm", "pnpm", "yarn", "bun":
            if args == ["test"] || args == ["run", "test"] { return .tests }
            if args == ["run", "build"] || (head != "npm" && args == ["build"]) { return .build }
            return nil
        case "git":
            guard let verb = args.first, ["status", "diff", "log", "show", "branch"].contains(verb) else { return nil }
            let safe: Set<String> = ["--short", "-s", "--stat", "--oneline", "--porcelain", "-b", "--cached", "--staged", "--name-only", "--graph"]
            return args.dropFirst().allSatisfy { safe.contains($0) || plain($0) || $0.range(of: #"^-[0-9]{1,4}$"#, options: .regularExpression) != nil } ? .read : nil
        case "ls":
            return args.allSatisfy { $0.range(of: #"^-[alhRtrS1dF]{1,8}$"#, options: .regularExpression) != nil || plain($0) } ? .read : nil
        case "rg", "grep":
            return !args.isEmpty && only(args, ["-n", "-i", "-l", "-w", "-F", "-c", "-r", "-R", "--hidden", "-S"], valued: ["-g", "-t", "--type"]) ? .read : nil
        case "cat", "head", "tail", "wc":
            return !args.isEmpty && only(args, ["-n", "-l", "-c"], valued: head == "cat" ? [] : ["-n"]) ? .read : nil
        case "pwd":
            return args.isEmpty ? .read : nil
        default:
            return nil
        }
    }
}
