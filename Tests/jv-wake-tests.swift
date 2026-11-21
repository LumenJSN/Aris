// Tests for jv-wake (2026-11-18): being called by name has to simply work, in a noisy room or over music, and
// never wake for nothing; and dictation types what was said, whole. Synthetic inputs only (no microphone, no sound).
// Called from main.swift.
import Foundation

private let jvRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func jvSource(_ path: String) -> String { (try? String(contentsOf: jvRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runJvWakeTests() {
    jvLockScreenTests()
    jvSteadyNoiseTests()
    jvUntrainedOverAudioTests()
    jvMicDownTests()
    jvBluetoothSpeakerTests()
    jvWakeNameTests()
    jvWakeStatusTests()
    jvCleanerTests()
    jvLongDictationTests()
    jvDictationKeyTests()
    jvDictationTroubleTests()
    jvEnglishEndpointTests()
}

/// Repeatable noise: each 10 ms frame's loudness around `level`, `spread` up or down (a fan's own wobble).
private func jvNoise(_ level: Float, frames: Int, spread: Float = 0.15, seed: UInt64 = 7) -> [Float] {
    var state = seed
    return (0..<frames).map { _ in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Float(state >> 40) / Float(1 << 24)
        return level * (1 + spread * (unit * 2 - 1))
    }
}

/// Two loudnesses heard together (their powers add).
private func jvOver(_ voice: [Float], _ noise: [Float]) -> [Float] { zip(voice, noise).map { ($0 * $0 + $1 * $1).squareRoot() } }

// MARK: - 4. The lock screen

private func jvLockScreenTests() {
    check(ArisWakeArm.screenAway(lockedNow: true, displayAsleepNow: false), "lock: a display awake on the lock screen is still away")
    check(ArisWakeArm.screenAway(lockedNow: false, displayAsleepNow: true) && !ArisWakeArm.screenAway(lockedNow: false, displayAsleepNow: false),
          "lock: asleep is away, unlocked and awake is back")
    var state = ArisWakeArm.State()
    state.screenAway = ArisWakeArm.screenAway(lockedNow: true, displayAsleepNow: false)
    check(ArisWakeArm.blocker(state) == .screenAway, "lock: locked, the wake word is not armed")
    state.conversationOpen = true
    check(ArisWakeArm.blocker(state) == .screenAway, "lock: nor a conversation's listening")
    let wake = jvSource("Aris/private/Aris/ArisController+Wake.swift")
    check(wake.contains("self.screenAway = Self.screenIsAwayNow()") && !wake.contains("self.screenAway = false"),
          "lock: \"screens did wake\" on the lock screen no longer says the screen is back")
    check(wake.contains("let awayNow = Self.screenIsAwayNow()") && wake.contains("screenAway = awayNow"),
          "lock: every arming asks the Mac whether it is locked, whatever the notices said")
    check(wake.contains("guard !screenAway, training == nil, !recordingCalls else { return }"), "lock: the barge-in watch stays off while away")
}

// MARK: - 2. Steady noise

private func jvSteadyNoiseTests() {
    func events(_ levels: [Float]) -> [ArisVoiceGate.Event] {
        var gate = ArisVoiceGate()
        return levels.compactMap { gate.feed($0) }
    }
    func gate(after levels: [Float]) -> ArisVoiceGate {
        var gate = ArisVoiceGate()
        for level in levels { _ = gate.feed(level) }
        return gate
    }
    // A cooker hood at 0.03 that never stops, then "아리스" at 2.2 times it (about 7 dB over the hood).
    let hood = jvNoise(0.03, frames: 600)
    let call = jvOver([Float](repeating: 0.066, count: 60), Array(hood[400..<460]))
    let heard = events(Array(hood[0..<400]) + call + Array(hood[460..<600]))
    check(heard.first == .started(atFrame: 400), "noise: a call about 7 dB over a steady hood starts a phrase")
    // The old rule (four times an average the hood had pushed up) needed about 12 dB.
    check(gate(after: Array(hood[0..<400])).line < 0.066 * 1.05, "noise: over the hood the line sits under the call")
    check(events(hood + hood).isEmpty, "noise: the hood alone, its wobble included, never starts a phrase")
    let louder = jvNoise(0.08, frames: 600, seed: 11)
    check(events(louder).isEmpty && gate(after: Array(louder[0..<300])).quietest > 0.06,
          "noise: a louder hood is taken in within two seconds and still starts nothing")

    // Talking itself is not the room: three seconds of syllables, with the short gaps between words, leave the line low.
    let quiet = [Float](repeating: 0.002, count: 60)
    let syllables = (0..<10).flatMap { _ in [Float](repeating: 0.2, count: 22) + [Float](repeating: 0.003, count: 8) }
    let talked = gate(after: quiet + syllables)
    check(talked.quietest < 0.005 && talked.line <= ArisVoiceGate.quietestTalk * 1.01, "noise: the room does not follow speech")
    check(events(quiet + syllables + quiet).first == .started(atFrame: 60), "noise: and the talking itself is one phrase from its start")
    // A quiet room is as before: the absolute line holds.
    check(gate(after: quiet).line == ArisVoiceGate.quietestTalk, "noise: in a quiet room talking must pass 0.01, as before")
}

// MARK: - 1. Untrained, over other audio

private func jvUntrainedOverAudioTests() {
    typealias S = ArisWakeStrict
    let owner: Float = 26.85
    check(S.admits(playing: true, score: nil, threshold: nil), "untrained: over playback a candidate is checked, no longer turned away")
    check(!S.admits(playing: true, score: 15.0, threshold: owner) && S.admits(playing: true, score: 12.0, threshold: owner),
          "untrained: a trained print over playback is as strict as before")
    // What each listener wrote, as the controller reads it (the exact name at the start; no near spelling over audio).
    func wakes(trained: Bool, music: Bool, playing: Bool, recognizer: String, whisper: String) -> Bool {
        S.textWakes(trained: trained, music: music, playing: playing,
                    recognizer: ArisWakeWord.verified(recognizer, nearAllowed: false), whisper: ArisWakeWord.verified(whisper, nearAllowed: false))
    }
    check(wakes(trained: false, music: false, playing: true, recognizer: "아리스 다음 곡 틀어줘", whisper: "아리스, 다음 곡"),
          "untrained: over this Mac's playback both listeners hearing the call wakes Aris")
    check(wakes(trained: false, music: true, playing: false, recognizer: "Aris what time is it", whisper: "Aris, what time is it?"),
          "untrained: over music in the room too")
    check(!wakes(trained: false, music: true, playing: true, recognizer: "사랑해 오늘 밤", whisper: "아리스"),
          "untrained: lyrics Whisper writes as the name (the recognizer heard the song) never wake it")
    check(!wakes(trained: false, music: false, playing: true, recognizer: "아리스", whisper: "사랑해"), "untrained: nor the recognizer alone")
    check(!wakes(trained: false, music: false, playing: true, recognizer: "어리스", whisper: "아이리스"), "untrained: near spellings never count over audio")
    check(!wakes(trained: true, music: false, playing: true, recognizer: "아리스", whisper: "아리스"),
          "untrained: a trained Mac's text still never wakes over playback (its strong print does)")
    check(wakes(trained: false, music: false, playing: false, recognizer: "아리스", whisper: "") && wakes(trained: false, music: false, playing: false, recognizer: "", whisper: "아리스"),
          "untrained: in a quiet room either listener wakes it, as before")
    let wake = jvSource("Aris/private/Aris/ArisController+Wake.swift")
    check(!wake.contains("guard self.wakeListener === listener, !playing else { return }") && wake.contains("var recognizerNamed = false, whisperNamed = false"),
          "untrained: the recognizer's path is no longer shut over playback; each listener's finding is kept for the other")
    check(wake.contains("guard ArisEchoGuard.ignoresName(") || wake.contains("if ArisEchoGuard.ignoresName("), "untrained: Aris's own voice saying its name is still ignored first")
}

// MARK: - 3. A wake microphone that won't open

private func jvMicDownTests() {
    typealias A = ArisWakeArm
    check((1...40).allSatisfy { A.pause(afterListenFailures: $0) != nil } && A.pause(afterListenFailures: 40) == .seconds(600),
          "mic down: checks that can't listen are tried again forever, at most ten minutes apart")
    check(A.speechRecheck(after: 99) == .seconds(600), "mic down: the speech model is looked for every ten minutes, never given up on")
    check(ArisAudioQuiet.wakeRestartDelay(restarts: 500) == ArisAudioQuiet.longestWakeRestart, "mic down: a microphone that won't open is tried every minute")

    var down = ArisWakeDown()
    check(!down.isDown && !down.shouldTell(at: 1_000), "mic down: working, nothing to tell")
    down.failed(at: 100)
    down.failed(at: 130)
    check(down.isDown && down.since == 100, "mic down: the run of failures counts from the first")
    check(!down.shouldTell(at: 100 + ArisWakeDown.tellAfter - 1), "mic down: not told before two minutes")
    check(down.shouldTell(at: 100 + ArisWakeDown.tellAfter), "mic down: told at two minutes")
    check(!down.shouldTell(at: 900) && !down.shouldTell(at: 5_000), "mic down: told once, not again while it stays down")
    down.worked()
    check(!down.isDown, "mic down: working again ends the run")
    down.failed(at: 6_000)
    check(down.shouldTell(at: 6_000 + ArisWakeDown.tellAfter), "mic down: a new run, once it lasts, is told again")
    check(ArisWakeDown.title(english: false).contains("못 듣고") && ArisWakeDown.body(english: true).contains("keeps trying"),
          "mic down: Korean first, with the English the way the neighbours have it")

    let wake = jvSource("Aris/private/Aris/ArisController+Wake.swift")
    let downLive = jvSource("Aris/private/Aris/ArisController+WakeDown.swift")
    let rest = jvSource("Aris/private/Aris/ArisWakeRestLive.swift")
    check(wake.contains("case .systemDidWake:") && wake.contains("self.wakeMicMayWorkAgain(\"the Mac woke\")"), "mic down: waking from sleep tries again")
    check(wake.contains("wakeMicMayWorkAgain(\"the audio devices changed\")") && rest.contains("wakeMicMayWorkAgain(\"the reason to rest changed\")"),
          "mic down: a route change, or another app letting the microphone go, tries again from the shortest pause")
    check(wake.contains("case .permission?:") && downLive.contains("Self.permissionProblem() != nil") && downLive.contains("wakeMicMayWorkAgain(\"the permission was given\")"),
          "mic down: the permission given in System Settings arms the wake word without a relaunch")
    check(downLive.contains("ArisNoticeRoute.announcement(title: ArisWakeDown.title(") && downLive.contains("ArisTurnScope.outside { Task"),
          "mic down: told through the notice pill, outside any turn")
    check(wake.components(separatedBy: "wakeMicFailed()").count == 3 && !wake.contains("the microphone stays closed\")"),
          "mic down: both failures (open, check) count toward telling; none closes it for good")
}

// MARK: - 7. A Bluetooth loudspeaker is a speaker

private func jvBluetoothSpeakerTests() {
    check(!ArisDucking.isHeadphones(transport: .bluetooth, dataSource: nil, hasInput: false),
          "bluetooth: a loudspeaker (no microphone of its own) is no headphone: no ducking under Aris's own voice, the echo guard stays on")
    check(ArisDucking.isHeadphones(transport: .bluetooth, dataSource: nil, hasInput: true), "bluetooth: a headset (AirPods) still is")
    check(ArisEchoGuard.ignoresName(headphones: ArisDucking.isHeadphones(transport: .bluetooth, dataSource: nil, hasInput: false), ownVoiceAudible: true, saidName: true),
          "bluetooth: over a loudspeaker the name in Aris's own sentence is its own voice")
    let ducking = jvSource("Aris/private/Aris/ArisDucking.swift")
    check(ducking.contains("ArisDuplexRoute.isHeadphones(") && !ducking.contains("case .bluetooth: return true"),
          "bluetooth: one classification (the duplex path's) on the old path too")
}

// MARK: - 5. The name is the user's

private func jvWakeNameTests() {
    typealias N = ArisWakeName
    let standard = N(name: nil)
    check(standard.isDefault && Set(standard.spellings) == ["아리스", "아리쓰", "aris"], "name: a fresh install answers to 아리스, as the recognisers write it")
    check(N(name: "  자비스 ").name == "자비스" && N(name: "x").isDefault && N(name: "아리스2").isDefault && N(name: String(repeating: "가", count: 21)).isDefault,
          "name: a typed name is trimmed; too short, too long or not letters falls back to 아리스")
    // The detector, a custom name.
    N.overrideForTests = N(name: "자비스")
    check(ArisWakeWord.heard("자비스 불 꺼줘") && ArisWakeWord.heard("헤이 자비스") && ArisWakeWord.heard("자비스야, 날씨"),
          "name: the chosen name wakes it, with 헤이 before and 야 after")
    check(!ArisWakeWord.heard("아리스 불 꺼줘") && !ArisWakeWord.verified("아리스", nearAllowed: true) && !ArisWakeWord.verified("알리스", nearAllowed: true),
          "name: the old name and its near spellings no longer do")
    check(!ArisWakeWord.heard("자비스타 카페") && !ArisWakeWord.heard("오늘 자비스 봤어"), "name: still only a whole word at the start")
    check(ArisWakeWord.stripped("자비스, 음악 틀어줘") == "음악 틀어줘" && ArisWakeWord.strippedCall("어 자비스 지금 몇 시야") == "지금 몇 시야",
          "name: the request is what follows the chosen name")
    // The echo checks and Whisper's reading.
    check(ArisEchoGuard.namesAris("자비스가 할게요") && !ArisEchoGuard.namesAris("아리스가 할게요"), "name: Aris saying its wake name is its own voice")
    var evidence = ArisWakeEvidence(nearAllowed: false, playing: false)
    evidence.whisper = .heard("그래서 자비스가 그랬어")
    check(evidence.whisperNamesAris, "name: Whisper's text naming the chosen name counts")
    check(ArisWakeDoubt.checkPrompt(language: "ko") == "자비스" && ArisWakeDoubt.checkPrompt(language: "en") == "자비스", "name: Whisper is prompted with it")
    // Learned spellings from the training's recordings.
    let learned = N(name: "자비스").learning(from: ["자비스", "Jarvis.", "jarvis", "자비스요", "자비스요", "시청해 주셔서 감사합니다", "자 비스 일 이"])
    check(learned.learned == ["jarvis", "자비스요"], "name: what the recogniser wrote twice or more is learned; once, a long line or the name itself is not")
    N.overrideForTests = learned
    check(ArisWakeWord.heard("Jarvis, lights off") && ArisWakeWord.verified("jarvis", nearAllowed: false) && ArisEchoGuard.namesAris("I'm Jarvis"),
          "name: a learned spelling wakes it and counts for the echo checks too")
    let again = learned.learning(from: ["쟈비스", "쟈비스"])
    check(again.learned == ["쟈비스", "jarvis", "자비스요"] && N(name: "자비스", learned: Array(repeating: "가나", count: 3) + ["다라", "마바", "사아", "자차", "카타", "파하"]).learned.count == N.mostLearned,
          "name: the newest learned first, at most six")
    N.overrideForTests = N(name: nil, learned: ["애리스"])
    check(ArisWakeWord.heard("애리스 타이머") && ArisWakeWord.verified("알리스", nearAllowed: true) && ArisWakeWord.heard("아리스 타이머"),
          "name: the default keeps its spellings and near ones, plus what it learned")
    N.overrideForTests = N(name: "자비스")
    check(ArisWakeWords.start(english: false) == "“자비스” 라고 불러줘" && ArisWakeWords.start(english: true) == "Say “자비스”",
          "name: the training asks for the chosen name")
    N.overrideForTests = nil
    check(ArisWakeWords.start(english: false) == "“아리스” 라고 불러줘" && ArisWakeWords.doneSpoken(english: true) == "All set! Now just say Aris to call me.",
          "name: and for 아리스, word for word as before")
    check(ArisWakeWord.heard("아리스 불 꺼줘") && !ArisWakeWord.heard("자비스 불 꺼줘"), "name: with nothing stored, 아리스 as before")
    // Stored with the wake settings.
    if let defaults = UserDefaults(suiteName: testSuiteName("aris-jv-wake-tests")) {
        N.save(name: "자비스", to: defaults)
        N.save(learned: N(name: "자비스").learning(from: ["jarvis", "jarvis"]), to: defaults)
        check(N.load(defaults) == N(name: "자비스", learned: ["jarvis"]), "name: the name and its learned spellings are stored")
        N.save(name: "프라이데이", to: defaults)
        check(N.load(defaults) == N(name: "프라이데이"), "name: a new name forgets the old one's spellings")
        N.save(name: "", to: defaults)
        check(N.load(defaults).isDefault && defaults.string(forKey: N.nameKey) == nil, "name: cleared, it is 아리스 again")
    }
    // The settings row: the window's text field and a button, nothing new.
    let row = ArisWakeNameRows.row(name: "자비스", english: false)
    if case .field(.wakeName, let text, let placeholder, let button) = row.control {
        check(text == "자비스" && placeholder == "아리스" && button.action == .resetWakeName && button.enabled, "name: one row with the existing text field")
    } else {
        check(false, "name: one row with the existing text field")
    }
    if case .field(_, _, _, let button) = ArisWakeNameRows.row(name: "아리스").control { check(!button.enabled, "name: 기본값 is off while it is 아리스") }
    let rows = ArisSettingsBuilder.sections(.aris, ArisSettingsSnapshot()).first { $0.id == "aris.call" }?.rows ?? []
    check(rows.contains { $0.id == ArisWakeNameRows.rowID }, "name: the row is in 부르기, beside the wake word's switch")
    check(ArisSettingsCopyMore.english[ArisWakeNameRows.title] == "Wake name", "name: the row has its English")
    let training = jvSource("Aris/private/Aris/ArisController+Wake.swift")
    check(training.contains("learnWakeSpellings(from: trainingRecordings)"), "name: training learns how the user says it")
}

// MARK: - 6. Why it isn't listening

private func jvWakeStatusTests() {
    typealias W = ArisWakeStatus
    func line(_ state: W.State) -> String { W.line(state, english: false) }
    let on = W.State(settingOn: true)
    check(line(on) == "듣고 있어요", "status: listening")
    check(line(W.State()) == "꺼져 있어요" && line(W.State(settingOn: true, blocker: .settingOff)) == "꺼져 있어요", "status: turned off")
    check(line(W.State(settingOn: true, blocker: .micInUse)).contains("다른 앱이 마이크를"), "status: another app is using the microphone")
    check(line(W.State(settingOn: true, blocker: .permission)).contains("권한"), "status: permission missing")
    check(line(W.State(settingOn: true, blocker: .screenAway)).contains("화면이 잠겨"), "status: screen locked")
    check(line(W.State(settingOn: true, micDown: true)).contains("다시 시도"), "status: the microphone is down and retried")
    check(line(W.State(settingOn: true, playing: true, trained: true)).contains("내 목소리가 또렷할 때만"),
          "status: other audio playing, trained: which rule (only a clear voice print)")
    check(line(W.State(settingOn: true, playing: true, whisperReady: true)).contains("두 번 확인"),
          "status: other audio playing, untrained: which rule (both listeners)")
    check(line(W.State(settingOn: true, playing: true)).contains("깨어나지 않아요"), "status: other audio playing, no Whisper: it can't wake, and says what fixes it")
    check(W.english.count >= 15 && W.english.values.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(\.isASCII) || $0.contains("·") },
          "status: every line has its English")
    let snapshot: ArisSettingsSnapshot = { var s = ArisSettingsSnapshot(); s.wakeStatus = "다른 앱이 마이크를 쓰는 중이라 쉬고 있어요"; return s }()
    let wakeRow = ArisSettingsBuilder.sections(.aris, snapshot).first { $0.id == "aris.call" }?.rows.first { $0.id == "aris.wake" }
    check(wakeRow?.desc == snapshot.wakeStatus, "status: the line is the wake word row's own description in Settings")
    check(jvSource("Aris/private/Aris/ArisDiagnostics.swift").contains("호출어 \\(ArisWakeStatusLive.shared.line(english: false))"), "status: and in the diagnostics' info.txt")
    let wake = jvSource("Aris/private/Aris/ArisController+Wake.swift")
    check(wake.contains("noteWakeStatus(blocker: blocker,"), "status: written whenever the controller decides whether to listen")
}

// MARK: - 8. The cleaner keeps real words

private func jvCleanerTests() {
    typealias C = ArisDictationCleaner
    // Sentences that must come through exactly as said.
    let unchanged = [
        "음식이 너무 맛있었어", "그 그림 정말 예쁘다", "음악 좀 틀어줘", "어디 가?", "어머니께 전화해", "어제 그 사람 만났어",
        "많이 많이 먹어", "천천히 천천히 가자", "하나 하나 확인했어", "가자 가자", "그래서 왔어, 아니 근데 왜 그래?",
        "아니 그게 아니라 내일이야", "그거 아니 이거", "음은 소리고 어는 감탄이야",
        "bye bye", "no no no", "very very good", "I know that that is true", "We went home, I mean we had to",
        "It's fine, I mean really fine", "Umbrella in the car", "Uhura was there", "Hmmm okay",
        "the um-brella stand", "3시 반에 보자",
    ]
    for sentence in unchanged {
        check(C.clean(sentence, endStop: false) == sentence, "cleaner: \"\(sentence)\" comes through unchanged")
    }
    // What it is for still works.
    check(C.clean("어 내일 회의 음 6시, 아니 7시로 옮기자") == "내일 회의 7시로 옮기자.", "cleaner: fillers out, a take-back of a number")
    check(C.clean("Let's meet on Tuesday, I mean Wednesday", endStop: false) == "Let's meet on Wednesday", "cleaner: a take-back after a comma")
    check(C.clean("철수한테, 아니 영희한테 보내", endStop: false) == "영희한테 보내", "cleaner: 아니 after a comma, a word for a word")
    check(C.clean("um, so basically uh yeah", endStop: false) == "so basically yeah", "cleaner: English fillers as whole words")
}

// MARK: - 9, 10. Long dictation: Whisper reads it all, and it goes in whole

private func jvLongDictationTests() {
    let rate = 16_000.0
    // Ninety seconds of "speech" with a quiet moment every four seconds.
    let speech = (0..<Int(rate * 90)).map { i -> Float in (i / Int(rate)) % 4 == 3 && i % Int(rate) < 4_000 ? 0 : Float(sin(Double(i) * 0.07)) * 0.3 }
    let windows = ArisLongTurn.windows(of: speech, sampleRate: rate)
    check(windows.count == 4 && windows.first?.lowerBound == 0 && windows.last?.upperBound == speech.count
          && zip(windows, windows.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound } && windows.allSatisfy { $0.count <= Int(rate * 30) },
          "long dictation: 90 s is read in windows of at most 30 s, none of it skipped")
    check(windows.dropLast().allSatisfy { speech[$0.upperBound - 1] == 0 || speech[$0.upperBound] == 0 }, "long dictation: each cut lands in a quiet moment")
    check(ArisLongTurn.whisperTimeout(samples: speech.count, sampleRate: rate, first: .seconds(3)) == .seconds(7),
          "long dictation: Whisper may take 3 s plus 2 s a further window (7 s for 90 s)")
    let dictation = jvSource("Aris/private/Aris/ArisController+Dictation.swift")
    check(!dictation.contains("dictationWhisperLimit") && dictation.contains("let recording = listener.secondListenSamples"),
          "long dictation: past 28 s Whisper is no longer skipped; the live text is kept only when Whisper can't")
    // Insertion.
    let long = String(repeating: "오늘 회의에서 정한 것들을 정리해서 보내 드릴게요. ", count: 400)
    check(long.count > 4_000 && ArisInsert.text(from: long) == long.trimmingCharacters(in: .whitespaces), "long dictation: 12,000 characters go in whole")
    check(ArisInsert.maxLength >= 20 * 60 * 60 && (try? JSONSerialization.data(withJSONObject: ["text": String(repeating: "가", count: ArisInsert.maxLength)]))!.count < HTTPRequestParser.maxBytes,
          "long dictation: the cap holds 20 minutes of talk and still fits the helper's 1 MiB request")
}

// MARK: - 11. ⌥ with another key never starts dictation

private func jvDictationKeyTests() {
    let t0 = ContinuousClock.now
    func run(_ events: [(Int, ArisDictationKey.Event)]) -> [ArisDictationKey.Action] {
        var state = ArisDictationKey.State()
        return events.map { state.handle($0.1, at: t0 + .milliseconds($0.0)) }.filter { $0 != .none }
    }
    check(run([(0, .down(alone: true)), (60, .otherKey), (130, .up), (200, .tick)]).isEmpty, "key: right ⌥ + 2 (typing ™): no microphone, no notch")
    check(run([(0, .down(alone: true)), (180, .otherKey), (400, .otherKey), (600, .up)]).isEmpty, "key: ⌥ held with letters typed: nothing")
    check(run([(0, .down(alone: true)), (200, .tick), (1_500, .up)]) == [.start, .finish], "key: a lone hold past 200 ms dictates")
    check(run([(0, .down(alone: true)), (200, .tick), (700, .otherKey)]) == [.start, .cancel], "key: another key after it started cancels it")
    check(run([(0, .down(alone: true)), (90, .up), (260, .down(alone: true)), (320, .up), (4_000, .down(alone: true))]) == [.startLocked, .finish],
          "key: a double tap still dictates hands-free")
    let tap = jvSource("Aris/private/Aris/ArisDictationKeyTap.swift")
    let controller = jvSource("Aris/private/Aris/ArisController+Dictation.swift")
    check(tap.contains("if case .down = event, state.hasStarted,") && controller.contains("case .startLocked:"),
          "key: the tap keeps a first quick tap for its second; the controller starts hands-free on it")
}

// MARK: - 12, 13. A paste that can't happen now: said in full, waited for, never lost

private func jvDictationTroubleTests() {
    typealias W = ArisDictationWait
    check(W.stage(after: .milliseconds(500)) == .typing && W.status(.typing, english: false) == nil, "wait: a quick paste says nothing")
    check(W.stage(after: .seconds(2)) == .waiting && W.status(.waiting, english: false)?.contains("끝나면 넣을게요") == true,
          "wait: past 1.5 s the notch says it waits for the keys")
    check(W.stage(after: .seconds(7)) == .waitingCopied && W.status(.waitingCopied, english: true)?.contains("copied") == true,
          "wait: past 6 s the words are on the clipboard too, and it says so")
    check(W.insertTimeout > 92, "wait: the app waits as long as the helper may (90 s for the keys, 2 s for the paste)")
    // The permission line in full, with the list to open, on the notice pill.
    for appOn in [false, true] {
        let line = ArisHelperInstallWords.notTyped(appSwitchOn: appOn, english: false)
        let notice = ArisNoticeRoute.problem(line: line, title: W.pillLine(english: false), english: false)
        let opensPane = notice.actions.contains { action in
            if case .fixes(let fixes) = action.role { return fixes.first == .pane(.accessibility) }
            return false
        }
        check(notice.body == line && notice.kind == .problem && opensPane, "trouble: the whole reason is on the notice, with the list to open (switch \(appOn ? "on" : "off"))")
    }
    check(W.pillLine(english: false).count <= 20, "trouble: the pill's own line is short enough not to be cut")
    let dictation = jvSource("Aris/private/Aris/ArisController+Dictation.swift")
    let wait = jvSource("Aris/private/Aris/ArisController+DictationWait.swift")
    check(dictation.contains("let outcome = await insertDictationShowingWait(text, state: state)") && wait.contains("state.lastText = text")
          && wait.contains("_ = state.copy(text)") && wait.contains("timeout: ArisDictationWait.insertTimeout"),
          "trouble: the words are kept for ⌃⌘V before the paste, copied if the wait is long, and the app waits out the helper")
    check(dictation.contains("ArisNoticeRoute.problem(line: line, title: ArisDictationWait.pillLine("), "trouble: with the pill on, the notice carries the full line")
    check(!jvSource("ArisAgent/ArisDesktopLock.swift").isEmpty && !wait.contains("ArisDesktopLock."), "trouble: the desktop lock itself is untouched")
}

// MARK: - 14. English words look finished too

private func jvEnglishEndpointTests() {
    typealias E = ArisEndpoint
    for finished in ["open Safari", "what time is it", "set an alarm for 7", "turn off the lights", "what's the weather tomorrow", "open Safari please", "thank you so much"] {
        check(E.looksComplete(finished), "english: \"\(finished)\" looks finished (no punctuation from the recognizer)")
    }
    for open in ["set a timer for", "can you", "remind me to", "open Safari and", "tell me about the", "what is", "hello", "um"] {
        check(!E.looksComplete(open), "english: \"\(open)\" still needs more")
    }
    check(E.looksComplete("내일 날씨 알려줘") && !E.looksComplete("그 파일 열어") && !E.looksComplete("이 파일을"), "english: Korean is read as before")
    // It reaches the policy as its "words finished" input: an English request now gets the quick end, not the slow one.
    check(ArisEndpointPolicy.endCase(score: nil, complete: E.looksComplete("open Safari"), hanging: E.isHanging("open Safari")) == .noScoreComplete
          && ArisEndpointPolicy.endCase(score: 0.8, complete: E.looksComplete("what time is it"), hanging: false) == .confident,
          "english: the policy sees English as finished (confident with Smart Turn)")
}
