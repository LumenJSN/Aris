//
//  ArisProgramFinder.swift
//  aris-agent
//
//  Where the programs Aris starts live: the brain CLIs (codex, claude, agy), a connected service's own program (npx,
//  uvx, bunx), and what those need to run (node). launchd starts the agent with a bare PATH, so a CLI installed under
//  nvm, fnm, volta, asdf, bun or an npm prefix read as "not installed" although it works in the user's terminal, and a
//  launcher that begins `#!/usr/bin/env node` died at once (audit cli-paths-8, mcp-4).
//
//  The user's own PATH is asked for once, from their login shell as a terminal starts it, with a time limit, and kept.
//  It is asked in the background (at the agent's start): no lookup ever waits on the shell.
//  The folders Aris always knew are looked in first and stay first on a child's PATH, so nothing that was found
//  before is found anywhere else now; the shell's folders only add what was missing.
//

import Foundation

/// The folders on the user's own PATH, as a terminal window has it.
enum ArisLoginPath {
    /// Printed around the PATH, so a banner or a prompt the shell's start-up files write is never read as part of it.
    static let marker = "__ARIS_LOGIN_PATH__"
    /// How long the shell may take to start and answer.
    static let limit: TimeInterval = 5
    /// A shell that couldn't be asked is asked again only after this long.
    static let retryAfter: TimeInterval = 1_800
    /// No PATH has more folders than this.
    static let maxFolders = 64

    /// The tests' folders (no shell is started); nil for the user's own.
    nonisolated(unsafe) static var override: [String]?
    /// The user's own: their shell, asked in the background; what it found is kept on disk too (aris-tools and the gate
    /// treat these folders as protected places, security review M4).
    static let shared = Lookup(shell: { userShell() }, limit: limit, retryAfter: retryAfter) { answer in
        ArisProtectedPlaces.keepLoginFolders(answer, home: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    /// The folders as they are known now; none until the shell has answered (the known folders still work). Never
    /// waits on the shell: it is started once, off the caller's queue (a lookup on the server queue held every
    /// request up to the shell's 5 s limit), and asked again only after a shell that couldn't answer.
    static var folders: [String] {
        if let override { return override }
        return shared.folders()
    }

    /// Asks the shell now, in the background: called at the agent's start, so its PATH is there by the first question.
    static func warm() {
        if override == nil { shared.start() }
    }

    /// One user's login-shell PATH: asked at most once at a time, off the caller's queue, and kept.
    final class Lookup: @unchecked Sendable {
        private let shell: () -> String
        private let limit: TimeInterval
        private let retryAfter: TimeInterval
        private let keep: ([String]) -> Void
        private let lock = NSLock()
        private let queue = DispatchQueue(label: "aris.login-path", qos: .utility)
        private var kept: (folders: [String], asked: Bool, at: Date)?
        private var running = false

        init(shell: @escaping () -> String, limit: TimeInterval, retryAfter: TimeInterval, keep: @escaping ([String]) -> Void = { _ in }) {
            self.shell = shell
            self.limit = limit
            self.retryAfter = retryAfter
            self.keep = keep
        }

        /// What is known now (none before the first answer). A shell that couldn't answer is asked again after
        /// `retryAfter`, in the background too.
        func folders(now: Date = Date()) -> [String] {
            lock.withLock {
                if let kept, kept.asked || now.timeIntervalSince(kept.at) < retryAfter { return kept.folders }
                startLocked()
                return kept?.folders ?? []
            }
        }

        /// Starts the shell unless it already answered or is being asked.
        func start() {
            lock.withLock { if kept == nil { startLocked() } }
        }

        /// Waits until a running ask has answered (the tests).
        func settle() { queue.sync {} }

        private func startLocked() {
            guard !running else { return }
            running = true
            queue.async { [self] in
                let answer = ArisLoginPath.ask(shell: shell(), timeout: limit)
                if answer == nil {
                    FileHandle.standardError.write(Data("aris-agent: the login shell's PATH couldn't be read; only the usual folders are searched\n".utf8))
                }
                // On disk before anyone is given the folders.
                if let answer { keep(answer) }
                lock.withLock {
                    kept = (answer ?? [], answer != nil, Date())
                    running = false
                }
            }
        }
    }

    /// The user's shell: the one in their account (launchd gives the agent no SHELL), zsh when there is none.
    static func userShell(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let shell = environment["SHELL"], shell.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: shell) { return shell }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    /// The words that make `shell` print its PATH between two marks, started as a terminal starts it (login and
    /// interactive: nvm, fnm and the like are set up in .zshrc); nil for a shell Aris doesn't know how to ask.
    static func arguments(shell: String) -> [String]? {
        switch (shell as NSString).lastPathComponent {
        case "zsh", "bash", "sh", "dash", "ksh":
            return ["-l", "-i", "-c", "printf '\\n%s%s%s\\n' '\(marker)' \"$PATH\" '\(marker)'"]
        case "fish":
            return ["-l", "-i", "-c", "printf '\\n%s%s%s\\n' '\(marker)' (string join : $PATH) '\(marker)'"]
        default:
            return nil
        }
    }

    /// Starts the shell and reads its PATH: nil when it couldn't start, ran past `timeout`, or printed no PATH.
    static func ask(shell: String, timeout: TimeInterval, environment: [String: String] = ProcessInfo.processInfo.environment) -> [String]? {
        guard let arguments = arguments(shell: shell) else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // No terminal, no stdin: a start-up file that asks something gets its end at once and can't hold the agent.
        var asked = environment
        asked["HOME"] = home
        asked["USER"] = NSUserName()
        asked["LOGNAME"] = NSUserName()
        asked["TERM"] = "dumb"
        let result = ArisSkillProcess.run(shell, arguments, environment: asked, directory: home, timeout: timeout, maxOutput: 64 * 1_024)
        guard !result.timedOut else { return nil }
        return folders(inOutput: result.stdout)
    }

    /// The folders in what the shell printed: the text between the last pair of marks, split at colons. Only absolute
    /// paths, each once, in the shell's order; nil when there is no marked PATH.
    static func folders(inOutput output: String) -> [String]? {
        let pieces = output.components(separatedBy: marker)
        guard pieces.count >= 3 else { return nil }
        let path = pieces[pieces.count - 2]
        guard !path.contains("\n") else { return nil }
        var seen: Set<String> = []
        let folders = path.split(separator: ":").map(String.init)
            .filter { $0.hasPrefix("/") && seen.insert($0).inserted }
        return folders.isEmpty ? nil : Array(folders.prefix(maxFolders))
    }
}

enum ArisPrograms {
    /// The folders Aris has always looked in, in order.
    static func knownFolders(home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> [String] {
        [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
    }

    /// The program named `name`: the first of `known` (whole paths, `~` for the home folder) that is there, else the
    /// first folder of the user's own PATH that has it.
    static func find(_ name: String, known: [String], login: () -> [String] = { ArisLoginPath.folders }) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let listed = known.map { $0.hasPrefix("~") ? home + $0.dropFirst() : $0 }
        if let path = listed.first(where: isProgram) { return URL(fileURLWithPath: path) }
        guard !name.isEmpty, !name.contains("/") else { return nil }
        // A program on the user's own PATH is taken only from a place nobody else can write (security review M4).
        return login().map { ($0 as NSString).appendingPathComponent(name) }.first { isProgram($0) && isOwnersOnly($0) }.map(URL.init(fileURLWithPath:))
    }

    /// Whether only the user (or root) can change what runs at `path`: the folder it is found in, the file itself once
    /// its links are followed, and that file's own folder are each owned by the user or root and writable by neither
    /// their group nor everyone. A program in a shared or world-writable folder could be swapped by anyone, and it
    /// would run as the agent.
    static func isOwnersOnly(_ path: String) -> Bool {
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let checked = [(path as NSString).deletingLastPathComponent, real, (real as NSString).deletingLastPathComponent]
        return checked.allSatisfy { item in
            var info = stat()
            return stat(item, &info) == 0 && (info.st_uid == getuid() || info.st_uid == 0) && info.st_mode & 0o022 == 0
        }
    }

    /// `name` in the folders Aris always looked in, then on the user's own PATH.
    static func find(_ name: String) -> URL? {
        find(name, known: knownFolders().map { $0 + "/" + name })
    }

    /// An executable file (links followed), never a folder.
    static func isProgram(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    /// The PATH a child gets: `first` (Aris's own folders, as before), then what the agent itself was started with,
    /// then the folders of the user's own PATH that aren't in it yet. Nothing found before moves; node under nvm, a
    /// bun or volta folder and an npm prefix are added at the end.
    static func childPath(first: [String], inherited: String?, login: [String] = ArisLoginPath.folders) -> String {
        var seen: Set<String> = []
        return (first + (inherited ?? "").split(separator: ":").map(String.init) + login)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }
}
