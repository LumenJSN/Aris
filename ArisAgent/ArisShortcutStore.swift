//
//  ArisShortcutStore.swift
//  aris-agent
//
//  Where learned shortcuts live (aris/shortcuts.json, private) and how they run:
//  each saved command, checked again against the replayable shapes, through zsh
//  with a short time limit. A shortcut that fails is forgotten.
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

    func learn(_ commands: [String], reply: String, as key: String) {
        let learned = ArisShortcuts.Learned(commands: commands, reply: reply, learned: ISO8601DateFormatter().string(from: Date()))
        lock.withLock { save(ArisShortcuts.saving(learned, as: key, in: load())) }
        FileHandle.standardError.write(Data("aris-agent: learned a shortcut (\(commands.count) command(s))\n".utf8))
    }

    func forget(_ key: String) {
        lock.withLock {
            var shortcuts = load()
            shortcuts.removeValue(forKey: key)
            save(shortcuts)
        }
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
