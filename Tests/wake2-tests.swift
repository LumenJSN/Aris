// Tests for the wake word's two stages and its rests (wake2):
// - stage 1 hands on only a voice (ArisWakeVoice), from a start a short dip no longer throws away (ArisVoiceGate);
// - the recognizer that checks a candidate is handed everything from just before the candidate phrase, whatever was
//   said since (ArisWakeCore.audio(from:)), so the words right after the name are never lost;
// - the wake word rests, its microphone closed, while the screen is away, the lid is closed with no display, another
//   app uses a microphone, the Mac is on battery in Low Power Mode or only a headset's microphone is here, and comes
//   back by itself (ArisWakeArm, ArisWakeRest), over recorded sequences of events;
// - what is said about it is true (ArisWakeHonesty), and nothing a rejected phrase said is kept.
// Everything here is synthetic audio and plain values: no microphone, no sound.
import Foundation

private struct Noise {
    var state: UInt64
    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(state >> 40) / Float(1 << 24) - 0.5
    }
}

/// A room's hiss, `seconds` long.
private func quiet(_ seconds: Double, seed: UInt64 = 7) -> [Float] {
    var noise = Noise(state: seed)
    return (0..<Int(seconds * 16_000)).map { _ in noise.next() * 0.001 }
}

/// A voiced sound: a 140 Hz pitch with its overtones, as loud as a voice at arm's length.
private func voiced(_ seconds: Double, pitch: Double = 140) -> [Float] {
    (0..<Int(seconds * 16_000)).map { index in
        let t = Double(index) / 16_000
        return Float((1...12).reduce(0.0) { $0 + sin(2 * .pi * pitch * Double($1) * t) / Double($1) }) * 0.06
    }
}

/// A sound with no pitch: a sleeve on the desk, a burst of typing, a whisper.
private func hiss(_ seconds: Double, seed: UInt64 = 3) -> [Float] {
    var noise = Noise(state: seed)
    return (0..<Int(seconds * 16_000)).map { _ in noise.next() * 0.3 }
}

/// Feeds `audio` in 100 ms chunks, as the microphone's tap does; every event in order.
private func feed(_ core: inout ArisWakeCore, _ audio: [Float]) -> [ArisWakeCore.Event] {
    var events: [ArisWakeCore.Event] = []
    var position = 0
    while position < audio.count {
        let end = min(audio.count, position + 1600)
        events += core.take(Array(audio[position..<end]))
        position = end
    }
    return events
}

private func candidates(_ events: [ArisWakeCore.Event]) -> Int {
    events.filter { if case .candidate = $0 { return true } else { return false } }.count
}

private func wakeVoiceTests() {
    typealias V = ArisWakeVoice
    let lead = ArisWakeCore.leadFrames
    let spoken = V.frames(quiet(0.15) + voiced(0.6))
    check(V.verdict(spoken, lead: lead, ended: false) == .voice, "voice check: a voiced start is a voice, decided before it ends")
    check(spoken.dropFirst(lead + 3).prefix(20).allSatisfy { $0.voicing > 0.8 }, "voice check: a vowel repeats at its pitch (over 0.8)")
    let rustle = V.frames(quiet(0.15) + hiss(0.7))
    check(rustle.dropFirst(lead + 3).prefix(40).allSatisfy { $0.voicing < 0.3 }, "voice check: noise does not repeat (under 0.3)")
    check(V.verdict(rustle, lead: lead, ended: false) == .notVoice, "voice check: half a second with nothing voiced is not a voice")
    let clack = V.frames(quiet(0.15) + hiss(0.06) + quiet(0.3))
    check(V.verdict(Array(clack.prefix(lead + 8)), lead: lead, ended: false) == .wait, "voice check: too little yet, it waits")
    check(V.verdict(clack, lead: lead, ended: true) == .notVoice, "voice check: a key clack that ended is not a voice")
    let breathThenVoice = V.frames(quiet(0.15) + hiss(0.2).map { $0 * 0.2 } + voiced(0.4))
    check(V.verdict(breathThenVoice, lead: lead, ended: false) == .voice, "voice check: a breath before the voice (“헤이 아리스”) still passes")
    check(V.verdict(V.frames(quiet(0.15) + voiced(0.6, pitch: 90)), lead: lead, ended: false) == .voice
          && V.verdict(V.frames(quiet(0.15) + voiced(0.6, pitch: 320)), lead: lead, ended: false) == .voice,
          "voice check: a low voice and a child's high one are both voices")
    check(V.enabled(setting: nil) && V.enabled(setting: "auto") && !V.enabled(setting: "off"), "voice check: on unless the preference says off")
    check(V.frames([Float](repeating: 0, count: 100)).isEmpty && V.verdict([], lead: lead, ended: true) == .notVoice,
          "voice check: nothing to read is not a voice")
}

private func wakeGateTests() {
    func events(_ levels: [Float]) -> [ArisVoiceGate.Event] {
        var gate = ArisVoiceGate()
        return levels.compactMap { gate.feed($0) }
    }
    let hush = [Float](repeating: 0.0005, count: 60), far = [Float](repeating: 0.02, count: 40)
    check(events(hush + [0.02, 0.009] + far + hush) == [.started(atFrame: 60), .ended(fromFrame: 60, toFrame: 102)],
          "gate: a voice from across the room that dips under the line for one frame still starts, from its first frame")
    check(events(hush + [0.02, 0.009, 0.008] + far + hush).first == .started(atFrame: 60), "gate: a dip of two frames too")
    check(events(hush + [0.02, 0.009, 0.008, 0.007] + far + hush).isEmpty,
          "gate: a longer gap is not one start (the quiet moment begins again, as before)")
    check(events(hush + [0.2, 0.2, 0.2] + hush).isEmpty, "gate: a click still isn't talking")
    check(events(hush + [Float](repeating: 0.2, count: 50) + hush) == [.started(atFrame: 60), .ended(fromFrame: 60, toFrame: 110)],
          "gate: an ordinary phrase starts and ends where it did")
}

private func wakeCoreTests() {
    typealias C = ArisWakeCore
    // Untrained: a voice is handed on, with the audio from just before it began.
    var core = C(mode: .waiting(nil))
    var events = feed(&core, quiet(1) + voiced(0.5) + quiet(0.6))
    check(events.first == .voice(true) && events.contains(.candidate(score: nil, sure: false)) && events.last == .voice(false),
          "stage 1: a voice after a quiet moment is handed on to the recognizer")
    check(core.candidateStartSample == 16_000 - C.lead && core.counts == C.Counts(phrases: 1, notVoice: 0, printChecks: 0, candidates: 1),
          "stage 1: the candidate's audio starts 150 ms before the phrase")
    check(core.candidateAudio(seconds: 0.3).count == 4800 && core.candidateAudio(seconds: 9).count == core.received - (16_000 - C.lead),
          "stage 1: the second listen gets the phrase from its start, as much as there is")

    // A sound that is not a voice never reaches the recognizer.
    core = C(mode: .waiting(nil))
    events = feed(&core, quiet(1) + hiss(0.7) + quiet(0.6))
    check(candidates(events) == 0 && core.counts.notVoice == 1 && core.counts.phrases == 1 && core.candidateStartSample == nil,
          "stage 1: a rustle opens the loudness gate and stops there: no recognizer, no Whisper")
    check(events == [.voice(true), .voice(false)], "stage 1: the conversation still hears that something sounded")
    core = C(mode: .waiting(nil), voiceCheck: false)
    check(candidates(feed(&core, quiet(1) + hiss(0.7) + quiet(0.6))) == 1, "stage 1: with the check off every loud sound is handed on, as before")

    // While a check runs, or in a conversation, nothing is handed on.
    core = C(mode: .waiting(nil), paused: true)
    check(candidates(feed(&core, quiet(1) + voiced(0.5) + quiet(0.6))) == 0, "stage 1: paused, a voice is not handed on")
    core.paused = false
    check(candidates(feed(&core, voiced(0.5) + quiet(0.6))) == 1, "stage 1: and the next one is")

    // The hand-over: “아리스” … a pause … “타이머 삼 분”, and the recognizer is ready only after the pause.
    core = C(mode: .waiting(nil))
    let name = quiet(1) + voiced(0.5), pause = quiet(0.5), request = voiced(0.8, pitch: 160)
    check(candidates(feed(&core, name)) == 1, "hand-over: the name is a candidate while it is still being said")
    // The controller holds further candidates back while its recognizer starts and checks this one.
    core.paused = true
    _ = feed(&core, pause + request)
    let old = core.audio(from: nil), new = core.audio(from: core.candidateStartSample)
    check(old.count == request.count + C.lead, "hand-over, before: only the phrase open at that moment reached the recognizer (the name was gone)")
    check(new.count == C.lead + 8000 + pause.count + request.count, "hand-over: everything from just before the name reaches the recognizer")
    check(Array(new.suffix(request.count)) == request && Array(new.dropFirst(C.lead).prefix(8000)) == voiced(0.5),
          "hand-over: the name and the words after it, sample for sample")
    _ = feed(&core, quiet(0.6))
    check(core.audio(from: nil).count == C.lead && core.audio(from: core.candidateStartSample).count == new.count + 9600,
          "hand-over, before: once every phrase had ended only the last 150 ms was handed over; now still all of it")

    // Only the last seconds are held, in memory.
    core = C(mode: .waiting(nil))
    _ = feed(&core, quiet(14))
    check(core.audio(from: 0).count <= C.kept * 2 && core.audio(from: 0).count >= C.kept && core.oldestSample > 0 && core.audio(from: core.received + 99).isEmpty,
          "the buffer: between six and twelve seconds, never more, and never past its end")

    // Trained: the voice print decides, after the voice check.
    let word = [400.0, 900.0, 1600.0, 700.0]
    let model = ArisWakeModel.trained(from: (1...5).map { toneWord(word, stretch: 1 + Double($0) * 0.04, seed: $0) })
    check(model != nil, "trained: five recordings make a model")
    core = C(mode: .waiting(model))
    events = feed(&core, quiet(1) + toneWord(word, stretch: 1.1, seed: 9, lead: 0).map { $0 * 0.3 } + quiet(1.5))
    check(candidates(events) == 1 && core.counts.printChecks == 1 && core.lastScore != nil, "trained: the taught word is compared once and handed on")
    core = C(mode: .waiting(model))
    events = feed(&core, quiet(1) + toneWord([1500, 300, 2500, 200, 1200], seed: 4, lead: 0).map { $0 * 0.3 } + quiet(1.5))
    check(candidates(events) == 0 && core.counts.printChecks == 1, "trained: another word is compared and stops at stage 1")
    core = C(mode: .waiting(model))
    events = feed(&core, quiet(1) + hiss(0.7) + quiet(1.5))
    check(candidates(events) == 0 && core.counts.printChecks == 0 && core.counts.notVoice == 1, "trained: a rustle is not even compared")

    // Training hands on what was said, and the level for the orb.
    core = C(mode: .training)
    events = feed(&core, quiet(1) + voiced(0.5) + quiet(0.6))
    let phrases = events.compactMap { event -> [Float]? in if case .phrase(let samples) = event { return samples } else { return nil } }
    check(phrases.count == 1 && abs(phrases[0].count - (8000 + 2 * C.lead)) <= 480 && candidates(events) == 0,
          "training: each phrase said is handed on whole, never as a candidate")
    check(events.contains { if case .level(let shown) = $0 { return shown > 0.3 } else { return false } } && !events.contains(.voice(true)),
          "training: the orb gets its level")
}

private func wakeArmTests() {
    typealias A = ArisWakeArm
    check(A.blocker(A.State(lidClosed: true)) == .lidClosed && A.blocker(A.State(micInUse: true)) == .micInUse
          && A.blocker(A.State(lowPower: true)) == .lowPower, "arm: the lid, another app's microphone and Low Power Mode each hold the wake word")
    check(A.blocker(A.State(conversationOpen: true, micInUse: true)) == nil && A.blocker(A.State(conversationOpen: true, lowPower: true)) == nil,
          "arm: a conversation the user opened keeps listening between turns (another app's sound pauses it by its own rule)")
    check(A.blocker(A.State(conversationOpen: true, lidClosed: true)) == .lidClosed, "arm: nobody talks to a closed lid, conversation or not")
    check(A.blocker(A.State(settingOn: false, micInUse: true)) == .settingOff && A.blocker(A.State(idle: false, micInUse: true)) == .busy
          && A.blocker(A.State(screenAway: true, lidClosed: true)) == .screenAway && A.blocker(A.State(headsetOnly: true, micInUse: true)) == .headsetOnly,
          "arm: the earlier guards still come first")
}

/// The wake word over a sequence of events, with only the pure rules: what ArisController.waitForWakeWord decides.
private struct WakeDay {
    var state = ArisWakeArm.State()
    var facts = ArisWakeRest.Facts(lidClosed: false)
    var micUse = ArisWakeRest.MicUse()
    var log = ArisWakeRest.Log()
    var clock: TimeInterval = 0
    var lines: [String] = []
    /// Muted, quiet hours: Aris's voice, not its ears.
    var muted = false
    var night = false

    /// The microphone is open for the wake word after this look.
    mutating func look(after seconds: TimeInterval = 0) -> Bool {
        clock += seconds
        ArisWakeRest.apply(facts, micInUse: micUse.note(recording: facts.recorder != nil, at: clock), to: &state)
        if let line = log.line(for: ArisWakeRest.reason(state), wakeWordOn: ArisWakeRest.mayRun(state)) { lines.append(line) }
        return ArisWakeArm.blocker(state) == nil
    }

    var reason: ArisWakeRest.Reason? { ArisWakeRest.reason(state) }
}

private func wakeRestSequenceTests() {
    typealias R = ArisWakeRest
    var day = WakeDay()
    check(day.look() && day.reason == nil && day.lines.isEmpty, "a day: armed at the desk, nothing to log")

    // Lock, unlock.
    day.state.screenAway = true
    check(!day.look() && day.reason == .screenAway, "a day: locked, the microphone is closed")
    day.state.screenAway = false
    check(day.look() && day.lines == ["wake word rests: the screen is locked or asleep (its microphone is closed)", "wake word listens again: the screen is back"],
          "a day: unlocked, it listens again; one line each way")

    // A call starts and ends; the app blips its microphone when the call connects.
    day.facts.recorder = "us.zoom.xos"
    check(!day.look(after: 60) && day.reason == .micInUse, "a day: a call starts, the microphone is closed at once")
    check(!day.look(after: 2) && !day.look(after: 2) && day.lines.count == 3, "a day: looked at again and again during the call, still one line")
    day.facts.recorder = nil
    check(!day.look(after: 600) && !day.look(after: 2), "a day: the call's microphone closed a moment ago: not yet")
    day.facts.recorder = "us.zoom.xos"
    check(!day.look(after: 0.5), "a day: it was only a blip (the call goes on)")
    day.facts.recorder = nil
    check(!day.look(after: 1) && day.look(after: 3), "a day: three seconds after the call really ended it listens again")
    check(day.lines.suffix(2) == ["wake word rests: another app is using a microphone (its microphone is closed)",
                                  "wake word listens again: the other app let the microphone go"], "a day: the call's two lines")

    // Muted, quiet hours: Aris's voice goes quiet, its ears do not (the existing rule).
    day.muted = true
    day.night = true
    check(day.look(after: 60) && day.reason == nil && ArisQuiet.decide(starter: .user, muted: true, moment: .init(night: true)) == .textOnly(.muted),
          "a day: muted at night Aris still hears its name, and answers in text")

    // On battery, Low Power Mode on and off; the charger.
    day.facts.onBattery = true
    check(day.look(after: 60), "a day: on battery alone, it listens")
    day.facts.lowPowerMode = true
    check(!day.look(after: 60) && day.reason == .lowPower, "a day: Low Power Mode on battery, it rests")
    day.facts.onBattery = false
    check(day.look(after: 60), "a day: the charger goes in, it listens again (Low Power Mode still on)")
    day.facts.onBattery = true
    day.state.conversationOpen = true
    check(day.look(after: 5) && day.reason == nil, "a day: a conversation the user opened on battery listens between its turns")
    day.state.conversationOpen = false
    check(!day.look(after: 5), "a day: and once it closes the wake word rests again")
    day.facts.lowPowerMode = false
    check(day.look(after: 60), "a day: Low Power Mode off")

    // The lid, with and without a display.
    day.facts.lidClosed = true
    day.facts.externalDisplays = 1
    check(day.look(after: 60), "a day: lid closed at the desk with a display, it listens (through whichever microphone the plan names)")
    day.facts.externalDisplays = 0
    check(!day.look(after: 60) && day.reason == .lidClosed, "a day: the display is unplugged, the lid is all there was: it rests")
    day.facts.lidClosed = false
    check(day.look(after: 60), "a day: lid open")
    check(R.lidRests(R.Facts(lidClosed: nil)) == false, "a day: a Mac with no lid never rests for one")

    // A headset connects on a Mac whose lid is closed (only its microphone is left), then a call on top of it.
    day.state.headsetOnly = true
    check(!day.look(after: 60) && day.reason == .headsetOnly, "a day: only a headset's microphone, it rests (the headset stays in music mode)")
    day.facts.recorder = "com.apple.FaceTime"
    check(!day.look(after: 5) && day.reason == .headsetOnly && day.lines.last?.contains("Bluetooth headset") == true,
          "a day: a call on the headset changes nothing, and adds no line")
    day.state.headsetOnly = false
    check(!day.look(after: 5) && day.reason == .micInUse, "a day: another microphone appears mid-call: still resting, now for the call")
    day.facts.recorder = nil
    check(!day.look(after: 1) && day.look(after: 3), "a day: the call ends")

    // A turn under way does not end a rest, and the setting off is not a rest.
    day.facts.recorder = "com.hnc.Discord"
    _ = day.look(after: 10)
    day.state.idle = false
    let before = day.lines.count
    check(!day.look(after: 1) && day.reason == .micInUse && day.lines.count == before, "a day: a talk-key turn during a call: the rest stands, no line")
    day.state.idle = true
    day.state.settingOn = false
    check(!day.look(after: 1) && day.reason == nil && day.lines.count == before,
          "a day: the setting switched off mid-call: no rest to speak of, and no line claiming it listens again")
    day.state.settingOn = true
    check(!day.look(after: 1) && day.lines.count == before + 1 && day.lines.last?.hasPrefix("wake word rests: another app") == true,
          "a day: switched back on while the call goes on: it rests, and says so afresh")
    day.facts.recorder = nil
    check(!day.look(after: 1) && day.look(after: 3), "a day: the call ends: armed")
    check(day.lines.allSatisfy { $0.hasPrefix("wake word rests: ") || $0.hasPrefix("wake word listens again: ") }, "a day: every line is a rest or a return")
}

private func wakeRestRuleTests() {
    typealias R = ArisWakeRest
    typealias P = ArisOtherAudio.Process
    let own = P(pid: 10, bundle: "com.lumenjsn.aris", output: false, input: true)
    let agent = P(pid: 11, bundle: "com.lumenjsn.aris.aris-agent", output: false, input: true)
    let siri = P(pid: 12, bundle: "com.apple.CoreSpeech", output: false, input: true)
    let zoom = P(pid: 13, bundle: "us.zoom.xos", output: true, input: true)
    let music = P(pid: 14, bundle: "com.spotify.client", output: true, input: false)
    check(R.recorder([own, agent, siri, music], ownPid: 10) == nil, "who records: Aris itself, macOS's “Siri야” listener and an app that only plays are not a call")
    check(R.recorder([own, siri, music, zoom], ownPid: 10) == zoom, "who records: a call app is")
    check(R.recorder([P(pid: 20, bundle: nil, output: false, input: true)], ownPid: 10)?.pid == 20, "who records: a process with no bundle id too")
    check(R.recorder([P(pid: 10, bundle: nil, output: false, input: true)], ownPid: 10) == nil, "who records: never Aris's own process")

    check(R.restsForOtherApps(setting: nil) && R.restsForOtherApps(setting: "on") && !R.restsForOtherApps(setting: "off"),
          "who records: the rest for another app's microphone holds unless the preference says off")

    var use = R.MicUse()
    check(!use.note(recording: false, at: 0) && use.recheck(at: 0) == nil, "microphone use: nothing, nothing pending")
    check(use.note(recording: true, at: 1) && use.note(recording: false, at: 2) && use.recheck(at: 3) == 2, "microphone use: it counts at once, and for three seconds after")
    check(use.note(recording: false, at: 4.9) && !use.note(recording: false, at: 5) && use.recheck(at: 5) == nil, "microphone use: then it is over")

    check(R.lowPowerRests(R.Facts(lowPowerMode: true, onBattery: true)) && !R.lowPowerRests(R.Facts(lowPowerMode: true, onBattery: false))
          && !R.lowPowerRests(R.Facts(lowPowerMode: false, onBattery: true)), "low power: only on battery")
    check(R.lidRests(R.Facts(lidClosed: true)) && !R.lidRests(R.Facts(lidClosed: true, externalDisplays: 1)) && !R.lidRests(R.Facts(lidClosed: false)),
          "the lid: closed with no other display")

    typealias S = ArisWakeArm.State
    check(R.reason(S(settingOn: false, screenAway: true)) == nil && R.reason(S(permissionOK: false, micInUse: true)) == nil
          && R.reason(S(onboardingSeen: false, lowPower: true)) == nil, "a rest: only a wake word that is on and allowed can rest")
    check(R.reason(S(idle: false, listenerOpen: true, micInUse: true)) == .micInUse, "a rest: a turn under way does not end it")
    check(R.reason(S(screenAway: true, micInUse: true, lowPower: true)) == .screenAway && R.reason(S(micInUse: true, lowPower: true)) == .micInUse,
          "a rest: one reason is said, the nearest first")
    check(R.recheckEvery(.micInUse) == 2 && R.recheckEvery(nil) == 10 && R.recheckEvery(.lowPower) == 10,
          "looking again: often only while another app has the microphone (that look is the cheap one)")

    for reason in R.Reason.allCases {
        let korean = R.words(reason, english: false), english = R.words(reason, english: true)
        check(korean.hasSuffix("이름 듣기는 쉬는 중") && english.hasPrefix("Not listening for “Aris”: ") && korean.count <= 34,
              "words: \(reason.rawValue) says in a few words why, in both languages")
    }
    check(R.words(.micInUse, app: "Zoom", english: false) == "Zoom에서 마이크를 쓰는 중이라 이름 듣기는 쉬는 중"
          && R.words(.micInUse, app: "FaceTime", english: true) == "Not listening for “Aris”: FaceTime is using the microphone"
          && R.words(.micInUse, app: "", english: false) == R.words(.micInUse, english: false), "words: the app on the microphone is named when it has a name")

    typealias App = R.App
    let apps = [App(pid: 1, bundle: "com.google.Chrome", name: "Google Chrome", regular: true), App(pid: 2, bundle: "com.google.Chrome.helper", name: "Google Chrome Helper", regular: false),
                App(pid: 3, bundle: "us.zoom.xos", name: "zoom.us", regular: true)]
    check(R.appName(recorder: "us.zoom.xos", pid: 3, among: apps) == "zoom.us", "the app's name: the app itself")
    check(R.appName(recorder: "com.google.Chrome.helper", pid: 2, among: apps) == "Google Chrome", "the app's name: a browser's helper is the browser")
    check(R.appName(recorder: "com.apple.avconferenced", pid: 9, among: apps) == nil && R.appName(recorder: "", pid: nil, among: apps) == nil
          && R.appName(recorder: "com.google.ChromeCanary", pid: 8, among: apps) == nil, "the app's name: none when there is no app to name")

    check(R.kept("오늘 회의 몇 시야", path: "rejected") == "" && R.kept("아리스", path: "whisper") == "아리스" && R.kept(nil, path: "voice") == "",
          "the tuning log: what a phrase that was not the name said is never written down")
}

private func wakeHonestyTests() {
    let line = ArisWakeHonesty.settingsLine, english = ArisWakeHonesty.settingsLineEnglish
    check(["마이크가 켜져", "마이크 표시", "보내거나 남기지", "알아서 쉬어요"].allSatisfy(line.contains), "honesty: the settings row says all four truths")
    check(["microphone is on", "indicator", "nothing is sent or kept", "rests by itself"].allSatisfy(english.contains), "honesty: and in English")
    check(ArisSettingsCopyMore.english[line] == english && ArisWakeHonesty.line(english: false).hasSuffix("알아서 쉬어요."), "honesty: the settings pages find its English")

    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris")
    func source(_ path: String) -> String { (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? "" }
    check(source("components/Settings/ArisSettingsBuilder.swift").contains("ArisWakeHonesty.note") && ArisSettingsCopyMore.english[ArisWakeHonesty.note] == ArisWakeHonesty.noteEnglish && ArisWakeHonesty.note.contains("마이크 표시") && ArisWakeHonesty.noteUntrained.contains("모두 확인해요"), "honesty: the small line under the calling card says it (the row keeps one short sentence), and the settings pages find its English")
    let wake = source("private/Aris/ArisController+Wake.swift")
    check(wake.contains("source: detector, from: detector.candidateSample)"), "hand-over: the check's recognizer starts from the candidate phrase")
    check(wake.contains("ArisWakeRestLive.shared.fill(&state)") && wake.contains("case .lidClosed?, .micInUse?, .lowPower?: return stopWaitingForWakeWord()"),
          "rests: read before the microphone opens, and each one closes it")
    check(wake.contains("ArisWakeRestLive.shared.screenWentAway(") && wake.contains("!ArisWakeRestLive.shared.keepsMicrophoneClosed"),
          "rests: the lock is written down, and a resting wake word does not open for Aris's own voice either")
    check(wake.contains("ArisWakeRest.kept(whisperHeard, path: path)"), "the tuning log: goes through the rule")
    let detector = source("private/Aris/ArisWakeDetector.swift")
    check(detector.contains("core.take(samples)") && detector.contains("self?.queue.sync { self?.take(samples) }") && !detector.contains("removeFirst"),
          "the detector: one wake-up per buffer, and all its listening is ArisWakeCore's")
    check(source("private/Aris/Home/ArisHomeView.swift").contains("ArisWakeRestRow(hidden: showsTurn)")
          && source("private/Aris/ArisStatusItem.swift").contains("ArisWakeRestLive.shared.words"), "rests: the open notch and the ✦ menu say why")
    let live = source("private/Aris/ArisWakeRestLive.swift")
    check(live.contains("facts.recorder != nil && ArisWakeRest.restsForOtherApps(setting:"), "rests: the live watcher asks that preference")
    check(live.contains("category: \"microphone\"") && !live.contains("AVAudioEngine") && !live.contains("requestAccess") && !live.contains("INFocusStatusCenter"),
          "rests: logged with the microphone's lines; the facts are read without opening a device or asking for a permission")
}

func runWake2Tests() {
    wakeVoiceTests()
    wakeGateTests()
    wakeCoreTests()
    wakeArmTests()
    wakeRestSequenceTests()
    wakeRestRuleTests()
    wakeHonestyTests()
}
