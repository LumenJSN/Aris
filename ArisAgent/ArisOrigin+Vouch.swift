//
//  ArisOrigin+Vouch.swift
//  aris-agent and aris-tools
//
//  The helper vouches for its own children (security review 4, M2). Who a process's parents are proves nothing: a
//  launchd job that is a script can start Aris's own tool in the background and then become the real aris-agent, and
//  that tool has "the genuine agent" as its parent and every grant of Aris's (measured, U2). So a tool that macOS
//  charges to Aris asks the helper itself, and the helper answers from what it knows first-hand:
//
//   · the helper writes down every process it starts (its pid and the moment it started), in the one place every
//     start goes through (ArisChildren);
//   · the tool sends its pid over a loopback connection with Aris's token; the helper looks at who really holds that
//     connection, then walks from that process up through its parents until it meets one it started, or gives up. The
//     tool is never asked who its parents are;
//   · the tool, for its part, takes the answer only from the real helper: the process holding the other end of its
//     connection is the one launchd runs under Aris's label, started as this app's aris-agent and signed as it.
//
//  A process whose parents no longer lead to the helper (it detached itself: double fork, setsid) is not vouched for.
//  The walk and the wire format are pure (tested); the probes ask the kernel.
//

import Darwin
import Foundation

extension ArisOrigin {
    /// Where the helper answers "did I start this process?": loopback only, with Aris's token. Its own small listener,
    /// not the app's port: the helper's own tool calls wait for the tool, and the tool must not wait for them.
    static let vouchPort: UInt16 = 23352
    static let vouchRoute = "/vouch"
    /// How long a tool waits for the helper's answer, in seconds.
    static let vouchTimeout = 3
    /// The most the two sides read of each other.
    static let vouchMaxBytes = 8 * 1_024

    /// A process as the kernel has it now: its parent and when it started (microseconds since 1970).
    struct Live: Equatable {
        let parent: pid_t
        let started: UInt64
    }

    // MARK: The walk (pure)

    /// The process the helper started that `pid` is, or descends from; nil when the walk reaches launchd, the helper
    /// itself, a process that is gone, or a "parent" that started after its child (a pid that was given to a newer
    /// process is not the parent). `recorded` is the helper's own list: a pid counts only with the start time it was
    /// written down with, so a later process with the same number never passes.
    static func recordedAncestor(of pid: pid_t, helper: pid_t, live: (pid_t) -> Live?, recorded: (pid_t, UInt64) -> Bool,
                                 limit: Int = ancestorLimit) -> pid_t? {
        var current = pid
        var childStarted: UInt64?
        var seen: Set<pid_t> = []
        for _ in 0...limit {
            guard current > 1, current != helper, seen.insert(current).inserted, let found = live(current) else { return nil }
            if let childStarted, found.started > childStarted { return nil }
            if recorded(current, found.started) { return current }
            childStarted = found.started
            current = found.parent
        }
        return nil
    }

    // MARK: The question and the answer (pure)

    /// The tool's question, as the HTTP request the helper's parser reads.
    static func vouchRequest(pid: pid_t, token: String, port: UInt16 = vouchPort) -> Data {
        let body = "{\"pid\":\(pid)}"
        return Data(("POST \(vouchRoute) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\(ClaudeHookToken.header): \(token)\r\n"
                     + "Content-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body).utf8)
    }

    /// The pid a question names; nil for anything else.
    static func vouchedPid(body: Data) -> pid_t? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any], object.count == 1,
              let number = object["pid"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let pid = pid_t(exactly: number), pid > 1 else { return nil }
        return pid
    }

    /// `sealed`: the helper verified the whole app at its own start and its files are as they were then
    /// (ArisOrigin+Start); said only with a yes.
    static func vouchResponse(_ vouched: Bool, sealed: Bool = false) -> Data {
        let body = vouched && sealed ? "{\"vouched\":true,\"sealed\":true}" : "{\"vouched\":\(vouched)}"
        return Data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body).utf8)
    }

    static let vouchRefusal = Data("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n".utf8)

    /// What the helper said: nil while the answer has not all arrived; true only for a whole "200" whose body says
    /// yes. Anything else (another status, other text, a yes without the 200) is a no.
    static func vouchAnswer(_ received: Data) -> Bool? { vouchReply(received)?.vouched }

    /// The helper's whole answer: whether it started this process, and whether it says the app is as it verified it.
    struct VouchReply: Equatable {
        let vouched: Bool
        let sealed: Bool
        static let no = VouchReply(vouched: false, sealed: false)
    }

    /// As `vouchAnswer`, with what the helper said about the app's seal: counted only with a yes, and only when it
    /// is plainly `true`.
    static func vouchReply(_ received: Data) -> VouchReply? {
        let terminator = Data("\r\n\r\n".utf8)
        guard let end = received.range(of: terminator) else { return received.count > vouchMaxBytes ? .no : nil }
        guard let head = String(data: received[received.startIndex..<end.lowerBound], encoding: .utf8) else { return .no }
        let lines = head.components(separatedBy: "\r\n")
        guard lines.first == "HTTP/1.1 200 OK" else { return .no }
        let lengths = lines.dropFirst().compactMap { line -> Int? in
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count == 2 && parts[0].lowercased() == "content-length" ? Int(parts[1]) : nil
        }
        guard lengths.count == 1, let length = lengths.first, length > 0, length <= vouchMaxBytes else { return .no }
        let body = received[end.upperBound...]
        guard body.count >= length else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: body.prefix(length)) as? [String: Any],
              let said = object["vouched"] as? NSNumber, CFGetTypeID(said) == CFBooleanGetTypeID() else { return .no }
        let sealed = (object["sealed"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
        return VouchReply(vouched: said.boolValue, sealed: said.boolValue && sealed)
    }

    // MARK: Probes

    /// The parent and start time of a running process; nil when there is none with that pid.
    static func live(_ pid: pid_t) -> Live? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Live(parent: pid_t(info.pbi_ppid), started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }

    /// Whether process `pid` holds a TCP socket from `localPort` to `remotePort` on 127.0.0.1 (read through libproc,
    /// as lsof does). With `remotePort` 0: a listening socket on `localPort`.
    static func holdsSocket(pid: pid_t, localPort: UInt16, remotePort: UInt16) -> Bool {
        guard pid > 0 else { return false }
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return false }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / stride)
        let used = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, bytes) }
        guard used > 0 else { return false }
        for fd in fds.prefix(Int(used) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.stride)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size, info.psi.soi_kind == SOCKINFO_TCP else { continue }
            let ends = info.psi.soi_proto.pri_tcp.tcpsi_ini
            // A listening socket has no far end: it matches on the local port alone.
            if remotePort == 0 { if socketPort(ends.insi_lport) == localPort && socketPort(ends.insi_fport) == 0 { return true } else { continue } }
            if socketPort(ends.insi_lport) == localPort && socketPort(ends.insi_fport) == remotePort
                && isLoopback(version: ends.insi_vflag, address: ends.insi_faddr.ina_46.i46a_addr4.s_addr) { return true }
        }
        return false
    }

    /// An IPv4 socket whose other end is 127.0.0.1 (`address` in network order).
    static func isLoopback(version: UInt8, address: in_addr_t) -> Bool {
        Int32(version) & INI_IPV4 != 0 && UInt32(bigEndian: address) == INADDR_LOOPBACK
    }

    private static func socketPort(_ raw: Int32) -> UInt16 {
        UInt16(bigEndian: UInt16(truncatingIfNeeded: raw))
    }

    /// Asks the helper whether it started this process or one of its parents. True only when the answer is yes and
    /// `answeredByHelper` (given this end's port, while the connection is still open) says the real helper holds the
    /// other end. Any failure (nobody listens, no answer in time, another process on the port) is a no.
    static func askHelper(pid: pid_t, token: String, port: UInt16 = vouchPort, answeredByHelper: (UInt16) -> Bool) -> Bool {
        helperReply(pid: pid, token: token, port: port, answeredByHelper: answeredByHelper).vouched
    }

    /// As `askHelper`, with what the helper said about the app's seal (counted under the same conditions as its yes).
    /// `listens`: the real helper holds the listening socket on `port` now. Asked before anything is sent: when the
    /// helper could not take the port, whoever holds it instead (it can be another account on the Mac) would be
    /// handed Aris's token with every tool start (security review 6, L4). With a no, nothing is connected or sent.
    static func helperReply(pid: pid_t, token: String, port: UInt16 = vouchPort, listens: () -> Bool = { true },
                            answeredByHelper: (UInt16) -> Bool) -> VouchReply {
        guard listens() else { return .no }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return .no }
        defer { close(fd) }
        var wait = timeval(tv_sec: vouchTimeout, tv_usec: 0)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.stride))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &wait, socklen_t(MemoryLayout<timeval>.stride))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.stride))
        var address = loopback(port: port)
        let length = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) } }
        guard connected == 0, let mine = localPort(of: fd) else { return .no }
        let question = vouchRequest(pid: pid, token: token, port: port)
        let sent = question.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        guard sent == question.count else { return .no }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            if let answer = vouchReply(received) { return answer.vouched && answeredByHelper(mine) ? answer : .no }
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { return .no }
            received.append(contentsOf: buffer.prefix(count))
        }
    }

    static func loopback(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
        return address
    }

    /// The port this end of a connected socket has.
    static func localPort(of fd: Int32) -> UInt16? {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let found = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        return found == 0 ? UInt16(bigEndian: address.sin_port) : nil
    }
}
