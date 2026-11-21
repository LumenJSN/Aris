//
//  ArisProcessGroup.swift
//  aris-agent
//
//  A brain child leads a process group of its own (ArisExactProcess and Foundation's Process both start it so): the
//  tools it runs (aris-tools, a shell, Peekaboo, an MCP server of Codex's) are in that group. Stopping the brain stops
//  the group. Only the group's own members are signalled, each checked by its group and by having started no earlier
//  than the brain itself, so a number the system gave to some other process since is never reached.
//  Darwin and Foundation only (the skills sandbox probe builds it with ArisProcessEnd).
//

import Darwin
import Foundation

enum ArisProcessGroup {
    /// The pids in process group `pgid`.
    static func members(_ pgid: pid_t) -> [pid_t] {
        guard pgid > 1 else { return [] }
        let bytes = proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(pgid), nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.stride + 16)
        let used = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(pgid), $0.baseAddress, Int32($0.count)) }
        guard used > 0 else { return [] }
        return pids.prefix(Int(used) / MemoryLayout<pid_t>.stride).filter { $0 > 1 }
    }

    /// The group and start time of `pid`; nil when it is gone.
    static func info(_ pid: pid_t) -> (group: pid_t, started: UInt64)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return (pid_t(info.pbi_pgid), info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }

    /// Sends `signal` to every member of group `pgid` that is still in it and started no earlier than `since` (the
    /// leader's start time). Never the helper's own group. How many were signalled.
    @discardableResult
    static func signal(_ pgid: pid_t, since: UInt64, _ signal: Int32) -> Int {
        guard pgid > 1, pgid != getpgrp() else { return 0 }
        var sent = 0
        for pid in members(pgid) where pid != getpid() {
            guard let found = info(pid), found.group == pgid, found.started >= since else { continue }
            if kill(pid, signal) == 0 { sent += 1 }
        }
        return sent
    }

    /// Whether anything of group `pgid` started since `since` is still running.
    static func alive(_ pgid: pid_t, since: UInt64) -> Bool {
        members(pgid).contains { pid in info(pid).map { $0.group == pgid && $0.started >= since } ?? false }
    }

    /// The group of a brain whose leader started at `since`: SIGTERM, up to `grace` for it to go, then SIGKILL to what is
    /// left. Blocks the caller (the helper's exit, the sweep at start).
    static func stop(_ pgid: pid_t, since: UInt64, grace: TimeInterval) {
        signal(pgid, since: since, SIGTERM)
        let until = Date().addingTimeInterval(grace)
        while alive(pgid, since: since), Date() < until { usleep(20_000) }
        signal(pgid, since: since, SIGKILL)
    }
}
