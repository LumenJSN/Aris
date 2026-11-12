//
//  ArisRiskPolicy+ReadCommands.swift
//  aris-agent
//
//  Shell commands that only read (audit gate-22, gate-18). The owner's rule is that reading never asks, yet "배터리 몇
//  퍼센트야?" (pmset -g batt), "내 IP 뭐야" (ipconfig getifaddr en0) and "디스크 목록 보여줘" (diskutil list) showed a card
//  or were refused, because the gate knew a program only by its name. Here each program has the exact shapes of its
//  arguments that read and nothing else; any other shape keeps what it had (a card, or never for the never-list). A
//  never-list program (diskutil, launchctl, dscl) is let through only when the whole line is that one plain command:
//  chained, piped, quoted oddly or with any shell syntax it is never, as before. Programs are matched by their bare
//  name, like the other reading commands. Pure, so the tests run it with tables.
//

import Foundation

/// What a read-only shape does: runs at once (`outsideText`: its output carries names other people chose, like a
/// volume's or a nearby device's; `files`: the files it reads, still checked for keys and tokens), or asks on the user's
/// card (a read that could show something private: a login-item's environment, a whole user record with its hint).
enum ArisReadOnlyForm: Equatable {
    case runs(outsideText: Bool, files: [String] = [])
    case asks
}

extension ArisRiskPolicy {
    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: "^(?:" + pattern + ")$", options: .regularExpression) != nil
    }

    /// The read-only shape of `words` (one command, already read word by word); nil when it isn't one.
    static func readOnlyForm(_ words: [String]) -> ArisReadOnlyForm? {
        guard let program = words.first else { return nil }
        let arguments = Array(words.dropFirst())
        switch program {
        case "uptime": return arguments.isEmpty ? .runs(outsideText: false) : nil
        case "pmset": return pmset(arguments)
        case "ipconfig": return ipconfig(arguments)
        case "sysctl": return sysctl(arguments)
        case "ps": return ps(arguments)
        case "top": return top(arguments)
        case "sips": return sips(arguments)
        case "defaults": return defaults(arguments)
        case "system_profiler": return systemProfiler(arguments)
        case "networksetup": return networksetup(arguments)
        case "diskutil": return diskutil(arguments)
        case "launchctl": return launchctl(arguments)
        case "dscl": return dscl(arguments)
        default: return nil
        }
    }

    /// `pmset -g [batt|ps|…]`: the power settings and the battery, shown.
    private static func pmset(_ arguments: [String]) -> ArisReadOnlyForm? {
        guard arguments.first == "-g", arguments.count <= 2 else { return nil }
        let shown: Set<String> = ["batt", "ps", "cap", "sched", "custom", "live", "therm", "assertions"]
        return arguments.count == 1 || shown.contains(arguments[1]) ? .runs(outsideText: false) : nil
    }

    /// `ipconfig getifaddr en0`, `getiflist`, `ifcount`.
    private static func ipconfig(_ arguments: [String]) -> ArisReadOnlyForm? {
        if arguments == ["getiflist"] || arguments == ["ifcount"] { return .runs(outsideText: false) }
        return arguments.count == 2 && arguments[0] == "getifaddr" && matches(arguments[1], "[a-z]+[0-9]+") ? .runs(outsideText: false) : nil
    }

    /// `sysctl [-n] <name>…`: values read by name, never set (no -w, no name=value).
    private static func sysctl(_ arguments: [String]) -> ArisReadOnlyForm? {
        let names = arguments.first == "-n" ? Array(arguments.dropFirst()) : arguments
        return !names.isEmpty && names.allSatisfy { matches($0, "[a-z0-9_.]+") } ? .runs(outsideText: false) : nil
    }

    /// `ps aux`, `ps -ax -o pid,comm`, `ps -p 123`: never with the environment (e, -E), which can hold keys.
    private static func ps(_ arguments: [String]) -> ArisReadOnlyForm? {
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            if ["-o", "-O", "-p", "-u", "-U", "-g", "-G", "-t"].contains(word) {
                guard index + 1 < arguments.count, matches(arguments[index + 1], "[A-Za-z0-9%,=_.:/-]+"), !arguments[index + 1].hasPrefix("-") else { return nil }
                index += 2
            } else if matches(word, "-?[AaxuwrmcMjlvfhSdX]+") {
                index += 1
            } else {
                return nil
            }
        }
        return .runs(outsideText: true)
    }

    /// `top -l 1 [-n 5] [-o cpu] …`: a few samples and done (never the endless screen).
    private static func top(_ arguments: [String]) -> ArisReadOnlyForm? {
        var samples: Int?
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            if ["-u", "-S", "-R", "-F"].contains(word) { index += 1; continue }
            guard ["-l", "-n", "-o", "-O", "-s", "-stats", "-pid", "-ncols"].contains(word), index + 1 < arguments.count,
                  matches(arguments[index + 1], "[A-Za-z0-9,_+]+") else { return nil }
            if word == "-l" { samples = Int(arguments[index + 1]) }
            index += 2
        }
        guard let samples, (1...5).contains(samples) else { return nil }
        return .runs(outsideText: true)
    }

    /// `sips -g <property>… <image>…`: an image's size and properties (its file is still checked like any file read).
    private static func sips(_ arguments: [String]) -> ArisReadOnlyForm? {
        var index = 0, asked = 0
        while index + 1 < arguments.count, arguments[index] == "-g" || arguments[index] == "--getProperty" {
            guard matches(arguments[index + 1], "[A-Za-z]+") else { return nil }
            asked += 1
            index += 2
        }
        let files = Array(arguments[index...])
        guard asked > 0, !files.isEmpty, files.allSatisfy({ !$0.hasPrefix("-") }) else { return nil }
        return .runs(outsideText: true, files: files)
    }

    /// Key names that could hold a credential: such a default is asked about, never read at once.
    private static let secretKeyWords = ["token", "password", "passwd", "secret", "credential", "apikey", "api_key", "api-key", "license", "auth", "session", "cookie"]

    /// `defaults read <domain> <key>`, `defaults read-type <domain> <key>`, and a whole domain only for the Mac's own
    /// (com.apple.…, the global domain). The domain is a name, never a file's path; no -app, no -currentHost.
    private static func defaults(_ arguments: [String]) -> ArisReadOnlyForm? {
        guard arguments.count >= 2, arguments.count <= 3, ["read", "read-type"].contains(arguments[0]) else { return nil }
        let domain = arguments[1]
        let global = ["-g", "-globalDomain", "NSGlobalDomain"].contains(domain)
        guard global || (matches(domain, "[A-Za-z0-9._-]+") && !domain.hasPrefix("-") && !domain.hasPrefix(".")) else { return nil }
        guard arguments.count == 3 else {
            return arguments[0] == "read" && (global || domain.lowercased().hasPrefix("com.apple.")) ? .runs(outsideText: true) : nil
        }
        let key = arguments[2]
        guard matches(key, "[A-Za-z0-9._ -]+"), !key.hasPrefix("-"), !secretKeyWords.contains(where: key.lowercased().contains) else { return nil }
        return .runs(outsideText: true)
    }

    /// `system_profiler [-json|-xml] [-detailLevel mini|basic|full] [SP…DataType]…`.
    private static func systemProfiler(_ arguments: [String]) -> ArisReadOnlyForm? {
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            if word == "-detailLevel" {
                guard index + 1 < arguments.count, ["mini", "basic", "full"].contains(arguments[index + 1]) else { return nil }
                index += 2
            } else if ["-json", "-xml", "-listDataTypes", "-nospawn"].contains(word) || matches(word, "SP[A-Za-z0-9]+DataType") {
                index += 1
            } else {
                return nil
            }
        }
        return .runs(outsideText: true)
    }

    /// `networksetup -get…|-list… [<service or port>]`: one flag that only shows.
    private static func networksetup(_ arguments: [String]) -> ArisReadOnlyForm? {
        guard let flag = arguments.first, matches(flag, "-(get|list)[a-z]+"), arguments.count <= 3,
              arguments.dropFirst().allSatisfy({ matches($0, "[A-Za-z0-9 ._-]+") && !$0.hasPrefix("-") }) else { return nil }
        return .runs(outsideText: true)
    }

    private static let diskName = "(/dev/)?disk[0-9]+(s[0-9]+)*"

    /// `diskutil list [disk]`, `diskutil info <disk | / | /Volumes/…>`, `diskutil apfs list`.
    private static func diskutil(_ arguments: [String]) -> ArisReadOnlyForm? {
        switch arguments.first {
        case "list" where arguments.count == 1 || (arguments.count == 2 && matches(arguments[1], diskName)):
            return .runs(outsideText: true)
        case "info" where arguments.count == 2:
            let target = arguments[1]
            let volume = matches(target, "/Volumes/[^/]+") && !target.contains("..")
            return target == "/" || target == "-all" || matches(target, diskName) || volume ? .runs(outsideText: true) : nil
        case "apfs" where arguments == ["apfs", "list"]:
            return .runs(outsideText: true)
        default:
            return nil
        }
    }

    /// `launchctl list` shows what is loaded. One job's own record, and `print`, can show its environment: the user's card.
    private static func launchctl(_ arguments: [String]) -> ArisReadOnlyForm? {
        if arguments == ["list"] { return .runs(outsideText: true) }
        guard arguments.count == 2 else { return nil }
        switch arguments[0] {
        case "list": return matches(arguments[1], "[A-Za-z0-9._-]+") && !arguments[1].hasPrefix("-") ? .asks : nil
        case "print", "print-disabled": return matches(arguments[1], "(system|gui/[0-9]+|user/[0-9]+)(/[A-Za-z0-9._-]+)?") ? .asks : nil
        default: return nil
        }
    }

    /// What of a user's record is shown at once: nothing about how they sign in.
    private static let shownUserKeys: Set<String> = ["UserShell", "NFSHomeDirectory", "RealName", "UniqueID", "PrimaryGroupID", "RecordName", "GeneratedUID"]

    /// `dscl . -list /Users|/Groups`, `dscl . -read /Users/<name> <key>…` for the keys above. A whole record (it holds
    /// the password hint) or any other key asks on the user's card. Only the local directory, only -read and -list.
    private static func dscl(_ arguments: [String]) -> ArisReadOnlyForm? {
        guard arguments.count >= 3, arguments[0] == ".", ["-read", "-list"].contains(arguments[1]),
              matches(arguments[2], "/[A-Za-z0-9._/-]+"), !arguments[2].contains("..") else { return nil }
        let keys = Array(arguments.dropFirst(3))
        guard keys.allSatisfy({ matches($0, "[A-Za-z0-9_]+") }) else { return nil }
        if arguments[1] == "-list" {
            return ["/Users", "/Groups"].contains(arguments[2]) && keys.count <= 1 && keys.allSatisfy(shownUserKeys.contains) ? .runs(outsideText: true) : .asks
        }
        return matches(arguments[2], "/Users/[A-Za-z0-9._-]+") && !keys.isEmpty && keys.allSatisfy(shownUserKeys.contains) ? .runs(outsideText: true) : .asks
    }

    // MARK: - Restart, shut down, log out, sleep

    /// `osascript -e 'tell application "System Events" to restart'` (or shut down, log out, sleep), exactly: what the user's
    /// card names in plain words (audit gate-18). It always asks (never remembered: ArisRiskPolicy.isRepeatable);
    /// shutdown, reboot and halt themselves need root and stay on the never-list.
    /// The same through aris-tools (`<tools> osascript -e '…'`), which is how a brain with no shell of its own sends
    /// it (VM run 2: an API brain's restart showed the raw script). Anything else in the script is no power command.
    static func powerCommand(_ command: String, tools: String = "") -> String? {
        guard var words = ArisCommandPolicy.words(command) else { return nil }
        if !tools.isEmpty, words.first == tools { words.removeFirst() }
        return ArisCommandPolicy.powerScript(words).flatMap { ArisCommandPolicy.powerVerb(script: $0) }
    }
}

// MARK: - A file's name that says it holds a secret

extension ArisRiskPolicy {
    private static let secretWords = ["credential", "secret", "token", "password", "passwd", "passphrase"]
    /// Source files: about tokens and passwords far more often than holding one.
    private static let codeTypes: Set<String> = ["swift", "py", "js", "mjs", "cjs", "ts", "tsx", "jsx", "go", "rs", "java", "kt", "c", "h", "cc", "cpp",
                                                 "hpp", "m", "mm", "rb", "php", "cs", "css", "scss", "html", "vue", "svelte"]
    /// Writing and documents: "password-policy.md" is about passwords, "passwords.md" may hold them.
    private static let documentTypes: Set<String> = ["md", "mdx", "rst", "adoc", "pdf", "doc", "docx", "pages", "ppt", "pptx"]
    /// What comes before "tokens" in a design system's file (design-tokens.json): not credentials.
    private static let designWords: Set<String> = ["design", "color", "colour", "theme", "style", "spacing", "typography", "font", "ui", "css",
                                                   "brand", "semantic", "layout", "motion"]
    /// An example of a .env file, kept in a repository for its names only.
    private static let envExamples: Set<String> = [".env.example", ".env.sample", ".env.template", ".env.dist"]

    /// What a document's name may end in without saying anything about what it holds ("passwords old", "password list").
    private static let nameFillers: Set<String> = ["list", "lists", "backup", "backups", "old", "new", "copy", "final", "bak"]

    /// A lowercased name's words, split at anything that isn't a letter or a digit.
    private static func nameWords(_ name: String) -> [String] {
        name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func isSecretWord(_ word: String) -> Bool { secretWords.contains { word == $0 || word == $0 + "s" } }

    /// Whether a file's name (lowercased) says it holds keys, tokens or passwords (audit gate-22: a name that merely
    /// contains "token" or "password" asked for a card; design-tokens.json, tokenizer.py and password-policy.md are not
    /// secrets). Still secrets: SSH keys, shell histories, .env files (not the .example kind), and by kind of file:
    /// - source code, only when the whole name is the word (secrets.py, credentials.swift);
    /// - a document, when the name ends in the word (passwords.md, "AppleId password.pdf"), a number or a word such as
    ///   list, backup, old or copy after it aside ("passwords-2026.md", "password list.md": security review 2 L2);
    /// - anything else (json, txt, yaml, csv, no extension…), when the word is anywhere in the name, as before, except
    ///   a tokenizer's files and a design system's tokens.
    static func namesSecret(_ file: String) -> Bool {
        if file.hasPrefix("id_rsa") || file.hasPrefix("id_ed25519") || file.hasPrefix("id_ecdsa") || file.hasPrefix("id_dsa") || file.hasSuffix("_history") { return true }
        if file == ".env" || file.hasPrefix(".env.") { return !envExamples.contains(file) }
        let type = (file as NSString).pathExtension
        let stem = type.isEmpty ? file : (file as NSString).deletingPathExtension
        let words = nameWords(stem)
        if codeTypes.contains(type) { return words.count == 1 && isSecretWord(words[0]) }
        if documentTypes.contains(type) {
            return words.reversed().first { !$0.allSatisfy(\.isNumber) && !nameFillers.contains($0) }.map(isSecretWord) ?? false
        }
        // Words that only begin like "token" (tokenizer, tokenization) and a design system's tokens aren't credentials.
        let plain = words.enumerated().filter { index, word in
            if word.hasPrefix("tokeniz") || word.hasPrefix("tokenis") { return false }
            if word == "tokens" || word == "token", index > 0, designWords.contains(words[index - 1]) { return false }
            return true
        }.map(\.element).joined(separator: " ")
        return secretWords.contains(where: plain.contains)
    }
}
