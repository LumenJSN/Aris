//
//  ArisProtectedPlaces.swift
//  aris-tools, aris-agent
//
//  The places under the home folder that Aris never moves, trashes, overwrites or restores into: its own folder, keys,
//  startup files and tools on the PATH. One list, used by the activity undo, `aris-tools move` and the risk gate, so
//  they can't disagree. Compared without regard to case or Unicode form (APFS treats ".ZSHRC" as ".zshrc"), and a
//  path that contains a protected place counts too (moving ~/.config would carry ~/.config/aris away).
//

import Foundation

enum ArisProtectedPlaces {
    /// Relative to the home folder.
    static let relative = [
        ".config/aris", ".config/boring-notch", ".ssh", ".gnupg", "Library/LaunchAgents", ".local/bin", "bin",
        ".zshrc", ".zshenv", ".zprofile", ".zlogin", ".bashrc", ".bash_profile", ".bash_login", ".profile",
        ".gitconfig", ".config/git", ".config/fish", ".claude", ".codex", ".gemini",
        // The folders a shell's start-up files read more files from (security review M4: the agent now starts the user's
        // login shell to learn his PATH, so a file moved in here would run inside the agent).
        ".oh-my-zsh", ".zsh", ".config/zsh", ".zshrc.d", ".bashrc.d",
        // The user's skills and their checked runtime: only the agent's skills code changes them.
        "Library/Application Support/Aris/Skills", "Library/Application Support/Aris/skills-runtime",
        // Computer use's checked runtime (Peekaboo) and Peekaboo's own store (its snapshots hold other apps' windows):
        // only the agent's desktop engine touches them (security review I11, I12).
        "Library/Application Support/Aris/computer-runtime", ".peekaboo",
    ]

    /// The shell and tool settings among `relative` that the user may ask Aris to edit (audit gate-17: "내 .zshrc에 alias
    /// 하나 추가해줘" was refused while the same edit by a shell redirect only asked). An edit there asks on a card that
    /// shows the whole change, every time. Everything else in `relative` is still never edited: Aris's own folders, keys
    /// (.ssh, .gnupg), login items, and the AI tools' own folders (.claude, .codex, .gemini hold hooks and tokens).
    /// Moving, trashing, renaming and undo keep the whole list above: this second list is for edits alone.
    static let editableOnCard = [".zshrc", ".zshenv", ".zprofile", ".zlogin", ".bashrc", ".bash_profile", ".bash_login", ".profile",
                                 ".gitconfig", ".config/git", ".config/fish", "bin", ".local/bin",
                                 ".oh-my-zsh", ".zsh", ".config/zsh", ".zshrc.d", ".bashrc.d"]

    /// Whether an edit of `path` is refused outright: `blocks`, but for the places an edit may ask about instead (the
    /// list above, and the login PATH's folders: an edit there asks with its whole change, it is never automatic).
    static func blocksEdit(_ path: String, home: String, apps: [String] = appPlaces()) -> Bool {
        blocks(path, home: home, places: relative.filter { !editableOnCard.contains($0) }, apps: apps)
    }

    // MARK: - Aris's own app (security review 4, M6)

    /// Where Aris is installed. The helper, its tools and the built-in skill live inside the app now, so the app is
    /// protected exactly as ~/.config/aris is: nothing a brain asks for edits, moves, trashes or writes into it.
    static let installedApp = "/Applications/Aris.app"
    /// The app this very program runs from, its links followed; nil for a loose copy (a developer's build, the tests).
    static let runningApp: String? = ArisOrigin.program(of: getpid()).flatMap(ArisOrigin.app(ofProgram:))
        .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }

    static func appPlaces(running: String? = runningApp) -> [String] {
        ([installedApp] + [running].compactMap { $0 }).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Whether `path` is Aris's app or anything inside it (compared like every protected place: case and Unicode form
    /// folded, /private dropped). `path` is standardized here; links are the caller's business.
    static func inApp(_ path: String, apps: [String] = appPlaces()) -> Bool {
        let target = key(unprivate((path as NSString).standardizingPath))
        return apps.map { key(unprivate(($0 as NSString).standardizingPath)) }.contains { target == $0 || target.hasPrefix($0 + "/") }
    }

    /// Whether `path` is a folder that holds Aris's app (moving or trashing /Applications would carry it away).
    static func holdsApp(_ path: String, apps: [String] = appPlaces()) -> Bool {
        let target = key(unprivate((path as NSString).standardizingPath))
        return target.count > 1 && apps.map { key(unprivate(($0 as NSString).standardizingPath)) }.contains { $0.hasPrefix(target + "/") }
    }

    // MARK: - The login shell's PATH (security review M4)

    /// Where the agent keeps the folders of the user's login-shell PATH (ArisLoginPath), one a line, under the home folder.
    static let loginFoldersFile = ".config/aris/aris/login-path-folders"

    /// Home's own everyday folders: never a protected place, whatever a PATH says.
    private static let everydayFolders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Library", "Applications"]

    /// The folders of the user's login-shell PATH as the agent last kept them. The agent searches them for the programs
    /// it starts (codex, claude, agy, npx) and puts them on every child's PATH, so a file moved or written into one
    /// would run inside the agent: they count as protected places (never moved into, trashed or renamed; an edit asks
    /// with its whole change). Read only from a plain file of the user's own that nobody else can read or write; home
    /// itself, a folder above it and home's everyday folders are never taken. None when there is no such file.
    static func loginFolders(home: String) -> [String] {
        let base = unprivate((home as NSString).standardizingPath)
        let file = base + "/" + loginFoldersFile
        var info = stat()
        guard lstat(file, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_size <= 65_536,
              let text = try? String(contentsOfFile: file, encoding: .utf8) else { return [] }
        let open = Set(([""] + everydayFolders).map { key($0.isEmpty ? base : base + "/" + $0) })
        let folders = text.split(whereSeparator: \.isNewline).map { unprivate((String($0) as NSString).standardizingPath) }.filter { folder in
            let named = key(folder)
            return folder.hasPrefix("/") && folder.count > 1 && !open.contains(named) && !key(base).hasPrefix(named + "/")
        }
        return Array(folders.prefix(64))
    }

    /// A path without the /private that macOS puts before /var, /tmp and /etc (the same place either way), so a folder
    /// is compared the same whether or not it exists yet.
    private static func unprivate(_ path: String) -> String {
        ["/private/var", "/private/tmp", "/private/etc"].contains { path == $0 || path.hasPrefix($0 + "/") } ? String(path.dropFirst("/private".count)) : path
    }

    /// The agent's side: the folders kept for `loginFolders`, written owner-only and whole (a temporary file, renamed).
    /// False when it couldn't be written (the folders then simply aren't protected yet).
    @discardableResult
    static func keepLoginFolders(_ folders: [String], home: String) -> Bool {
        let file = URL(fileURLWithPath: home).appendingPathComponent(loginFoldersFile)
        let temporary = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).\(UUID().uuidString)")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data((folders.filter { $0.hasPrefix("/") && !$0.contains("\n") }.joined(separator: "\n") + "\n").utf8))
            try handle.close()
        } catch {
            unlink(temporary.path)
            return false
        }
        guard rename(temporary.path, file.path) == 0 else { unlink(temporary.path); return false }
        return true
    }

    /// Whether `path` is one of the login PATH's folders, inside one, or holds one (those outside the home folder too:
    /// /opt/homebrew/bin). `path` is standardized here; links are the caller's business.
    static func inLoginFolder(_ path: String, home: String) -> Bool {
        let target = key(unprivate((path as NSString).standardizingPath))
        return loginFolders(home: home).map(key).contains { target == $0 || target.hasPrefix($0 + "/") || $0.hasPrefix(target + "/") }
    }

    /// The text as the runtime checks compare it: compatibility-folded (ｐｅｅｋａｂｏｏ is peekaboo), case-folded, nothing
    /// invisible left in.
    private static func plain(_ text: String) -> String {
        String(String.UnicodeScalarView(key(text.precomposedStringWithCompatibilityMapping).unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint }))
    }

    /// A path into computer use's runtime folder or Peekaboo's own store (an aris-tools argument that would open, move or
    /// read it). Merely naming Peekaboo isn't one (security review I11, re-review 1).
    static func namesRuntimePlace(_ text: String) -> Bool {
        let folded = plain(text)
        return folded.contains("/computer-runtime") || folded.contains("/.peekaboo")
    }

    /// Wrappers that run the word after them as the program.
    private static let runners: Set<String> = ["env", "exec", "command", "nohup", "nice", "time", "caffeinate", "xargs", "builtin", "noglob"]

    /// Whether a command line runs Peekaboo or anything in computer use's runtime folder as a program (at any command
    /// start: after ; & | a line break, $( or a backtick, past env assignments and wrappers like env or exec). Only the
    /// agent runs Peekaboo, on every brain. A command that only names it (ls of a folder called peekaboo, a fetch of its
    /// page, a note) runs something else and isn't one (security review I11, re-review 1). The callers pass a desktop
    /// heredoc's first line only: its body is never run.
    static func executesComputerRuntime(_ command: String) -> Bool {
        commandStarts(command).contains { piece in
            var words = shellWords(piece)[...]
            var wrapped = false
            while let first = words.first, first.contains("=") && !first.hasPrefix("=") || runners.contains(plain(first)) {
                if runners.contains(plain(first)) { wrapped = true }
                words = words.dropFirst()
            }
            let isRuntime = { (word: String) -> Bool in
                let folded = plain(word)
                return (folded as NSString).lastPathComponent == "peekaboo" || folded.contains("computer-runtime")
            }
            // After a wrapper (nice -n 5 peekaboo), any word of its own may be the program.
            return wrapped ? words.contains(where: isRuntime) : words.first.map(isRuntime) ?? false
        }
    }

    /// The line cut wherever a command could start: outside quotes at ; & | ( a line break or a backtick; inside double
    /// quotes at a backtick or $(; never inside single quotes. An unclosed quote, a heredoc or $'…' (where this scan could
    /// read quotes differently from the shell) cuts everywhere.
    private static func commandStarts(_ command: String) -> [String] {
        let everywhere = command.components(separatedBy: CharacterSet(charactersIn: ";&|\n\r`("))
        var pieces: [String] = [], piece = ""
        var single = false, double = false, escaped = false
        var previous: Character?
        for character in command {
            defer { previous = character }
            if escaped { escaped = false; piece.append(character); continue }
            if !single, character == "\\" { escaped = true; piece.append(character); continue }
            if !single, !double, (character == "<" && previous == "<") || (character == "'" && previous == "$") { return everywhere }
            if character == "'", !double { single.toggle(); piece.append(character); continue }
            if character == "\"", !single { double.toggle(); piece.append(character); continue }
            let cuts = single ? false : double ? character == "`" || (character == "(" && previous == "$") : ";&|(`".contains(character) || character.isNewline
            if cuts { pieces.append(piece); piece = "" } else { piece.append(character) }
        }
        pieces.append(piece)
        return single || double ? everywhere : pieces
    }

    /// A piece's words with their quotes taken off (a rough reading: enough to find the program).
    private static func shellWords(_ piece: String) -> [String] {
        var words: [String] = [], word = "", quote: Character?, inWord = false
        for character in piece {
            if let open = quote {
                if character == open { quote = nil } else { word.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character; inWord = true
            } else if character == " " || character == "\t" || character == "$" {
                if inWord { words.append(word); word = ""; inWord = false }
            } else {
                word.append(character); inWord = true
            }
        }
        if inWord { words.append(word) }
        return words
    }

    /// The comparison form of a path: canonical Unicode, with full case folding as APFS does (so "ſ" is "s" and "ﬁ" is "fi").
    static func key(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
    }

    /// Whether `path` is the home folder, at or under a protected place, or contains one. `path` is standardized here
    /// ("..", "."); links are the caller's business (resolve them first). By name (folded, so look-alike spellings
    /// match) and, for what exists, by what is on disk: a path that is the same file or folder as a protected place, or
    /// as one that holds one (a hard link, an odd spelling the folding doesn't know), or lies inside one, is blocked.
    /// `places`: the protected places to check against (`blocksEdit`'s shorter list); nil for all of them, the login
    /// PATH's folders under home included.
    static func blocks(_ path: String, home: String, places given: [String]? = nil, apps: [String] = appPlaces()) -> Bool {
        // Aris's own app, wherever it is installed (also outside the home folder): never read from, written or moved.
        if inApp(path, apps: apps) { return true }
        let std = (path as NSString).standardizingPath, base = (home as NSString).standardizingPath
        let target = key(std), root = key(base)
        if target == root { return true }
        guard target.hasPrefix(root + "/") else { return false }
        let inside = String(target.dropFirst(root.count + 1))
        let plainBase = unprivate(base)
        let places = given ?? relative + loginFolders(home: base).filter { $0.hasPrefix(plainBase + "/") }.map { String($0.dropFirst(plainBase.count + 1)) }
        let byName = places.map(key).contains { place in
            inside == place || inside.hasPrefix(place + "/") || place.hasPrefix(inside + "/")
        }
        return byName || sameOnDisk(std, home: base, places: places)
    }

    private static func identity(_ path: String, following: Bool = false) -> String? {
        var info = stat()
        return (following ? stat(path, &info) : lstat(path, &info)) == 0 ? "\(info.st_dev):\(info.st_ino)" : nil
    }

    private static func sameOnDisk(_ path: String, home: String, places: [String]) -> Bool {
        // A protected place that is itself a link (a dotfile manager's): the link and what it points at both count.
        var protectedIDs = Set<String>(), holderIDs = Set<String>()
        func add(_ full: String, to set: inout Set<String>) {
            for following in [false, true] { if let id = identity(full, following: following) { set.insert(id) } }
        }
        for place in places {
            add(home + "/" + place, to: &protectedIDs)
            var holder = (place as NSString).deletingLastPathComponent
            while !holder.isEmpty {
                add(home + "/" + holder, to: &holderIDs)
                holder = (holder as NSString).deletingLastPathComponent
            }
        }
        if let own = identity(path), protectedIDs.contains(own) || holderIDs.contains(own) { return true }
        // Any folder on the way down that is a protected place under another name.
        var walked = home
        for part in path.dropFirst(home.count).split(separator: "/").dropLast() {
            walked += "/" + part
            if let id = identity(walked), protectedIDs.contains(id) { return true }
        }
        return false
    }
}
