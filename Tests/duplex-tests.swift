// Tests for jv-duplex: one owner for the microphone and the speaker during conversation, echo cancelled, behind
// `arisDuplexAudio` (off by default). The ring buffer (wrap, sample-indexed reads, late subscribers), the fan-out, the
// lifetime state machine, the route and fallback decisions, the barge-in threshold over synthetic level sequences,
// the engine's controller over a fake of the AVFoundation side, and the wiring that keeps the switch-off path as it
// was. Called from main.swift; uses its check().
import AVFoundation
import Foundation

private let duplexRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func duplexSource(_ path: String) -> String { (try? String(contentsOf: duplexRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runDuplexTests() {
    duplexRingTests()
    duplexFanoutTests()
    duplexLifetimeTests()
    duplexRouteTests()
    duplexBargeInTests()
    duplexEngineTests()
    duplexWiringTests()
}

private func ramp(_ from: Int, _ count: Int) -> [Float] { (from..<(from + count)).map(Float.init) }

private func duplexRingTests() {
    var ring = ArisSampleRing(capacity: 10)
    ring.append(ramp(0, 4))
    check(ring.written == 4 && ring.oldest == 0 && ring.read(from: 0).samples == ramp(0, 4), "duplex ring: holds what was written, from sample 0")
    ring.append(ramp(4, 9))
    check(ring.written == 13 && ring.oldest == 3 && ring.read(from: 0).start == 3 && ring.read(from: 0).samples == ramp(3, 10),
          "duplex ring: after a wrap a read from before what is held starts at the oldest sample, in order")
    check(ring.read(from: 7).samples == ramp(7, 6) && ring.read(from: 7, limit: 2).samples == [7, 8], "duplex ring: reads by absolute sample index, with a limit")
    check(ring.read(from: 99).samples.isEmpty && ring.read(from: 99).start == 13, "duplex ring: a read past the end is empty (nothing invented)")
    check(ring.last(3) == [10, 11, 12] && ring.last(50) == ramp(3, 10), "duplex ring: the last n samples")
    ring.append(ramp(13, 25))
    check(ring.written == 38 && ring.read(from: 0).samples == ramp(28, 10), "duplex ring: one chunk longer than the ring keeps its last samples")
    ring.restart()
    check(ring.read(from: 0).samples.isEmpty && ring.oldest == 38, "duplex ring: a restart is a new take: no pre-roll from the last one")
    ring.append([1, 2])
    check(ring.read(from: 30).samples == [1, 2] && ring.read(from: 30).start == 38, "duplex ring: after a restart only the new take is read")
    let eightSeconds = ArisAudioFanout(capacity: Int(ArisAudioFanout.sampleRate * ArisAudioFanout.heldSeconds))
    check(ArisAudioFanout.heldSeconds == 8 && ArisAudioFanout.sampleRate == 16_000 && eightSeconds.written == 0, "duplex ring: about 8 s at 16 kHz mono")
}

private final class Collected: @unchecked Sendable {
    var samples: [Float] = []
    var starts: [Int] = []
    var calls = 0
}

private func duplexFanoutTests() {
    let fanout = ArisAudioFanout(capacity: 100)
    let early = Collected(), late = Collected(), fromNow = Collected()
    let earlyToken = fanout.subscribe(from: nil) { s, start in early.samples += s; early.starts.append(start) }
    fanout.push(ramp(0, 30))
    fanout.push(ramp(30, 30))
    // A late consumer asks for audio from sample 20: the ring's part first, then live, no gap and nothing twice.
    fanout.subscribe(from: 20) { s, start in late.samples += s; late.starts.append(start) }
    fanout.subscribe(from: nil) { s, _ in fromNow.samples += s }
    fanout.push(ramp(60, 10))
    check(early.samples == ramp(0, 70) && early.starts == [0, 30, 60], "duplex fan-out: every chunk to an early subscriber, with its start index")
    check(late.samples == ramp(20, 50) && late.starts == [20, 60], "duplex fan-out: a late subscriber gets the ring from its sample, then live, gapless")
    check(fromNow.samples == ramp(60, 10), "duplex fan-out: from nil means only what comes next")
    fanout.unsubscribe(earlyToken)
    fanout.unsubscribe(earlyToken)
    fanout.push(ramp(70, 5))
    check(early.samples.count == 70 && late.samples.last == 74 && fanout.subscriberCount == 2, "duplex fan-out: an unsubscribed sink gets nothing more (twice is safe)")
    let order = Collected()
    let ordered = ArisAudioFanout(capacity: 10)
    ordered.subscribe(from: nil) { _, _ in order.starts.append(1) }
    ordered.subscribe(from: nil) { _, _ in order.starts.append(2) }
    ordered.push([0])
    check(order.starts == [1, 2], "duplex fan-out: subscribers are served in the order they came")
    let old = ArisAudioFanout(capacity: 1000)
    old.push(ramp(0, 50))
    old.restart()
    let fresh = Collected()
    old.subscribe(from: 0) { s, _ in fresh.samples += s }
    check(fresh.samples.isEmpty, "duplex fan-out: after the engine restarts, pre-roll never reaches the previous take")
    old.unsubscribeAll()
    check(old.subscriberCount == 0 && old.last(5).isEmpty, "duplex fan-out: everyone dropped at once")
    // A slow sink on another thread: chunks still arrive whole and in order.
    let threaded = ArisAudioFanout(capacity: 50_000)
    let got = Collected()
    threaded.subscribe(from: nil) { s, _ in got.samples += s }
    DispatchQueue.concurrentPerform(iterations: 1) { _ in for i in 0..<100 { threaded.push(ramp(i * 10, 10)) } }
    check(got.samples == ramp(0, 1000), "duplex fan-out: pushes from the tap's thread arrive in order")
}

private func duplexLifetimeTests() {
    typealias L = ArisDuplexLifetime
    var life = L()
    var effects: [L.Effect]
    (life, effects) = life.reduce(.need(.voice))
    check(effects.isEmpty && !life.running && life.needs.isEmpty, "duplex lifetime: Aris's voice alone never starts the engine (no microphone for an answer nobody listens to)")
    (life, effects) = life.reduce(.need(.wake))
    check(effects == [.start] && life.running, "duplex lifetime: the wake word starts it")
    (life, effects) = life.reduce(.need(.turn(1)))
    check(effects.isEmpty, "duplex lifetime: a second consumer rides on the running engine")
    (life, effects) = life.reduce(.release(.wake))
    check(effects.isEmpty && life.running, "duplex lifetime: the wake word handing over to a key turn keeps it running")
    (life, effects) = life.reduce(.release(.turn(1)))
    guard case .stopAfterLinger(let token)? = effects.first else { return check(false, "duplex lifetime: the last release lingers") }
    check(life.running && L.linger == 1.5, "duplex lifetime: the last listener letting go stops it after 1.5 s, not at once")
    (life, effects) = life.reduce(.need(.turn(2)))
    check(effects.isEmpty && life.running, "duplex lifetime: taken again within the linger: no stop, no restart")
    (life, effects) = life.reduce(.lingerElapsed(token: token))
    check(effects.isEmpty && life.running, "duplex lifetime: an old linger never stops an engine taken since")
    (life, effects) = life.reduce(.need(.voice))
    (life, effects) = life.reduce(.release(.turn(2)))
    check(effects.isEmpty && life.running, "duplex lifetime: Aris's line keeps a running engine to its end")
    (life, effects) = life.reduce(.release(.voice))
    guard case .stopAfterLinger(let second)? = effects.first else { return check(false, "duplex lifetime: the line's end lingers") }
    (life, effects) = life.reduce(.lingerElapsed(token: second))
    check(effects == [.stop] && !life.running, "duplex lifetime: with nothing listening it stops when the linger ends (microphone indicator off)")

    var away = L()
    (away, _) = away.reduce(.need(.conversation))
    (away, effects) = away.reduce(.away(true))
    check(effects == [.stop, .dropConsumers] && !away.running, "duplex lifetime: lock or sleep stops it at once, consumers told")
    (away, effects) = away.reduce(.need(.wake))
    check(effects.isEmpty && !away.running, "duplex lifetime: nothing starts it while the screen is away")
    (away, effects) = away.reduce(.away(false))
    check(effects == [.start], "duplex lifetime: back, it runs again for what still needs it")

    var legacy = L()
    (legacy, _) = legacy.reduce(.need(.wake))
    (legacy, effects) = legacy.reduce(.legacyMicOpening)
    check(effects == [.stop, .dropConsumers] && !legacy.running, "duplex lifetime: dictation or 호출어 녹음 opening its own engine stops it first: never two on the microphone")
    (legacy, effects) = legacy.reduce(.legacyMicOpening)
    check(effects.isEmpty, "duplex lifetime: a legacy microphone with nothing running changes nothing")

    var failing = L()
    (failing, _) = failing.reduce(.need(.wake))
    (failing, effects) = failing.reduce(.started(ok: false))
    check(effects == [.dropConsumers, .markFailed] && !failing.running, "duplex lifetime: voice processing failing to start marks the pair failed")
    (failing, effects) = failing.reduce(.started(ok: true))
    check(effects.isEmpty, "duplex lifetime: a good start changes nothing")

    var changing = L()
    (changing, _) = changing.reduce(.need(.wake))
    (changing, effects) = changing.reduce(.configurationChanged(routeAllows: true, at: 0))
    check(effects == [.rebuild] && changing.running, "duplex lifetime: a configuration change rebuilds (voice processing on again, consumers kept)")
    (changing, _) = changing.reduce(.configurationChanged(routeAllows: true, at: 1))
    (changing, _) = changing.reduce(.configurationChanged(routeAllows: true, at: 2))
    (changing, effects) = changing.reduce(.configurationChanged(routeAllows: true, at: 3))
    check(effects == [.stop, .dropConsumers, .markFailed] && !changing.running, "duplex lifetime: changes that keep coming (4 in 30 s) fall back to the old path")
    var spaced = L()
    (spaced, _) = spaced.reduce(.need(.wake))
    for at in [0.0, 40, 80, 120, 160] { (spaced, effects) = spaced.reduce(.configurationChanged(routeAllows: true, at: at)) }
    check(effects == [.rebuild], "duplex lifetime: changes far apart keep rebuilding")
    var phones = L()
    (phones, _) = phones.reduce(.need(.wake))
    (phones, effects) = phones.reduce(.configurationChanged(routeAllows: false, at: 0))
    check(effects == [.stop, .dropConsumers] && !phones.running, "duplex lifetime: headphones plugged in: stopped, consumers reopen on the old path (not marked failed)")
    var idle = L()
    (idle, effects) = idle.reduce(.configurationChanged(routeAllows: true, at: 0))
    check(effects.isEmpty, "duplex lifetime: a change while stopped needs nothing")
}

private func duplexRouteTests() {
    typealias R = ArisDuplexRoute
    let speakers = R.Output(id: 2, kind: .builtIn, dataSource: "ispk", hasInput: false)
    let base = R.Facts(switchOn: true, plannedInput: 1, defaultInput: 1, inputKind: .builtIn, output: speakers)
    check(R.plan(base) == .duplex(key: "1>2"), "duplex route: the Mac's microphone and speakers: duplex")
    var off = base; off.switchOn = false
    check(R.plan(off) == .legacy(.switchOff), "duplex route: switch off: the old path, always")
    var headset = base; headset.defaultInput = 9
    check(R.plan(headset) == .legacy(.notDefaultInput), "duplex route: a headset is the default input (Aris pins the Mac's): old path, no headset microphone touched")
    var noMic = base; noMic.plannedInput = nil
    check(R.plan(noMic) == .legacy(.noMicrophone), "duplex route: no microphone: old path")
    var aggregateIn = base; aggregateIn.inputKind = .aggregate
    var virtualOut = base; virtualOut.output = R.Output(id: 5, kind: .virtual, dataSource: nil, hasInput: true)
    check(R.plan(aggregateIn) == .legacy(.inputKind) && R.plan(virtualOut) == .legacy(.outputKind),
          "duplex route: aggregate or virtual devices (err -10876 territory): old path")
    var jack = base; jack.output = R.Output(id: 2, kind: .builtIn, dataSource: "hdpn", hasInput: false)
    var airPods = base; airPods.output = R.Output(id: 7, kind: .bluetooth, dataSource: nil, hasInput: true)
    check(R.plan(jack) == .legacy(.headphones) && R.plan(airPods) == .legacy(.headphones),
          "duplex route: headphones (the jack, a Bluetooth headset): old path, nothing to cancel")
    var jbl = base; jbl.output = R.Output(id: 8, kind: .bluetooth, dataSource: nil, hasInput: false)
    check(R.plan(jbl) == .duplex(key: "1>8"), "duplex route: a Bluetooth loudspeaker (no microphone) is a speaker: duplex")
    var failed = base; failed.failed = ["1>2"]
    var otherPair = jbl; otherPair.failed = ["1>2"]
    check(R.plan(failed) == .legacy(.failedBefore) && R.plan(otherPair).isDuplex, "duplex route: a pair that failed stays on the old path this run; another pair may try")
    var noOut = base; noOut.output = nil
    check(R.plan(noOut) == .legacy(.noOutput), "duplex route: no output: old path")
    check(!R.isHeadphones(R.Output(id: 8, kind: .bluetooth, dataSource: nil, hasInput: false)) && R.isHeadphones(R.Output(id: 7, kind: .bluetooth, dataSource: nil, hasInput: true))
          && !R.isHeadphones(R.Output(id: 3, kind: .wired, dataSource: nil, hasInput: false)),
          "duplex route: ducking's headphones: a Bluetooth headset yes, a Bluetooth loudspeaker no (the old rule took every Bluetooth output for headphones)")
    check(!ArisDucking.isHeadphones(transport: .bluetooth, dataSource: nil, hasInput: false) && ArisDucking.isHeadphones(transport: .bluetooth, dataSource: nil, hasInput: true),
          "duplex route: the old path now uses the same rule (jv-wake: a Bluetooth loudspeaker is a speaker there too)")
    check(R.tail(legacy: 0.8, cancelled: true) == 0.15 && R.tail(legacy: 0.8, cancelled: false) == 0.8 && R.tail(legacy: 0.1, cancelled: true) == 0.1,
          "duplex route: a line through the canceller waits a 0.15 s tail, not the output's latency plus the room")
    check(!ArisDuplexSwitch.isOn && ArisDuplexSwitch.key == "arisDuplexAudio", "duplex route: the switch is off by default")
}

/// Hops of 10 ms: (mic RMS, what Aris plays). Returns the hop the watch fired on, or nil.
private func fires(_ watch: inout ArisBargeIn, _ hops: [(Float, Float)]) -> Int? {
    for (i, hop) in hops.enumerated() where watch.feed(mic: hop.0, playback: hop.1) { return i }
    return nil
}

private func duplexBargeInTests() {
    typealias B = ArisBargeIn
    check(B.cancelledMode(headphones: false, speakersAllowed: true, voiceCancelled: true) == .cancelled
          && B.cancelledMode(headphones: false, speakersAllowed: true, voiceCancelled: false) == nil
          && B.cancelledMode(headphones: true, speakersAllowed: true, voiceCancelled: true) == nil
          && B.cancelledMode(headphones: false, speakersAllowed: false, voiceCancelled: true) == nil,
          "duplex barge-in: armed on speakers only while Aris's line goes through the canceller (and the setting allows it)")
    check(B.framesCancelled > B.framesBetween && B.framesCancelled * 10 < 200 && B.framesCancelled < B.framesSpeakers,
          "duplex barge-in: stricter than between turns, short enough for silence within 200 ms")
    // Aris talks at 0.2 RMS; the canceller leaves a residual of 3% in the microphone, with a room floor of 0.003.
    let aris: Float = 0.2, residual: Float = 0.006
    var echoOnly = B(mode: .cancelled)
    let talking = (0..<600).map { i in (residual * (1 + 0.3 * Float(sin(Double(i) / 3))), aris) }
    check(fires(&echoOnly, talking) == nil, "duplex barge-in: 6 s of Aris's residual echo alone never stops it")
    // Learned, then the user talks at 0.05 over it.
    var overAris = B(mode: .cancelled)
    _ = fires(&overAris, Array(talking.prefix(300)))
    let user = (0..<40).map { _ in (Float(0.05), aris) }
    let fired = fires(&overAris, user)
    check(fired == B.framesCancelled - 1, "duplex barge-in: the user's voice over Aris stops it after \(B.framesCancelled) hops (\(B.framesCancelled * 10) ms)")
    check(overAris.lookback >= 0.14 && overAris.lookback <= 0.16, "duplex barge-in: over Aris the turn's audio starts where the voice did")
    var blip = B(mode: .cancelled)
    _ = fires(&blip, Array(talking.prefix(300)))
    let cough = (0..<8).map { _ in (Float(0.08), aris) } + Array(talking.prefix(30))
    check(fires(&blip, cough) == nil, "duplex barge-in: a short sound (80 ms) over Aris is not a barge-in")
    var between = B(mode: .between)
    var cancelled = B(mode: .cancelled)
    let soft = (0..<12).map { _ in (Float(0.05), Float(0)) }
    check(fires(&between, soft) != nil && fires(&cancelled, soft) == nil, "duplex barge-in: 120 ms of voice starts a turn between turns, but doesn't stop Aris")
    // Right at the start of a line, before the residual is learned: a loud residual (25% of the output) doesn't fire.
    var fresh = B(mode: .cancelled)
    let loudResidual = (0..<100).map { _ in (Float(0.05), aris) }
    check(fires(&fresh, loudResidual) == nil, "duplex barge-in: before anything is learned the watch errs towards Aris's own voice")
    check(B(mode: .cancelled).echoGain == B.startingResidualGain && B(mode: .speakers).echoGain == B.startingEchoGain,
          "duplex barge-in: the canceller's residual starts lower than the uncancelled echo")
}

// MARK: - The engine over a fake of the AVFoundation side

private final class FakeHardware: ArisDuplexHardware, @unchecked Sendable {
    var starts = 0, stops = 0
    var failNext = false
    var running = false
    var frames: (@Sendable ([Float]) -> Void)?
    var onConfigurationChange: (@Sendable () -> Void)?
    var onVoiceLevel: (@Sendable (Float, Float) -> Void)?
    var played = 0, volume: Float = 1, voiceStops = 0
    var isRunning: Bool { running }

    func start(frames: @escaping @Sendable ([Float]) -> Void) throws -> String {
        starts += 1
        if failNext { failNext = false; throw ArisVoiceFailure() }
        self.frames = frames
        running = true
        return "fake"
    }
    func stop() { if running { stops += 1 }; running = false }
    func play(_ buffer: AVAudioPCMBuffer, done: @escaping @Sendable () -> Void) -> Bool { guard running else { return false }; played += 1; return true }
    func stopVoice() { voiceStops += 1 }
    func setVoiceVolume(_ volume: Float) { self.volume = volume }
}

private struct ArisVoiceFailure: Error {}

private final class Pending: @unchecked Sendable {
    var work: [@Sendable () -> Void] = []
    var route = ArisDuplexRoute.Facts(switchOn: true, plannedInput: 1, defaultInput: 1, inputKind: .builtIn,
                                      output: .init(id: 2, kind: .builtIn, dataSource: "ispk", hasInput: false))
    var lost = 0
}

/// Lets the engine's queue and the main queue run what they have.
private func settle() {
    for _ in 0..<5 { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private func duplexEngineTests() {
    let hardware = FakeHardware(), pending = Pending()
    let engine = ArisAudioEngine(hardware: hardware, facts: { _ in pending.route }, after: { _, work in pending.work.append(work) })
    let lost: @Sendable () -> Void = { pending.lost += 1 }
    guard let wake = engine.open(.wake, use: .wake, lost: lost) else { return check(false, "duplex engine: the wake word opens it") }
    check(hardware.starts == 1 && engine.running, "duplex engine: the wake word starts the hardware once")
    let heard = Collected()
    engine.attach(wake, from: nil) { s, _ in heard.samples += s }
    hardware.frames?(ramp(0, 160))
    check(heard.samples == ramp(0, 160), "duplex engine: the processed chunks reach the wake detector")
    // A key turn takes the engine while the wake word lets go: no restart, and the turn's audio from its mark.
    guard let turn = engine.open(.turn(1), use: .talk, lost: lost) else { return check(false, "duplex engine: a key turn opens it") }
    let mark = engine.fanout.written
    engine.close(wake)
    hardware.frames?(ramp(160, 160))
    let turnHeard = Collected()
    engine.attach(turn, from: mark) { s, _ in turnHeard.samples += s }
    check(hardware.starts == 1 && turnHeard.samples == ramp(160, 160),
          "duplex engine: a key turn started late still gets everything said since it asked (the first word waits in the ring)")
    check(engine.openVoice(), "duplex engine: with a turn listening, Aris's line plays through the canceller")
    settle()
    engine.close(turn)
    settle()
    check(engine.running && pending.work.isEmpty, "duplex engine: Aris's line keeps the engine to its end")
    engine.closeVoice()
    settle()
    check(pending.work.count == 1 && engine.running, "duplex engine: nothing listening any more: a linger, not a stop")
    pending.work.removeFirst()()
    settle()
    check(!engine.running && hardware.stops == 1 && !engine.openVoice(), "duplex engine: the linger ends: stopped; an answer now uses the old output")

    // Route: headphones: the old path; the engine never starts.
    pending.route.output = .init(id: 7, kind: .bluetooth, dataSource: nil, hasInput: true)
    check(engine.open(.wake, use: .wake, lost: lost) == nil && hardware.starts == 1, "duplex engine: headphones: the consumer is sent to the old path")
    pending.route.output = .init(id: 2, kind: .builtIn, dataSource: "ispk", hasInput: false)

    // A configuration change it can ride: rebuilt, the subscriber kept, the stream continuous.
    guard let again = engine.open(.wake, use: .wake, lost: lost) else { return check(false, "duplex engine: reopens") }
    let kept = Collected()
    engine.attach(again, from: nil) { s, _ in kept.samples += s }
    hardware.running = false
    hardware.onConfigurationChange?()
    settle()
    hardware.frames?([1, 2, 3])
    check(hardware.starts == 3 && kept.samples == [1, 2, 3] && pending.lost == 0, "duplex engine: a configuration change rebuilds; consumers keep their stream")
    // Headphones plugged in under it: stopped, consumers told once, on the main queue.
    pending.route.output = .init(id: 2, kind: .builtIn, dataSource: "hdpn", hasInput: false)
    hardware.running = false
    hardware.onConfigurationChange?()
    settle()
    check(!engine.running && pending.lost == 1, "duplex engine: a route that no longer suits it drops the consumers (each reopens on the old path)")
    engine.close(again)
    pending.route.output = .init(id: 2, kind: .builtIn, dataSource: "ispk", hasInput: false)

    // Another Aris microphone opens: the engine stops first.
    guard let third = engine.open(.wake, use: .wake, lost: lost) else { return check(false, "duplex engine: opens after the route came back") }
    engine.legacyMicOpening()
    settle()
    check(!engine.running && pending.lost == 2 && !hardware.running, "duplex engine: dictation's own engine never shares the microphone with it")
    engine.close(third)
    settle()

    // Voice processing failing to start: the old path for that pair, the rest of the run.
    hardware.failNext = true
    let startsBefore = hardware.starts
    check(engine.open(.wake, use: .wake, lost: lost) == nil && hardware.starts == startsBefore + 1, "duplex engine: a failed start sends the consumer to the old path")
    check(engine.open(.wake, use: .wake, lost: lost) == nil && hardware.starts == startsBefore + 1, "duplex engine: that pair is not tried again this run")
    pending.route.output = .init(id: 8, kind: .bluetooth, dataSource: nil, hasInput: false)
    let other = engine.open(.wake, use: .wake, lost: lost)
    check(other != nil && hardware.starts == startsBefore + 2, "duplex engine: another pair (a Bluetooth loudspeaker) may try")
    if let other { engine.close(other) }
    engine.away(true)
    settle()
    check(!engine.running, "duplex engine: lock or sleep stops it at once")

    // An open conversation holds it from the turn through the answer to the next voice.
    let held = ArisAudioEngine(hardware: FakeHardware(), facts: { _ in pending.route }, after: { _, work in pending.work.append(work) })
    held.conversation(open: true)
    settle()
    check(held.running && held.servesVoice, "duplex engine: an open conversation runs it, and Aris's answer goes through the canceller")
    held.conversation(open: false)
    settle()
    check(held.running && !held.servesVoice, "duplex engine: the conversation closing starts the linger")
}

private func duplexWiringTests() {
    let detector = duplexSource("Aris/private/Aris/ArisWakeDetector.swift")
    let listener = duplexSource("Aris/private/Aris/ArisListener.swift")
    let speaker = duplexSource("Aris/private/Aris/ArisSpeaker.swift")
    let devices = duplexSource("Aris/private/Aris/ArisMicDevices.swift")
    let conversation = duplexSource("Aris/private/Aris/ArisController+Conversation.swift")
    let ducking = duplexSource("Aris/private/Aris/ArisDucking.swift")
    let latency = duplexSource("Aris/private/Aris/ArisOutputLatency.swift")
    let hardware = duplexSource("Aris/private/Aris/Audio/ArisVoiceProcessingHardware.swift")
    let facade = duplexSource("Aris/private/Aris/Audio/ArisDuplexAudio.swift")
    check(detector.contains("if use == .wake, let hold = ArisDuplexHold.open(") && detector.contains("duplex.close()"),
          "duplex wiring: the wake detector takes the engine's chunks in place of its own engine (training keeps its own)")
    check(listener.contains("feed == nil && ArisDuplexSwitch.isOn ? await ArisDuplexKeySource.open(use: use)") && listener.contains("listen(to source: ArisAudioSource"),
          "duplex wiring: a key turn's or card's listener hears the engine's stream; with the switch off it is never even asked")
    check(speaker.contains("if ArisDuplexSwitch.isOn, duplexVoice == nil") && speaker.contains("duplexVoice.play(buffer)") && speaker.contains("endDuplexVoice(stopping: true)"),
          "duplex wiring: the speaker schedules on the engine's player only with the switch on, and stops it at once")
    check(devices.components(separatedBy: "if ArisDuplexSwitch.isOn { ArisDuplexAudio.legacyMicOpening() }").count == 3,
          "duplex wiring: every engine of its own (pin, the AirPods' pin) stops the duplex engine first")
    check(conversation.contains("if ArisDuplexSwitch.isOn { ArisDuplexAudio.conversation(open: true) }") && conversation.contains("ArisDuplexAudio.conversation(open: false)")
          && conversation.contains("?? ArisBargeIn.cancelledMode("), "duplex wiring: the conversation holds the engine; the voice watch stays armed over a cancelled line")
    check(ducking.contains("ArisDuplexRoute.isHeadphones(") && latency.contains("ArisDuplexSwitch.isOn ? ArisDuplexRoute.tail("),
          "duplex wiring: headphones follow the duplex rule on both paths (jv-wake); the echo tail changes only with the switch on")
    check(hardware.contains("try mic.setVoiceProcessingEnabled(true)") && hardware.contains("isVoiceProcessingAGCEnabled = false")
          && hardware.contains("isVoiceProcessingBypassed = false") && hardware.contains("duckingLevel: .min") && hardware.contains("format: nil"),
          "duplex wiring: voice processing on while stopped, AGC off, not bypassed, other audio ducked at the minimum, the tap in the node's own format")
    check(facade.contains("guard ArisDuplexSwitch.isOn else { return nil }") && facade.contains("default: false"), "duplex wiring: off by default; off, no engine is made")
}
