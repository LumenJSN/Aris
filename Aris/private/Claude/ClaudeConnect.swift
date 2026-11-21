//
//  ClaudeConnect.swift
//  Aris
//
//  Settings › Claude Code 연결 (ClaudeHookSettings): the sandboxed app can't write ~/.claude on its own, so the first
//  time the user picks the folder in an open panel (that is the macOS grant); a security-scoped bookmark keeps the
//  grant for disconnecting, the next update of the hooks, and the uninstall. settings.json is backed up before every
//  change (settings.json.pre-aris.<time>, 0600), a new one is made 0600, and someone else's status line is replaced
//  only after asking. Nothing here needs the helper.
//

import AppKit
import os

@MainActor
enum ClaudeConnect {
    private static let log = Logger(subsystem: "com.lumenjsn.aris", category: "claude")
    static let bookmarkKey = "arisClaudeFolderBookmark"

    static var folder: URL { URL(fileURLWithPath: UserHome.path).appendingPathComponent(".claude", isDirectory: true) }
    /// Whether Aris's hooks were there the last time the file was read here (Settings' dot).
    private(set) static var connectedNow: Bool?

    /// Adds the hooks (asking for the folder the first time). The line Settings shows after it.
    static func connect() -> (line: String, ok: Bool) {
        guard let script = Bundle.main.path(forResource: "aris-claude-hook", ofType: "sh"),
              let status = Bundle.main.path(forResource: "aris-claude-statusline", ofType: "sh")
        else { return ("이 Aris에는 Claude Code 연결 스크립트가 들어 있지 않아요.", false) }
        return withFolder(asking: true) { folder in
            let file = folder.appendingPathComponent("settings.json")
            let before = try read(file)
            var replace = false
            if case .theirs(let command) = ClaudeHookSettings.statusLine(before) { replace = askReplace(command) }
            let after = ClaudeHookSettings.connecting(before, script: script, statusScript: status, replaceTheirs: replace)
            connectedNow = true
            if NSDictionary(dictionary: before).isEqual(to: after) { return ("이미 연결돼 있어요.", true) }
            try write(after, to: file, folder: folder)
            log.notice("claude: hooks written")
            return ("Claude Code를 연결했어요. 새로 여는 세션부터 노치에 보여요.", true)
        }
    }

    /// Takes Aris's hooks and status line off (only with the folder already granted; nothing to do without it).
    static func disconnect() -> (line: String, ok: Bool) {
        withFolder(asking: false) { folder in
            let file = folder.appendingPathComponent("settings.json")
            let before = try read(file)
            let after = ClaudeHookSettings.disconnecting(before)
            connectedNow = false
            if NSDictionary(dictionary: before).isEqual(to: after) { return ("연결돼 있지 않아요.", true) }
            try write(after, to: file, folder: folder)
            log.notice("claude: hooks removed")
            return ("Claude Code 연결을 끊었어요. 설정 파일은 백업해 뒀어요.", true)
        }
    }

    /// Settings' dot: read through the kept grant, never asking.
    static func refreshConnected() {
        guard let folder = resolvedFolder() else { connectedNow = nil; return }
        defer { folder.stopAccessingSecurityScopedResource() }
        connectedNow = (try? read(folder.appendingPathComponent("settings.json"))).map(ClaudeHookSettings.connected)
    }

    /// The uninstall: Aris's hooks off, quietly, when the folder was granted.
    static func removeQuietly() {
        guard resolvedFolder() != nil else { return }
        _ = disconnect()
    }

    // MARK: - The folder

    private enum Trouble: Error { case notGranted, wrongFolder, unreadable, notObject }

    private static func withFolder(asking: Bool, _ work: (URL) throws -> (line: String, ok: Bool)) -> (line: String, ok: Bool) {
        guard let folder = resolvedFolder() ?? (asking ? askForFolder() : nil) else {
            return asking ? ("~/.claude 폴더를 고르지 않아서 아무것도 바꾸지 않았어요.", false) : ("연결돼 있지 않아요.", true)
        }
        defer { folder.stopAccessingSecurityScopedResource() }
        do {
            return try work(folder)
        } catch Trouble.notObject, Trouble.unreadable {
            return ("~/.claude/settings.json을 읽을 수 없어서 아무것도 바꾸지 않았어요.", false)
        } catch {
            log.error("claude: \(error.localizedDescription, privacy: .public)")
            return ("Claude Code 설정을 고치지 못했어요.", false)
        }
    }

    /// The kept grant, already started; nil without one (or one that no longer resolves to ~/.claude).
    private static func resolvedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
              same(url, folder), url.startAccessingSecurityScopedResource() else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    private static func askForFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = folder
        panel.prompt = ArisUIWords.text("허용", "Allow")
        panel.message = ArisUIWords.text("Claude Code를 연결하려면 홈 폴더의 .claude 폴더를 골라 주세요. Aris는 그 안의 settings.json만 고쳐요.",
                                         "To connect Claude Code, choose the .claude folder in your home folder. Aris only changes settings.json in it.")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, same(url, folder) else { return nil }
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    private static func same(_ a: URL, _ b: URL) -> Bool {
        a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: - The file

    /// The settings as an object; {} when the file is missing or empty (a Claude Code that hasn't written one yet).
    private static func read(_ file: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        guard let data = try? Data(contentsOf: file) else { throw Trouble.unreadable }
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Trouble.notObject }
        return object
    }

    private static func write(_ settings: [String: Any], to file: URL, folder: URL) throws {
        let fm = FileManager.default
        let existed = fm.fileExists(atPath: file.path)
        if existed {
            let stamp = DateFormatter.arisBackupStamp.string(from: Date())
            let backup = folder.appendingPathComponent(ClaudeHookSettings.backupName(stamp: stamp))
            try fm.copyItem(at: file, to: backup)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: file, options: .atomic)
        if !existed { try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
    }

    /// Someone else's status line is there: replaced only on the user's yes.
    private static func askReplace(_ command: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = ArisUIWords.text("Claude Code에 이미 상태 줄이 있어요", "Claude Code already has a status line")
        alert.informativeText = ArisUIWords.text("Aris의 상태 줄로 바꾸면 노치에서 사용량을 볼 수 있어요. 지금 상태 줄: \(command)",
                                                 "Aris's status line shows your usage in the notch. Current status line: \(command)")
        alert.addButton(withTitle: ArisUIWords.text("그대로 두기", "Keep mine"))
        alert.addButton(withTitle: ArisUIWords.text("Aris 상태 줄로 바꾸기", "Use Aris's"))
        return alert.runModal() == .alertSecondButtonReturn
    }
}

private extension DateFormatter {
    static let arisBackupStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
