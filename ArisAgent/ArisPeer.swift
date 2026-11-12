//
//  ArisPeer.swift
//  aris-agent
//
//  Who is on the other end of a loopback connection. The token alone can't tell the app from a Claude Code session
//  (both hold it), so every answer to a card (POST /confirm) and every turn that may vouch for a Claude Code launch
//  (POST /ask) is taken only from the Aris app itself: the pid it names is alive with the start time it names (as for
//  background tasks), that process is the Aris app by its code signature, and it really holds this connection's other
//  end (its socket, read through libproc as lsof does).
//
//  "Is the Aris app" is asked of the process itself, through the kernel's audit token for it: signed under the app's
//  identifier by this helper's own team (ArisOrigin+Signature). It used to be whatever bundle id macOS's list of
//  running apps reported, which any bundle that calls itself com.lumenjsn.aris gets (security review 4, M5).
//

import AppKit
import Darwin

enum ArisPeer {
    static let appBundleId = "com.lumenjsn.aris"

    /// Which identity check failed (for the audit line).
    enum Failure: String, Equatable {
        case noClaim = "no pid named"
        case alive = "not alive with that start time"
        case bundle = "not the Aris app"
        case socket = "doesn't hold this connection"
        case sameConnection = "the requester's own connection"
    }

    /// Whether process `pid` holds a TCP socket from `localPort` to `remotePort` on 127.0.0.1.
    static func owns(pid: Int32, localPort: UInt16, remotePort: UInt16) -> Bool {
        ArisOrigin.holdsSocket(pid: pid, localPort: localPort, remotePort: remotePort)
    }

    /// An IPv4 socket whose other end is 127.0.0.1 (`address` in network order), where the agent listens.
    static func isLoopback(version: UInt8, address: in_addr_t) -> Bool {
        ArisOrigin.isLoopback(version: version, address: address)
    }

    /// " (held by pid N: name)" for the process listening on `port`, or "" when none can be found: for the log line
    /// when the agent's own port is taken.
    static func holderNote(ofPort port: UInt16) -> String {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return "" }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.stride + 16)
        let used = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32($0.count)) }
        for pid in pids.prefix(Int(used) / MemoryLayout<pid_t>.stride) where pid > 0 && pid != getpid() {
            guard owns(pid: pid, localPort: port, remotePort: 0) else { continue }
            var name = [CChar](repeating: 0, count: 256)
            let length = proc_name(pid, &name, UInt32(name.count))
            let shown = length > 0 ? String(cString: name) : "?"
            return " (port \(port) held by pid \(pid): \(shown))"
        }
        return ""
    }

    /// The app's id when process `pid` is signed as the Aris app (and is not one of the helper programs); else nil.
    static func bundleId(pid: Int32) -> String? {
        let signed = ArisOrigin.isSigned(pid, as: [appBundleId])
        // Until the new checks are enforced (ArisRollout), a process the signature does not show as the app is still
        // taken by what macOS's list of running apps calls it, as before, and that is written down.
        let listed = signed || ArisRollout.enforcing ? nil : NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let counted = countedBundleId(reported: appId(isSignedAsApp: signed, listed: listed, enforcing: ArisRollout.enforcing), program: ArisOrigin.program(of: pid))
        if !signed, counted == appBundleId { ArisRollout.wouldRefuse("a process as the Aris app: its signature does not say so (pid \(pid))") }
        return counted
    }

    /// The id a process counts under: the app's when its signature says so; while the new checks are not enforced,
    /// also what the list of running apps calls it.
    static func appId(isSignedAsApp: Bool, listed: String?, enforcing: Bool) -> String? {
        signedId(isSignedAsApp: isSignedAsApp) ?? (enforcing ? nil : listed)
    }

    /// What a process counts as before the helper programs are left out: the app's id only when its own code
    /// signature says so. No name it gives itself and no list of running apps is asked.
    static func signedId(isSignedAsApp: Bool) -> String? { isSignedAsApp ? appBundleId : nil }

    /// The programs that sit beside the app's own inside Aris.app (one row per permission). macOS may report the
    /// app's bundle id for them too, since they run from inside it; they are never "the Aris app itself".
    static let helperPrograms: Set<String> = ["aris-agent", "aris-tools", "ArisXPCHelper"]

    /// The bundle id a process counts under for the app check: what its signature says, except for the helper programs
    /// inside the app and for a process whose program can't be read, which count under none.
    static func countedBundleId(reported: String?, program: String?) -> String? {
        guard let program, !program.isEmpty, !helperPrograms.contains((program as NSString).lastPathComponent) else { return nil }
        return reported
    }

    /// Nil when the caller of a connection from `remotePort` to the agent's `agentPort` is the Aris app named by `pid`
    /// and `started`, and not the connection that asked for a launch (`requesterPort`); else the first check that failed.
    static func failure(pid: Int32?, started: Double?, remotePort: UInt16?, agentPort: UInt16, requesterPort: UInt16?) -> Failure? {
        guard let pid, let remotePort else { return .noClaim }
        return ArisTeammateGate.appCheck(alive: ArisTaskEnd.isAlive(pid: pid, started: started), bundleId: bundleId(pid: pid),
                                         ownsSocket: owns(pid: pid, localPort: remotePort, remotePort: agentPort),
                                         sameConnection: requesterPort == remotePort)
    }

    static func isApp(pid: Int32?, started: Double?, remotePort: UInt16?, agentPort: UInt16, requesterPort: UInt16?) -> Bool {
        failure(pid: pid, started: started, remotePort: remotePort, agentPort: agentPort, requesterPort: requesterPort) == nil
    }
}
