// Tests for the hook server that never holds Claude Code up (2026-11-12, after a QA session found 35 hook requests
// in a week that got no answer within Claude Code's 5 s). A hook event with nothing to decide is answered from the
// server's own queues at once, whatever the main thread, the consumer, a held card or a slow route is doing; a
// request is read to its end however it comes; only Claude's PermissionRequest is kept open, only while its card
// shows, and it is let go with the neutral reply the moment Aris is not going to ask; closing the server lets every
// client go. The installer registers only the events Aris uses, with short timeouts, and touches only its own hooks.
// Called from main.swift; uses its check(). The live tests run a real server on a free loopback port of their own
// (never 23350) with stand-in consumers; nothing of the user's is read or changed.
import Foundation
import Network

private let hooksToken = String(repeating: "f00d", count: 16)

// MARK: - A small HTTP client over a plain socket

private final class HooksClient {
    let fd: Int32
    private var pending = Data()

    init?(port: UInt16, timeout: Double = 5) {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var one: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard ok == 0 else { close(fd); return nil }
    }

    deinit { close(fd) }

    @discardableResult
    func write(_ data: Data) -> Bool {
        var sent = 0
        return data.withUnsafeBytes { raw -> Bool in
            while sent < data.count {
                let n = Darwin.send(fd, raw.baseAddress! + sent, data.count - sent, 0)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    struct Answer {
        let status: Int
        let head: String
        let body: Data
        var closes: Bool { head.lowercased().contains("connection: close") }
        var length: Int? { head.lowercased().components(separatedBy: "\r\n").first { $0.hasPrefix("content-length:") }.flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } }
    }

    /// The next response; nil when none came (closed, reset, or the socket's timeout).
    func answer() -> Answer? {
        let blank = Data("\r\n\r\n".utf8)
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            if let end = pending.range(of: blank) {
                let head = String(decoding: pending[pending.startIndex..<end.lowerBound], as: UTF8.self)
                let status = Int(head.split(separator: " ").dropFirst().first ?? "") ?? 0
                let length = head.lowercased().components(separatedBy: "\r\n").first { $0.hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } ?? 0
                if pending.endIndex - end.upperBound >= length {
                    let body = Data(pending[end.upperBound..<(end.upperBound + length)])
                    pending = Data(pending[(end.upperBound + length)...])
                    return Answer(status: status, head: head, body: body)
                }
            }
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { return nil }
            pending.append(contentsOf: chunk[0..<n])
        }
    }

    /// True when the server has closed the connection (nothing more comes).
    func isClosed() -> Bool {
        var byte: UInt8 = 0
        return recv(fd, &byte, 1, 0) <= 0 && errno != EAGAIN
    }
}

private func hooksNow() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }

private func hooksFreePort() -> UInt16 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) } }
    _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
    return UInt16(bigEndian: address.sin_port)
}

private func hooksEvent(_ name: String, session: String = "s1", tool: String? = "Bash", input: [String: Any] = ["command": "ls"], padding: Int = 0) -> Data {
    var object: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": "/tmp/hooks-fast"]
    if let tool { object["tool_name"] = tool }
    object["tool_input"] = padding > 0 ? ["content": String(repeating: "x", count: padding)] : input
    return try! JSONSerialization.data(withJSONObject: object)
}

private func hooksRequest(_ body: Data, path: String = "/hook", port: UInt16 = 23350, method: String = "POST", token: String? = hooksToken,
                          extra: [String] = [], length: Bool = true, type: String = "application/json") -> Data {
    var lines = ["\(method) \(path) HTTP/1.1", "Host: 127.0.0.1:\(port)", "Content-Type: \(type)"]
    if let token { lines.append("X-Aris-Token: \(token)") }
    if length { lines.append("Content-Length: \(body.count)") }
    return Data(((lines + extra).joined(separator: "\r\n") + "\r\n\r\n").utf8) + body
}

/// What the stand-in consumer was given.
private final class HooksSeen: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    private var kept: [HookHold] = []
    private var ended: [HookHold.End] = []
    private var slowReplies: [(HookReply) -> Void] = []

    var events: [String] { lock.withLock { names } }
    var holds: [HookHold] { lock.withLock { kept } }
    var ends: [HookHold.End] { lock.withLock { ended } }
    var slowCount: Int { lock.withLock { slowReplies.count } }
    func note(_ name: String) { lock.withLock { names.append(name) } }
    func keep(_ hold: HookHold) { lock.withLock { kept.append(hold) } }
    func end(_ why: HookHold.End) { lock.withLock { ended.append(why) } }
    func slow(_ reply: @escaping (HookReply) -> Void) { lock.withLock { slowReplies.append(reply) } }
    func answerSlow(_ reply: HookReply) { lock.withLock { slowReplies }.forEach { $0(reply) } }
}

/// A server on a free port. `showsCards`: the stand-in notch puts every card up (and keeps its hold); else it never does.
private func hooksServer(limits: HookLimits = .standard, seen: HooksSeen = HooksSeen(), showsCards: Bool = true, eventDelay: TimeInterval = 0,
                         token: @escaping () -> String? = { hooksToken }) -> (server: ClaudeHookServer, port: UInt16, seen: HooksSeen) {
    let port = hooksFreePort()
    let consumer = HookConsumer(
        event: { event in
            if eventDelay > 0 { Thread.sleep(forTimeInterval: eventDelay) }
            seen.note(event.name)
        },
        status: { _ in seen.note("status") },
        approval: { event, hold in
            seen.note("card:" + event.name)
            guard showsCards else { return }
            if hold.show(onEnd: { seen.end($0) }) { seen.keep(hold) } else { hold.answer(nil) }
        },
        slow: { path, _, reply in
            seen.note("slow:" + path)
            seen.slow(reply)
        })
    let server = ClaudeHookServer(port: NWEndpoint.Port(rawValue: port)!, token: token, consumer: consumer, limits: limits)
    server.start()
    for _ in 0..<200 {
        if HooksClient(port: port) != nil { break }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return (server, port, seen)
}

private func hooksWait(_ seconds: Double = 2, until done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !done(), Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
    return done()
}

/// One whole request on a new connection: the answer and how long it took, in milliseconds.
private func hooksAsk(_ port: UInt16, _ request: Data, timeout: Double = 5) -> (answer: HooksClient.Answer?, ms: Double) {
    let start = hooksNow()
    guard let client = HooksClient(port: port, timeout: timeout) else { return (nil, 0) }
    client.write(request)
    let answer = client.answer()
    return (answer, hooksNow() - start)
}

// MARK: - Reading a request (pure)

private func hooksReaderTests() {
    let body = hooksEvent("PreToolUse")
    let whole = hooksRequest(body)

    // In pieces: every prefix is "more", the whole is the request.
    let allMore = (1..<whole.count).allSatisfy { cut in
        if case .more = HookRequestReader.read(whole.prefix(cut)) { return true }
        return false
    }
    check(allMore, "a request that arrives in pieces is not answered before its Content-Length is in")
    if case .request(let request) = HookRequestReader.read(whole) {
        check(request.method == "POST" && request.path == "/hook" && request.body == body, "a whole request is read with exactly its body")
    } else { check(false, "a whole request is read with exactly its body") }

    // Big: more than one 65,536-byte read, up to the limit.
    let big = hooksEvent("PreToolUse", padding: 200_000)
    let bigWhole = hooksRequest(big)
    var fed = Data(), stillMore = true, readBig: HTTPRequest?
    for start in stride(from: 0, to: bigWhole.count, by: 65_536) {
        fed = fed + bigWhole[start..<min(start + 65_536, bigWhole.count)]
        switch HookRequestReader.read(fed) {
        case .more: break
        case .request(let request): readBig = request
        default: stillMore = false
        }
    }
    check(stillMore && readBig?.body == big, "a 200 KB body arriving in 65,536-byte reads is read whole")
    let atLimit = hooksRequest(Data(repeating: 0x20, count: HTTPRequestParser.maxBytes))
    if case .request(let request) = HookRequestReader.read(atLimit) { check(request.body.count == 1_048_576, "a body of exactly 1 MiB is read") } else { check(false, "a body of exactly 1 MiB is read") }
    let overHead = Data("POST /hook HTTP/1.1\r\nHost: 127.0.0.1:23350\r\nContent-Length: 1048577\r\n\r\n".utf8)
    if case .tooBig(let head) = HookRequestReader.read(overHead) {
        check(head.path == "/hook" && ClaudeHookRoute.isHook(head), "a body over 1 MiB is told from its head alone, before any of it arrives")
    } else { check(false, "a body over 1 MiB is told from its head alone, before any of it arrives") }

    // Two at once (pipelined, or a kept-alive connection used again): the first is read; what follows is not.
    let second = hooksRequest(hooksEvent("PostToolUse"))
    if case .request(let request) = HookRequestReader.read(whole + second) {
        check(request.body == body, "of two requests sent at once the first is read, with only its own body")
    } else { check(false, "of two requests sent at once the first is read, with only its own body") }
    if case .request(let request) = HookRequestReader.read(hooksRequest(body, extra: ["Connection: keep-alive"])) {
        check(request.headers["connection"] == "keep-alive" && request.body == body, "a keep-alive request is read like any other")
    } else { check(false, "a keep-alive request is read like any other") }
    let reply = String(decoding: HookReply.neutral.bytes, as: UTF8.self)
    check(reply.hasPrefix("HTTP/1.1 200 OK\r\n") && reply.contains("\r\nConnection: close\r\n") && reply.contains("\r\nContent-Length: 2\r\n") && reply.hasSuffix("\r\n\r\n{}"),
          "every reply closes its connection and states its body's exact length (the neutral one is {})")
    let refusal = String(decoding: HookReply.refusal("401 Unauthorized").bytes, as: UTF8.self)
    check(refusal.hasPrefix("HTTP/1.1 401 Unauthorized\r\n") && refusal.contains("Content-Length: 0") && refusal.contains("Connection: close") && refusal.hasSuffix("\r\n\r\n"),
          "a refusal has no body and closes too")

    // Malformed.
    func refused(_ text: String) -> Bool {
        if case .refuse(let status) = HookRequestReader.read(Data(text.utf8)) { return status == "400 Bad Request" }
        return false
    }
    check(refused("NONSENSE\r\n\r\n"), "a first line that isn't a request is refused")
    check(refused("POST /hook HTTP/1.1\r\nContent-Length: abc\r\n\r\n"), "a Content-Length that isn't a number is refused")
    check(refused("POST /hook HTTP/1.1\r\nContent-Length: -5\r\n\r\n"), "a negative Content-Length is refused")
    if case .refuse = HookRequestReader.read(Data([0xff, 0xfe]) + Data("\r\n\r\n".utf8)) { check(true, "a head that isn't text is refused") } else { check(false, "a head that isn't text is refused") }
    if case .refuse = HookRequestReader.read(Data(repeating: 0x41, count: HTTPRequestParser.maxHeadBytes + 1)) { check(true, "a head that doesn't end in 64 KiB is refused") }
    else { check(false, "a head that doesn't end in 64 KiB is refused") }
    check(HookRequestReader.read(Data()) == .more(wantsContinue: false) && HookRequestReader.read(Data("POST /hook HT".utf8)) == .more(wantsContinue: false),
          "nothing yet, or half a head, waits for more")

    // Expect: 100-continue.
    let expecting = hooksRequest(body, extra: ["Expect: 100-continue"])
    let headOnly = expecting.prefix(expecting.count - body.count)
    check(HookRequestReader.read(headOnly) == .more(wantsContinue: true), "a client that waits for 100 Continue is told to go on once its head is in")
    check(HookRequestReader.read(headOnly.dropLast(4)) == .more(wantsContinue: false), "not before the head is all there")
    check(HookRequestReader.read(whole.prefix(whole.count - 5)) == .more(wantsContinue: false), "and a client that didn't ask is not told")
    if case .request(let request) = HookRequestReader.read(expecting) { check(request.body == body, "with its body in, the request that asked for 100 Continue is read") }
    else { check(false, "with its body in, the request that asked for 100 Continue is read") }

    // Chunked.
    func chunked(_ pieces: [Data], sizeSuffix: String = "", trailer: String = "") -> Data {
        var wire = hooksRequest(Data(), extra: ["Transfer-Encoding: chunked"], length: false)
        for piece in pieces { wire += Data("\(String(piece.count, radix: 16))\(sizeSuffix)\r\n".utf8) + piece + Data("\r\n".utf8) }
        return wire + Data("0\r\n\(trailer)\r\n".utf8)
    }
    let half = body.count / 2
    let inChunks = chunked([body.prefix(half), body.suffix(from: half)])
    if case .request(let request) = HookRequestReader.read(inChunks) { check(request.body == body, "a body sent in chunks is put together") }
    else { check(false, "a body sent in chunks is put together") }
    let chunkedMore = (1..<inChunks.count).allSatisfy { cut in
        if case .more = HookRequestReader.read(inChunks.prefix(cut)) { return true }
        return false
    }
    check(chunkedMore, "a chunked body in pieces is not answered before its last chunk is in")
    if case .request(let request) = HookRequestReader.read(chunked([body], sizeSuffix: ";name=value", trailer: "X-Trailer: 1\r\n")) {
        check(request.body == body, "chunk extensions and trailers are read past")
    } else { check(false, "chunk extensions and trailers are read past") }
    let badSize = hooksRequest(Data(), extra: ["Transfer-Encoding: chunked"], length: false) + Data("zz\r\nabc\r\n0\r\n\r\n".utf8)
    if case .refuse = HookRequestReader.read(badSize) { check(true, "a chunk size that isn't hexadecimal is refused") } else { check(false, "a chunk size that isn't hexadecimal is refused") }
    let badEnd = hooksRequest(Data(), extra: ["Transfer-Encoding: chunked"], length: false) + Data("3\r\nabcXX0\r\n\r\n".utf8)
    if case .refuse = HookRequestReader.read(badEnd) { check(true, "a chunk that doesn't end where its size says is refused") } else { check(false, "a chunk that doesn't end where its size says is refused") }
    let hugeChunk = hooksRequest(Data(), extra: ["Transfer-Encoding: chunked"], length: false) + Data("100001\r\n".utf8)
    if case .tooBig = HookRequestReader.read(hugeChunk) { check(true, "chunks adding up to more than 1 MiB are too big, told from the size line") } else { check(false, "chunks adding up to more than 1 MiB are too big, told from the size line") }

    // The parser the agent shares is unchanged: its head is the same head.
    if case .complete(let head) = HTTPRequestParser.head(whole), case .complete(let request) = HTTPRequestParser.parse(whole) {
        check(head.method == request.method && head.path == request.path && head.headers == request.headers && whole.count - head.bodyStart == body.count,
              "the parser's head is the request's own method, path and headers, and says where the body starts")
    } else { check(false, "the parser's head is the request's own method, path and headers, and says where the body starts") }
    check(HTTPRequestParser.head(whole.prefix(20)) == .incomplete && HTTPRequestParser.parse(whole.prefix(whole.count - 1)) == .incomplete,
          "an unfinished head, and an unfinished body, are both incomplete to the parser")
}

// MARK: - What a request is for (pure)

private func hooksRouteTests() {
    func parsed(_ data: Data) -> HTTPRequest {
        if case .request(let request) = HookRequestReader.read(data) { return request }
        return HTTPRequest(method: "", path: "", body: Data())
    }
    func action(_ data: Data, token: String? = hooksToken) -> HookAction { ClaudeHookRoute.decide(parsed(data), token: token) }
    func refusedWith(_ status: String, _ action: HookAction) -> Bool {
        if case .refuse(let reply, _) = action { return reply.status == status && reply.body.isEmpty }
        return false
    }
    let tool = hooksEvent("PreToolUse")

    check(refusedWith("401 Unauthorized", action(hooksRequest(tool, token: nil))), "no token is refused 401")
    check(refusedWith("401 Unauthorized", action(hooksRequest(tool, token: String(repeating: "0", count: 64)))), "a wrong token is refused 401")
    check(refusedWith("401 Unauthorized", action(hooksRequest(tool), token: nil)), "with no token file every request is refused (fails closed)")
    check(refusedWith("401 Unauthorized", action(hooksRequest(tool, token: nil, extra: ["Origin: https://evil.example"]))), "the token is checked first")
    check(refusedWith("400 Bad Request", action(hooksRequest(tool, extra: ["Origin: https://evil.example"]))), "a page's request (any Origin) is refused")
    check(refusedWith("400 Bad Request", action(hooksRequest(tool, extra: []).replacing("Host: 127.0.0.1:23350", with: "Host: evil.example:23350"))), "a Host that isn't this listener is refused")
    check(refusedWith("400 Bad Request", action(hooksRequest(tool, method: "GET"))), "anything but POST is refused")
    check(refusedWith("400 Bad Request", action(hooksRequest(tool, path: "/other"))), "an unknown path is refused")
    check(refusedWith("400 Bad Request", action(hooksRequest(tool, type: "text/plain"))), "a body that isn't declared JSON is refused")
    check(refusedWith("400 Bad Request", action(hooksRequest(Data("not json".utf8)))), "a body that isn't JSON is refused")
    check(refusedWith("400 Bad Request", action(hooksRequest(Data("{\"a\":1}".utf8)))), "JSON that isn't a hook event is refused")
    if case .event(let event) = action(hooksRequest(tool).replacing("X-Aris-Token", with: "X-Boring-Notch-Token")) { check(event.name == "PreToolUse", "hooks installed before the rename (the old header) still get in") }
    else { check(false, "hooks installed before the rename (the old header) still get in") }
    if case .event(let event) = ClaudeHookRoute.decide(parsed(hooksRequest(tool, port: 40123)), token: hooksToken, port: 40123) { check(event.name == "PreToolUse", "the Host is checked against the port the server listens on") }
    else { check(false, "the Host is checked against the port the server listens on") }

    let noDecision = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Stop", "StopFailure",
                      "SubagentStart", "SubagentStop", "Notification", "PreCompact"]
    let allEvents = noDecision.allSatisfy { name in
        if case .event(let event) = action(hooksRequest(hooksEvent(name))) { return event.name == name && !event.needsDecision }
        return false
    }
    check(allEvents, "every hook event but the permission request needs no decision: it is answered at once (PreToolUse too: Aris never allows or denies a tool here)")
    if case .approval(let event) = action(hooksRequest(hooksEvent("PermissionRequest"))) { check(event.needsDecision && event.agent == "claude", "Claude's PermissionRequest is the one request that waits for a card") }
    else { check(false, "Claude's PermissionRequest is the one request that waits for a card") }
    let fromCodex = action(hooksRequest(hooksEvent("PermissionRequest"), extra: ["X-Agent: codex"]))
    if case .event(let event) = fromCodex { check(event.agent == "codex", "Codex's permission request is only told: it asks in its own terminal") } else { check(false, "Codex's permission request is only told: it asks in its own terminal") }
    if case .status(let object) = action(hooksRequest(Data("{\"session_id\":\"s\"}".utf8), path: "/status")) { check(object["session_id"] as? String == "s", "the status line's report is taken with its JSON") }
    else { check(false, "the status line's report is taken with its JSON") }
    let slow = ["/aris/todos", "/aris/events"].allSatisfy { path in
        if case .slow(let found, let body) = action(hooksRequest(Data("{\"op\":\"list\"}".utf8), path: path)) { return found == path && body["op"] as? String == "list" }
        return false
    }
    check(slow, "aris-tools' todo and event requests go to the app's slow routes with their JSON")
    check(ClaudeHookRoute.opensHook(Data("POST /hook HTTP/1.1\r\nHo".utf8)) && !ClaudeHookRoute.opensHook(Data("POST /hooks HTTP/1.1".utf8)) && !ClaudeHookRoute.opensHook(Data("POST /aris/todos ".utf8)),
          "a request that opens with POST /hook is known as a hook event before it is all in")
}

private extension Data {
    func replacing(_ old: String, with new: String) -> Data {
        Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: old, with: new).utf8)
    }
}

// MARK: - A held request (pure)

private func hooksHoldTests() {
    final class Replies: @unchecked Sendable {
        private let lock = NSLock()
        private var sent: [Data?] = []
        var all: [Data?] { lock.withLock { sent } }
        func add(_ body: Data?) { lock.withLock { sent.append(body) } }
    }
    func hold() -> (HookHold, Replies) {
        let replies = Replies()
        return (HookHold { replies.add($0) }, replies)
    }
    let allow = Data("{\"allow\":true}".utf8)

    var (h, r) = hold()
    var ends: [HookHold.End] = []
    check(h.show(onEnd: { ends.append($0) }) && h.isShown && !h.isOver, "a hold whose card went up is shown and open")
    h.answer(allow)
    h.answer(nil)
    check(!h.end(.timedOut) && r.all.count == 1 && r.all[0] == allow && ends.isEmpty && h.isOver, "the card's answer is sent once; nothing after it counts and the card is not dropped twice")

    (h, r) = hold()
    ends = []
    _ = h.show(onEnd: { ends.append($0) })
    check(h.end(.timedOut) && r.all.count == 1 && r.all[0] == nil && ends == [.timedOut], "a card whose time passed gets the neutral reply and is taken down")
    h.answer(allow)
    check(r.all.count == 1, "an answer after that is not sent")

    (h, r) = hold()
    check(h.end(.notShown) && r.all.count == 1 && r.all[0] == nil, "a hold whose card never went up is let go with the neutral reply")
    check(!h.show(onEnd: { _ in }), "and the notch, arriving late, is told to show no card")

    (h, r) = hold()
    ends = []
    _ = h.show(onEnd: { ends.append($0) })
    check(!h.end(.notShown) && r.all.isEmpty && !h.isOver, "the not-shown limit does nothing to a card that is up")
    check(h.end(.clientGone) && ends == [.clientGone], "a client that went away takes its card down")

    (h, r) = hold()
    ends = []
    _ = h.show(onEnd: { ends.append($0) })
    check(h.end(.serverClosing) && r.all.count == 1 && r.all[0] == nil && ends == [.serverClosing], "the server closing lets a held request go with the neutral reply")

    let limits = HookLimits.standard
    check(limits.answer == 0.15 && limits.read == 1 && limits.cardShown == 3 && limits.slow == 20 && limits.linger == 1,
          "the limits: 150 ms to answer an event, 1 s for a request to arrive, 3 s for a card to go up, 20 s for a to-do or event route")
    check(limits.card == ArisCardEdit.questionTimeout && limits.card == 120, "a card keeps its request open as long as Aris's own cards wait: 120 s")
    let counts = HookCounts().counting(.late).counting(.late).counting(.answered).counting(.cardNotShown)
    check(counts.late == 2 && counts.answered == 1 && counts.cardNotShown == 1 && counts.unread == 0 && HookCounts().late == 0,
          "late answers and cards not shown are counted, each count a new value")
}

// MARK: - The live server

private func hooksLiveTests() {
    // An event with nothing to decide.
    do {
        let (server, port, seen) = hooksServer()
        let (answer, ms) = hooksAsk(port, hooksRequest(hooksEvent("PreToolUse"), port: port))
        check(answer?.status == 200 && answer?.body == Data("{}".utf8) && answer?.closes == true && answer?.length == 2,
              "a hook event is answered 200 {} with its length and Connection: close")
        check(ms < 400, "and at once (\(Int(ms)) ms)")
        check(hooksWait { seen.events == ["PreToolUse"] }, "and the event reaches the consumer")
        check(hooksAsk(port, hooksRequest(Data("{\"session_id\":\"s\"}".utf8), path: "/status", port: port)).answer?.status == 200 && hooksWait { seen.events.contains("status") },
              "a status report is answered 200 and passed on")
        check(hooksWait { server.openConnections == 0 }, "answered connections are closed and forgotten")
        check(server.stats.counts.answered == 1 && server.stats.counts.late == 0, "an ordinary answer is counted as answered, not late")
        server.stop()
    }

    // A stalled consumer.
    do {
        let (server, port, seen) = hooksServer(eventDelay: 0.6)
        let names = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"]
        let times = names.map { hooksAsk(port, hooksRequest(hooksEvent($0), port: port)) }
        check(times.allSatisfy { $0.answer?.status == 200 && $0.ms < 400 }, "a stalled consumer does not delay the reply (four events, each consumer call 600 ms: slowest answer \(Int(times.map(\.ms).max() ?? 0)) ms)")
        check(seen.events.count < 4, "the replies were out before the consumer had the events")
        check(hooksWait(6) { seen.events.count == 4 } && seen.events == names, "and the consumer still gets every event, in the order they came")
        server.stop()
    }

    // A held PermissionRequest and a slow route.
    do {
        let (server, port, seen) = hooksServer()
        let card = HooksClient(port: port)
        card?.write(hooksRequest(hooksEvent("PermissionRequest", tool: "Bash"), port: port))
        check(hooksWait { seen.holds.count == 1 && seen.holds[0].isShown }, "a PermissionRequest is held while its card shows")
        let todo = HooksClient(port: port)
        todo?.write(hooksRequest(Data("{\"op\":\"list\"}".utf8), path: "/aris/todos", port: port))
        check(hooksWait { seen.slowCount == 1 }, "a to-do request waits for the app")
        let half = HooksClient(port: port)
        half?.write(hooksRequest(hooksEvent("PreToolUse"), port: port).prefix(60))
        let times = (0..<20).map { _ in hooksAsk(port, hooksRequest(hooksEvent("PreToolUse"), port: port)) }
        check(times.allSatisfy { $0.answer?.status == 200 && $0.ms < 400 },
              "a held PermissionRequest, a waiting to-do request and a half-sent request do not delay a PreToolUse (slowest of 20: \(Int(times.map(\.ms).max() ?? 0)) ms)")
        // The card's answer goes back on its own connection.
        let allow = ClaudeDecision.allow.responseBody(input: [:])!
        seen.holds[0].answer(allow)
        let decided = card?.answer()
        check(decided?.status == 200 && decided?.body == allow && decided?.closes == true, "the card's answer goes back on the held connection, which then closes")
        seen.answerSlow(.ok(Data("{\"ok\":true}".utf8)))
        check(todo?.answer()?.body == Data("{\"ok\":true}".utf8), "the to-do request gets the app's answer when it comes")
        server.stop()
        check(half?.answer()?.status == 200 || half?.isClosed() == true, "stopping the server lets a half-sent request's client go")
    }

    // The notch never puts the card up (a stalled main thread).
    do {
        var limits = HookLimits.standard
        limits.cardShown = 0.2
        let (server, port, seen) = hooksServer(limits: limits, showsCards: false)
        let (answer, ms) = hooksAsk(port, hooksRequest(hooksEvent("PermissionRequest"), port: port))
        check(answer?.status == 200 && answer?.body == Data("{}".utf8) && ms >= 150 && ms < 1_000,
              "a card the notch doesn't put up in time is let go with the neutral reply (\(Int(ms)) ms for a 200 ms limit)")
        check(server.stats.counts.cardNotShown == 1 && seen.events == ["card:PermissionRequest"], "and counted")
        server.stop()
    }

    // The card's own time, and a client that goes away.
    do {
        var limits = HookLimits.standard
        limits.card = 0.3
        let (server, port, seen) = hooksServer(limits: limits)
        let (answer, ms) = hooksAsk(port, hooksRequest(hooksEvent("PermissionRequest"), port: port))
        check(answer?.status == 200 && answer?.body == Data("{}".utf8) && ms >= 250 && ms < 1_500, "a card unanswered for its whole time is let go with the neutral reply (\(Int(ms)) ms for a 300 ms limit)")
        check(hooksWait { seen.ends == [.timedOut] } && server.stats.counts.cardTimedOut == 1, "and its card is taken down")
        server.stop()
    }
    do {
        let (server, port, seen) = hooksServer()
        var client = HooksClient(port: port)
        client?.write(hooksRequest(hooksEvent("PermissionRequest"), port: port))
        check(hooksWait { seen.holds.count == 1 }, "a card is up for a waiting client")
        client = nil
        check(hooksWait { seen.ends == [.clientGone] }, "a client that goes away (answered in the terminal, or its session quit) takes its card down")
        check(hooksWait { server.openConnections == 0 }, "and its connection is closed")
        server.stop()
    }

    // Closing the server.
    do {
        let (server, port, seen) = hooksServer()
        let cards = (0..<3).compactMap { _ -> HooksClient? in
            let client = HooksClient(port: port, timeout: 3)
            client?.write(hooksRequest(hooksEvent("PermissionRequest"), port: port))
            return client
        }
        let todo = HooksClient(port: port, timeout: 3)
        todo?.write(hooksRequest(Data("{\"op\":\"list\"}".utf8), path: "/aris/todos", port: port))
        let idle = HooksClient(port: port, timeout: 3)
        check(hooksWait { seen.holds.count == 3 && seen.slowCount == 1 && server.openConnections == 5 }, "three cards, a to-do request and an idle connection are open")
        let start = hooksNow()
        server.stop()
        let answers = cards.map { $0.answer() }
        check(answers.allSatisfy { $0?.status == 200 && $0?.body == Data("{}".utf8) }, "closing the server answers every held PermissionRequest with the neutral reply")
        check(todo?.answer()?.status == 503, "a to-do request in flight is told the server is going (503), never left waiting")
        check(idle?.isClosed() == true, "an idle connection is closed")
        check(hooksNow() - start < 1_000, "all of it within a second (\(Int(hooksNow() - start)) ms)")
        check(hooksWait { seen.ends.count == 3 && seen.ends.allSatisfy { $0 == .serverClosing } }, "and the cards are taken down")
        check(hooksWait { HooksClient(port: port) == nil }, "the port is closed: a new client fails at once")
        check(server.stats.counts.closedByServer == 5, "the connections closed by the server are counted")
    }

    // Deadlines.
    do {
        var limits = HookLimits.standard
        limits.read = 0.2
        let (server, port, _) = hooksServer(limits: limits)
        let hook = HooksClient(port: port)
        let whole = hooksRequest(hooksEvent("PreToolUse"), port: port)
        hook?.write(whole.prefix(whole.count - 10))
        let other = HooksClient(port: port)
        other?.write(hooksRequest(Data("{\"op\":\"list\"}".utf8), path: "/aris/todos", port: port).prefix(40))
        let start = hooksNow()
        let late = hook?.answer()
        check(late?.status == 200 && late?.body == Data("{}".utf8) && hooksNow() - start < 1_000, "a hook event that doesn't arrive in time gets the neutral reply and its connection is closed")
        check(other?.answer()?.status == 408, "anything else that doesn't arrive in time is refused 408")
        check(server.stats.counts.unread == 2, "both are counted")
        server.stop()
    }
    do {
        var limits = HookLimits.standard
        limits.answer = 0.1
        let slowToken = HooksSeen()
        let (server, port, seen) = hooksServer(limits: limits, token: {
            if slowToken.events.isEmpty { slowToken.note("read"); Thread.sleep(forTimeInterval: 0.5) }
            return hooksToken
        })
        let (answer, ms) = hooksAsk(port, hooksRequest(hooksEvent("PreToolUse"), port: port))
        check(answer?.status == 200 && answer?.body == Data("{}".utf8) && ms < 400, "an answer that isn't out in the limit goes out neutral anyway (a 500 ms token read, a 100 ms limit: \(Int(ms)) ms)")
        check(server.stats.counts.late == 1, "and is counted as late")
        check(hooksWait { seen.events == ["PreToolUse"] }, "the event still reaches the consumer once the token is checked")
        let card = HooksClient(port: port)
        card?.write(hooksRequest(hooksEvent("PermissionRequest"), port: port))
        let up = hooksWait { seen.holds.count == 1 }
        Thread.sleep(forTimeInterval: 0.3)
        check(up && seen.holds.first?.isOver == false, "a card is not cut short by the 100 ms limit")
        server.stop()
    }
    do {
        var limits = HookLimits.standard
        limits.slow = 0.3
        let (server, port, _) = hooksServer(limits: limits)
        let (answer, ms) = hooksAsk(port, hooksRequest(Data("{\"op\":\"list\"}".utf8), path: "/aris/todos", port: port))
        check(answer?.status == 504 && ms < 1_500 && server.stats.counts.slowTimedOut == 1, "a to-do route that never answers is closed with 504 at its limit")
        server.stop()
    }

    // Over the wire: the checks, big bodies, 100 Continue, chunks, two at once.
    do {
        let (server, port, seen) = hooksServer()
        check(hooksAsk(port, hooksRequest(hooksEvent("PreToolUse"), port: port, token: "wrong")).answer?.status == 401, "a wrong token is refused 401 over the wire")
        check(hooksAsk(port, hooksRequest(hooksEvent("PreToolUse"), port: port, extra: ["Origin: https://evil.example"])).answer?.status == 400, "a page's request is refused 400 over the wire")
        check(hooksAsk(port, hooksRequest(hooksEvent("PreToolUse"), port: 23350)).answer?.status == 400, "a Host naming another port is refused")
        check(seen.events.isEmpty, "none of them reaches the consumer")

        let big = hooksAsk(port, hooksRequest(hooksEvent("PreToolUse", padding: 200_000), port: port))
        check(big.answer?.status == 200 && big.ms < 500, "a 200 KB event is read and answered (\(Int(big.ms)) ms)")
        let over = hooksRequest(hooksEvent("PreToolUse", padding: 1_100_000), port: port)
        let tooBig = hooksAsk(port, over)
        check(tooBig.answer?.status == 200 && tooBig.answer?.body == Data("{}".utf8) && tooBig.ms < 1_500, "an event over 1 MiB gets the neutral reply without being read")
        check(hooksAsk(port, hooksRequest(Data(repeating: 0x20, count: 1_100_000), path: "/aris/todos", port: port)).answer?.status == 413, "anything else over 1 MiB is refused 413")
        check(hooksAsk(port, hooksRequest(hooksEvent("PreToolUse", padding: 1_100_000), port: port, token: "wrong")).answer?.status == 413, "and so is an oversized event without the token")
        check(server.stats.counts.tooBig == 3, "bodies over the limit are counted")

        let body = hooksEvent("PostToolUse")
        let expecting = hooksRequest(body, port: port, extra: ["Expect: 100-continue"])
        let waiting = HooksClient(port: port)
        waiting?.write(expecting.prefix(expecting.count - body.count))
        check(waiting?.answer()?.status == 100, "a client that waits for 100 Continue is told to go on")
        waiting?.write(body)
        check(waiting?.answer()?.status == 200, "and is answered once its body is in")

        var chunkedWire = hooksRequest(Data(), port: port, extra: ["Transfer-Encoding: chunked"], length: false)
        chunkedWire += Data("\(String(body.count, radix: 16))\r\n".utf8) + body + Data("\r\n0\r\n\r\n".utf8)
        check(hooksAsk(port, chunkedWire).answer?.status == 200, "a chunked event is read and answered")

        let pair = HooksClient(port: port, timeout: 2)
        let one = hooksRequest(hooksEvent("Stop"), port: port)
        pair?.write(one + one)
        let first = pair?.answer()
        check(first?.status == 200 && first?.closes == true && pair?.answer() == nil,
              "of two requests sent at once the first is answered with Connection: close and the connection closes: the second is never left waiting")
        check(hooksWait { seen.events.filter { $0 == "Stop" }.count == 1 && seen.events.contains("PostToolUse") }, "only what was answered reaches the consumer")
        server.stop()
    }
}

// MARK: - Cards and the Claude store

@MainActor private func hooksStoreTests() {
    // The chimes stay off here (nothing is written: the registration lasts only for this run).
    UserDefaults.standard.register(defaults: ["claudeSounds": false])
    func pump(_ seconds: Double = 1, until done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        return done()
    }
    final class Replies: @unchecked Sendable {
        private let lock = NSLock()
        private var sent: [Data?] = []
        var all: [Data?] { lock.withLock { sent } }
        func add(_ body: Data?) { lock.withLock { sent.append(body) } }
    }
    func permission(_ input: [String: Any] = ["command": "rm -rf build"]) -> ClaudeHookEvent {
        ClaudeHookEvent(json: ["hook_event_name": "PermissionRequest", "session_id": "s1", "cwd": "/tmp/p", "tool_name": "Bash", "tool_input": input])!
    }

    var store = ClaudeStore()
    var replies = Replies()
    var hold = HookHold { [replies] in replies.add($0) }
    store.take(permission(), hold: hold)
    check(store.approvals.count == 1 && store.approvals[0].toolName == "Bash" && store.approvals[0].summary == "rm -rf build" && hold.isShown && store.sessions["s1"]?.state == .notification,
          "a held PermissionRequest becomes a card, and its session shows it is asking")
    store.decide(store.approvals[0].id, .allow)
    let allowed = replies.all.first.flatMap { $0 }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    check(replies.all.count == 1 && ((allowed?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])?["behavior"] as? String == "allow" && store.approvals.isEmpty,
          "the card's answer is what the held request gets")

    store = ClaudeStore()
    replies = Replies()
    hold = HookHold { [replies] in replies.add($0) }
    store.take(permission(), hold: hold, cardPossible: false)
    check(store.approvals.isEmpty && replies.all.count == 1 && replies.all[0] == nil && store.sessions["s1"] != nil,
          "with no card possible (the Mac locked, its display asleep) the request gets the neutral reply at once and no card goes up")

    store = ClaudeStore()
    replies = Replies()
    hold = HookHold { [replies] in replies.add($0) }
    hold.end(.notShown)
    store.take(permission(), hold: hold)
    check(store.approvals.isEmpty && replies.all.count == 1, "a notch that gets to the request after the server let it go shows no card")

    // Answered in the terminal: the same call finishing, or the turn ending.
    store = ClaudeStore()
    replies = Replies()
    hold = HookHold { [replies] in replies.add($0) }
    store.take(permission(), hold: hold)
    store.apply(ClaudeHookEvent(json: ["hook_event_name": "PostToolUse", "session_id": "s1", "cwd": "/tmp/p", "tool_name": "Bash", "tool_input": ["command": "rm -rf build"]])!)
    check(store.approvals.isEmpty && replies.all.count == 1 && replies.all[0] == nil && hold.isOver,
          "a card answered in the terminal lets its request go with the neutral reply (it used to stay open until Claude Code's own timeout)")
    replies = Replies()
    hold = HookHold { [replies] in replies.add($0) }
    store.take(permission(), hold: hold)
    store.apply(ClaudeHookEvent(json: ["hook_event_name": "Stop", "session_id": "s1", "cwd": "/tmp/p"])!)
    check(store.approvals.isEmpty && replies.all.count == 1 && replies.all[0] == nil, "and so does the turn ending")

    // Esc hands the question to the terminal: no decision.
    store = ClaudeStore()
    replies = Replies()
    hold = HookHold { [replies] in replies.add($0) }
    store.take(permission(), hold: hold)
    store.decide(store.approvals[0].id, .passthrough)
    check(replies.all.count == 1 && replies.all[0] == nil, "handing a card to the terminal answers its request with no decision")

    // The hold ends on its own: the card comes down.
    for why in [HookHold.End.timedOut, .clientGone, .serverClosing] {
        store = ClaudeStore()
        replies = Replies()
        hold = HookHold { [replies] in replies.add($0) }
        store.take(permission(), hold: hold)
        let wasUp = store.approvals.count == 1
        hold.end(why)
        check(wasUp && pump { store.approvals.isEmpty } && replies.all.count == 1, "a hold that ends (\(why)) takes its card down, and the request was answered once")
    }

    // A dropped card never sends a decision; its held request is let go once, and not after an answer.
    store = ClaudeStore()
    var decisions: [ClaudeDecision] = []
    var dropped = 0
    let approval = ClaudeApproval(id: UUID(), sessionId: "s", cwd: "/p", toolName: "Bash", summary: "ls", kind: .tool)
    store.requestApproval(approval, resolve: { decisions.append($0) }, onDrop: { dropped += 1 })
    store.cancelApproval(approval.id)
    store.cancelApproval(approval.id)
    check(decisions.isEmpty && dropped == 1, "a dropped card sends no decision and lets its request go once")
    dropped = 0
    let second = ClaudeApproval(id: UUID(), sessionId: "s", cwd: "/p", toolName: "Bash", summary: "ls", kind: .tool)
    store.requestApproval(second, resolve: { decisions.append($0) }, onDrop: { dropped += 1 })
    store.decide(second.id, .deny)
    store.cancelApproval(second.id)
    check(decisions.count == 1 && dropped == 0, "a card already answered is not let go again when it is dropped")
}

// MARK: - The main thread wedged (QA BUG-37: Aris hung whole for 8 and 7 minutes on 2026-11-09)

/// The app's own wiring (HookConsumer.feeding, a real ClaudeStore) with the main thread kept from running anything:
/// this function is on it and never lets the main queue run until its last lines.
@MainActor private func hooksWedgedMainTests() {
    UserDefaults.standard.register(defaults: ["claudeSounds": false])
    let store = ClaudeStore()
    var applied: [String] = []
    store.onEvent = { event, _ in applied.append(event.name) }
    var limits = HookLimits.standard
    limits.cardShown = 0.3
    let port = hooksFreePort()
    let consumer = HookConsumer.feeding({ store }, slow: { _, _, reply in reply(.refusal("503 Service Unavailable")) })
    let server = ClaudeHookServer(port: NWEndpoint.Port(rawValue: port)!, token: { hooksToken }, consumer: consumer, limits: limits)
    server.start()
    for _ in 0..<200 {
        if HooksClient(port: port) != nil { break }
        Thread.sleep(forTimeInterval: 0.01)
    }

    let names = (0..<10).flatMap { _ in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"] }
    let times = names.map { hooksAsk(port, hooksRequest(hooksEvent($0), port: port)) }
    check(times.allSatisfy { $0.answer?.status == 200 && $0.answer?.body == Data("{}".utf8) && $0.ms < 400 },
          "with the main thread wedged every hook event is still answered 200 {} at once (40 events, slowest \(Int(times.map(\.ms).max() ?? 0)) ms)")
    check(applied.isEmpty && store.sessions.isEmpty, "nothing reached the store meanwhile: the main thread really ran nothing")
    let (card, ms) = hooksAsk(port, hooksRequest(hooksEvent("PermissionRequest"), port: port))
    check(card?.status == 200 && card?.body == Data("{}".utf8) && ms >= 250 && ms < 1_500,
          "with the main thread wedged a PermissionRequest gets the neutral reply at the card-did-not-come-up bound (\(Int(ms)) ms for a 300 ms bound)")
    check(server.stats.counts.cardNotShown == 1 && server.stats.counts.late == 0 && server.stats.counts.answered == 40, "counted as a card not shown; no event was late")
    let after = hooksAsk(port, hooksRequest(hooksEvent("PreToolUse"), port: port))
    check(after.answer?.status == 200 && after.ms < 400, "and events keep being answered after it")

    // The main thread comes back.
    let deadline = Date().addingTimeInterval(3)
    while applied.count < 42, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    check(applied == names + ["PermissionRequest", "PreToolUse"], "when the main thread comes back the store gets every event, in the order they came")
    check(store.approvals.isEmpty, "and the card whose request was already let go is not shown late")
    server.stop()
}

// MARK: - The installer's event set

private func hooksInstallerTests() {
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/install-claude-hooks.py")
    guard let text = try? String(contentsOf: script, encoding: .utf8) else {
        check(false, "install-claude-hooks.py is beside the tests folder (\(script.path))")
        return
    }
    func list(_ name: String) -> [String] {
        guard let start = text.range(of: "\n\(name) = ["), let end = text.range(of: "]", range: start.upperBound..<text.endIndex) else { return [] }
        return text[start.upperBound..<end.lowerBound].split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n\"")) }.filter { !$0.isEmpty }
    }
    let events = list("EVENTS"), retired = list("RETIRED_EVENTS")
    check(events == ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Stop", "StopFailure",
                     "Notification", "PreCompact", "PermissionRequest"],
          "the installer registers the eleven events Aris uses")
    check(retired == ["SubagentStart", "SubagentStop"], "and takes its own hooks off the two it no longer uses (a subagent's start and stop)")
    check(Set(events).isDisjoint(with: retired), "no event is both registered and retired")
    check(ArisClaudeHookCheck.needed.allSatisfy(events.contains), "the events a teammate's job waits on (its session's start and Stop) are registered")
    // SessionEnd has no state of its own: it takes the session's row away.
    check(events.allSatisfy { $0 == "SessionEnd" || ClaudeHookEvent(json: ["hook_event_name": $0, "session_id": "s", "notification_type": "permission_prompt"])?.claudeState != nil },
          "every registered event changes what the notch shows")
    check(text.contains("\nEVENT_TIMEOUT = 2\n") && text.contains("\nPERMISSION_TIMEOUT = 130\n"), "an event's hook waits 2 s at most, the permission request 130 s")
    check(130 > HookLimits.standard.card && 130 - HookLimits.standard.card <= 15, "the permission request's timeout is just past the card's own time, so Aris's neutral reply comes first")
    check(HookLimits.standard.read < 2 && HookLimits.standard.answer < 2, "the server's own limits are inside the hook's timeout: its answer, even a late one, comes first")
    check(text.contains("URL = \"\(ArisUninstallCleanup.hookURL)\""), "the installer's hooks are the ones uninstall and the hook check recognise: by their URL")
}

// MARK: - By construction: what the server's own files may touch

private func hooksSourceTests() {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Aris/private/Claude")
    func source(_ name: String) -> String { (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    let own = ["ClaudeHookServer.swift", "ClaudeHookConnection.swift", "ClaudeHookRoute.swift", "ClaudeHookWire.swift", "ClaudeHookHold.swift"].map(source)
    check(own.allSatisfy { !$0.isEmpty }, "the server's five files are there")
    let waits = ["MainActor", "DispatchQueue.main", "ClaudeStore", "EventKit", "ArisAgentClient", "ArisTodoRoute", "ArisEventRoute", "await ", ".sync {"]
    let touched = waits.filter { word in own.dropFirst().contains { $0.contains(word) } }
    check(touched.isEmpty, "a connection's path never names the main thread, the store, Reminders, Calendar or the helper, and never waits on another queue (found: \(touched))")
    check(!own[0].contains("MainActor") && !own[0].contains("DispatchQueue.main") && !own[0].contains("ClaudeStore"),
          "the listener's own state is kept on its own queue, not the main thread")
    let live = source("ClaudeHookLive.swift")
    check(live.contains("cardPossible: { !ArisQuietGate.screenIsAway() }"), "the running app puts no card up on a locked Mac or a sleeping display")
    check(live.contains("static let live = HookConsumer.feeding({ ClaudeStore.shared }"), "the running app feeds its store through the same consumer the wedged-main-thread test runs")
    check(live.components(separatedBy: "await ArisAgentClient.grant(for: ArisActionGrant.key(").count == 3 && live.components(separatedBy: "guard grant.granted else { return reply(.ok(").count == 3, "both app routes still refuse a write without the helper's grant")
}

func runHooksFastTests() {
    print("\n# hooks: answered at once")
    hooksReaderTests()
    hooksRouteTests()
    hooksHoldTests()
    hooksLiveTests()
    MainActor.assumeIsolated { hooksStoreTests() }
    MainActor.assumeIsolated { hooksWedgedMainTests() }
    hooksInstallerTests()
    hooksSourceTests()
}
