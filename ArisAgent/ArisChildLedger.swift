//
//  ArisChildLedger.swift
//  aris-agent
//
//  The running brains on disk (pid and start time, sealed: ArisTaskSeal), so a helper that starts after one that died
//  can stop what that one left once both numbers match and the process has lost its parent, and SIGTERM or SIGINT to
//  the helper stops them all, with their process groups (ArisProcessGroup), before it exits.
//

import Darwin
import Foundation

/// The brain processes this helper has running, on disk (children.json: pid and start time, sealed: ArisTaskSeal).
/// At start only a brain whose pid still has that start time, still leads its group and has lost its parent is
/// stopped.
final class ArisChildLedger {
    struct Entry: Codable, Equatable {
        let pid: Int32
        let started: UInt64
    }

    /// What the file holds, sealed: the helper generation that wrote it (moved on at every start, so an older list
    /// never opens again), the helper itself (pid and start time), and its brains.
    struct Written: Codable, Equatable {
        let generation: Int
        let helper: Entry
        let entries: [Entry]
    }

    static let shared = ArisChildLedger(home: FileManager.default.homeDirectoryForCurrentUser.path)

    let file: URL
    let home: String
    private let lock = NSLock()
    private var entries: [Entry] = []

    /// The generation this helper writes under (the one its start-up sweep moved to).
    let generation: Int

    init(home: String) {
        self.home = home
        file = Self.file(home: home)
        generation = Self.generation(home: home)
    }

    static func file(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("children.json")
    }

    static func generationFile(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("children.generation")
    }

    /// The current helper generation (0 before any).
    static func generation(home: String) -> Int {
        guard let sealed = ArisPrivateFile.read(generationFile(home: home)),
              let raw = ArisTaskSeal.opened(sealed, purpose: "children-generation", home: home) else { return 0 }
        return Int(String(decoding: raw, as: UTF8.self)) ?? 0
    }

    /// A brain started (`pid`, with the start time the kernel gives it).
    func add(_ pid: pid_t) {
        guard let found = ArisProcessGroup.info(pid) else { return }
        lock.withLock {
            entries.append(Entry(pid: pid, started: found.started))
            save()
        }
    }

    func remove(_ pid: pid_t) {
        lock.withLock {
            let before = entries.count
            entries.removeAll { $0.pid == pid }
            if entries.count != before { save() }
        }
    }

    var running: [Entry] { lock.withLock { entries } }

    /// At the helper's exit (SIGTERM, SIGINT): every brain's group is stopped, then the file is emptied.
    func stopAll(grace: TimeInterval = 2) {
        let all = lock.withLock { entries }
        for entry in all where Self.matches(entry) { ArisProcessGroup.signal(entry.pid, since: entry.started, SIGTERM) }
        let until = Date().addingTimeInterval(grace)
        while all.contains(where: { ArisProcessGroup.alive($0.pid, since: $0.started) }), Date() < until { usleep(20_000) }
        for entry in all { ArisProcessGroup.signal(entry.pid, since: entry.started, SIGKILL) }
        lock.withLock {
            entries = []
            save()
        }
    }

    /// At start: what a previous helper left running is stopped, each one only when its pid still has the start time
    /// written down (a pid given to another process since is left alone). How many groups were stopped.
    @discardableResult
    /// `orphaned`: whether the process lost its parent (a dead helper's brain is launchd's now); the tests' own children
    /// have the test as their parent.
    static func sweep(home: String, grace: TimeInterval = 1, orphaned: (pid_t) -> Bool = { ArisOrigin.live($0)?.parent == 1 }) -> Int {
        let file = file(home: home)
        let current = generation(home: home)
        // This start is a new generation: a list written before it never opens again.
        if let next = ArisTaskSeal.sealedFile(Data(String(current + 1).utf8), purpose: "children-generation", home: home) {
            try? ArisPrivateFile.write(next, to: generationFile(home: home))
        }
        // Only the last helper's own sealed list counts (ArisTaskSeal): one anyone else wrote, or an older one put back,
        // names nothing to stop.
        guard let sealed = ArisPrivateFile.read(file), let data = ArisTaskSeal.opened(sealed, purpose: "children", home: home),
              let written = try? JSONDecoder().decode(Written.self, from: data), written.generation == current else {
            try? ArisPrivateFile.write(Data(), to: file)
            return 0
        }
        let live = written.entries.filter { matches($0) && orphaned($0.pid) }
        for entry in live { ArisProcessGroup.stop(entry.pid, since: entry.started, grace: grace) }
        try? ArisPrivateFile.write(Data(), to: file)
        if !live.isEmpty {
            try? FileHandle.standardError.write(contentsOf: Data("aris-agent: stopped \(live.count) brain process(es) an earlier helper left running\n".utf8))
        }
        return live.count
    }

    /// The pid is that very process (its start time to the microsecond) and still leads its group.
    static func matches(_ entry: Entry) -> Bool {
        guard let now = ArisProcessGroup.info(entry.pid) else { return false }
        return now.started == entry.started && now.group == entry.pid
    }

    /// Called with `lock` held. Never once an uninstall is removing ~/.config/aris (it would bring the folder back).
    private func save() {
        guard !ArisUninstallQuiet.folderIsFrozen else { return }
        let helper = Entry(pid: getpid(), started: ArisProcessGroup.info(getpid())?.started ?? 0)
        guard let data = try? JSONEncoder().encode(Written(generation: generation, helper: helper, entries: entries)),
              let sealed = ArisTaskSeal.sealedFile(data, purpose: "children", home: home) else { return }
        try? ArisPrivateFile.write(sealed, to: file)
    }
}
