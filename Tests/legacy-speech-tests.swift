// Tests for legacy-speech: Aris listens on macOS 14 and 15 with Apple's older engine (SFSpeechRecognizer), behind
// the same ArisRecognizer interface as macOS 26's SpeechAnalyzer. Engine choice by macOS and the hidden switch, the
// tasks swapped before Apple's one-minute limit with their text stitched, the language picked, no "macOS 26 for
// talking" gate left, the test-file feed, and a talk turn, a wake check and a dictation through the protocol with fake
// recognition tasks. Called from main.swift; uses its check().
import AVFoundation
import Foundation

private let legacyRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func legacySource(_ path: String) -> String { (try? String(contentsOf: legacyRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runLegacySpeechTests() {
    legacyEngineChoiceTests()
    legacyStitchTests()
    legacyRotationRuleTests()
    legacyLocaleTests()
    legacyPrerequisiteTests()
    legacyFeedTests()
    legacyWiringTests()
    legacyRecognizerTestsBlocking()
}

// MARK: - Which engine

private func legacyEngineChoiceTests() {
    typealias E = ArisListenEngine
    check(E.pick(osMajor: 14, forceLegacy: false) == .legacy && E.pick(osMajor: 15, forceLegacy: false) == .legacy,
          "engine: macOS 14 and 15 listen with the older engine (SFSpeechRecognizer)")
    check(E.pick(osMajor: 26, forceLegacy: false) == .analyzer && E.pick(osMajor: 27, forceLegacy: false) == .analyzer,
          "engine: macOS 26 and later listen with SpeechAnalyzer")
    check(E.pick(osMajor: 26, forceLegacy: true) == .legacy && E.pick(osMajor: 27, forceLegacy: true) == .legacy
          && E.pick(osMajor: 14, forceLegacy: true) == .legacy,
          "engine: the hidden switch holds a macOS 26 Mac to the older engine")
    check(E.forced(osMajor: 26, forceLegacy: true) && !E.forced(osMajor: 15, forceLegacy: true) && !E.forced(osMajor: 26, forceLegacy: false),
          "engine: 'held to the older engine' only where the switch, not the macOS, chose it")
    check(E.forceLegacyKey == "arisForceLegacySpeech" && ArisListenFeed.fileKey == "arisListenFeedFile",
          "engine: the hidden switch and the test file are plain Defaults keys")

    let name = testSuiteName("aris-legacy-engine-tests")
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    let host = E.osMajor
    check(E.current(defaults: defaults) == E.pick(osMajor: host, forceLegacy: false), "engine: untouched, this Mac's macOS decides")
    defaults.set(true, forKey: E.forceLegacyKey)
    check(E.current(defaults: defaults) == .legacy, "engine: with the switch on, the older engine on any macOS")
    defaults.removePersistentDomain(forName: name)

    typealias W = ArisListenEngineWords
    check(W.settingsLine(engine: .legacy, place: .onDevice, osMajor: 15, forced: false) == "기기 안 Apple 음성 인식 (macOS 15)",
          "settings: 듣기 엔진 on macOS 15 says 기기 안 Apple 음성 인식 (macOS 15)")
    check(W.settingsLine(engine: .legacy, place: .server, osMajor: 14, forced: false) == "Apple 서버 음성 인식 (macOS 14)",
          "settings: server recognition is said as Apple 서버")
    check(W.settingsLine(engine: .analyzer, place: nil, osMajor: 26, forced: false).contains("새 엔진")
          && W.settingsLine(engine: .legacy, place: .onDevice, osMajor: 26, forced: true).contains("예전 엔진으로 고정"),
          "settings: the new engine and the switch are named")
    let pairs = ArisSettingsCopy.pairs(catalog: Data(legacySource("Aris/components/Settings/Settings.xcstrings").utf8))
    var table = ArisSettingsCopyTable(pairs)
    let lines = [W.settingsLine(engine: .legacy, place: .onDevice, osMajor: 15, forced: false), W.settingsLine(engine: .legacy, place: .server, osMajor: 14, forced: false),
                 W.settingsLine(engine: .analyzer, place: nil, osMajor: 26, forced: false), W.settingsLine(engine: .legacy, place: .onDevice, osMajor: 26, forced: true),
                 W.settingsLine(engine: .legacy, place: .server, osMajor: 27, forced: true), W.rowTitle]
    check(lines.allSatisfy { table.english($0) != nil }, "settings: every 듣기 엔진 line has its English")
    check(table.english(W.settingsLine(engine: .legacy, place: .onDevice, osMajor: 15, forced: false)) == "Apple speech recognition on this Mac (macOS 15)",
          "settings: the English names the Mac and the macOS")
    check(W.serverNotice(language: "한국어", english: false).contains("Apple 서버") && W.serverNotice(language: "Korean", english: true).contains("Apple's servers"),
          "notice: the one-time server line says where the voice goes")
}

// MARK: - The text across tasks

/// What a listener shows and keeps, fed the stitch's reports.
private struct Collected {
    var heard = ArisHeardText()
    var shown: [String] = []
    mutating func take(_ report: (kept: String, guess: String)) { shown.append(heard.take(kept: report.kept, guess: report.guess)) }
}

private func legacyStitchTests() {
    var stitch = ArisTaskStitch(), out = Collected()
    let first = stitch.begin()
    out.take(stitch.update(first, text: "오늘 회의는", final: false))
    out.take(stitch.update(first, text: "오늘 회의는 세 시에", final: false))
    check(out.shown.last == "오늘 회의는 세 시에" && out.heard.finished.isEmpty, "stitch: one task's guesses replace each other")
    // The task is swapped at a pause: the next one hears while the first finishes its last words.
    let second = stitch.begin()
    out.take(stitch.update(second, text: "시작해요", final: false))
    check(out.shown.last == "오늘 회의는 세 시에 시작해요", "stitch: the new task's words follow the old one's, a space between")
    out.take(stitch.update(first, text: "오늘 회의는 세 시에.", final: true))
    check(out.heard.finished == "오늘 회의는 세 시에." && out.shown.last == "오늘 회의는 세 시에. 시작해요",
          "stitch: the old task's final words are kept, the new one's still a guess")
    out.take(stitch.update(second, text: "시작해요.", final: true))
    check(out.heard.whole == "오늘 회의는 세 시에. 시작해요." && stitch.whole == out.heard.whole, "stitch: two tasks, one text")

    // A later task finishing first waits for the one before it: the order is kept.
    var order = ArisTaskStitch(), kept = Collected()
    let a = order.begin(), b = order.begin()
    kept.take(order.update(b, text: "second", final: true))
    check(kept.heard.finished.isEmpty && kept.shown.last == "second", "stitch: a later task's end is held until the one before it ends")
    kept.take(order.update(a, text: "first", final: true))
    check(kept.heard.whole == "first second", "stitch: then both, in order")

    // A silent task leaves no double space; a report after a task ended is ignored.
    var quiet = ArisTaskStitch(), q = Collected()
    let one = quiet.begin(); q.take(quiet.update(one, text: "hello", final: true))
    let two = quiet.begin(); q.take(quiet.end(two))
    let three = quiet.begin(); q.take(quiet.update(three, text: "world", final: true))
    q.take(quiet.update(one, text: "late words", final: false))
    check(q.heard.whole == "hello world", "stitch: a task that heard nothing adds nothing; late reports of an ended task are ignored")

    // An empty final from a task that wrote words keeps them.
    var empty = ArisTaskStitch(), e = Collected()
    let t = empty.begin(); e.take(empty.update(t, text: "keep me", final: false)); e.take(empty.update(t, text: "", final: true))
    check(e.heard.whole == "keep me", "stitch: an empty final keeps what the task wrote")

    // On-device recognition starting over inside a task after a long pause: what it wrote before is kept.
    var reset = ArisTaskStitch(), r = Collected()
    let task = reset.begin()
    r.take(reset.update(task, text: "Please send the report to the team", final: false))
    r.take(reset.update(task, text: "Thanks", final: false))
    check(r.shown.last == "Please send the report to the team Thanks", "stitch: a reset inside a task keeps the words before it")
    check(!ArisTaskStitch.looksLikeReset(from: "I scream for", to: "Ice cream for you") && !ArisTaskStitch.looksLikeReset(from: "send the report to", to: "send the")
          && ArisTaskStitch.looksLikeReset(from: "one two three four five", to: "six"),
          "stitch: a recogniser changing its mind is never taken for a reset")
    var all = ArisTaskStitch(), al = Collected()
    let x = all.begin(); al.take(all.update(x, text: "unfinished", final: false))
    al.take(all.endAll())
    check(al.heard.finished == "unfinished" && all.allEnded, "stitch: stopping keeps the last guess of a task that never ended")

    // While waiting for the wake word a finished phrase without the name is forgotten.
    var waiting = ArisHeardText(waiting: true)
    _ = waiting.take(kept: "오늘 날씨", guess: "")
    check(waiting.finished.isEmpty, "heard: while waiting, a finished phrase is forgotten")
    waiting.waiting = false
    _ = waiting.take(kept: "", guess: "아리스 타이머")
    check(waiting.whole == "아리스 타이머", "heard: after the name, the turn's words are kept")
}

// MARK: - When a task is swapped

private func legacyRotationRuleTests() {
    typealias R = ArisTaskRotation
    check(!R.shouldRotate(age: 30, quietFor: 5) && !R.shouldRotate(age: 44.9, quietFor: 1), "rotation: no swap in a task's first 45 s")
    check(!R.shouldRotate(age: 46, quietFor: 0.2) && R.shouldRotate(age: 46, quietFor: 0.4), "rotation: after 45 s, at a pause of 0.35 s")
    check(R.shouldRotate(age: 55, quietFor: 0) && R.latest < 60, "rotation: at 55 s whatever is said, before Apple's one-minute limit")
    var quick = 0, restart = true
    for _ in 0..<3 { (quick, restart) = R.afterEnd(quickEnds: quick, age: 0.5, wroteWords: false) }
    check(quick == 3 && !restart, "rotation: three tasks in a row ending at once with no words: it stops trying")
    check(R.afterEnd(quickEnds: 2, age: 10, wroteWords: false) == (0, true) && R.afterEnd(quickEnds: 2, age: 1, wroteWords: true) == (0, true),
          "rotation: a task that heard for a while or wrote words is followed by another")
}

// MARK: - The language

private func legacyLocaleTests() {
    // The older engine's own identifiers (underscores), with Aris's languages Korean then English.
    let older = ["en_GB", "en_US", "ja_JP", "ko_KR", "zh_CN"]
    check(ArisHearingLocale.pick(chosen: ["ko", "en"], chosenByUser: true, system: ["ko-KR"], supported: older) == "ko_KR",
          "locale: Korean and English chosen → the older engine hears Korean (the first language), as the 26 path picks")
    check(ArisHearingLocale.pick(chosen: ["en", "ko"], chosenByUser: true, system: ["ko-KR"], supported: older) == "en_US",
          "locale: English first → English, in the region people expect")
    check(ArisHearingLocale.pick(chosen: ["ko", "en"], chosenByUser: false, system: ["en-GB"], supported: older) == "en_GB",
          "locale: untouched on an English Mac → the Mac's own English")
    check(ArisHearingLocale.pick(chosen: ["vi"], chosenByUser: true, system: ["vi-VN"], supported: older) == "ko_KR",
          "locale: a language the older engine lacks → Korean, never a locale it can't make")
}

// MARK: - No "macOS 26 for talking"

private func legacyPrerequisiteTests() {
    typealias P = ArisPrerequisites
    check(P.missing(osMajor: 14, helperInstalled: true).isEmpty && P.missing(osMajor: 15, helperInstalled: true).isEmpty,
          "prerequisites: macOS 14 and 15 lack nothing for talking any more")
    check(P.missing(osMajor: 15, helperInstalled: false) == [.helper] && P.Missing.allCases == [.helper],
          "prerequisites: only a missing helper is said")
    check(P.atLaunch([]) == nil && P.atLaunch([.helper]) == .helper, "prerequisites at launch: no macOS card")
    check(ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 0, missing: [], english: false) == "모두 잘 되고 있어요",
          "settings status: all well on macOS 14 and 15")
    let prereq = legacySource("Aris/private/Aris/ArisPrerequisites.swift")
    check(!prereq.contains("voiceFromMajor") && !prereq.contains("Talking to Aris needs macOS"), "prerequisites: the macOS 26 line is gone")
    let controller = ["ArisController.swift", "ArisController+Conversation.swift", "ArisController+Countdown.swift", "ArisController+Dictation.swift",
                      "ArisController+Gesture.swift", "ArisController+Scribe.swift", "ArisController+Tasks.swift", "ArisController+Turn.swift",
                      "ArisController+Wake.swift"].map { legacySource("Aris/private/Aris/" + $0) }
    check(controller.allSatisfy { !$0.isEmpty && !$0.contains("macOS 26.0") }, "controller: talking, hands-free, wake word, cards and dictation have no macOS 26 gate")
    check(!legacySource("Aris/private/Aris/Dictation/ArisDictationPillCenter.swift").contains("#available(macOS 26"),
          "pill: dictation's pill shows on macOS 14 and 15 too")
    // What is macOS 26's own keeps its check (the notch glass, the polish model).
    check(legacySource("Aris/private/Aris/Notice/ArisNoticeCenter.swift").contains("#available(macOS 26.0, *)")
          && legacySource("Aris/private/Aris/ArisDictationPolish.swift").contains("#available(macOS 26.0, *)"),
          "prerequisites: macOS 26's own glass and polish keep their checks")
}

// MARK: - The test file instead of a microphone

private func legacyFeedTests() {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-legacy-feed-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    // One second of a 440 Hz tone at 48 kHz stereo, as a recorded clip might be.
    let url = folder.appendingPathComponent("tone.caf")
    let source = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    if let file = try? AVAudioFile(forWriting: url, settings: source.settings), let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 48_000) {
        buffer.frameLength = 48_000
        for channel in 0..<2 { for i in 0..<48_000 { buffer.floatChannelData![channel][i] = 0.3 * sin(Float(i) * 2 * .pi * 440 / 48_000) } }
        try? file.write(from: buffer)
    }
    guard let feed = try? ArisListenFeed(url: url) else { return check(false, "feed: a recorded clip is read") }
    check(abs(feed.duration - 1.0) < 0.02 && feed.format.sampleRate == 16_000 && feed.format.channelCount == 1,
          "feed: the clip is heard as 16 kHz mono, its own length")
    let chunk = feed.next(frames: 1600)
    let peak = chunk.map { b in (0..<Int(b.frameLength)).map { abs(b.floatChannelData![0][$0]) }.max() ?? 0 } ?? 0
    check(chunk?.frameLength == 1600 && peak > 0.2, "feed: 100 ms chunks of the clip")
    for _ in 0..<10 { _ = feed.next(frames: 1600) }
    let after = feed.next(frames: 1600)
    let afterPeak = after.map { b in (0..<Int(b.frameLength)).map { abs(b.floatChannelData![0][$0]) }.max() ?? 1 } ?? 1
    check(afterPeak == 0, "feed: silence once the clip is over (a hands-free pause is heard as one)")

    let name = testSuiteName("aris-legacy-feed-tests")
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    check(ArisListenFeed.configured(defaults: defaults) == nil, "feed: no setting, the microphone")
    defaults.set(folder.appendingPathComponent("missing.wav").path, forKey: ArisListenFeed.fileKey)
    check(ArisListenFeed.configured(defaults: defaults) == nil, "feed: a file that isn't there, the microphone")
    defaults.set(url.path, forKey: ArisListenFeed.fileKey)
    check(ArisListenFeed.configured(defaults: defaults)?.path == url.path, "feed: the file the setting names")
    defaults.removePersistentDomain(forName: name)

    // The paced feed hands chunks on until stopped.
    let delivered = Counter()
    feed.start(on: DispatchQueue(label: "aris.legacy.feed.test")) { buffer in delivered.add(Int(buffer.frameLength)) }
    Thread.sleep(forTimeInterval: 0.45)
    feed.stop()
    let count = delivered.value
    Thread.sleep(forTimeInterval: 0.25)
    check(count >= 1600 * 3 && delivered.value == count, "feed: chunks at a microphone's pace, none after stop")
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    func add(_ n: Int) { lock.withLock { stored += n } }
    var value: Int { lock.withLock { stored } }
}

// MARK: - Wiring

private func legacyWiringTests() {
    let listener = legacySource("Aris/private/Aris/ArisListener.swift")
    check(!listener.contains("@available(macOS 26") && !listener.contains("SpeechAnalyzer(") && listener.contains("ArisRecognizer"),
          "listener: available from macOS 14, hearing through ArisRecognizer")
    check(listener.contains("ArisListenEngine.current()") && listener.contains("ArisRotatingRecognizer(maker: ArisSFSpeechTasks())")
          && listener.contains("if engine == .analyzer, #available(macOS 26.0, *) { return ArisAnalyzerRecognizer() }"),
          "listener: the engine is picked at every listen; SpeechAnalyzer only where macOS 26 has it")
    check(listener.contains("usesMicrophone: source == nil && feed == nil") && listener.contains("Self.testFeed()"),
          "listener: a test file stands in for the microphone (no 'no microphone' line then)")
    let engines = legacySource("Aris/private/Aris/ArisSpeechEngines.swift")
    check(engines.contains("request.shouldReportPartialResults = true") && engines.contains("request.requiresOnDeviceRecognition = place == .onDevice")
          && engines.contains("supportsOnDeviceRecognition ? .onDevice : .server"),
          "older engine: partial results, on the Mac when it has the language's model, else Apple's servers")
    check(engines.contains("ArisLegacyServerNotice") && engines.contains("guard !defaults.bool(forKey: saidKey) else { return }"),
          "older engine: the server notice is said once")
    check(engines.contains("@available(macOS 26.0, *)\n@MainActor\nfinal class ArisAnalyzerRecognizer"),
          "new engine: SpeechAnalyzer stays behind its macOS 26 check")
    check(!listener.contains("requestAuthorization") && !engines.contains("requestAuthorization"),
          "permissions: the older engine asks for no new permission (Speech Recognition is Aris's row already)")
    let controller = legacySource("Aris/private/Aris/ArisController.swift"), wake = legacySource("Aris/private/Aris/ArisController+Wake.swift")
    check(controller.contains("listener.onProblem = { [weak self, weak listener] line in") && controller.contains("self.failDictation(line, endsDictation: true)")
          && wake.contains("self.wakeListenFailed(listener)\n        }\n"),
          "older engine: a turn, a dictation and a wake check say why when the engine can't hear")
    let builder = legacySource("Aris/components/Settings/ArisSettingsBuilder.swift")
    check(builder.contains("id: \"voice.engine\"") && builder.contains("ArisListenEngineWords.rowTitle"), "settings: 목소리 · 언어 shows 듣기 엔진")
    var s = ArisSettingsSnapshot()
    check(!ArisSettingsBuilder.sections(.voice, s).flatMap(\.rows).contains { $0.id == "voice.engine" }, "settings: no engine row in a still picture")
    s.listenEngine = ArisListenEngineWords.settingsLine(engine: .legacy, place: .onDevice, osMajor: 15, forced: false)
    let row = ArisSettingsBuilder.sections(.voice, s).flatMap(\.rows).first { $0.id == "voice.engine" }
    check(row?.title == "듣기 엔진" && row?.desc == "기기 안 Apple 음성 인식 (macOS 15)", "settings: the row says the engine in use")
    check(legacySource("Aris/components/Settings/ArisLiveSettings.swift").contains("s.listenEngine = ArisHearingShown.line()"), "settings: the live window reads it")
    let names = ["ArisListenEngine", "ArisRecognizer", "ArisSpeechEngines", "ArisListenFeed"].map { legacySource("Aris/private/Aris/\($0).swift").lowercased() }
    check(names.allSatisfy { !$0.isEmpty && !$0.contains("voice" + "os") && !$0.contains("wispr") && !$0.contains("superwhisper") },
          "older engine: its files name no other product")
}

// MARK: - Through the protocol, with fake recognition tasks

/// SFSpeechRecognizer's tasks, faked: each records its audio; the test says what it heard and when it ends.
@MainActor
private final class FakeTasks: ArisSpeechTaskMaker {
    final class Task: ArisSpeechTask, @unchecked Sendable {
        let onText: @MainActor (String, Bool) -> Void
        let onEnd: @MainActor (String?) -> Void
        private let lock = NSLock()
        private var frames = 0
        private(set) var audioEnded = false
        private(set) var cancelled = false
        /// What it answers endAudio() with (nil: it never answers).
        var lastWords: String? = ""
        init(onText: @escaping @MainActor (String, Bool) -> Void, onEnd: @escaping @MainActor (String?) -> Void) { self.onText = onText; self.onEnd = onEnd }
        var heardFrames: Int { lock.withLock { frames } }
        func append(_ buffer: AVAudioPCMBuffer) { lock.withLock { frames += Int(buffer.frameLength) } }
        func endAudio() {
            audioEnded = true
            guard let lastWords else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.onText(lastWords, true) } }
        }
        func cancel() { cancelled = true }
        @MainActor func say(_ text: String, final: Bool = false) { onText(text, final) }
        @MainActor func fail(_ problem: String? = nil) { onEnd(problem) }
    }

    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    var place = ArisListenPlace.onDevice
    var refuse = false
    private(set) var tasks: [Task] = []
    var nextLastWords: [String?] = []

    func prepare(locale: Locale) throws { if refuse { throw ArisFailure(message: ArisListenEngineWords.unavailable(english: true)) } }

    func make(hints: [String], onText: @escaping @MainActor (String, Bool) -> Void, onEnd: @escaping @MainActor (String?) -> Void) -> ArisSpeechTask {
        let task = Task(onText: onText, onEnd: onEnd)
        if !nextLastWords.isEmpty { task.lastWords = nextLastWords.removeFirst() }
        tasks.append(task)
        return task
    }
}

/// `seconds` of audio, loud (speech) or silent, in 1 s buffers, as the listener would hand them on.
private func feedAudio(_ input: ArisRecognizerInput, seconds: Int, loud: Bool, then tick: () -> Void = {}) {
    for _ in 0..<seconds {
        let buffer = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for i in 0..<16_000 { buffer.floatChannelData![0][i] = loud ? 0.2 * sin(Float(i) * 0.3) : 0 }
        input.append(buffer)
        tick()
    }
}

/// A short pause (0.5 s of quiet).
private func pause(_ input: ArisRecognizerInput) {
    let buffer = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: 8_000)!
    buffer.frameLength = 8_000
    input.append(buffer)
}

/// What ArisListener does with a recognizer: shows every report, keeps the text, returns it at stop.
@MainActor
private final class ListenerLike {
    let recognizer: ArisRecognizer
    var heard: ArisHeardText
    var shown: [String] = []
    init(_ recognizer: ArisRecognizer, waiting: Bool = false) {
        self.recognizer = recognizer
        heard = ArisHeardText(waiting: waiting)
        recognizer.onHeard = { [unowned self] kept, guess in self.shown.append(self.heard.take(kept: kept, guess: guess)) }
    }
    func stop() async -> String {
        await recognizer.finish()
        return heard.whole
    }
}

private final class LegacyFlag: @unchecked Sendable { var done = false }

private func legacyRecognizerTestsBlocking() {
    let flag = LegacyFlag()
    Task { @MainActor in
        await legacyRecognizerTests()
        flag.done = true
    }
    while !flag.done { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

@MainActor
private func legacyRecognizerTests() async {
    let locale = Locale(identifier: "ko-KR")

    // A talk turn (⌥Space held): partial words while talking, the final text at release.
    do {
        let tasks = FakeTasks(), recognizer = ArisRotatingRecognizer(maker: tasks)
        let turn = ListenerLike(recognizer)
        let missing = try? await recognizer.modelMissing(locale: locale)
        guard let input = try? await recognizer.start(locale: locale, hints: ["Aris"]) else { return check(false, "older engine: starts") }
        check(missing == false && input.format.sampleRate == 16_000 && tasks.tasks.count == 1, "talk turn: one task, 16 kHz audio, no model to wait for")
        feedAudio(input, seconds: 3, loud: true)
        check(tasks.tasks[0].heardFrames == 48_000, "talk turn: the task gets every buffer the listener hands on")
        tasks.tasks[0].say("오늘 날씨")
        tasks.tasks[0].say("오늘 날씨 어때")
        check(turn.shown == ["오늘 날씨", "오늘 날씨 어때"], "talk turn: partial words reach the notch as they come")
        tasks.nextLastWords = []
        tasks.tasks[0].lastWords = "오늘 날씨 어때?"
        let said = await turn.stop()
        check(said == "오늘 날씨 어때?" && tasks.tasks[0].audioEnded, "talk turn: the key's release gives the task's final words")
        check(ArisWakeWord.stripped(said) == "오늘 날씨 어때?" && ArisEndpoint.looksComplete(said), "talk turn: what is asked of the AI, a finished question")
    }

    // The wake word: a waiting listener sees the name, then the turn carries on.
    do {
        let tasks = FakeTasks(), recognizer = ArisRotatingRecognizer(maker: tasks)
        let wake = ListenerLike(recognizer, waiting: true)
        _ = try? await recognizer.start(locale: locale, hints: ArisHearingLocale.hints(vocabulary: [], locale: "ko-KR", waitingForWakeWord: true))
        tasks.tasks[0].say("아리스")
        check(wake.shown.last.map(ArisWakeWord.heard) == true, "wake word: the older engine's words are checked for the name")
        wake.heard.waiting = false
        tasks.tasks[0].say("아리스 타이머 삼 분 맞춰 줘")
        tasks.tasks[0].lastWords = "아리스 타이머 삼 분 맞춰 줘"
        let said = await wake.stop()
        check(ArisWakeWord.stripped(said) == "타이머 삼 분 맞춰 줘", "wake word: the words after the name are the request")
    }

    // A long hands-free dictation (75 s): the task is swapped at the first pause after 45 s, and again at 55 s with
    // no pause, the text stitched; release gives all of it.
    do {
        let tasks = FakeTasks(), recognizer = ArisRotatingRecognizer(maker: tasks)
        let dictation = ListenerLike(recognizer)
        guard let input = try? await recognizer.start(locale: locale, hints: []) else { return check(false, "dictation: starts") }
        feedAudio(input, seconds: 40, loud: true) { recognizer.tick() }
        tasks.tasks[0].say("첫 번째 문장입니다")
        check(tasks.tasks.count == 1, "dictation: no swap in the first 45 s")
        feedAudio(input, seconds: 6, loud: true) { recognizer.tick() }
        check(tasks.tasks.count == 1, "dictation: after 45 s, no swap while the voice goes on")
        tasks.tasks[0].lastWords = "첫 번째 문장입니다. 두 번째 문장입니다."
        pause(input)
        recognizer.tick()
        check(tasks.tasks.count == 2 && tasks.tasks[0].audioEnded, "dictation: swapped at the pause after 45 s; the old task is told the audio ended")
        feedAudio(input, seconds: 1, loud: true)
        check(tasks.tasks[1].heardFrames == 16_000 && tasks.tasks[0].heardFrames == 46 * 16_000 + 8_000,
              "dictation: the audio after the swap goes to the new task only")
        tasks.tasks[1].say("세 번째")
        // The old task's final words arrive after the new one already hears.
        while !tasks.tasks[0].audioEnded || dictation.heard.finished.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        check(dictation.shown.last == "첫 번째 문장입니다. 두 번째 문장입니다. 세 번째", "dictation: the old task's final words, then the new one's guess")
        tasks.tasks[1].lastWords = "세 번째 문장도 길게 이어집니다."
        feedAudio(input, seconds: 56, loud: true) { recognizer.tick() }
        check(tasks.tasks.count == 3, "dictation: swapped at 55 s even with no pause (Apple's one-minute limit)")
        tasks.tasks[2].say("마지막")
        tasks.tasks[2].lastWords = "마지막 문장입니다."
        let said = await dictation.stop()
        check(said == "첫 번째 문장입니다. 두 번째 문장입니다. 세 번째 문장도 길게 이어집니다. 마지막 문장입니다.",
              "dictation: more than a minute, three tasks, one text in order")
        check(ArisDictationCleaner.clean(said, endStop: true) == said, "dictation: the stitched text goes to the cleaner and insertion as it is")
        check(recognizer.started == 3 && tasks.tasks.allSatisfy(\.audioEnded), "dictation: every task was ended")
    }

    // A task that ends by itself (an error, the limit) while Aris still listens: the next one listens at once.
    do {
        let tasks = FakeTasks(), recognizer = ArisRotatingRecognizer(maker: tasks)
        let turn = ListenerLike(recognizer)
        guard let input = try? await recognizer.start(locale: locale, hints: []) else { return check(false, "restart: starts") }
        feedAudio(input, seconds: 20, loud: true)
        tasks.tasks[0].say("hands free words", final: true)
        check(tasks.tasks.count == 2 && turn.heard.finished == "hands free words", "restart: a task that ended by itself is followed by another; its words kept")
        feedAudio(input, seconds: 5, loud: true)
        tasks.tasks[1].fail()
        check(tasks.tasks.count == 3, "restart: after an error too")
        var problems: [String] = []
        recognizer.onProblem = { problems.append($0) }
        tasks.tasks[2].fail()
        tasks.tasks[3].fail()
        check(problems.isEmpty, "restart: two quick ends are retried quietly")
        tasks.tasks[4].fail()
        check(tasks.tasks.count == 5 && problems == [ArisListenEngineWords.couldNotHear(english: ArisUIWords.english)],
              "restart: three tasks in a row ending at once: it stops trying and says so, once")
        let said = await turn.stop()
        check(said == "hands free words", "restart: what was heard is still the turn's")
    }

    // macOS Dictation off (kLSRErrorDomain 201, seen in the VM): no retries, the line that says what to turn on.
    do {
        let tasks = FakeTasks(), recognizer = ArisRotatingRecognizer(maker: tasks)
        let turn = ListenerLike(recognizer)
        var problems: [String] = []
        recognizer.onProblem = { problems.append($0) }
        _ = try? await recognizer.start(locale: locale, hints: [])
        let line = ArisListenEngineWords.problem(domain: "kLSRErrorDomain", code: 201, english: false)
        tasks.tasks[0].fail(line)
        check(line == ArisListenEngineWords.dictationOff(english: false) && problems == [ArisListenEngineWords.dictationOff(english: false)] && tasks.tasks.count == 1,
              "dictation off: the first task's error ends the listen at once with 받아쓰기를 켜 주세요")
        check(ArisListenEngineWords.dictationOff(english: false).contains("시스템 설정 › 키보드 › 받아쓰기") && ArisListenEngineWords.dictationOff(english: true).contains("System Settings › Keyboard › Dictation"),
              "dictation off: the line says where to turn it on")
        check(ArisListenEngineWords.problem(domain: "kAFAssistantErrorDomain", code: 1110, english: true) == nil && ArisListenEngineWords.problem(domain: "kLSRErrorDomain", code: 301, english: true) == nil,
              "dictation off: no speech or a cancel is an ordinary end the next task follows")
        let said = await turn.stop()
        check(said.isEmpty, "dictation off: nothing made up")
    }

    // Stopping while the last task never answers: its last guess is the text, after a short wait.
    do {
        let tasks = FakeTasks(), recognizer = ArisRotatingRecognizer(maker: tasks)
        let turn = ListenerLike(recognizer)
        _ = try? await recognizer.start(locale: locale, hints: [])
        tasks.tasks[0].say("never finished")
        tasks.tasks[0].lastWords = nil
        let started = Date()
        let said = await turn.stop()
        let waited = Date().timeIntervalSince(started)
        check(said == "never finished" && waited >= ArisTaskRotation.finishWait - 0.1 && waited < ArisTaskRotation.finishWait + 1.5 && tasks.tasks[0].cancelled,
              "stop: a task with no final words is waited for 2 s, its guess kept, then cancelled")
    }

    // A recogniser that can't listen now says why.
    do {
        let tasks = FakeTasks(); tasks.refuse = true
        let recognizer = ArisRotatingRecognizer(maker: tasks)
        do {
            _ = try await recognizer.start(locale: locale, hints: [])
            check(false, "older engine: an unavailable recogniser fails the start")
        } catch {
            check(error.localizedDescription == ArisListenEngineWords.unavailable(english: true) && tasks.tasks.isEmpty,
                  "older engine: an unavailable recogniser fails the start with what to do")
        }
        let server = FakeTasks(); server.place = .server
        check(ArisRotatingRecognizer(maker: server).place == .server, "older engine: where it recognises is known (the notice and Settings say it)")
    }

    // Through the protocol: the listener holds `any ArisRecognizer`; either engine is driven the same way.
    let anyRecognizer: ArisRecognizer = ArisRotatingRecognizer(maker: FakeTasks())
    check((anyRecognizer as? ArisRotatingRecognizer) != nil, "protocol: the older engine is an ArisRecognizer like SpeechAnalyzer's")
}
