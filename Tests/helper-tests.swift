// Acceptance tests for the clean-room XPC helper, its client and brightness (cleanroom-specs/10, 11).
import CoreGraphics
import Foundation

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private final class FakeDisplays: ArisBrightnessBackend, @unchecked Sendable {
    var levels: [CGDirectDisplayID: Float] = [1: 0.5, 2: 0.3]
    var main: CGDirectDisplayID = 1
    var online: [CGDirectDisplayID] = [1, 2]
    var builtin: Set<CGDirectDisplayID> = [2]
    var supported: Set<CGDirectDisplayID> = [1, 2]
    var smooth = false

    func level(of display: CGDirectDisplayID) -> Float? { supported.contains(display) ? levels[display] : nil }
    func setLevel(_ level: Float, of display: CGDirectDisplayID) -> Bool {
        guard supported.contains(display) else { return false }
        levels[display] = level
        return true
    }
    func nudge(by delta: Float, of display: CGDirectDisplayID) -> Bool? {
        guard smooth, let current = levels[display] else { return nil }
        levels[display] = min(1, max(0, current + delta))
        return true
    }
    func mainDisplay() -> CGDirectDisplayID { main }
    func onlineDisplays() -> [CGDirectDisplayID] { online }
    func isBuiltin(_ display: CGDirectDisplayID) -> Bool { builtin.contains(display) }
    func supportsBrightness(_ display: CGDirectDisplayID) -> Bool { supported.contains(display) }
}

private func helperUnitTests() {
    let ran = Box<[(String, [String])]>([])
    let status = Box<Int32?>(0)
    let runner: ArisProcessRunner = { executable, arguments, done in ran.value.append((executable, arguments)); done(status.value) }
    let answer = Box<Bool?>(nil)
    ArisAgentRestart.run(using: runner, uid: 501) { answer.value = $0 }
    check(answer.value == true && ran.value.first?.0 == "/bin/launchctl"
          && ran.value.first?.1 == ["kickstart", "-k", "gui/501/com.lumenjsn.aris.agent"], "helper: restart runs launchctl with the fixed arguments; 0 -> true")
    status.value = 1
    ArisAgentRestart.run(using: runner, uid: 501) { answer.value = $0 }
    check(answer.value == false, "helper: restart exit 1 -> false")
    status.value = nil
    answer.value = nil
    ArisAgentRestart.run(using: runner, uid: 501) { answer.value = $0 }
    check(answer.value == false, "helper: restart that can't start -> false")
    // The live runner: a real exit status through the termination handler, and a timeout that stops a hung program.
    let exit = Box<Int32??>(nil)
    let live = ArisAgentRestart.liveRunner(timeout: 2)
    live("/bin/sh", ["-c", "exit 3"]) { exit.value = .some($0) }
    for _ in 0..<200 where exit.value == nil { Thread.sleep(forTimeInterval: 0.01) }
    check(exit.value == .some(3), "helper: the live runner reports the exit status without blocking")
    let hung = Box<Int32??>(nil)
    let started = Date()
    ArisAgentRestart.liveRunner(timeout: 0.3)("/bin/sleep", ["5"]) { hung.value = .some($0) }
    for _ in 0..<200 where hung.value == nil { Thread.sleep(forTimeInterval: 0.01) }
    check(hung.value == .some(nil) && Date().timeIntervalSince(started) < 1.5, "helper: a program that hangs past the timeout counts as failed")

    let displays = FakeDisplays()
    let brightness = ArisDisplayBrightness(backend: displays)
    check(brightness.display() == 1, "brightness: the main display when it supports brightness")
    displays.supported = [2]
    check(brightness.display() == 2, "brightness: else the first built-in display")
    displays.supported = []
    check(brightness.display() == 2, "brightness: a built-in display is chosen even when neither answers")
    displays.builtin = []
    check(brightness.display() == 1 && brightness.level() == nil && !brightness.set(0.4), "brightness: no built-in -> main (and calls fail)")
    displays.supported = [1, 2]; displays.builtin = [2]
    check(brightness.set(1.4) && displays.levels[1] == 1 && brightness.set(-2) && displays.levels[1] == 0, "brightness: set is clamped")
    displays.levels[1] = 0.5
    check(brightness.adjust(by: 0.1).map { abs($0 - 0.6) < 0.0001 } == true, "brightness: adjust by hand when there's no smooth change")
    check(brightness.adjust(by: 0.7) == 1, "brightness: adjust is clamped")
    displays.smooth = true
    displays.levels[1] = 0.2
    check(brightness.adjust(by: -0.15).map { abs($0 - 0.05) < 0.0001 } == true, "brightness: the smooth change, then the level read back")

    var queue = ArisStepQueue()
    check(queue.add(0.15) == 0.15 && queue.add(0.15) == nil && queue.add(-0.15) == nil && queue.add(0.15) == nil,
          "brightness steps: the first goes now, the rest wait")
    check(queue.finished().map { abs($0 - 0.15) < 0.0001 } == true && queue.inFlight, "brightness steps: the waiting ones go next, added up")
    check(queue.finished() == nil && !queue.inFlight, "brightness steps: then idle")
}

/// A listener delegate that keeps the accepted connections, so a test can cut them (like a helper crash).
private final class CuttableListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    var accepted: [NSXPCConnection] = []
    let service: ArisHelperService
    init(_ service: ArisHelperService) { self.service = service }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = ArisHelperName.interface()
        connection.exportedObject = service
        accepted.append(connection)
        connection.resume()
        return true
    }
}

private func helperRoundTripTests() async {
    let displays = FakeDisplays()
    let service = ArisHelperServiceObject(runner: { _, _, done in done(0) }, brightness: ArisDisplayBrightness(backend: displays))
    let delegate = ArisHelperListener(requirePeer: false) { service }
    let listener = NSXPCListener.anonymous()
    listener.delegate = delegate
    listener.resume()
    let endpoint = listener.endpoint
    let client = ArisHelperClient { NSXPCConnection(listenerEndpoint: endpoint) }
    let restarted = await client.restartArisAgent()
    let set = await client.setScreenBrightness(0.5)
    let adjusted = await client.adjustScreenBrightness(by: 0.1)
    check(restarted && set && displays.levels[1] == 0.6 && adjusted.map { abs($0 - 0.6) < 0.0001 } == true,
          "helper over XPC: restart, set 0.5, adjust +0.1 -> 0.6")

    let cuttable = CuttableListener(service)
    let second = NSXPCListener.anonymous()
    second.delegate = cuttable
    second.resume()
    let secondEndpoint = second.endpoint
    let made = Box(0)
    let reconnecting = ArisHelperClient { made.value += 1; return NSXPCConnection(listenerEndpoint: secondEndpoint) }
    _ = await reconnecting.setScreenBrightness(0.4)
    cuttable.accepted.forEach { $0.invalidate() }
    var waited = 0
    while await reconnecting.isAvailable, waited < 200 { try? await Task.sleep(for: .milliseconds(10)); waited += 1 }
    let droppedOut = await !reconnecting.isAvailable
    let again = await reconnecting.setScreenBrightness(0.7)
    let back = await reconnecting.isAvailable
    check(droppedOut && again && back && made.value == 2, "helper over XPC: a cut connection flips unavailable, the next call reconnects")
    listener.invalidate()
    second.invalidate()
}

@MainActor
private func brightnessControllerTests() async {
    let sent = Box<[Float]>([])
    let gate = Box<CheckedContinuation<Void, Never>?>(nil)
    let brightness = ArisBrightness(adjust: { delta in
        sent.value.append(delta)
        if sent.value.count == 1 { await withCheckedContinuation { gate.value = $0 } }
        return true
    }, set: { _ in true })
    brightness.adjust(by: 0.15)
    while gate.value == nil { await Task.yield() }
    brightness.adjust(by: 0.15)
    brightness.adjust(by: 0.15)
    gate.value?.resume()
    for _ in 0..<100 where sent.value.count < 2 { try? await Task.sleep(for: .milliseconds(5)) }
    check(sent.value.count == 2 && sent.value[0] == 0.15 && abs(sent.value[1] - 0.3) < 0.0001,
          "brightness: presses during a pending call are added up and sent next (\(sent.value))")
}

func runHelperTestsBlocking() {
    helperUnitTests()
    let done = Box(false)
    Task { @MainActor in
        await helperRoundTripTests()
        await brightnessControllerTests()
        done.value = true
    }
    while !done.value { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}
