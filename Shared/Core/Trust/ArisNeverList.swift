//
//  ArisNeverList.swift
//  Shared/Core (aris-agent, tests)
//
//  The short never-list: refused whoever asks, at every level, grant or no grant. Fixed (Settings can't change it).
//  Only what is catastrophic or self-defeating:
//    · Aris disabling its own safeguards: its folder (keys, token, journals, the record, the trust settings), its app,
//      its LaunchAgent, its preference domains, killing or unloading its helper, answering its own cards or the
//      system's password and permission prompts, the System Settings panes that grant permissions or hold accounts,
//      and the trust settings and record changed by any capability (only the owner's own words or Settings do that).
//    · Credential stores: ~/.ssh, ~/.gnupg, the keychains, the AI tools' token folders, cloud credentials.
//    · Destroying the system or the home folder: erasing or repartitioning disks, formatting, SIP and firmware
//      controls, rm -r of /, home, /Users, /System, /Library, /Applications, /usr, /bin, /sbin, /etc; deleting those
//      folders for good, or home's own everyday folders whole.
//    · Paying without the owner naming both the amount and the payee, except a payment the capability registry
//      marks (decision 1): that asks on its own card instead (ArisTrustPolicy.payment).
//  Read conservatively on purpose (a token that looks like a protected path counts). Pure.
//

import Foundation

enum ArisNeverRule: String, CaseIterable, Codable, Sendable {
    case ownSafeguards, credentials, destroysSystem, unnamedPayment, neverEffect

    var korean: String {
        switch self {
        case .ownSafeguards: "Aris 자신의 안전장치(키, 기록, 설정, 권한 창)는 건드리지 않아요."
        case .credentials: "비밀번호·키 보관소는 건드리지 않아요."
        case .destroysSystem: "시스템이나 홈 폴더를 지우는 일은 하지 않아요."
        case .unnamedPayment: "금액과 받는 곳을 직접 말해 주셔야 결제할 수 있어요."
        case .neverEffect: "이건 Aris가 하지 않는 일이에요."
        }
    }

    var english: String {
        switch self {
        case .ownSafeguards: "Aris never touches its own safeguards (its keys, record, settings, permission prompts)."
        case .credentials: "Aris never touches password or key stores."
        case .destroysSystem: "Aris never erases the system or the home folder."
        case .unnamedPayment: "A payment needs you to name both the amount and who is paid."
        case .neverEffect: "That is something Aris never does."
        }
    }
}

enum ArisNeverList {
    // MARK: - The data

    /// Aris's own places, relative to home (its work folder inside is the exception).
    static let ownPlaces = [".config/aris", ".config/boring-notch", "Library/Application Support/Aris", ".peekaboo"]
    static let ownWorkFolder = ".config/aris/aris/work"
    static let ownAbsolute = ["/Applications/Aris.app"]
    static let ownLaunchAgentPrefix = "Library/LaunchAgents/com.lumenjsn.aris"
    static let ownDomains = ["aris-agent", "com.lumenjsn.aris"]
    static let ownProcesses = ["aris-agent", "aris", "com.lumenjsn.aris", "com.lumenjsn.aris.agent"]
    static let credentialPlaces = [".ssh", ".gnupg", "Library/Keychains", ".aws", ".codex", ".claude", ".gemini", ".netrc", ".git-credentials",
                                   ".docker/config.json", ".kube/config", ".config/gh/hosts.yml", ".npmrc", ".pypirc"]
    static let credentialAbsolute = ["/Library/Keychains"]
    /// Folders no change removes whole, or recursively deletes.
    static let systemRoots = ["/", "/Users", "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/etc", "/private", "/var", "/opt"]
    /// Home's own folders, never deleted for good whole (moving them to the Trash is a change that can be taken back).
    static let everydayFolders = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Library", "Applications", "Public"]
    /// Programs that are never run, whatever their arguments.
    static let neverPrograms: Set<String> = ["csrutil", "nvram", "fdesetup", "bless", "tccutil", "kextload", "kmutil", "systemsetup"]
    static let formatPrefixes = ["mkfs", "newfs"]
    static let diskutilVerbs = ["erase", "partition", "zero", "secureerase", "reformat", "deletecontainer", "deletevolume", "erasevolume", "randomdisk"]
    static let securityVerbs = ["dump-keychain", "find-generic-password", "find-internet-password", "export", "delete-keychain",
                                "unlock-keychain", "set-key-partition-list", "authorizationdb"]
    /// Apps Aris never acts in: itself, the system's password and permission prompts, computer use's own runtime.
    static let neverApps: Set<String> = ["aris", "아리스", "com.lumenjsn.aris", "securityagent", "com.apple.securityagent", "coreautha",
                                         "com.apple.coreautha", "localauthenticationremoteservice", "com.apple.localauthentication.uiagent",
                                         "universalaccessauthwarn", "com.apple.accessibility.universalaccessauthwarn", "peekaboo",
                                         "boo.peekaboo.mac", "authenticationservicesagent"]
    /// System Settings panes that grant permissions or hold accounts (names and settings links, lowercased).
    static let protectedPanes = ["privacy & security", "privacy and security", "개인정보 보호 및 보안", "users & groups", "users and groups",
                                 "사용자 및 그룹", "passwords", "암호", "profiles", "프로파일", "device management", "기기 관리",
                                 "com.apple.preference.security", "com.apple.settings.privacysecurity", "com.apple.preferences.users",
                                 "com.apple.passwords", "com.apple.preferences.configurationprofiles", "privacy_"]
    /// Capabilities no model call may use: the trust settings and the record change only by the owner.
    static let neverCapabilityPrefixes = ["trust.", "record.erase", "record.edit"]

    // MARK: - The check

    /// Why the call is on the never-list; nil when it isn't. `ownerNamed`: the key-argument kinds the owner's own words
    /// gave (ArisProvenanceTracker), for the payment rule.
    static func rule(for call: ArisCallFacts, effect: ArisEffectClass, home: String, ownerNamed: Set<ArisKeyArgument.Kind> = []) -> ArisNeverRule? {
        if effect == .never { return .neverEffect }
        if neverCapabilityPrefixes.contains(where: call.capability.hasPrefix) { return .ownSafeguards }
        if call.payment, !(ownerNamed.contains(.amount) && ownerNamed.contains(.payee)) { return .unnamedPayment }
        for path in call.values(.path) {
            if let rule = pathRule(path, effect: effect, home: home) { return rule }
        }
        for command in call.values(.command) {
            if let rule = commandRule(command, home: home) { return rule }
        }
        for app in call.values(.app) + call.values(.url) {
            if let rule = appRule(app) { return rule }
        }
        return nil
    }

    /// A path's rule: Aris's own places and credential stores for any effect (reading included); the system's and
    /// home's roots for a change.
    static func pathRule(_ raw: String, effect: ArisEffectClass, home: String) -> ArisNeverRule? {
        let path = normalized(raw, home: home)
        let home = normalized(home, home: home)
        let inside = { (folder: String) in path == folder || path.hasPrefix(folder == "/" ? "/" : folder + "/") }
        let work = home + "/" + ownWorkFolder.lowercased()
        if !inside(work) {
            if ownPlaces.contains(where: { inside(home + "/" + $0.lowercased()) }) || ownAbsolute.contains(where: { inside($0.lowercased()) })
                || path.hasPrefix(home + "/" + ownLaunchAgentPrefix.lowercased()) { return .ownSafeguards }
        }
        if credentialPlaces.contains(where: { inside(home + "/" + $0.lowercased()) }) || credentialAbsolute.contains(where: { inside($0.lowercased()) }) {
            return .credentials
        }
        guard effect == .changeReversible || effect == .changePermanent else { return nil }
        // The roots themselves (and anything holding home) are never changed whole: neither moved nor removed.
        let roots = systemRoots.map { $0.lowercased() } + [home]
        if roots.contains(path) || home.hasPrefix(path + "/") { return .destroysSystem }
        if effect == .changePermanent, everydayFolders.contains(where: { path == home + "/" + $0.lowercased() }) { return .destroysSystem }
        return nil
    }

    /// A command line's rule, by each of its commands (after ; && || | and inside $( ) or backticks).
    static func commandRule(_ line: String, home: String) -> ArisNeverRule? {
        for words in commands(in: line) {
            var words = words.drop { $0.contains("=") && !$0.hasPrefix("-") }
            while let first = words.first, ["sudo", "doas", "env", "nohup", "time", "exec", "command", "nice"].contains(first) || first.hasPrefix("-") {
                words = words.dropFirst()
            }
            guard let first = words.first else { continue }
            let program = (first as NSString).lastPathComponent
            let rest = Array(words.dropFirst()).map { $0.lowercased() }
            if neverPrograms.contains(program) || formatPrefixes.contains(where: program.hasPrefix) { return .destroysSystem }
            if program == "diskutil", rest.contains(where: { verb in diskutilVerbs.contains(where: verb.hasPrefix) }) { return .destroysSystem }
            if program == "dd", rest.contains(where: { $0.hasPrefix("of=/dev/") }) { return .destroysSystem }
            if program == "security", rest.contains(where: securityVerbs.contains) { return .credentials }
            if program == "rm", rest.contains(where: isRecursiveFlag),
               words.dropFirst().filter({ !$0.hasPrefix("-") }).contains(where: { isRoot($0, home: home) }) { return .destroysSystem }
            if ["launchctl", "killall", "pkill"].contains(program), rest.contains(where: { word in ownProcesses.contains(word) || word.contains("lumenjsn.aris") || word.hasSuffix("/aris-agent") }) {
                return .ownSafeguards
            }
            if program == "defaults", let verb = rest.first, ["write", "delete", "import", "rename"].contains(verb),
               rest.dropFirst().first.map({ domain in ownDomains.contains { domain.hasSuffix($0) } }) == true { return .ownSafeguards }
            if program == "open", rest.contains(where: { appRule($0) != nil }) { return .ownSafeguards }
            // A word that names a protected place, wherever it stands (a redirection's target, a script's argument).
            for word in words.dropFirst() + [first] {
                for token in pathTokens(word) {
                    if let rule = pathRule(token, effect: .observe, home: home) { return rule }
                }
            }
        }
        // A redirection into a protected place.
        for token in line.split(whereSeparator: { " \t\n<>|;&".contains($0) }).map(String.init) where token.hasPrefix("/") || token.hasPrefix("~") || token.hasPrefix("$HOME") {
            if let rule = pathRule(token, effect: .observe, home: home) { return rule }
        }
        return nil
    }

    static func appRule(_ value: String) -> ArisNeverRule? {
        let lowered = value.lowercased().trimmingCharacters(in: .whitespaces)
        if neverApps.contains(lowered) { return .ownSafeguards }
        let settings = lowered.contains("system settings") || lowered.contains("시스템 설정") || lowered.contains("x-apple.systempreferences")
            || lowered.contains("system preferences") || lowered.contains("com.apple.systempreferences")
        if settings, protectedPanes.contains(where: lowered.contains) { return .ownSafeguards }
        if lowered.hasPrefix("x-apple.systempreferences:"), protectedPanes.contains(where: lowered.contains) { return .ownSafeguards }
        return nil
    }

    // MARK: - Reading

    /// `~`, `$HOME` and `${HOME}` expanded, `.` and `..` resolved, lowercased (APFS ignores case), `/private` kept apart.
    static func normalized(_ raw: String, home: String) -> String {
        var path = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t'\""))
        for prefix in ["${HOME}", "$HOME", "~"] where path == prefix || path.hasPrefix(prefix + "/") {
            path = home + path.dropFirst(prefix.count)
            break
        }
        if !path.hasPrefix("/") { path = home + "/" + path }
        let standardized = (path as NSString).standardizingPath
        let trimmed = standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
        return trimmed.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func isRecursiveFlag(_ word: String) -> Bool {
        word == "--recursive" || (word.hasPrefix("-") && !word.hasPrefix("--") && (word.contains("r") || word.contains("R")))
    }

    private static func isRoot(_ word: String, home: String) -> Bool {
        let cleaned = word.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        if cleaned == "*" || cleaned == "/*" || cleaned == "~/*" || cleaned == "$HOME/*" { return true }
        let path = normalized(cleaned.hasSuffix("/*") ? String(cleaned.dropLast(2)) : cleaned, home: home)
        let home = normalized(home, home: home)
        guard cleaned.hasPrefix("/") || cleaned.hasPrefix("~") || cleaned.hasPrefix("$HOME") || cleaned.hasPrefix("${HOME}") else { return false }
        if systemRoots.map({ $0.lowercased() }).contains(path) || path == home || home.hasPrefix(path + "/") { return true }
        return everydayFolders.contains { path == home + "/" + $0.lowercased() }
    }

    /// The path-looking parts of a word (`of=/x`, `--file=~/y`, a plain path).
    private static func pathTokens(_ word: String) -> [String] {
        word.split(whereSeparator: { "=:,".contains($0) }).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'\"()")) }
            .filter { $0.hasPrefix("/") || $0.hasPrefix("~") || $0.hasPrefix("$HOME") || $0.hasPrefix("${HOME}") }
    }

    /// Each command of a line as its words (quotes taken off): split at ; & | newlines, `$(`, `(` and backticks.
    static func commands(in line: String) -> [[String]] {
        var pieces: [String] = []
        var current = ""
        var quote: Character?
        for character in line {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
                continue
            }
            switch character {
            case "'", "\"": quote = character
            case ";", "&", "|", "\n", "`", "(", ")": pieces.append(current); current = ""
            default: current.append(character)
            }
        }
        pieces.append(current)
        return pieces.map { piece in
            piece.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init).filter { $0 != "$" }
        }.filter { !$0.isEmpty }
    }
}

// MARK: - What a shell line may reach

/// A shell line read as far as words can be read: clear, on the never-list, or uncertain (it may reach a protected
/// place in a way words can't settle: a `cd`, a glob or `..`, a variable, a command substitution, a recursive read of
/// a folder that holds one). Uncertain never runs on its own: the policy asks. The helper also runs every shell line
/// under ArisShellSandbox, which denies those places whatever the words said.
enum ArisShellReach: Equatable, Sendable {
    case clear
    case uncertain(String)
    case never(ArisNeverRule)
}

extension ArisNeverList {
    /// Programs that read whole folders by themselves (or with their usual flags).
    static let folderReaders: Set<String> = ["tar", "zip", "ditto", "rsync", "scp", "rclone", "rg", "ag", "ack", "find", "grep", "egrep", "fgrep",
                                             "cp", "du", "git", "mdfind", "xargs", "duplicity", "restic", "borg", "7z", "rar", "base64", "cat"]

    /// Every protected place, absolute and folded (Aris's own and the credential stores).
    static func protectedPlaces(home: String) -> [String] {
        let folded = normalized(home, home: home)
        return (ownPlaces + credentialPlaces).map { folded + "/" + $0.lowercased() } + (ownAbsolute + credentialAbsolute).map { $0.lowercased() }
            + [folded + "/" + ownLaunchAgentPrefix.lowercased()]
    }

    static func shellReach(_ line: String, home: String, cwd: String? = nil) -> ArisShellReach {
        if let rule = commandRule(line, home: home) { return .never(rule) }
        let folder = normalized(cwd ?? home, home: home)
        if let rule = pathRule(folder, effect: .observe, home: home) { return .never(rule) }
        if ["$(", "`", "<(", ">(", "${"].contains(where: { line.contains($0) && !(line.contains("${HOME}") && $0 == "${") }) {
            return .uncertain("command or variable expansion")
        }
        let places = protectedPlaces(home: home)
        let holdsPlace = { (path: String) in path == "/" || places.contains { $0.hasPrefix(path + "/") } }
        for words in commands(in: line) {
            guard let first = words.first else { continue }
            let program = (first as NSString).lastPathComponent
            if ["cd", "pushd", "popd", "chdir"].contains(program) { return .uncertain("the line changes folder") }
            let recursive = folderReaders.contains(program) || words.contains { $0 == "--recursive" || ($0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("R")) }
            let removing = ["rm", "srm", "shred", "trash"].contains(program) && words.contains(where: isRecursiveFlag)
            let roots = systemRoots.map { $0.lowercased() } + [normalized(home, home: home)] + everydayFolders.map { normalized(home, home: home) + "/" + $0.lowercased() }
            for raw in words.dropFirst() {
                for word in raw.split(separator: "=").map(String.init) where !word.hasPrefix("-") {
                    let cleaned = word.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                    guard !cleaned.isEmpty else { continue }
                    if cleaned.contains("$"), !(cleaned.hasPrefix("$HOME") || cleaned.hasPrefix("${HOME}")) || cleaned.dropFirst().contains("$") {
                        return .uncertain("a variable")
                    }
                    let absolute = cleaned.hasPrefix("/") || cleaned.hasPrefix("~") || cleaned.hasPrefix("$HOME") || cleaned.hasPrefix("${HOME}")
                    let resolvedRaw = absolute ? cleaned : folder + "/" + cleaned
                    if cleaned.contains("..") { return .uncertain("a path with ..") }
                    if let glob = cleaned.firstIndex(where: { "*?[{".contains($0) }) {
                        let head = String(cleaned[..<glob])
                        let base = normalized(absolute ? (head.isEmpty ? "/" : head) : folder + "/" + head, home: home)
                        let dir = head.hasSuffix("/") || head.isEmpty ? base : (base as NSString).deletingLastPathComponent
                        if holdsPlace(dir) || pathRule(dir, effect: .observe, home: home) != nil || places.contains(where: { $0.hasPrefix(base) }) {
                            return .uncertain("a pattern that could match a protected place")
                        }
                        continue
                    }
                    let resolved = normalized(resolvedRaw, home: home)
                    if let rule = pathRule(resolved, effect: .observe, home: home) { return .never(rule) }
                    if removing, roots.contains(resolved) || holdsPlace(resolved) { return .never(.destroysSystem) }
                    if recursive, holdsPlace(resolved) { return .uncertain("reads a folder that holds keys or Aris's own files") }
                }
            }
        }
        return .clear
    }
}
