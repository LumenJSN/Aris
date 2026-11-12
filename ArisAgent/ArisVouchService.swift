//
//  ArisVouchService.swift
//  aris-agent
//
//  Where the helper answers a tool's question "did you start me?" (security review 4, M2; ArisOrigin+Vouch,
//  ArisChildren). A small listener of its own on 127.0.0.1, apart from the app's port and its queue: the helper's own
//  tool calls wait for the tool, so the tool's question must never wait behind them.
//
//  A question counts only with Aris's token, and only for the process that really holds the asking end of the
//  connection (read from the kernel, as ArisPeer does for the app): the pid in the question is checked, never
//  believed. The answer stays open until the tool has looked at who answered, then the tool closes.
//

import Darwin
import Foundation

enum ArisVouchService {
    /// How long a connection may take to ask, and how long the answer waits for the tool to close, in seconds.
    static let patience = 3
    /// After a failed start (the port is held by something else), how long until the next try.
    static let retryEvery: UInt32 = 5

    /// The answer to one question (pure): yes only for a well-formed, authenticated question about the process that
    /// holds the connection, which the helper itself started or which descends from one it started.
    enum Verdict: Equatable {
        case refused
        case answered(Bool)
    }

    static func verdict(_ request: HTTPRequest, token: String?, port: UInt16, holdsConnection: (pid_t) -> Bool, vouches: (pid_t) -> Bool) -> Verdict {
        guard let token, request.hasToken(token), request.method == "POST", request.path == ArisOrigin.vouchRoute,
              request.isLocalClient(port: Int(port)), request.isJSON, let pid = ArisOrigin.vouchedPid(body: request.body) else { return .refused }
        return .answered(holdsConnection(pid) && vouches(pid))
    }

    /// Starts listening (the socket is bound before this returns, so a child started next can already ask); the
    /// connections are taken on a thread of their own and each question is answered on a global queue. When the port
    /// is held by something else it says so once and tries again every few seconds.
    static func start(port: UInt16 = ArisOrigin.vouchPort) {
        let first = listen(on: port)
        let thread = Thread {
            var listener = first
            var told = false
            while true {
                guard listener >= 0 else {
                    if !told {
                        FileHandle.standardError.write(Data("aris-agent: can't listen on \(port) for aris-tools' questions\(ArisPeer.holderNote(ofPort: port)); aris-tools won't use Aris's permissions until it can\n".utf8))
                        told = true
                    }
                    sleep(retryEvery)
                    listener = listen(on: port)
                    continue
                }
                told = false
                accept(from: listener, port: port, token: { ClaudeHookToken.load() }, vouches: ArisChildren.vouches(for:))
                close(listener)
                listener = -1
            }
        }
        thread.name = "aris-vouch"
        thread.start()
    }

    /// A listening socket on 127.0.0.1 (`port` 0: any free port), or -1.
    static func listen(on port: UInt16) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.stride))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var address = ArisOrigin.loopback(port: port)
        let length = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) } }
        guard bound == 0, Darwin.listen(fd, 64) == 0 else {
            close(fd)
            return -1
        }
        return fd
    }

    /// Takes connections until the listener fails or is closed.
    static func accept(from listener: Int32, port: UInt16, token: @escaping @Sendable () -> String?, vouches: @escaping @Sendable (pid_t) -> Bool) {
        while true {
            var address = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
            let fd = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.accept(listener, $0, &length) } }
            if fd < 0 {
                if errno == EINTR || errno == ECONNABORTED { continue }
                return
            }
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            let asker = UInt16(bigEndian: address.sin_port)
            DispatchQueue.global(qos: .userInitiated).async {
                answer(fd, asker: asker, port: port, token: token(), vouches: vouches)
                close(fd)
            }
        }
    }

    private static func answer(_ fd: Int32, asker: UInt16, port: UInt16, token: String?, vouches: (pid_t) -> Bool) {
        var wait = timeval(tv_sec: patience, tv_usec: 0)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.stride))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &wait, socklen_t(MemoryLayout<timeval>.stride))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.stride))
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        var request: HTTPRequest?
        while request == nil, received.count <= ArisOrigin.vouchMaxBytes {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { return }
            received.append(contentsOf: buffer.prefix(count))
            switch HTTPRequestParser.parse(received, limit: { _, _, _ in ArisOrigin.vouchMaxBytes }) {
            case .complete(let parsed): request = parsed
            case .invalid: return
            case .incomplete: continue
            }
        }
        guard let request else { return }
        let found = verdict(request, token: token, port: port,
                            holdsConnection: { ArisOrigin.holdsSocket(pid: $0, localPort: asker, remotePort: port) }, vouches: vouches)
        let reply: Data
        switch found {
        case .refused: reply = ArisOrigin.vouchRefusal
        // With a yes, also whether the app is still as this helper verified it at its start (ArisOrigin+Start).
        case .answered(let vouched): reply = ArisOrigin.vouchResponse(vouched, sealed: vouched && ArisOrigin.sealStandsAsVerified())
        }
        let sent = reply.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        guard sent == reply.count else { return }
        // The tool looks at who holds this end before it closes; until then (or its patience) the connection stays.
        while recv(fd, &buffer, buffer.count, 0) > 0 {}
    }
}
