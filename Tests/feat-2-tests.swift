// Tests for the four things built on feat-2: the microphone plan that keeps a Bluetooth headset in music mode
// (ArisMicPlan, ArisOwnOutput), quiet hours at any half hour (ArisQuietSpan, ArisQuietHoursWords), a teammate's
// terminal (ArisTerminal), and the dropped-file chips that learn (ArisDropLearned). Called from main.swift; uses its
// check(). Pure rules, source reads and one engine that only mixes into memory: no microphone is opened, nothing
// plays, no window opens, and no preference of the user's is read or written.
import AVFoundation
import Foundation

func runFeat2Tests() {
    feat2MicPlanTests()
    feat2MicEventTests()
    feat2VoiceRouteTests()
    feat2OwnOutputTests()
    feat2MicWiringTests()
    feat2QuietSpanTests()
    feat2QuietGateTests()
    feat2QuietSpokenTests()
    feat2QuietRowTests()
    feat2TerminalChoiceTests()
    feat2TerminalPlanTests()
    feat2WarpTests()
    feat2TerminalSettingTests()
    feat2TerminalWiringTests()
    feat2LearnedShapeTests()
    feat2LearnedCountingTests()
    feat2LearnedLabelTests()
    feat2LearnedWiringTests()
}

private func feat2Source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

// MARK: - Which microphone, for whom

/// Device lists as Core Audio gave them (ids and transports recorded from a MacBook Pro with a display, a phone
/// nearby and Teams installed; the headsets as they show when connected).
private enum Feat2Devices {
    typealias D = ArisAudioDevice
    static let builtInMic = D(id: 88, transport: .builtIn, hasInput: true)
    static let builtInSpeakers = D(id: 81, transport: .builtIn, hasInput: false, hasOutput: true)
    static let display = D(id: 93, transport: .wired, hasInput: false, hasOutput: true)
    static let phoneMic = D(id: 114, transport: .continuity, hasInput: true)
    static let teams = D(id: 71, transport: .virtual, hasInput: true, hasOutput: true)
    static let airPodsMic = D(id: 120, transport: .bluetooth, hasInput: true)
    static let airPodsOut = D(id: 121, transport: .bluetooth, hasInput: false, hasOutput: true)
    static let speaker = D(id: 108, transport: .bluetooth, hasInput: false, hasOutput: true)
    static let usbMic = D(id: 130, transport: .wired, hasInput: true)

    static let desk = [display, speaker, builtInMic, builtInSpeakers, phoneMic, teams]
    static let withHeadset = desk + [airPodsMic, airPodsOut]
    /// The lid closed: the Mac's own microphone and speakers are gone.
    static let lidClosed = [display, phoneMic, teams, airPodsMic, airPodsOut]
    static let lidClosedWithUSB = lidClosed + [usbMic]
}

private func feat2MicPlanTests() {
    typealias P = ArisMicPlan
    typealias V = Feat2Devices
    for use in ArisMicUse.allCases {
        check(P.make(for: use, defaultInput: 88, devices: V.desk) == .open(id: 88, transport: .builtIn),
              "mic (\(use.rawValue)): with the Mac's own microphone as the input, that one is opened, by its id")
        check(P.make(for: use, defaultInput: 120, devices: V.withHeadset) == .open(id: 88, transport: .builtIn),
              "mic (\(use.rawValue)): with a headset as the default input, the Mac's own microphone is opened instead")
        check(P.make(for: use, defaultInput: 120, devices: V.lidClosedWithUSB) == .open(id: 130, transport: .wired),
              "mic (\(use.rawValue)): the lid closed with a USB microphone plugged in: the USB one, never the headset's")
        check(P.make(for: use, defaultInput: nil, devices: [V.display, V.speaker, V.builtInSpeakers]) == P.none,
              "mic (\(use.rawValue)): a Mac with no input device at all has no microphone to open")
        check(P.make(for: use, defaultInput: 130, devices: V.withHeadset + [V.usbMic]) == .open(id: 130, transport: .wired),
              "mic (\(use.rawValue)): a microphone the user chose himself that is no headset is used as chosen")
        check(P.make(for: use, defaultInput: 999, devices: V.withHeadset) == .open(id: 88, transport: .builtIn)
              && P.make(for: use, defaultInput: nil, devices: V.withHeadset) == .open(id: 88, transport: .builtIn),
              "mic (\(use.rawValue)): a default input that can't be read or is gone: the Mac's own microphone")
    }
    check(P.make(for: .wake, defaultInput: 120, devices: V.lidClosed) == .pause(.headsetOnly),
          "mic: the lid closed and only a headset's microphone: the wake word opens nothing (the phone's and Teams' are never taken in its place)")
    check(P.make(for: .wake, defaultInput: 120, devices: [V.airPodsMic, V.airPodsOut]) == .pause(.headsetOnly),
          "mic: a Mac with no microphone of its own and a headset: the wake word pauses")
    for use in [ArisMicUse.talk, .dictation, .setup] {
        check(P.make(for: use, defaultInput: 120, devices: V.lidClosed) == .open(id: 120, transport: .bluetooth),
              "mic (\(use.rawValue)): the user's own press may use the headset's microphone when it is the only one")
    }
    check(P.make(for: .wake, defaultInput: 71, devices: V.withHeadset) == .open(id: 71, transport: .virtual)
          && P.make(for: .wake, defaultInput: 114, devices: V.lidClosed) == .open(id: 114, transport: .continuity),
          "mic: a virtual device or a phone's microphone is used only when the user made it the default himself")
    check(P.make(for: .wake, defaultInput: nil, devices: [V.phoneMic, V.teams]) == .open(id: 114, transport: .continuity),
          "mic: with no default, no microphone of the Mac's and no headset, whatever input is there is opened")
    check(ArisMicUse.wake.isDeliberate == false && ArisMicUse.talk.isDeliberate && ArisMicUse.dictation.isDeliberate && ArisMicUse.setup.isDeliberate,
          "mic: only the wake word (and a conversation's listening between turns) opens the microphone without a press")
    let codes: [(String, ArisAudioDevice.Transport)] = [("bltn", .builtIn), ("blue", .bluetooth), ("blea", .bluetooth), ("usb ", .wired), ("dprt", .wired),
                                                         ("hdmi", .wired), ("thun", .wired), ("ccwd", .continuity), ("ccwl", .continuity), ("virt", .virtual),
                                                         ("grup", .aggregate), ("fgrp", .aggregate), ("airp", .other), ("????", .other)]
    for (code, transport) in codes {
        let number = code.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        check(ArisAudioDevice.transport(code: number) == transport, "mic: Core Audio's transport “\(code)” is read as \(transport.rawValue)")
    }
    check(ArisAudioDevice.transport(code: 0) == .other, "mic: a transport that couldn't be read is no kind Aris prefers")
}

/// What happens over time: each step is the default input and the device list after an event, and what the wake
/// word's microphone must be on afterwards.
private func feat2MicEventTests() {
    typealias P = ArisMicPlan
    typealias V = Feat2Devices
    var open: UInt32?
    func settle(_ defaultInput: UInt32?, _ devices: [ArisAudioDevice]) -> (plan: P, reopened: Bool) {
        let plan = P.make(for: .wake, defaultInput: defaultInput, devices: devices)
        let reopen = P.mustReopen(openOn: open, plan: plan)
        if reopen { open = plan.device }
        return (plan, reopen)
    }
    check(settle(88, V.desk).reopened && open == 88, "mic over time: the wake word starts on the Mac's own microphone")
    let connected = settle(120, V.withHeadset)
    check(!connected.reopened && open == 88 && connected.plan == .open(id: 88, transport: .builtIn),
          "mic over time: headphones connect while it runs and become the default input: it stays on the Mac's microphone, nothing is reopened")
    check(!settle(88, V.withHeadset).reopened && !settle(120, V.withHeadset).reopened && !settle(88, V.withHeadset).reopened && open == 88,
          "mic over time: the default flipping back and forth (AirPods taken by a phone and given back) never moves it")
    check(!settle(88, V.desk).reopened && open == 88, "mic over time: the headphones disconnect: still the Mac's microphone")
    _ = settle(120, V.withHeadset)
    let closed = settle(120, V.lidClosed)
    check(closed.plan == .pause(.headsetOnly) && closed.reopened && open == nil,
          "mic over time: the lid closes with headphones on: the wake word's microphone is closed and it pauses")
    check(!settle(120, V.lidClosed).reopened && open == nil, "mic over time: more changes while it is paused open nothing")
    let usb = settle(120, V.lidClosedWithUSB)
    check(usb.reopened && open == 130, "mic over time: a USB microphone is plugged in while paused: the wake word opens it")
    let opened = settle(120, V.withHeadset)
    check(opened.reopened && open == 88, "mic over time: the lid opens again: back on the Mac's own microphone")
    let gone = settle(nil, [V.display, V.builtInSpeakers])
    check(gone.plan == P.none && gone.reopened && open == nil, "mic over time: every input gone: nothing stays open")
    check(P.mustReopen(openOn: nil, plan: .open(id: 88, transport: .builtIn)) && !P.mustReopen(openOn: 88, plan: .open(id: 88, transport: .builtIn))
          && P.mustReopen(openOn: 120, plan: .open(id: 88, transport: .builtIn)) && P.mustReopen(openOn: 120, plan: .pause(.headsetOnly))
          && !P.mustReopen(openOn: nil, plan: .pause(.headsetOnly)) && !P.mustReopen(openOn: nil, plan: P.none),
          "mic over time: a microphone is opened again exactly when the plan names another device, or none")
    typealias A = ArisWakeArm
    check(A.blocker(A.State(headsetOnly: true)) == .headsetOnly && A.blocker(A.State()) == nil
          && A.blocker(A.State(settingOn: false, headsetOnly: true)) == .settingOff
          && A.blocker(A.State(settingOn: false, conversationOpen: true, headsetOnly: true)) == .headsetOnly,
          "wake word: with only a headset's microphone it is held back, and so is a conversation's listening between turns")
    check(A.Blocker.headsetOnly.rawValue.contains("music mode"), "wake word: the log says why it waits")
}

// MARK: - The voice's way out

private func feat2VoiceRouteTests() {
    typealias R = ArisVoiceRoute
    typealias V = Feat2Devices
    check(R.pick(setting: nil, defaultInput: 120, devices: V.withHeadset) == .own && R.pick(setting: "auto", defaultInput: 120, devices: V.withHeadset) == .own,
          "voice: while a headset's microphone is the default input, Aris speaks through an output with no input side")
    check(R.pick(setting: nil, defaultInput: 88, devices: V.withHeadset) == .engine && R.pick(setting: nil, defaultInput: nil, devices: V.desk) == .engine
          && R.pick(setting: nil, defaultInput: 999, devices: V.desk) == .engine,
          "voice: with any other default input (or none) the voice goes out as it always did")
    check(R.pick(setting: "own", defaultInput: 88, devices: V.desk) == .own && R.pick(setting: "engine", defaultInput: 120, devices: V.withHeadset) == .engine,
          "voice: the preference arisVoiceOutput can hold it to either way")
    check(R.key == "arisVoiceOutput", "voice: the preference's name")
    check(ArisMicWords.opened(.wake, transport: .builtIn, id: 88) == "microphone opened: wake on built-in (device 88)"
          && ArisMicWords.opened(.talk, transport: .bluetooth, id: 120) == "microphone opened: talk on bluetooth (device 120)"
          && ArisMicWords.closed(.dictation, transport: nil) == "microphone closed: dictation"
          && ArisMicWords.closed(.wake, transport: .builtIn) == "microphone closed: wake (was on built-in)"
          && ArisMicWords.paused(.wake, why: .headsetOnly).hasPrefix("microphone not opened: wake pauses")
          && ArisMicWords.voice(.own, inputTransport: .bluetooth) == "voice output: own output, no input side (default input: bluetooth)"
          && ArisMicWords.voice(.engine, inputTransport: nil) == "voice output: the engine's (default input: none)",
          "log: every open, pause and close names who and the device's kind, and the voice's way out is said")
    check(ArisMicWords.wakePaused(english: false).contains("헤드폰 마이크만 있어서 이름 듣기를 쉬어요") && ArisMicWords.wakePaused(english: true).contains("paused")
          && !ArisMicWords.wakePaused(english: true).unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) },
          "wake word: its pause has one plain line in Korean and in English")
}

/// The own output's engine only mixes: what a player was given comes out of the pull, and silence after it. Nothing
/// is connected to any device (manual rendering), so nothing plays and nothing is opened.
private func feat2OwnOutputTests() {
    let engine = AVAudioEngine(), player = AVAudioPlayerNode()
    engine.attach(player)
    let voice = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    do {
        try ArisOwnOutput.detach(engine)
        engine.connect(player, to: engine.mainMixerNode, format: voice)
        try engine.start()
    } catch {
        return check(false, "own output: the engine goes into mixing only (\(error))")
    }
    check(engine.isInManualRenderingMode && engine.manualRenderingFormat.sampleRate == 48_000 && engine.manualRenderingFormat.channelCount == 2,
          "own output: the engine is off the hardware and mixes to 48 kHz stereo")
    let buffer = AVAudioPCMBuffer(pcmFormat: voice, frameCapacity: 2_400)!
    buffer.frameLength = 2_400
    for index in 0..<2_400 { buffer.floatChannelData![0][index] = 0.5 }
    var played = false
    player.scheduleBuffer(buffer, completionCallbackType: .dataRendered) { _ in played = true }
    player.play()
    let source = ArisOwnOutput.Source(engine.manualRenderingBlock)
    let frames: UInt32 = 512
    let list = AudioBufferList.allocate(maximumBuffers: 2)
    defer { for item in list { free(item.mData) }; free(list.unsafeMutablePointer) }
    for index in 0..<2 {
        list[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: malloc(Int(frames) * 4))
    }
    var loudest: Float = 0, lastLoudest: Float = 1
    for _ in 0..<40 {
        for item in list { memset(item.mData, 0x7F, Int(frames) * 4) }
        ArisOwnOutput.pull(source, frames: frames, into: list.unsafeMutablePointer)
        let samples = UnsafeBufferPointer(start: list[0].mData!.assumingMemoryBound(to: Float.self), count: Int(frames))
        lastLoudest = samples.map(abs).max() ?? 0
        loudest = max(loudest, lastLoudest)
    }
    check(loudest > 0.3 && loudest < 0.8, "own output: what the player was given comes out of the pull (\(loudest))")
    check(lastLoudest == 0, "own output: once the voice has ended the pull is silence, not what was in the buffer before")
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    check(played, "own output: a buffer's completion still fires when it has been mixed")
    engine.stop()
    ArisOwnOutput.attach(engine)
    check(!engine.isInManualRenderingMode, "own output: the engine can be given its hardware output back")
    check(ArisOwnOutput().isRunning == false, "own output: no unit runs until it is started")
}

// MARK: - Every microphone goes through the plan

private func feat2MicWiringTests() {
    let wake = feat2Source("Aris/private/Aris/ArisWakeDetector.swift"), listener = feat2Source("Aris/private/Aris/ArisListener.swift")
    let speaker = feat2Source("Aris/private/Aris/ArisSpeaker.swift"), controller = feat2Source("Aris/private/Aris/ArisController+Wake.swift")
    check(wake.contains("try ArisMicDevices.pin(engine, for: use)") && !wake.contains("ArisMicChoice.apply"),
          "wiring: the wake word's engine is pinned by the plan before its input is read")
    check(listener.contains("try ArisMicDevices.pin(engine, for: parts.use)") && !listener.contains("ArisMicChoice.apply"),
          "wiring: a turn's and dictation's engine is pinned by the plan before its tap is installed")
    if let pin = wake.range(of: "ArisMicDevices.pin("), let node = wake.range(of: "let mic = engine.inputNode") {
        check(pin.lowerBound < node.lowerBound, "wiring: the wake word pins its device before it touches the input node's format")
    } else {
        check(false, "wiring: the wake word pins its device before it touches the input node's format")
    }
    check(wake.contains("ArisMicDevices.noteClosed(use, transport: transport)") && listener.contains("ArisMicDevices.noteClosed(use, transport: nil)"),
          "wiring: every close of a microphone is logged with who had it")
    check(speaker.contains("ArisMicDevices.voiceRoute()") && speaker.contains("try ownOutput.start(engine)") && speaker.contains("ArisOwnOutput.detach(engine)")
          && !speaker.contains("inputNode") && !speaker.contains("setVoiceProcessingEnabled"),
          "wiring: the voice chooses its way out each time it starts, and never touches an input or voice processing")
    check(controller.contains("state.headsetOnly = micPlan == .pause(.headsetOnly)") && controller.contains("ArisMicWatch { [weak self] in self?.micDevicesChanged() }")
          && controller.contains("case .settingOff?, .otherAudio?, .headsetOnly?: return stopWaitingForWakeWord()"),
          "wiring: the wake word asks the plan each time it arms, closes its microphone when it must pause, and watches the devices")
    let engines = ["Aris/private/Aris/ArisWakeDetector.swift", "Aris/private/Aris/ArisListener.swift", "Aris/private/Aris/ArisSpeaker.swift",
                   "Aris/private/Aris/Onboarding/ArisOnboardingAudio.swift"]
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..").standardized
    var found: [String] = []
    for folder in ["Aris", "ArisAgent", "ArisTools", "ArisXPCHelper"] {
        let files = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift", let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if text.contains("AVAudioEngine()") || text.contains("AVAudioRecorder(") || text.contains("AVCaptureSession(") {
                found.append(String(file.path.dropFirst(root.path.count + 1)))
            }
        }
    }
    check(Set(found) == Set(engines), "wiring: no new audio engine or recorder has appeared outside the four known files (\(found.sorted()))")
}

// MARK: - Quiet hours: any hours

private func feat2QuietSpanTests() {
    typealias S = ArisQuietSpan
    check(S(stored: "23-7") == S(stored: "23:00-7:00") && S(stored: "23-7")?.start == 23 * 60 && S(stored: "23-7")?.end == 7 * 60,
          "quiet hours: the old range and the same two times with their minutes are the same night")
    check(S(stored: "22:30-6:00")?.start == 22 * 60 + 30 && S(stored: "22:30-6")?.end == 6 * 60 && S(stored: "0:30-8:05")?.end == 8 * 60 + 5,
          "quiet hours: a start or an end at any minute is read")
    check(S(stored: "off") == nil && S(stored: "7-7") == nil && S(stored: "22:30-22:30") == nil && S(stored: "7:00-7") == nil,
          "quiet hours: off, or a start and an end at the same minute, is no quiet time")
    for bad in ["", "밤", "25-7", "23-7-1", "23:60-7", "23:5-7", "-7", "23-", "+7-8", "23 - 7", "7:00:00-8", "a:30-8", "123-7"] {
        check(S(stored: bad) == S(stored: "23-7") && S.edges(bad) == nil, "quiet hours: “\(bad)” can't be read, so it is the standard night, never off")
    }
    check(S.edges("7-7").map { $0 == (420, 420) } == true && S.edges("off") == nil, "quiet hours: the same time twice is still two times the row can show")
    let night = S(stored: "22:30-6:00")!
    check(night.contains(minute: 22 * 60 + 30) && night.contains(minute: 23 * 60 + 59) && night.contains(minute: 0) && night.contains(minute: 5 * 60 + 59)
          && !night.contains(minute: 6 * 60) && !night.contains(minute: 22 * 60 + 29) && !night.contains(minute: 12 * 60),
          "quiet hours: 22:30 to 06:00 runs past midnight: 22:30 is quiet, 22:29 and 06:00 are not")
    let nap = S(stored: "13:00-14:30")!
    check(nap.contains(minute: 13 * 60) && nap.contains(minute: 14 * 60 + 29) && !nap.contains(minute: 14 * 60 + 30) && !nap.contains(minute: 12 * 60 + 59)
          && !nap.contains(minute: 0), "quiet hours: a range inside one day does not wrap")
    check(S.clock(0) == "0:00" && S.clock(7 * 60 + 5) == "7:05" && S.clock(23 * 60 + 30) == "23:30" && S.clock(24 * 60) == "0:00",
          "quiet hours: a time is written as hours and two-digit minutes")
    check(S.picked(start: 23 * 60, end: 7 * 60) == "23:00-7:00" && S.stored(start: 23 * 60, end: 7 * 60) == "23-7" && S.stored(start: 22 * 60, end: 7 * 60) == "22-7"
          && S.stored(start: 22 * 60 + 30, end: 6 * 60) == "22:30-6:00" && S.stored(start: 420, end: 420) == "7:00-7:00",
          "quiet hours: two times said aloud are stored as the old range when they are one, else as said")
    check(S.choice(for: "off") == "off" && S.choice(for: "22-7") == "22-7" && S.choice(for: "23:00-7:00") == S.custom && S.choice(for: "22:30-6:00") == S.custom
          && S.choice(for: "7:00-7:00") == S.custom && S.choice(for: "garbage") == "23-7",
          "quiet hours: the row shows off, an old range, or 직접 고르기 for two times of his own")
    check(S.choosing(S.custom, current: "23-7") == "23:00-7:00" && S.choosing(S.custom, current: "0-8") == "0:00-8:00" && S.choosing(S.custom, current: "off") == "23:00-7:00"
          && S.choosing(S.custom, current: "22:30-6:00") == "22:30-6:00" && S.choosing(S.custom, current: "broken") == "23:00-7:00",
          "quiet hours: 직접 고르기 keeps the hours that were set (the standard night when it was off)")
    check(S.choosing("off", current: "22:30-6:00") == "off" && S.choosing("0-8", current: "off") == "0-8" && S.choosing("nonsense", current: "off") == "23-7",
          "quiet hours: 끄기 and the old ranges are stored as they always were")
    check(S.setting(start: "21:30", current: "23:00-7:00") == "21:30-7:00" && S.setting(end: "8:30", current: "23:00-7:00") == "23:00-8:30"
          && S.setting(start: "7:00", current: "23:00-7:00") == "7:00-7:00" && S.setting(start: "x", current: "23:00-7:00") == "23:00-7:00"
          && S.setting(end: "6:00", current: "off") == "23:00-6:00",
          "quiet hours: a menu changes its own time and leaves the other")
    check(S.menuTimes(including: 23 * 60).count == 48 && S.menuTimes(including: 23 * 60).first == 0 && S.menuTimes(including: 23 * 60).last == 23 * 60 + 30
          && S.menuTimes(including: 22 * 60 + 45).count == 49 && S.menuTimes(including: 22 * 60 + 45)[46] == 22 * 60 + 45,
          "quiet hours: a menu lists every half hour, and a time set by voice between two of them in its place")
    typealias H = ArisQuietHours
    check(H(stored: "23-7")?.start == 23 && H(stored: "22:30-6:00")?.start == 22 && H(stored: "22:30-6:00")?.end == 6 && H(stored: "7-7") == nil && H(stored: "off") == nil,
          "quiet hours: the gate's own type reads the same values")
}

private func feat2QuietGateTests() {
    typealias G = ArisQuietGate
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let at = { (hour: Int, minute: Int) in calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour, minute: minute, second: 30))! }
    let quiet = { (hours: String, hour: Int, minute: Int) in
        G.verdict(.aris, muted: false, hours: hours, screenAway: false, now: at(hour, minute), calendar: calendar) == .textOnly(.night)
    }
    check(!quiet("22:30-6:00", 22, 29) && quiet("22:30-6:00", 22, 30) && quiet("22:30-6:00", 23, 59) && quiet("22:30-6:00", 0, 0)
          && quiet("22:30-6:00", 5, 59) && !quiet("22:30-6:00", 6, 0) && !quiet("22:30-6:00", 14, 0),
          "the gate at the edges: 22:30–06:00 starts at 22:30 sharp, runs across midnight and ends at 06:00 sharp")
    check(!quiet("1:00-1:30", 0, 59) && quiet("1:00-1:30", 1, 0) && quiet("1:00-1:30", 1, 29) && !quiet("1:00-1:30", 1, 30),
          "the gate at the edges: a half hour in the small hours is quiet for exactly that half hour")
    check(!quiet("7:00-7:00", 7, 0) && !quiet("7:00-7:00", 3, 0) && !quiet("off", 3, 0), "the gate: the same start and end, like off, is never quiet")
    check(quiet("23-7", 23, 0) && quiet("23-7", 6, 59) && !quiet("23-7", 7, 0) && !quiet("23-7", 22, 59) && quiet("nonsense", 2, 0),
          "the gate: the old ranges read as before, and an unreadable value is still the standard night")
    check(G.verdict(.user, muted: false, hours: "22:30-6:00", screenAway: false, now: at(23, 0), calendar: calendar) == .aloud
          && G.verdict(.userTimer, muted: false, hours: "22:30-6:00", screenAway: false, now: at(23, 0), calendar: calendar) == .aloud,
          "the gate: an answer to what the user asks, and his own timer, still sound inside his own hours")
}

private func feat2QuietSpokenTests() {
    typealias A = ArisQuietHoursAsk
    let said = { (words: String) in A.parse(ArisIntent.phrase(of: words)) }
    let korean: [(String, String)] = [
        ("방해 금지 시간을 밤 11시부터 아침 8시로 바꿔 줘", "23:00-8:00"), ("방해 금지 시간을 밤 11시부터 아침 7시로 바꿔 줘", "23-7"),
        ("방해금지 시간 밤 10시 반부터 아침 6시까지로 해 줘", "22:30-6:00"), ("조용한 시간 11시부터 7시까지", "23-7"),
        ("밤에는 조용히 12시부터 8시까지로 바꿔", "0-8"), ("방해 금지 시간을 저녁 9시부터 새벽 5시 30분까지로 맞춰 줘", "21:00-5:30"),
        ("방해 금지 시간 22시부터 7시까지", "22-7"), ("방해 금지 시간을 자정부터 아침 6시까지로", "0:00-6:00"),
        ("아리스, 방해 금지 시간을 오후 11시부터 오전 6시 30분으로 바꿔 줘", "23:00-6:30"), ("방해 금지 밤 11시부터 아침 8시까지", "23:00-8:00"),
    ]
    for (words, stored) in korean { check(said(words) == stored, "said in Korean: “\(words)” sets \(stored) (got \(said(words) ?? "nothing"))") }
    let english: [(String, String)] = [
        ("set quiet hours from 10 pm to 7 am", "22-7"), ("Set quiet hours from 10:30 PM to 6 AM.", "22:30-6:00"), ("quiet hours 11pm to 8am", "23:00-8:00"),
        ("change quiet hours to 11 to 7", "23-7"), ("make quiet time from midnight until 8 a.m.", "0-8"), ("quiet hours between 9 p.m. and 5:30 a.m.", "21:00-5:30"),
        ("set my quiet hours from 23:00 to 6:30", "23:00-6:30"), ("Aris, set quiet hours from ten pm to seven am", "22-7"),
    ]
    for (words, stored) in english { check(said(words) == stored, "said in English: “\(words)” sets \(stored) (got \(said(words) ?? "nothing"))") }
    for words in ["방해 금지 시간 꺼 줘", "방해 금지 시간을 꺼", "조용한 시간 없애 줘", "turn off quiet hours", "quiet hours off", "disable quiet hours please"] {
        check(said(words) == "off", "said: “\(words)” turns quiet hours off (got \(said(words) ?? "nothing"))")
    }
    for words in ["방해 금지 모드 켜 줘", "방해 금지 꺼 줘", "방해 금지 시간이 뭐야", "방해 금지 시간 알려 줘", "밤 11시부터 아침 8시까지 뭐 했어", "조용히 해 줘",
                  "quiet hours", "what are my quiet hours", "turn on do not disturb", "set a timer from 10 pm", "방해 금지 시간을 11시로 바꿔 줘",
                  "be quiet", "오늘 밤 11시에 깨워 줘", ""] {
        check(said(words) == nil, "said: “\(words)” does not set quiet hours")
    }
    check(ArisIntent.parse("방해 금지 시간을 밤 11시부터 아침 8시로 바꿔 줘") == .quietHours("23:00-8:00")
          && ArisIntent.parse("set quiet hours from 10 pm to 7 am") == .quietHours("22-7") && ArisIntent.parse("방해 금지 시간 꺼 줘") == .quietHours("off"),
          "aris: quiet hours are set on the Mac, with no AI")
    check(ArisIntent.parse("조용히 해 줘") == .arisMute(true) && ArisIntent.parse("타이머 10분") == .timer(seconds: 600, focus: false),
          "aris: the mute and the timer are still theirs")
    check(ArisIntent.parse("방해 금지 시간을 밤 11시부터 아침 8시로 바꿔야 할까?") == .ask("방해 금지 시간을 밤 11시부터 아침 8시로 바꿔야 할까?")
          && ArisIntent.parse("방해 금지 시간을 밤 11시부터 아침 8시로 바꾸지 마") == .ask("방해 금지 시간을 밤 11시부터 아침 8시로 바꾸지 마")
          && ArisIntent.guarded(.quietHours("23-7"), said: "방해 금지 시간 바꾸지 마") == .ask("방해 금지 시간 바꾸지 마"),
          "aris: a question or a don't about quiet hours is the AI's, never done")
    check(ArisIntent.parse("방해 금지 시간을 밤 11시부터 아침 8시로 바꾸고 음악 틀어 줘") == .ask("방해 금지 시간을 밤 11시부터 아침 8시로 바꾸고 음악 틀어 줘"),
          "aris: a request that goes on after the hours is the AI's, whole")
    check(ArisIntent.quietHours("23-7").isOneAct && !ArisIntent.quietHours("23-7").isReadOnly && ArisIntent.quietHours("23-7").acknowledgement(korean: true) == nil,
          "aris: setting the hours is one act whose reply says the new hours")
    typealias C = ArisQuietHoursCopy
    check(C.reply(stored: "23:00-8:00", was: "23-7", english: false) == "방해 금지 시간을 밤 11시부터 아침 8시까지로 바꿨어요."
          && C.reply(stored: "22:30-6:00", was: "23-7", english: true) == "Quiet hours are now 10:30 PM to 6 AM.",
          "reply: the new hours are said back")
    check(C.reply(stored: "23-7", was: "23:00-7:00", english: false) == "방해 금지 시간은 이미 밤 11시부터 아침 7시까지예요."
          && C.reply(stored: "23-7", was: "23-7", english: true) == "Quiet hours are already 11 PM to 7 AM.", "reply: never “바꿨어요” for hours that were already those")
    check(C.reply(stored: "off", was: "23-7", english: false).hasPrefix("방해 금지 시간을 껐어요") && C.reply(stored: "off", was: "off", english: false) == "방해 금지 시간은 이미 꺼져 있어요."
          && C.reply(stored: "off", was: "7:00-7:00", english: true) == "Quiet hours are already off." && C.reply(stored: "off", was: "23-7", english: true).hasPrefix("Quiet hours are off"),
          "reply: turning them off says so, from what they were")
    check(C.reply(stored: "7:00-7:00", was: "23-7", english: false).contains("방해 금지 시간이 없어요") && C.reply(stored: "7:00-7:00", was: "23-7", english: true).contains("same as off"),
          "reply: the same start and end is said to be no quiet hours, not a change to them")
    check(C.said(0, english: true) == "12 AM" && C.said(12 * 60, english: true) == "12 PM" && C.said(13 * 60 + 5, english: true) == "1:05 PM" && C.said(0, english: false) == "밤 12시",
          "reply: midnight and noon are said as people say them")
    let controller = feat2Source("Aris/private/Aris/ArisController+Local.swift"), live = feat2Source("Aris/private/Aris/ArisQuietLive.swift")
    check(controller.contains("case .quietHours(let stored):") && controller.contains("return setQuietHours(stored, korean: korean)")
          && live.contains("Defaults[.arisQuietHours] = stored") && live.contains("ArisQuietHoursCopy.reply(stored: stored, was: was, english: !korean)"),
          "wiring: the spoken hours are stored in the preference the gate reads, and answered from what was stored")
}

private func feat2QuietRowTests() {
    typealias C = ArisQuietHoursCopy
    var snapshot = ArisSettingsSnapshot()
    let rows = { (stored: String) -> [ArisSettingItem] in
        snapshot.quietHours = stored
        return ArisSettingsBuilder.sections(.aris, snapshot).first { $0.id == "aris.alerts" }?.rows.filter { $0.id.hasPrefix("aris.quiet") } ?? []
    }
    let standard = rows("23-7")
    if standard.count == 1, case .choice(let key, let options, let selected, _, _) = standard[0].control {
        check(key == .quietHours && options.map(\.id) == ["off", "22-7", "23-7", "0-8", "custom"] && options.last?.title == "직접 고르기" && selected == "23-7",
              "settings: 밤에는 조용히 offers 끄기, the three nights and 직접 고르기, and no menus until it is picked")
    } else {
        check(false, "settings: 밤에는 조용히 offers 끄기, the three nights and 직접 고르기, and no menus until it is picked")
    }
    check(rows("off").count == 1 && rows("garbage").count == 1, "settings: off and an unreadable value show the one row")
    let own = rows("22:30-6:00")
    check(own.map(\.id) == ["aris.quietHours", "aris.quietStart", "aris.quietEnd"] && own.map(\.title) == ["밤에는 조용히", "시작", "끝"],
          "settings: with 직접 고르기 picked, 시작 and 끝 sit under it")
    if own.count == 3, case .choice(_, _, let selected, _, _) = own[0].control, case .menu(let startKey, let starts, let start) = own[1].control,
       case .menu(let endKey, let ends, let end) = own[2].control {
        check(selected == "custom" && startKey == .quietStart && endKey == .quietEnd && start == "22:30" && end == "6:00" && starts.count == 48 && ends.count == 48
              && starts.first?.title == "00:00" && starts[45].id == "22:30" && starts[45].title == "22:30" && ends[12].title == "06:00",
              "settings: each menu lists every half hour and shows the stored time")
    } else {
        check(false, "settings: each menu lists every half hour and shows the stored time")
    }
    check(own.dropFirst().allSatisfy { !$0.indexed && $0.desc == nil }, "settings: the two menus are found through their row, and say nothing more")
    check(rows("7:00-7:00").last?.desc == C.sameTimes, "settings: the same start and end says it is off for now")
    if case .menu(_, let options, let selected)? = rows("22:45-6:00").dropFirst().first?.control {
        check(options.count == 49 && selected == "22:45" && options.contains { $0.id == "22:45" }, "settings: a time set by voice between two half hours is in the menu")
    } else {
        check(false, "settings: a time set by voice between two half hours is in the menu")
    }
    // In English every string of the rows has its English (the pages look each one up: ArisSettingsCopyMore).
    ArisSettingsCopy.install([:])
    let english = ArisSettingsWording.make(page: .aris, english: true)
    let shown = ArisSettingsWording.shown(english.sections([ArisSettingSection(id: "x", rows: Array(rows("7:00-7:00").dropFirst()))]))
    check(shown.contains("Start") && shown.contains("End") && shown.contains("11:30 PM") && shown.contains("12:00 AM") && shown.contains("7:00 AM")
          && !shown.contains { $0.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } },
          "settings in English: Start, End and the times are English, with nothing Korean left (\(shown.filter { $0.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } }.prefix(3)))")
    check(ArisSettingsCopy.english(C.customLabel) == "Custom" && ArisSettingsCopyMore.english.count >= 52
          && ArisSettingsCopyMore.english.allSatisfy { !$0.value.isEmpty && !$0.value.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } },
          "settings in English: every new string has its English beside it")
    let live = feat2Source("Aris/components/Settings/ArisLiveSettings.swift")
    check(live.contains("case .quietHours: quietHours = ArisQuietSpan.choosing(text, current: quietHours)")
          && live.contains("case .quietStart: quietHours = ArisQuietSpan.setting(start: text, current: quietHours)")
          && live.contains("case .quietEnd: quietHours = ArisQuietSpan.setting(end: text, current: quietHours)"),
          "wiring: the choice and both menus write the one preference")
}

// MARK: - A teammate's terminal

private func feat2TerminalChoiceTests() {
    typealias C = ArisTerminalChoice
    typealias F = ArisTerminalChoice.Facts
    let command = "cd '/Users/p/proj' && '/Users/p/.local/bin/claude' \"$(cat '/Users/p/.config/aris/aris/work/cc-x.txt')\""
    let pick = { (facts: F) in C.pick(facts, command: command) }
    check(pick(F()) == C.Pick(terminal: .terminal), "terminal: a Mac with only Terminal opens Terminal")
    check(pick(F(installed: [.terminal, .iTerm])).terminal == .iTerm, "terminal: with iTerm2 installed and nothing else known, iTerm2 (as before)")
    check(pick(F(installed: [.terminal, .iTerm, .ghostty, .kitty], running: [.kitty, .ghostty])).terminal == .kitty,
          "terminal: with nothing remembered, the running terminal whose window is nearest the front")
    check(pick(F(lastUsed: "ghostty", installed: [.terminal, .iTerm, .ghostty, .kitty], running: [.kitty])).terminal == .ghostty,
          "terminal: the one the user last ran Claude Code in comes before the one that happens to be in front")
    check(pick(F(pinned: "alacritty", lastUsed: "ghostty", installed: [.terminal, .ghostty, .alacritty], running: [.ghostty])).terminal == .alacritty,
          "terminal: a terminal pinned in Settings comes before everything")
    check(pick(F(pinned: "terminal", lastUsed: "ghostty", installed: [.terminal, .ghostty, .iTerm], running: [.ghostty])).terminal == .terminal,
          "terminal: Terminal pinned is Terminal, whatever else is installed or running")
    check(pick(F(lastUsed: "terminal", installed: [.terminal, .iTerm])).terminal == .terminal,
          "terminal: someone who runs Claude Code in Terminal gets Terminal, even with iTerm2 installed")
    check(pick(F(pinned: "kitty", lastUsed: "wezterm", installed: [.terminal, .iTerm])).terminal == .iTerm,
          "terminal: a pinned or remembered terminal that is no longer installed is passed by without a word")
    check(pick(F(pinned: "auto", lastUsed: "", installed: [.terminal, .wezterm])).terminal == .wezterm && pick(F(pinned: "rm -rf", lastUsed: "$(x)", installed: [.terminal])).terminal == .terminal,
          "terminal: 자동, an empty memory and anything that is no terminal's name mean nothing is pinned")
    check(C.order(F(installed: Set(ArisTerminal.allCases))) == [.iTerm, .ghostty, .warp, .kitty, .wezterm, .alacritty, .terminal],
          "terminal: with every terminal installed and nothing known, the order is iTerm2, Ghostty, Warp, kitty, WezTerm, Alacritty, Terminal")
    check(C.order(F(pinned: "warp", lastUsed: "kitty", installed: Set(ArisTerminal.allCases), running: [.ghostty, .kitty])) == [.warp, .kitty, .ghostty, .iTerm, .wezterm, .alacritty, .terminal],
          "terminal: pinned, then last used, then running front to back, then the rest, each once")
    // Warp: only a build that opens Tab Configs from a link, and only a command a Tab Config can hold.
    check(pick(F(lastUsed: "warp", installed: [.terminal, .warp, .iTerm], warpReady: true)) == C.Pick(terminal: .warp),
          "terminal: a Warp new enough to open a Tab Config from a link is used")
    check(pick(F(lastUsed: "warp", installed: [.terminal, .warp, .iTerm], warpReady: false)) == C.Pick(terminal: .iTerm, passedOver: .warp),
          "terminal: an older Warp is passed over for the next terminal, and that is told")
    check(pick(F(pinned: "warp", installed: [.terminal, .warp], warpReady: false)) == C.Pick(terminal: .terminal, passedOver: .warp),
          "terminal: an older Warp pinned in Settings falls back to Terminal, said honestly")
    check(C.pick(F(pinned: "warp", installed: [.terminal, .warp], warpReady: true), command: "cd '/Users/p/{{x}}' && claude") == C.Pick(terminal: .terminal, passedOver: .warp),
          "terminal: a folder Warp would read as a blank to fill in is never handed to Warp")
    check(pick(F(installed: [.terminal, .warp], running: [.terminal], warpReady: false)) == C.Pick(terminal: .terminal),
          "terminal: a Warp that was never going to be the one is not mentioned")
    typealias W = ArisTerminalWords
    check(W.passedOver(.warp, openedIn: .iTerm, english: false) == "Claude Code 작업 중 · 이 Warp는 명령을 받아 주지 못해서 iTerm2에서 열었어요"
          && W.passedOver(.warp, openedIn: .terminal, english: true) == "Claude Code at work · this Warp can't be handed a command, so it opened in Terminal",
          "terminal: the teammate's first line says which terminal was passed over and where it opened, in the request's language")
    check(Set(ArisTerminal.allCases.map(\.bundleId)).count == 7 && ArisTerminal(bundleId: "COM.MITCHELLH.GHOSTTY") == .ghostty && ArisTerminal(bundleId: "com.microsoft.VSCode") == nil
          && ArisTerminal(bundleId: nil) == nil && ArisTerminal(bundleId: "dev.warp.Warp-Stable") == .warp && ArisTerminal(bundleId: "org.alacritty") == .alacritty,
          "terminal: each of the seven is known by its bundle id, and an editor is not one")
    let policy = feat2Source("ArisAgent/ArisRiskPolicy.swift"), actions = feat2Source("ArisTools/ArisActions.swift")
    for terminal in ArisTerminal.allCases {
        check(policy.contains("\"\(terminal.bundleId)\"") && actions.contains("\"\(terminal.bundleId.lowercased())\""),
              "terminal: \(terminal.title) is on the risk policy's list of apps computer use never works in, and never typed into")
    }
}

private func feat2TerminalPlanTests() {
    typealias L = ArisTerminalLaunch
    let id = UUID(uuidString: "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9")!
    let work = "/Users/p/.config/aris/aris/work", warp = "/Users/p/.warp/tab_configs"
    // A folder with every character a shell or a script language treats specially; the task's text is never in the
    // command at all (it is in the prompt file the shell reads).
    let hostile = "/Users/p/it's \"quoted\" $(rm -rf ~) `id` \\ ; & | proj"
    let command = ArisClaudeLaunch.command(promptFile: work + "/cc-0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9.txt", cwd: hostile, claude: "/Users/p/.local/bin/claude")
    check(command == "cd '/Users/p/it'\\''s \"quoted\" $(rm -rf ~) `id` \\ ; & | proj' && '/Users/p/.local/bin/claude' \"$(cat '/Users/p/.config/aris/aris/work/cc-0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9.txt')\"",
          "launch: the command single-quotes the folder, the checked claude and the prompt file, as before")
    let plan = { (terminal: ArisTerminal) in L.plan(terminal, command: command, shell: "/bin/zsh", folder: work, warpFolder: warp, id: id) }
    check(plan(.terminal) == .script(ArisClaudeLaunch.script(command: command, host: .terminal)) && plan(.iTerm) == .script(ArisClaudeLaunch.script(command: command, host: .iTerm)),
          "launch: Terminal and iTerm2 are still opened by the same AppleScript")
    if case .script(let text) = plan(.terminal) {
        check(text == "tell application id \"com.apple.Terminal\"\n    activate\n    do script \"cd '/Users/p/it'\\\\''s \\\"quoted\\\" $(rm -rf ~) `id` \\\\ ; & | proj' && '/Users/p/.local/bin/claude' \\\"$(cat '/Users/p/.config/aris/aris/work/cc-0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9.txt')\\\"\"\nend tell",
              "launch: Terminal's script, word for word, with a hostile folder escaped twice (shell, then AppleScript)")
    } else {
        check(false, "launch: Terminal's script, word for word, with a hostile folder escaped twice (shell, then AppleScript)")
    }
    let script = work + "/cc-0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9.sh"
    let run = ["/bin/zsh", "-l", "-i", script]
    let expected: [(ArisTerminal, [String])] = [(.ghostty, ["--window-save-state=never", "-e"] + run), (.kitty, run),
                                               (.wezterm, ["start", "--always-new-process", "--"] + run), (.alacritty, ["-e"] + run)]
    for (terminal, arguments) in expected {
        if case .arguments(let made, let path, let text) = plan(terminal) {
            check(made == arguments && path == script, "launch: \(terminal.title) is started with exactly \(arguments.dropLast(4).joined(separator: " ")) <shell> -l -i <script>")
            check(text == "rm -f -- '\(script)'\n\(command)\nexec '/bin/zsh' -l -i\n",
                  "launch: \(terminal.title)'s launch script deletes itself, runs the command and leaves a shell open")
            check(!made.contains { $0.contains("$(") || $0.contains("'") || $0.contains(" ") || $0.contains("proj") },
                  "launch: nothing of the folder or the command is in \(terminal.title)'s arguments (only the script's path)")
        } else {
            check(false, "launch: \(terminal.title) is started with arguments")
        }
    }
    check(L.scriptFileName(id) == "cc-0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9.sh", "launch: the script sits beside the prompt file, under the same id's pattern")
    check(L.shell("/bin/zsh") == "/bin/zsh" && L.shell("/opt/homebrew/bin/fish") == "/opt/homebrew/bin/fish" && L.shell("/usr/local/bin/bash-5.2+x") == "/usr/local/bin/bash-5.2+x",
          "launch: the account's own shell runs the script")
    for bad in [nil, "", "zsh", "/bin/zsh; rm -rf ~", "/bin/z sh", "/bin/$(id)", "/bin/../bin/zsh", "/bin/zsh'", String(repeating: "/a", count: 150)] as [String?] {
        check(L.shell(bad) == "/bin/zsh", "launch: a shell path that is not a plain absolute path (\(bad ?? "none")) is zsh")
    }
    let launcher = feat2Source("ArisAgent/ArisTeammateLauncher.swift"), opener = feat2Source("ArisAgent/ArisTerminalOpener.swift")
    check(launcher.contains(#"^cc-[0-9a-f-]{36}\.(txt|sh)$"#), "launch: a launch script its terminal never ran is swept with the prompt files after a day")
    check(opener.contains("O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW") && opener.contains("ArisPrivateFile.prepareFolder(folder)") && opener.contains("mode: 0o700")
          && opener.contains("mode: 0o600") && opener.contains("ArisPrivateFile.isRealFolder(folder)"),
          "launch: the script and the Tab Config are new files that can't be links, the script in the 0700 work folder")
    check(opener.contains("configuration.createsNewApplicationInstance = true") && opener.contains("configuration.arguments = arguments")
          && !opener.contains("/bin/sh") && !opener.contains("Process()"),
          "launch: a terminal is started by macOS with its arguments as they are; no shell reads them")
}

private func feat2WarpTests() {
    typealias W = ArisWarpLaunch
    check(W.opensTabConfigs(version: "v0.2026.06.03.08.12.stable_02") && W.opensTabConfigs(version: "0.2026.11.04.08.11.stable_01") && W.opensTabConfigs(version: "v0.2027.01.07.08.02.stable_00")
          && W.opensTabConfigs(version: "v0.2026.06.01.08.00.stable_00"),
          "warp: a build from June 2026 on opens a Tab Config from its link")
    check(!W.opensTabConfigs(version: "v0.2026.04.08.08.36.stable_01") && !W.opensTabConfigs(version: "v0.2026.05.27.08.12.stable_02") && !W.opensTabConfigs(version: "v0.2025.12.17.08.12.stable_02")
          && !W.opensTabConfigs(version: nil) && !W.opensTabConfigs(version: "") && !W.opensTabConfigs(version: "1.2.3"),
          "warp: an older build, or one whose version can't be read, is not trusted with it")
    let id = UUID(uuidString: "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9")!
    check(W.configName(id) == "aris_teammate_0a1b2c3d4e5f60718293a4b5c6d7e8f9" && W.link(W.configName(id)) == "warp://tab_config/aris_teammate_0a1b2c3d4e5f60718293a4b5c6d7e8f9?new_window=true",
          "warp: the Tab Config has a name of Aris's own and is opened in a new window")
    check(URL(string: W.link(W.configName(id)))?.scheme == "warp", "warp: the link is a link")
    let command = "cd '/Users/p/it'\\''s \"q\" \\ proj' && '/Users/p/.local/bin/claude' \"$(cat '/Users/p/w/cc-x.txt')\""
    check(W.tabConfig(command: command) == "name = \"Aris · Claude Code\"\n\n[[panes]]\nid = \"main\"\ntype = \"terminal\"\ncommands = [\"cd '/Users/p/it'\\\\''s \\\"q\\\" \\\\ proj' && '/Users/p/.local/bin/claude' \\\"$(cat '/Users/p/w/cc-x.txt')\\\"\"]\n",
          "warp: the Tab Config, word for word: one terminal pane that runs the command, its quotes and backslashes escaped for TOML")
    check(W.tomlString("a\nb\tc\u{1}\u{7F}") == "\"a\\nb\\tc\\u0001\\u007F\"" && W.tomlString("한글 'x'") == "\"한글 'x'\"", "warp: control characters are escaped; other letters are kept")
    check(W.canRun(command) && !W.canRun("cd '/Users/p/{{repo}}' && claude"), "warp: a command holding {{…}} would open Warp's fill-in form, so it isn't handed over")
    check(!W.tabConfig(command: command).contains("[params"), "warp: nothing is asked before the command runs")
    let plan = ArisTerminalLaunch.plan(.warp, command: command, shell: "/bin/zsh", folder: "/w", warpFolder: "/Users/p/.warp/tab_configs", id: id)
    check(plan == .link("warp://tab_config/aris_teammate_0a1b2c3d4e5f60718293a4b5c6d7e8f9?new_window=true",
                        path: "/Users/p/.warp/tab_configs/aris_teammate_0a1b2c3d4e5f60718293a4b5c6d7e8f9.toml", contents: W.tabConfig(command: command)),
          "warp: its plan is the Tab Config's file in Warp's own folder, then the link")
}

private func feat2TerminalSettingTests() {
    typealias S = ArisTerminalSetting
    typealias M = ArisTerminalMemory
    let row = S.row(pinned: "auto", installed: [.terminal, .ghostty, .warp])
    check(row.id == "team.terminal" && row.title == "터미널" && row.control == .menu(.teammateTerminal, [.init(id: "auto", title: "자동"), .init(id: "terminal", title: "Terminal"),
                                                                                                      .init(id: "ghostty", title: "Ghostty"), .init(id: "warp", title: "Warp")], selected: "auto"),
          "settings: 터미널 is one menu: 자동, then the terminals installed on this Mac")
    if case .menu(_, let options, let selected) = S.row(pinned: "kitty", installed: []).control {
        check(options.map(\.id) == ["auto", "terminal"] && selected == "auto", "settings: a pinned terminal that is gone shows as 자동; Terminal is always listed")
    } else {
        check(false, "settings: a pinned terminal that is gone shows as 자동; Terminal is always listed")
    }
    if case .menu(_, _, let selected) = S.row(pinned: "ghostty", installed: [.ghostty]).control { check(selected == "ghostty", "settings: the pinned terminal is shown as picked") }
    check(ArisSettingsIndex.entry("team.terminal")?.page == .team && ArisSettingsIndex.teamAnchors.contains("team.terminal")
          && ArisSettingsIndex.search("터미널").first?.id == "team.terminal" && ArisSettingsIndex.search("ghostty").contains { $0.id == "team.terminal" },
          "settings: a search finds the row on the 팀원 page")
    ArisSettingsCopy.install([:])
    let english = ArisSettingsWording.make(page: .team, english: true)
    let shown = ArisSettingsWording.shown(english.sections([S.section(pinned: "auto", installed: [.terminal, .iTerm])]))
    check(shown.contains("Terminal") && shown.contains { $0.hasPrefix("The terminal a Claude Code teammate opens in") } && shown.contains("iTerm2")
          && shown.filter { $0.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } } == ["자동"],
          "settings in English: the row's own words have their English beside them (자동 is the catalog's)")
    let warp = TerminalRef(headers: ["x-warp-focus": "warp://session/0123456789abcdef0123456789abcdef"])
    let iterm = TerminalRef(headers: ["x-iterm-session": "w0t0p0:0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"])
    check(M.terminal(of: warp) == .warp && M.terminal(of: iterm) == .iTerm && M.terminal(of: TerminalRef(headers: ["x-term-program": "ghostty"])) == .ghostty
          && M.terminal(of: TerminalRef(headers: ["x-bundle-id": "net.kovidgoyal.kitty"])) == .kitty && M.terminal(of: TerminalRef(headers: ["x-term-program": "Apple_Terminal"])) == .terminal
          && M.terminal(of: TerminalRef(headers: ["x-term-program": "vscode"])) == nil && M.terminal(of: nil) == nil,
          "memory: the terminal a hook names is read from what TerminalRef already records; an editor's own terminal is none")
    check(M.used(event: "UserPromptSubmit", agent: "claude", terminal: warp, teammate: false) == .warp,
          "memory: a prompt the user sent to Claude Code himself says which terminal he uses")
    check(M.used(event: "UserPromptSubmit", agent: "claude", terminal: warp, teammate: true) == nil,
          "memory: a teammate's own session never counts (Aris chose that window)")
    check(M.used(event: "UserPromptSubmit", agent: "codex", terminal: warp, teammate: false) == nil && M.used(event: "PreToolUse", agent: "claude", terminal: warp, teammate: false) == nil
          && M.used(event: "SessionStart", agent: "claude", terminal: warp, teammate: false) == nil,
          "memory: only Claude Code's own prompt events count (a session's start may be a teammate's not yet matched)")
    check(M.pinned("auto") == nil && M.pinned("ghostty") == "ghostty" && M.pinned("") == nil && M.pinned("; rm") == nil, "memory: only a terminal's own name is ever sent to the agent as pinned")
    var watch = ArisTeammateCompletion()
    let job = UUID(), at = Date(timeIntervalSince1970: 1_800_000_000)
    watch.expect(job: job, cwd: "/Users/p/proj", launchedAt: at)
    _ = watch.observe("SessionStart", session: "ours", cwd: "/Users/p/proj", agent: "claude", source: "startup", at: at.addingTimeInterval(2))
    _ = watch.observe("SessionStart", session: "his", cwd: "/Users/p/other", agent: "claude", source: "startup", at: at.addingTimeInterval(3))
    check(watch.isTeammate(session: "ours") && !watch.isTeammate(session: "his") && !watch.isTeammate(session: "never heard"),
          "memory: a session that started in a waiting job's folder after its launch is the teammate's")
    _ = watch.observe("Stop", session: "ours", cwd: "/Users/p/proj", agent: "claude", at: at.addingTimeInterval(60))
    check(watch.isTeammate(session: "ours"), "memory: it stays the teammate's after its job is done")
}

private func feat2TerminalWiringTests() {
    let desk = feat2Source("ArisAgent/ArisTeammateDesk.swift"), client = feat2Source("Aris/private/Aris/ArisAgentClient+Teammate.swift")
    let teammate = feat2Source("Aris/private/Aris/ArisController+Teammate.swift"), live = feat2Source("Aris/components/Settings/ArisLiveSettings.swift")
    check(desk.contains("terminal: ArisTerminalWish(pinned: object[\"terminal\"] as? String, lastUsed: object[\"terminalUsed\"] as? String)")
          && desk.contains("try ArisTeammateLauncher.launchQuietly(command: command, title: title, wish: wish, english: english)") && desk.contains("ArisQuietLaunch.note(window.pick, english: state.english)"),
          "wiring: the agent takes the app's two hints, opens the picked terminal and names one it passed over")
    check(ArisTerminalWish(pinned: "ghostty", lastUsed: "warp") == ArisTerminalWish(pinned: "ghostty", lastUsed: "warp")
          && ArisTerminalWish(pinned: "x; rm -rf ~", lastUsed: "$(id)").pinned == nil && ArisTerminalWish(pinned: "x", lastUsed: "$(id)").lastUsed == nil
          && ArisTerminalWish(pinned: "auto").pinned == nil,
          "wiring: whatever a caller sends as a terminal, only a known terminal's name is kept")
    check(client.contains("body[\"terminal\"] = pinned") && client.contains("body[\"terminalUsed\"] = used.rawValue"),
          "wiring: the app sends the pinned terminal and the last one used with each launch")
    check(teammate.contains("setState(job.id, .running(step: launch.note ?? \"Claude Code 작업 중\"))") && teammate.contains("teammate: teammateWatch.isTeammate(session: event.sessionId)"),
          "wiring: the job's row shows the agent's note, and only the user's own sessions teach the terminal")
    check(live.contains("ArisTerminalSetting.section(pinned: teammateTerminal, installed: Self.installedTerminals())")
          && live.contains("case .teammateTerminal: teammateTerminal = ArisTerminalMemory.pinned(text) ?? ArisTerminal.automatic"),
          "wiring: the 팀원 page draws the row and its menu writes the preference")
    let job = UUID(), at = Date(timeIntervalSince1970: 1_800_000_000)
    let noted = ArisAgentReply.launched(ArisTeammateLaunch(job: job, pid: 42, cwd: "/p", at: at, window: 7, hooks: true, note: "Claude Code 작업 중 · 이 Warp는 명령을 받아 주지 못해서 Terminal에서 열었어요"))
    let plain = ArisAgentReply.launched(ArisTeammateLaunch(job: job, pid: 42, cwd: "/p", at: at, window: nil, hooks: nil))
    let read = { (reply: ArisAgentReply) in ArisAgentReply.parse(String(decoding: reply.line, as: UTF8.self).trimmingCharacters(in: .newlines)) }
    check(read(noted) == noted && read(plain) == plain,
          "wiring: the note travels with the launch, and a launch without one reads as before")
}

// MARK: - Dropped-file chips that learn

private func feat2LearnedShapeTests() {
    typealias L = ArisDropLearned
    check(L.normalized("  report-q3.pdf   민수에게\n메일로 보내줘. ", fileNames: ["report-q3.pdf"]) == "이 파일 민수에게 메일로 보내줘"
          && L.normalized("invoice 2026.pdf 민수에게 메일로 보내줘", fileNames: ["invoice 2026.pdf"]) == "이 파일 민수에게 메일로 보내줘",
          "shape: the same request about another file is the same shape (the file's name becomes 이 파일)")
    check(L.normalized("send Budget.xlsx to Minsu!", fileNames: ["budget.xlsx"]) == "send this file to Minsu"
          && L.normalized("send the budget to Minsu", fileNames: ["budget.xlsx"]) == "send this file to Minsu",
          "shape: in an English request the name becomes “this file”, with or without its ending")
    check(L.normalized("어제 받은 notes-final.docx 랑 합쳐서 요약해 줘", fileNames: ["a.pdf"]) == "어제 받은 이 파일 랑 합쳐서 요약해 줘",
          "shape: anything that reads as a file's name is replaced, the dropped one or not")
    check(L.key("이 파일 민수에게 메일로 보내 줘") == L.key("이 파일  민수에게 메일로 보내줘") && L.key("Send This File to Minsu") == L.key("send this file to minsu")
          && L.key("요약해 줘") != L.key("번역해 줘"),
          "shape: spacing and capitals don't make a new shape; other words do")
    check(L.normalized("", fileNames: []) == nil && L.normalized("   \n ", fileNames: []) == nil && L.normalized("...", fileNames: []) == nil, "shape: no words, nothing to remember")
    check(L.normalized(String(repeating: "가", count: 121), fileNames: []) == nil && L.normalized(String(repeating: "가", count: 120), fileNames: []) != nil,
          "shape: a request longer than 120 letters is a brief, not a habit: not remembered")
    for secret in ["비밀번호 hunter2로 압축해 줘", "이 파일 password 1234 로 잠가 줘", "api key 넣어서 올려 줘", "upload with token abc", "sk-ant-api03-AbCdEf0123456789xyzQRS 로 보내 줘",
                   "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 붙여서 보내", "암호 걸어서 보내 줘", "seed phrase 랑 같이 보관해 줘", "id_rsa 랑 같이 묶어 줘", "내 credentials 넣어 줘"] {
        check(L.normalized(secret, fileNames: ["a.pdf"]) == nil && L.looksSecret(secret), "shape: “\(secret.prefix(28))…” looks like it holds a secret, so it is never stored")
    }
    for plain in ["민수에게 메일로 보내 줘", "3페이지만 뽑아서 PDF로 만들어 줘", "send this to the design team on Slack", "2026년 11월 회의록 폴더에 넣어 줘", "summarize the key findings"] {
        check(L.normalized(plain, fileNames: []) != nil, "shape: “\(plain)” is an ordinary request and is remembered")
    }
    check(L.normalized("quarterly-report-2026-final-version2.pdf 민수에게 보내 줘", fileNames: ["quarterly-report-2026-final-version2.pdf"]) == "이 파일 민수에게 보내 줘"
          && L.normalized("passwords.txt 민수에게 보내 줘", fileNames: ["passwords.txt"]) == "이 파일 민수에게 보내 줘",
          "shape: a file's own name is never what makes a request a secret (it isn't stored at all)")
    check(L.kindKey([.pdf]) == "pdf" && L.kindKey([.pdf, .pdf, .pdf]) == "pdf" && L.kindKey([.pdf, .image]) == "image+pdf" && L.kindKey([.image, .pdf, .image]) == "image+pdf"
          && L.kindKey([]) == "" && Set([ArisDropKind.pdf, .document, .text, .image, .video, .audio, .folder, .other].map(L.name)).count == 8,
          "shape: files are told apart by their kinds, each once, whatever their order or number")
    let heard = ArisPendingFiles().adding([URL(fileURLWithPath: "/Users/p/a b.pdf"), URL(fileURLWithPath: "/Users/p/c.png")]).request(with: "이거 합쳐 줘")
    check(L.paths(in: heard) == ["/Users/p/a b.pdf", "/Users/p/c.png"] && L.paths(in: "이거 합쳐 줘").isEmpty && ArisPendingFiles.words(of: heard) == "이거 합쳐 줘",
          "shape: the files and his own words are read back out of the turn's request")
}

private func feat2LearnedCountingTests() {
    typealias L = ArisDropLearned
    let day = 86_400.0, start = Date(timeIntervalSince1970: 1_800_000_000)
    let at = { (days: Double) in start.addingTimeInterval(days * day) }
    var learned = L()
    learned = learned.recording("report.pdf 민수에게 메일로 보내줘", kinds: [.pdf], fileNames: ["report.pdf"], at: at(0))
    check(learned.habits.count == 1 && learned.habits[0].count == 1 && learned.habits[0].kind == "pdf" && learned.habits[0].request == "이 파일 민수에게 메일로 보내줘",
          "counting: the first use is remembered once, for that kind of file")
    check(learned.chips(for: [.pdf], at: at(0)).isEmpty, "threshold: one use is not a chip")
    learned = learned.recording("invoice.pdf 민수에게 메일로 보내 줘", kinds: [.pdf], fileNames: ["invoice.pdf"], at: at(3))
    check(learned.habits.count == 1 && learned.habits[0].count == 2 && learned.chips(for: [.pdf], at: at(3)).isEmpty, "threshold: two uses are not a chip, and the same shape counts up")
    learned = learned.recording("이 파일 민수에게 메일로 보내줘", kinds: [.pdf, .pdf], fileNames: ["a.pdf", "b.pdf"], at: at(10))
    check(learned.habits[0].count == 3 && learned.chips(for: [.pdf], at: at(10)).map(\.request) == ["이 파일 민수에게 메일로 보내줘"],
          "threshold: the third use within sixty days makes it a chip, worded as he last said it")
    check(learned.chips(for: [.image], at: at(10)).isEmpty && learned.chips(for: [.pdf, .image], at: at(10)).isEmpty && learned.chips(for: [], at: at(10)).isEmpty,
          "counting: a habit is for the kind of file it was made with, not for another")
    // Decay: the three uses must lie within sixty days of now.
    check(!learned.chips(for: [.pdf], at: at(59)).isEmpty && !learned.chips(for: [.pdf], at: at(60)).isEmpty && learned.chips(for: [.pdf], at: at(60.5)).isEmpty,
          "decay: sixty days after the first of its three uses it is no longer a chip")
    let revived = learned.recording("이 파일 민수에게 메일로 보내줘", kinds: [.pdf], fileNames: [], at: at(61))
    check(revived.habits[0].count == 4 && !revived.chips(for: [.pdf], at: at(61)).isEmpty, "decay: a use while it is still remembered brings the chip back (its last three are within sixty days)")
    let forgotten = learned.recording("이 파일 민수에게 메일로 보내줘", kinds: [.pdf], fileNames: [], at: at(100))
    check(forgotten.habits.count == 1 && forgotten.habits[0].count == 1 && forgotten.chips(for: [.pdf], at: at(100)).isEmpty,
          "decay: unused for more than sixty days it is forgotten, and starts again from one")
    // Not their words, or not to be kept: nothing changes.
    check(learned.recording("", kinds: [.pdf], fileNames: [], at: at(11)) == learned && learned.recording("요약해 줘", kinds: [], fileNames: [], at: at(11)) == learned
          && learned.recording("비밀번호 1234로 잠가 줘", kinds: [.pdf], fileNames: [], at: at(11)) == learned,
          "counting: no words, no files or a secret leave the memory as it was")
    // Ordering: the most used first, then the most recent; two at most.
    var many = learned
    for (request, uses) in [("요약해서 노션에 올려 줘", 5), ("영어로 번역해 줘", 3), ("3쪽만 남겨 줘", 4)] {
        for use in 0..<uses { many = many.recording(request, kinds: [.pdf], fileNames: [], at: at(12 + Double(use))) }
    }
    check(many.chips(for: [.pdf], at: at(20)).map(\.request) == ["요약해서 노션에 올려 줘", "3쪽만 남겨 줘"], "ordering: the two most used come up, the most used first")
    let tie = L().recording("가 해 줘", kinds: [.image], fileNames: [], at: at(0)).recording("가 해 줘", kinds: [.image], fileNames: [], at: at(1)).recording("가 해 줘", kinds: [.image], fileNames: [], at: at(2))
        .recording("나 해 줘", kinds: [.image], fileNames: [], at: at(3)).recording("나 해 줘", kinds: [.image], fileNames: [], at: at(4)).recording("나 해 줘", kinds: [.image], fileNames: [], at: at(5))
    check(tie.chips(for: [.image], at: at(6)).map(\.request) == ["나 해 줘", "가 해 줘"], "ordering: used equally often, the more recent first")
    let offer = ArisDropChips.offer([ArisDropFile(path: "/Users/p/a.pdf", kind: .pdf, text: .found, hold: nil, convertible: true)], english: false)
    let row = ArisDropRowItem.firstRow(learned: ArisDropLearnedChip.make(many.chips(for: [.pdf], at: at(20))), main: offer.main)
    check(row.count == 2 + offer.main.count && row.prefix(2).allSatisfy { if case .learned = $0 { return true } else { return false } }
          && row.dropFirst(2).map(\.id) == offer.main.map(\.id) && Set(row.map(\.id)).count == row.count,
          "ordering: his own chips come first, then the built-in ones in their own order, each with an id of its own")
    check(ArisDropRowItem.firstRow(learned: [], main: offer.main).map(\.id) == offer.main.map(\.id), "ordering: with nothing learned the row is the built-in chips, as before")
    // Forgetting.
    let chip = many.chips(for: [.pdf], at: at(20))[0]
    check(!many.forgetting(chip).habits.contains { $0.id == chip.id } && many.forgetting(chip).habits.count == many.habits.count - 1
          && many.forgetting(chip).chips(for: [.pdf], at: at(20)).map(\.request) == ["3쪽만 남겨 줘", "영어로 번역해 줘"],
          "forgetting: 이 제안 지우기 removes that one and the next one moves up")
    check(many.forgettingAll().habits.isEmpty && many.forgettingAll().chips(for: [.pdf], at: at(20)).isEmpty, "forgetting: 배운 제안 지우기 removes them all")
    // The cap: two hundred shapes, the least recently used going first.
    var full = L()
    for index in 0..<230 { full = full.recording("요청 \(index)번 해 줘", kinds: [.document], fileNames: [], at: at(Double(index) / 100)) }
    check(full.habits.count == 200 && !full.habits.contains { $0.request == "요청 0번 해 줘" } && full.habits.contains { $0.request == "요청 229번 해 줘" }
          && full.habits.contains { $0.request == "요청 30번 해 줘" } && !full.habits.contains { $0.request == "요청 29번 해 줘" },
          "cap: at most two hundred are kept, the oldest used dropped first")
    // Stored and read back; a damaged file starts over.
    let read = L(data: many.data)
    check(read == many && L(data: Data("not json".utf8)).habits.isEmpty && L(data: Data()).habits.isEmpty, "stored: what is written is what is read back, and a damaged file is an empty memory")
    let planted = try! JSONEncoder().encode([ArisDropHabit(kind: "pdf", request: String(repeating: "x", count: 500), count: 9, recent: [1, 2, 3]),
                                             ArisDropHabit(kind: "", request: "a", count: 3, recent: [1]), ArisDropHabit(kind: "pdf", request: "ok 해 줘", count: 3, recent: [1, 2, 3])])
    check(L(data: planted).habits.map(\.request) == ["ok 해 줘"], "stored: an entry that could not have been learned (too long, no kind) is not read")
    let store = feat2Source("Aris/private/Aris/Drop/ArisDropLearnedStore.swift")
    check(store.contains(".applicationSupportDirectory") && store.contains("drop-suggestions.json") && store.contains("0o600") && !store.contains("\".config"),
          "stored: in the app's own Application Support folder, readable only by the user, never under ~/.config/aris")
}

private func feat2LearnedLabelTests() {
    typealias W = ArisDropLearnedWords
    let labels: [(String, String)] = [
        ("이 파일 민수에게 메일로 보내줘", "민수에게 메일로 보내기"), ("이거 민수한테 메일 보내 줘", "민수한테 메일 보내기"), ("이 파일 요약해 줘", "요약하기"),
        ("이 파일을 영어로 번역해 주세요", "영어로 번역하기"), ("이걸 PDF로 만들어 줘", "PDF로 만들기"), ("이 파일들 노션에 올려 줘", "노션에 올리기"),
        ("이 파일 이름 바꿔 줘", "이름 바꾸기"), ("이거 좀 줄여줘", "줄이기"), ("이 파일 찾아 줘", "찾기"), ("이 파일 3쪽만 잘라 줘", "3쪽만 자르기"),
        ("이 파일 회의록 폴더에 넣어 줘", "회의록 폴더에 넣기"), ("이 파일 한 줄로 써 줘", "한 줄로 쓰기"), ("이 파일 팀에 알려줘", "팀에 알리기"),
        ("이 파일 깨끗하게 다듬어 줘", "깨끗하게 다듬기"), ("이 파일 슬랙에 공유해줄래", "슬랙에 공유하기"), ("민수에게 메일로 보내기", "민수에게 메일로 보내기"),
        ("이 파일 정리", "정리"), ("이 파일 표로 지어 줘", "표로 지어 주기"), ("이 파일 메일로 부쳐 줘", "메일로 부치기"),
    ]
    for (request, label) in labels { check(W.label(request) == label, "label: “\(request)” reads “\(label)” on its chip (got “\(W.label(request))”)") }
    check(W.label("send this file to Minsu") == "Send this file to Minsu" && W.label("please summarize this file") == "Summarize this file"
          && W.label("can you translate this into Korean") == "Translate this into Korean",
          "label: an English request is said as it was asked, with a capital and without “please”")
    let long = W.label("이 파일 다음 주 월요일 전체 회의 자료에 넣을 수 있게 한 장으로 요약해서 민수에게 메일로 보내 줘")
    check(ArisTeammateName.width(long) <= ArisDropLearned.labelWidth && long.contains("…") && long.hasSuffix("보내기") && long.hasPrefix("다음 주"),
          "label: a long request is cut in the middle to the chip's width, so its start and its verb both show (\(long))")
    check(W.label("이 파일") == "이 파일" && W.label("줘") == "줘", "label: a request that is nothing but the file word or an ending is shown as it is")
    let chips = ArisDropLearnedChip.make([ArisDropHabit(kind: "pdf", request: "이 파일 민수에게 메일로 보내줘", count: 3, recent: [1, 2, 3])])
    check(chips.count == 1 && chips[0].label == "민수에게 메일로 보내기" && chips[0].habit.request == "이 파일 민수에게 메일로 보내줘",
          "label: the chip shows the short label and sends the whole remembered request")
    check(W.forget(english: false) == "이 제안 지우기" && W.forget(english: true) == "Forget this suggestion"
          && W.help("x", english: false).contains("오른쪽 클릭") && W.help("x", english: true).contains("Right-click")
          && !W.help("x", english: true).unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) },
          "English: the menu's one item and the tooltip have their English")
    typealias S = ArisDropLearnedSetting
    var snapshot = ArisSettingsSnapshot()
    let row = { (count: Int) -> ArisSettingItem? in
        snapshot.dropHabits = count
        return ArisSettingsBuilder.sections(.memory, snapshot).flatMap(\.rows).first { $0.id == "memory.dropHabits" }
    }
    check(row(0)?.control == .buttons([ArisSettingButton(title: "모두 지우기", action: .forgetDropHabits, kind: .danger, enabled: false)]) && row(0)?.desc == S.none,
          "settings: 배운 제안 지우기 is on the 기억 page; with nothing learned its button rests")
    check(row(4)?.control == .buttons([ArisSettingButton(title: "모두 지우기", action: .forgetDropHabits, kind: .danger, enabled: true)]) && row(4)?.title == "배운 제안 지우기",
          "settings: with something learned the button forgets it all")
    check(ArisSettingsIndex.entry("memory.dropHabits")?.page == .memory && ArisSettingsIndex.search("배운 제안").first?.id == "memory.dropHabits", "settings: a search finds the row")
    ArisSettingsCopy.install([:])
    check(ArisSettingsCopy.english(S.title) == "Forget learned suggestions" && ArisSettingsCopy.english(S.some) != nil && ArisSettingsCopy.english(S.none) != nil
          && ArisSettingsCopy.english(S.heading) == "Suggestions for dropped files" && ArisSettingsCopy.english(S.button) != nil,
          "settings in English: the row's words have their English beside them")
}

private func feat2LearnedWiringTests() {
    let model = feat2Source("Aris/private/Aris/Drop/ArisDropModel.swift"), controller = feat2Source("Aris/private/Aris/ArisController.swift")
    let rows = feat2Source("Aris/private/Aris/Drop/ArisDropChipRows.swift"), view = feat2Source("Aris/private/Aris/Drop/ArisDropChipsView.swift")
    if let take = controller.range(of: "let heard = ArisAttachments.shared.take(into: said"), let learn = controller.range(of: "ArisDropModel.shared.learn(from: heard)"),
       let practice = controller.range(of: "if practiceTurn { return await answerPractice(said) }") {
        check(practice.lowerBound < take.lowerBound && take.lowerBound < learn.lowerBound,
              "wiring: a real turn's words are learned from once its files are in them; the setup's practice turn never is")
    } else {
        check(false, "wiring: a real turn's words are learned from once its files are in them; the setup's practice turn never is")
    }
    check(model.contains("learned.recording(ArisPendingFiles.words(of: heard), kinds: kinds") && model.contains("builtInRequest = request")
          && model.contains("let fromChip = builtInRequest == heard"),
          "wiring: only his own words are recorded (the part before the files' note), never a built-in chip's request")
    check(model.contains("aris.submitTyped(attachments.request(with: chip.habit.request))") && !model.contains("chip.habit.request, pending")
          && model.components(separatedBy: "aris.endConversation()").count == 2,
          "wiring: a learned chip sends exactly the remembered request the way the composer sends typed words: the same turn, cards and confirmations")
    check(rows.contains("ArisDropRowItem.firstRow(learned: learned, main: offer.main)") && rows.contains(".contextMenu { Button(ArisDropLearnedWords.forget(english: ArisUIWords.english)) { forget(chip) } }")
          && rows.contains("Look.learnedRim") && !rows.contains("repeatForever") && !rows.contains("NEW") && !rows.contains("✨"),
          "wiring: a learned chip is the same pill with a hairline, forgotten from its menu; nothing pulses and nothing says “new”")
    check(view.contains("learned: drop.learnedChips(attachments.files)") && view.contains("pressLearned: { drop.press($0) }") && view.contains("forget: { drop.forget($0) }"),
          "wiring: the chips over the composer show what was learned for the files that wait")
}
