//
//  ArisShortcutStore.swift
//  aris-agent
//
//  Where learned shortcuts live (aris/shortcuts.json, private) and how they run:
//  each saved command, checked again against the replayable shapes, through zsh
//  with a short time limit. A shortcut that fails is forgotten. Listed and deleted in 설정 › 기억 › 저장된 단계
//  (ArisShortcutsRoute) and removed by a memory wipe (ArisDataRoute).
//

import Foundation

final class ArisShortcutStore {
    static let shared = ArisShortcutStore()

    private static let commandTimeout: TimeInterval = 10
    private let lock = NSLock()
    private var file: URL { ArisAgentRunner.directory.appendingPathComponent("shortcuts.json") }

    func lookup(_ key: String) -> ArisShortcuts.Learned? {
        lock.withLock { load()[key] }
    }

    /// Requests handled once with only replayable commands, waiting for a second time (ArisShortcuts.sighted).
    private var seen: [String: [String]] = [:]

    /// Saved the second time the same words are handled with the same commands (never one-off phrasing).
    func learn(_ commands: [String], reply: String, as key: String) {
        let saved = lock.withLock { () -> Bool in
            let sighting = ArisShortcuts.sighted(commands, as: key, seen: seen)
            seen = sighting.seen
            guard sighting.save else { return false }
            let learned = ArisShortcuts.Learned(commands: commands, reply: ArisShortcuts.keptReply(reply), learned: ISO8601DateFormatter().string(from: Date()))
            save(ArisShortcuts.saving(learned, as: key, in: load()))
            return true
        }
        if saved { try? FileHandle.standardError.write(contentsOf: Data("aris-agent: learned a shortcut (\(commands.count) command(s))\n".utf8)) }
    }

    @discardableResult
    func forget(_ key: String) -> Bool {
        lock.withLock {
            var shortcuts = load()
            seen.removeValue(forKey: key)
            guard shortcuts.removeValue(forKey: key) != nil else { return false }
            save(shortcuts)
            return true
        }
    }

    /// For 설정 › 기억 (ArisShortcutsRoute): every shortcut, and forgetting one.
    var access: ArisShortcutsAccess {
        ArisShortcutsAccess(all: { [self] in lock.withLock { load() } }, forget: { [self] in forget($0) })
    }

    /// Runs every command in order; false as soon as one is refused or fails.
    func replay(_ learned: ArisShortcuts.Learned, tools: String, environment: [String: String]) -> Bool {
        for command in learned.commands {
            guard ArisShortcuts.isReplayable(command, tools: tools) else { return false }
            let process = ArisExactProcess()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // The helper's own call: its own aris-tools, never the link in the user's folder (security review 4, H1).
            process.arguments = ["-c", ArisAppBundle.ownCommand(command, told: tools)]
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let audit = { (ran: Bool) in ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(ArisShortcuts.replayAudit(command, ran: ran)), key: "local") }
            do { try ArisChildren.run(process) } catch { audit(false); return false }
            let deadline = Date().addingTimeInterval(Self.commandTimeout)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning {
                ArisProcessEnd.end(process)
                audit(false)
                return false
            }
            audit(process.terminationStatus == 0)
            guard process.terminationStatus == 0 else { return false }
        }
        return true
    }

    private func load() -> [String: ArisShortcuts.Learned] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: ArisShortcuts.Learned].self, from: data)) ?? [:]
    }

    private func save(_ shortcuts: [String: ArisShortcuts.Learned]) {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
