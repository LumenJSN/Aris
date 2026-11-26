//
//  ArisSessionTranscript.swift
//  aris-agent
//
//  A background job's brain keeps its conversation on disk only while the job is unfinished, so a helper that started
//  again can reopen it (ArisTaskRecovery). Once the job's end is in its journal (answered, failed, cancelled, lost,
//  stopped), the transcript of every session the journal names is removed, a few seconds later (the brain's process is
//  stopped by then and can't write it again), and again at the next start for any a crash left behind.
//
//  Where each brain keeps one (seen live, claude 2.1.327 and codex-cli 0.169.0):
//  · Claude Code: <CLAUDE_CONFIG_DIR or ~/.claude>/projects/<the working folder's real path, every character but a
//    letter or digit made "-">/<session id>.jsonl (the job's folder is the helper's, ~/.config/aris/aris);
//  · Codex: <CODEX_HOME or ~/.codex>/sessions/<year>/<month>/<day the thread began>/rollout-<time>-<thread id>.jsonl.
//  Only a file named exactly for that id is removed, and only when it is a plain file of the user's inside the expected
//  folder, every folder on the way a real one of his (never through a link).
//

import Darwin
import Foundation

enum ArisSessionTranscript {
    /// How long after a job's end its transcripts go: its process gets SIGTERM, then SIGKILL after ArisProcessEnd's grace.
    static let afterEnd: TimeInterval = ArisProcessEnd.defaultGrace + 2
    /// Codex's day folders looked in around the job's start (a thread begins the day its job did, local time).
    static let codexDays = 4

    /// The folder Claude Code keeps a working folder's sessions in.
    static func claudeFolder(workingFolder: String, home: String, environment: [String: String]) -> URL {
        let root = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.claude"
        let real = URL(fileURLWithPath: workingFolder).resolvingSymlinksInPath().path
        let name = String(real.unicodeScalars.map { scalar -> Character in
            (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)) ? Character(scalar) : "-"
        })
        return URL(fileURLWithPath: root).appendingPathComponent("projects").appendingPathComponent(name)
    }

    /// Codex's sessions folder.
    static func codexFolder(home: String, environment: [String: String]) -> URL {
        let root = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.codex"
        return URL(fileURLWithPath: root).appendingPathComponent("sessions")
    }

    /// The transcripts of `handle` (a session or thread id: a UUID, else nothing) on disk now.
    static func files(of handle: String, began: Date, home: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                      workingFolder: String? = nil, calendar: Calendar = .current) -> [URL] {
        guard let id = UUID(uuidString: handle)?.uuidString.lowercased() else { return [] }
        var found: [URL] = []
        let claude = claudeFolder(workingFolder: workingFolder ?? home + "/.config/aris/aris", home: home, environment: environment)
        let claudeFile = claude.appendingPathComponent(id + ".jsonl")
        if isRealFolder(claude, root: claude.deletingLastPathComponent().deletingLastPathComponent()), isOwnFile(claudeFile) { found.append(claudeFile) }
        let codex = codexFolder(home: home, environment: environment)
        for offset in -1..<(codexDays - 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: began) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = parts.year, let month = parts.month, let date = parts.day else { continue }
            let folder = codex.appendingPathComponent(String(format: "%04d", year)).appendingPathComponent(String(format: "%02d", month))
                .appendingPathComponent(String(format: "%02d", date))
            guard isRealFolder(folder, root: codex.deletingLastPathComponent()), let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names where name.hasPrefix("rollout-") && name.lowercased().hasSuffix("-" + id + ".jsonl") {
                let file = folder.appendingPathComponent(name)
                if isOwnFile(file) { found.append(file) }
            }
        }
        return found
    }

    /// Removes the transcripts of these handles. How many went.
    @discardableResult
    static func remove(_ handles: [String], began: Date, home: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                       workingFolder: String? = nil) -> Int {
        var removed = 0
        for handle in Set(handles) {
            for file in files(of: handle, began: began, home: home, environment: environment, workingFolder: workingFolder) where unlink(file.path) == 0 {
                removed += 1
            }
        }
        return removed
    }

    /// The job's end is in its journal: its transcripts go once its process is gone.
    static func forgetLater(_ handles: [String], began: Date, home: String) {
        guard !handles.isEmpty else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + afterEnd) {
            let removed = remove(handles, began: began, home: home)
            if removed > 0 { try? FileHandle.standardError.write(contentsOf: Data("aris-agent: removed \(removed) finished job transcript(s)\n".utf8)) }
        }
    }

    /// `folder` is `root` or inside it, and it and every folder above it up to `root` (included) is a real folder (no
    /// link) of this user's.
    static func isRealFolder(_ folder: URL, root: URL) -> Bool {
        let top = root.standardizedFileURL.path
        var current = folder.standardizedFileURL
        guard current.path == top || current.path.hasPrefix(top + "/") else { return false }
        while true {
            var info = stat()
            guard lstat(current.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else { return false }
            if current.path == top { return true }
            current.deleteLastPathComponent()
        }
    }

    /// A plain file (never a link) of this user's.
    static func isOwnFile(_ file: URL) -> Bool {
        var info = stat()
        return lstat(file.path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG && info.st_uid == getuid()
    }
}
