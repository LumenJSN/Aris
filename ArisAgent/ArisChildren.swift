//
//  ArisChildren.swift
//  aris-agent
//
//  The processes this helper started itself: the one place every start goes through, and the helper's own list of
//  them (pid and the moment the kernel says each started). A tool that macOS charges to Aris runs only when it is, or
//  descends from, one of these (security review 4, M2; ArisOrigin+Vouch): who a process's parent is can be arranged
//  by whoever started the helper, what the helper itself started cannot.
//
//  Every start in aris-agent is `ArisChildren.run(process)` or `ArisChildren.spawn(…)`; a test fails when a source
//  file starts a process any other way. The list is only in this process's memory: nothing on disk can add to it.
//

import Darwin
import Foundation

enum ArisChildren {
    /// Held while a child is started and written down, and while the list is read: a question about a child that
    /// exists is never answered before that child is on the list.
    private static let lock = NSRecursiveLock()
    nonisolated(unsafe) private static var started: [pid_t: UInt64] = [:]

    /// Starts `process` (Foundation's, or ArisExactProcess) and writes it down.
    /// Two things are looked at first, here because nothing the helper starts gets past this place (security review
    /// 4, H1): the link in the user's folder is never what the helper itself starts (its own aris-tools is), and an
    /// AI's program that changed in a way that needs the owner's yes is not started (ArisProgramApproval).
    static func run(_ process: Process) throws {
        if let asked = process.executableURL?.path, ArisAppBundle.executed(asked) != asked {
            process.executableURL = URL(fileURLWithPath: ArisAppBundle.executed(asked))
        }
        try ArisProgramApproval.check(process.executableURL)
        lock.lock()
        defer { lock.unlock() }
        try process.run()
        note(process.processIdentifier)
    }

    /// posix_spawn, with the child written down. The same arguments and result.
    static func spawn(_ pid: UnsafeMutablePointer<pid_t>, _ path: String, _ actions: UnsafePointer<posix_spawn_file_actions_t?>?,
                      _ attributes: UnsafePointer<posix_spawnattr_t?>?, _ argv: [UnsafeMutablePointer<CChar>?],
                      _ envp: [UnsafeMutablePointer<CChar>?]) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        let failed = posix_spawn(pid, path, actions, attributes, argv, envp)
        if failed == 0 { note(pid.pointee) }
        return failed
    }

    /// Writes down a child that has just been started. One that is already gone has no start time and is left out:
    /// nothing can descend from it any more.
    static func note(_ pid: pid_t, live: (pid_t) -> ArisOrigin.Live? = ArisOrigin.live) {
        guard pid > 1, let found = live(pid) else { return }
        lock.lock()
        defer { lock.unlock() }
        started[pid] = found.started
    }

    /// Whether the helper started the process with this pid and start time.
    static func isRecorded(_ pid: pid_t, started at: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return started[pid] == at
    }

    /// Whether `pid` is, or descends from, a process this helper started (the helper walks the parents itself).
    static func vouches(for pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ArisOrigin.recordedAncestor(of: pid, helper: getpid(), live: ArisOrigin.live, recorded: isRecorded) != nil
    }

    /// For the tests: the list, emptied.
    static func forgetAll() {
        lock.lock()
        defer { lock.unlock() }
        started = [:]
    }
}
