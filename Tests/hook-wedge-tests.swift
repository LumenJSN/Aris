// Tests for the hook server under a wedge that does not end (2026-11-12, after the QA records put all 35 hook
// timeouts of a week inside the two 2026-11-09 hangs of BUG-37: Aris's main thread parked for 40 and 5 minutes, a
// background thread parked in NSAppleScript's compile, and the hook server of then, d01c1e29, answering nothing).
// That server did everything for every connection on one serial queue with no deadline, so one request that stopped
// part way left every later connection unread. Here the app's own wiring (HookConsumer.feeding, a real ClaudeStore)
// runs with the main queue held for the whole test (this function is on the main thread and lets the main queue run
// only at its end) and, in the second part, with a background thread parked holding the lock the requests' own work
// needs, so that work never finishes either. Each wedge lasts seconds, and each check proves the answer came while it
// still held. Called from main.swift; uses its check(). The server listens on a free loopback port (never 23350).
import Foundation
import Network

private let wedgeToken = String(repeating: "beef", count: 16)

private func wedgeNow() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }

private func wedgeFreePort() -> UInt16 {
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

/// One request as Claude Code's http hook sends it, on a new connection: the status, the body and the milliseconds
/// until the whole answer was in (status 0: none within `timeout`).
private func wedgeAsk(_ port: UInt16, _ name: String, timeout: Double = 5) -> (status: Int, body: String, ms: Double) {
    let start = wedgeNow()
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    guard connected == 0 else { return (0, "", wedgeNow() - start) }
    let object: [String: Any] = ["hook_event_name": name, "session_id": "wedge", "cwd": "/tmp/hook-wedge", "tool_name": "Bash",
                                 "tool_input": ["command": "swift build"]]
    let body = try! JSONSerialization.data(withJSONObject: object)
    let head = "POST /hook HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nContent-Type: application/json\r\nX-Aris-Token: \(wedgeToken)\r\nContent-Length: \(body.count)\r\n\r\n"
    let request = Data(head.utf8) + body
    _ = request.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!, request.count, 0) }
    var received = Data()
    var chunk = [UInt8](repeating: 0, count: 4_096)
    while true {
        if let end = received.range(of: Data("\r\n\r\n".utf8)) {
            let text = String(decoding: received[received.startIndex..<end.lowerBound], as: UTF8.self)
            let status = Int(text.split(separator: " ").dropFirst().first ?? "") ?? 0
            let length = text.lowercased().components(separatedBy: "\r\n").first { $0.hasPrefix("content-length:") }
                .flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } ?? 0
            if received.endIndex - end.upperBound >= length {
                return (status, String(decoding: received[end.upperBound..<(end.upperBound + length)], as: UTF8.self), wedgeNow() - start)
            }
        }
        let n = recv(fd, &chunk, chunk.count, 0)
        if n <= 0 { return (0, "", wedgeNow() - start) }
        received.append(contentsOf: chunk[0..<n])
    }
}

/// Whether something accepts connections on `port` (nothing is sent).
private func wedgeListening(_ port: UInt16) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    return withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } == 0
}

private func wedgeThreads() -> Int {
    var list: thread_act_array_t?
    var count: mach_msg_type_number_t = 0
    guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return -1 }
    for index in 0..<Int(count) { mach_port_deallocate(mach_task_self_, list[index]) }
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(Int(count) * MemoryLayout<thread_act_t>.stride))
    return Int(count)
}

/// A background thread parked holding a lock (as ArisAppleScript's thread sat in NSAppleScript's compile), let go
/// only when the test is over.
private final class ParkedThread: @unchecked Sendable {
    let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)

    func park() {
        let parked = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            lock.lock()
            parked.signal()
            release.wait()
            lock.unlock()
        }
        parked.wait()
    }

    func letGo() { release.signal() }
}

@MainActor private func hookWedgeServer(_ store: ClaudeStore, limits: HookLimits = .standard,
                                        token: @escaping () -> String?) -> (server: ClaudeHookServer, port: UInt16) {
    let port = wedgeFreePort()
    let consumer = HookConsumer.feeding({ store }, slow: { _, _, reply in reply(.refusal("503 Service Unavailable")) })
    let server = ClaudeHookServer(port: NWEndpoint.Port(rawValue: port)!, token: token, consumer: consumer, limits: limits)
    server.start()
    for _ in 0..<200 {
        if wedgeListening(port) { break }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return (server, port)
}

@MainActor private func hookWedgeTests() {
    UserDefaults.standard.register(defaults: ["claudeSounds": false])
    final class Ran: @unchecked Sendable { var main = false }
    let ran = Ran()
    // Put on the main queue first: while it hasn't run, nothing else on the main queue has.
    DispatchQueue.main.async { ran.main = true }

    // The main thread wedged, nothing else: the store never gets to run, the card can't come up.
    let store = ClaudeStore()
    var applied: [String] = []
    store.onEvent = { event, _ in applied.append(event.name) }
    let (server, port) = hookWedgeServer(store, token: { wedgeToken })
    let events = (0..<3).flatMap { _ in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"] }
    let quick = events.map { wedgeAsk(port, $0) }
    check(quick.allSatisfy { $0.status == 200 && $0.body == "{}" && $0.ms < 400 } && !ran.main,
          "with the main thread held, every hook event is answered 200 {} at once (12 events, slowest \(Int(quick.map(\.ms).max() ?? 0)) ms)")
    let card = wedgeAsk(port, "PermissionRequest", timeout: 8)
    check(card.status == 200 && card.body == "{}" && card.ms >= 2_900 && card.ms < 4_500 && !ran.main,
          "a PermissionRequest gets the neutral reply at the 3 s bound for a card that did not come up (\(Int(card.ms)) ms)")
    check(server.stats.counts.cardNotShown == 1 && applied.isEmpty, "counted as a card not shown, and the store ran nothing meanwhile")
    server.stop()

    // The requests' own work stuck too: each needs the lock a parked background thread holds.
    let parked = ParkedThread()
    parked.park()
    let stuckStore = ClaudeStore()
    let (stuck, stuckPort) = hookWedgeServer(stuckStore, token: { parked.lock.withLock { wedgeToken } })
    let late = (events + ["PermissionRequest"]).map { wedgeAsk(stuckPort, $0) }
    check(late.allSatisfy { $0.status == 200 && $0.body == "{}" && $0.ms >= 100 && $0.ms < 1_000 } && !ran.main,
          "with the main thread held and every request's own work stuck, each still gets 200 {} at the 150 ms deadline (13 requests, \(Int(late.map(\.ms).min() ?? 0))–\(Int(late.map(\.ms).max() ?? 0)) ms)")
    check(stuck.stats.counts.late == 13 && stuck.stats.counts.answered == 0, "each is counted late, none as answered")
    stuck.stop()

    // A wedge that never ends must not take every thread: past `deciding` requests are answered without being read.
    var limits = HookLimits.standard
    limits.deciding = 4
    let boundStore = ClaudeStore()
    let (bound, boundPort) = hookWedgeServer(boundStore, limits: limits, token: { parked.lock.withLock { wedgeToken } })
    let threadsBefore = wedgeThreads()
    let flood = (0..<40).map { wedgeAsk(boundPort, events[$0 % events.count]) }
    let threadsAfter = wedgeThreads()
    check(flood.allSatisfy { $0.status == 200 && $0.body == "{}" && $0.ms < 1_000 },
          "40 hook events into a wedge that doesn't end are all answered 200 {} (slowest \(Int(flood.map(\.ms).max() ?? 0)) ms)")
    check(bound.stats.counts.late == 4 && bound.stats.counts.turnedAway == 36 && flood.dropFirst(4).allSatisfy { $0.ms < 100 },
          "four are looked at and answered by the deadline; the other 36 at once, without being read")
    check(threadsAfter - threadsBefore < 16, "and the stuck requests keep at most a few threads (\(threadsBefore) before, \(threadsAfter) after)")

    // The wedge ends.
    parked.letGo()
    let freed = (0..<100).contains { _ in
        Thread.sleep(forTimeInterval: 0.02)
        return wedgeAsk(boundPort, "PreToolUse").status == 200 && bound.stats.counts.answered > 0
    }
    check(freed, "once it ends, requests are looked at again and answered as usual")
    bound.stop()
    let deadline = Date().addingTimeInterval(3)
    while applied.count < 13, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    check(ran.main && applied == events + ["PermissionRequest"] && store.approvals.isEmpty,
          "when the main thread comes back the store gets every event in order, and the card let go meanwhile is never shown")
    check(stuckStore.approvals.isEmpty, "nor is the PermissionRequest whose own work was stuck")
}

func runHookWedgeTests() {
    print("\n# hooks: a wedge that does not end")
    MainActor.assumeIsolated { hookWedgeTests() }
}
