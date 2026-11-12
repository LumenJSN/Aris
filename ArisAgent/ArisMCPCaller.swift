//
//  ArisMCPCaller.swift
//  aris-agent
//
//  Who may use the tool bus (POST /mcp-tool): only an aris-tools started inside a brain's own process tree, during one
//  of its turns. Two checks, both needed: the call carries the turn credential that runner gave its process
//  (ARIS_MCP_TURN_FILE: random, new every turn, gone between turns), and the process holding the connection's other end
//  descends from that runner's brain process (libproc, as ArisPeer reads sockets). A Claude Code session or anything
//  else holding the agent's token has neither.
//

import Darwin
import Security
import Foundation

enum ArisMCPTurnCredential {
    /// Where the brain's aris-tools reads its turn's credential: a file the runner rewrites every turn (M1).
    static let environmentKey = "ARIS_MCP_TURN_FILE"

    /// A new 0700 folder in the temp folder, holding the (empty) 0600 credential file; nil when it can't be made.
    static func makeFile() -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-mcp-turn-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch { return nil }
        let file = folder.appendingPathComponent("turn")
        write("", to: file)
        return file
    }

    /// Writes the credential (0600, replaced whole).
    static func write(_ credential: String, to file: URL) {
        let temporary = file.deletingLastPathComponent().appendingPathComponent("turn.\(UUID().uuidString.prefix(6))")
        guard FileManager.default.createFile(atPath: temporary.path, contents: Data(credential.utf8), attributes: [.posixPermissions: 0o600]) else { return }
        if rename(temporary.path, file.path) != 0 { try? FileManager.default.removeItem(at: temporary) }
    }

    /// 32 random bytes as hex.
    static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Compared in constant time.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count, !x.isEmpty else { return false }
        return zip(x, y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// A credential's shape: 64 lowercase hex digits.
    static func isWellFormed(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}

enum ArisMCPCaller {
    /// The parent of `pid`; nil when it can't be read.
    static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    /// Whether `pid` is `root` or below it (at most 32 levels, through launchd never).
    static func descends(_ pid: pid_t, from root: pid_t, parent: (pid_t) -> pid_t? = ArisMCPCaller.parent) -> Bool {
        guard root > 1 else { return false }
        var current = pid
        for _ in 0..<32 {
            if current == root { return true }
            guard current > 1, let up = parent(current), up != current else { return false }
            current = up
        }
        return false
    }

    /// The processes below `root` (its whole tree, at most 512).
    static func tree(of root: pid_t) -> [pid_t] {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.stride + 32)
        let used = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32($0.count)) }
        let all = pids.prefix(Int(used) / MemoryLayout<pid_t>.stride).filter { $0 > 1 }
        return Array(all.filter { $0 != root && descends($0, from: root) }.prefix(512))
    }

    /// Whether the other end of a connection from `remotePort` to `agentPort` is held by a process in `root`'s tree.
    static func isInside(root: pid_t, remotePort: UInt16, agentPort: UInt16) -> Bool {
        tree(of: root).contains { ArisPeer.owns(pid: $0, localPort: remotePort, remotePort: agentPort) }
    }
}
