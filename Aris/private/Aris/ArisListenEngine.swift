//
//  ArisListenEngine.swift
//  Aris
//
//  Which of Apple's two speech engines hears Aris on this Mac. macOS 26 has SpeechAnalyzer (ArisAnalyzerRecognizer);
//  macOS 14 and 15 have only the older SFSpeechRecognizer (ArisRotatingRecognizer over ArisSFSpeechTasks), which
//  the owner asked for there ("14-15는 예전 엔진 쓰면 되지 않냐"). A hidden setting (arisForceLegacySpeech, no UI)
//  holds a macOS 26 Mac to the older engine, to test it on a 26 machine or VM.
//  Also the older engine's pure parts: its text stitched across its tasks (each about a minute at most), when a task
//  is swapped for the next, and what Settings and the one-time notice say. Foundation only (tested).
//

import Foundation

enum ArisListenEngine: String, Equatable, CaseIterable {
    /// SpeechAnalyzer + SpeechTranscriber (macOS 26).
    case analyzer
    /// SFSpeechRecognizer + SFSpeechAudioBufferRecognitionRequest (macOS 14 and 15, or held to it).
    case legacy

    /// The first macOS with SpeechAnalyzer.
    static let analyzerFromMajor = 26
    /// The hidden switch: true holds a macOS 26 Mac to the older engine (`defaults write com.lumenjsn.aris arisForceLegacySpeech -bool true`).
    static let forceLegacyKey = "arisForceLegacySpeech"

    static func pick(osMajor: Int, forceLegacy: Bool) -> ArisListenEngine {
        osMajor >= analyzerFromMajor && !forceLegacy ? .analyzer : .legacy
    }

    static var osMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    /// The engine this Mac uses now (the switch is read at every listen, so a change needs no restart).
    static func current(defaults: UserDefaults = .standard) -> ArisListenEngine {
        pick(osMajor: osMajor, forceLegacy: defaults.bool(forKey: forceLegacyKey))
    }

    /// Whether the switch, not the macOS, chose the older engine.
    static func forced(osMajor: Int, forceLegacy: Bool) -> Bool {
        forceLegacy && osMajor >= analyzerFromMajor
    }
}

/// Where the older engine recognises: on the Mac when it has the language's on-device model, else on Apple's servers.
enum ArisListenPlace: String, Equatable {
    case onDevice, server
}

/// What Settings › 목소리 · 언어 › 듣기 엔진 and the one-time notice say. Korean is the source (the settings catalog
/// has the English of the settings line); the notice has both.
enum ArisListenEngineWords {
    static let rowTitle = "듣기 엔진"

    /// The row's line: which engine, where it listens, and the macOS. `place`: the older engine's (nil: not known yet).
    static func settingsLine(engine: ArisListenEngine, place: ArisListenPlace?, osMajor: Int, forced: Bool) -> String {
        switch engine {
        case .analyzer:
            return "기기 안 Apple 음성 인식 (macOS \(osMajor), 새 엔진)"
        case .legacy:
            if forced { return place == .server ? "Apple 서버 음성 인식 (macOS \(osMajor), 예전 엔진으로 고정)" : "기기 안 Apple 음성 인식 (macOS \(osMajor), 예전 엔진으로 고정)" }
            return place == .server ? "Apple 서버 음성 인식 (macOS \(osMajor))" : "기기 안 Apple 음성 인식 (macOS \(osMajor))"
        }
    }

    /// Said once, the first time the older engine has to send the voice to Apple (no on-device model for `language`).
    static func serverNotice(language: String, english: Bool) -> String {
        english ? "This Mac has no on-device speech recognition for \(language), so Aris sends what you say to Apple's servers to recognise it."
            : "이 Mac에는 \(language) 음성 인식이 기기 안에 없어서, 말한 소리를 Apple 서버로 보내 알아들어요."
    }

    static func serverNoticeTitle(english: Bool) -> String {
        english ? "Listening through Apple's servers" : "Apple 서버로 듣는 중"
    }

    /// The older engine has no recogniser for the language at all.
    static func unsupported(_ locale: String, english: Bool) -> String {
        english ? "This Mac's speech recognition doesn't have \(locale)." : "이 Mac의 음성 인식에는 \(locale)이 없어요."
    }

    /// macOS's own Dictation (or Siri) is off: the older engine can't recognise anything then (its tasks end at once
    /// with kLSRErrorDomain 201), on the Mac or on Apple's servers.
    static func dictationOff(english: Bool) -> String {
        english ? "To listen on this Mac, Aris needs macOS Dictation: turn it on in System Settings › Keyboard › Dictation."
            : "이 Mac에서 들으려면 macOS 받아쓰기가 켜져 있어야 해요. 시스템 설정 › 키보드 › 받아쓰기를 켜 주세요."
    }

    /// The older engine's tasks kept ending at once for another reason.
    static func couldNotHear(english: Bool) -> String {
        english ? "Speech recognition stopped right after it started. Please try again in a moment."
            : "음성 인식이 시작하자마자 멈췄어요. 잠시 뒤에 다시 해 주세요."
    }

    /// What a task's error means for the user, by its domain and code; nil when it is an ordinary end (no speech, a
    /// cancel) the next task can follow.
    static func problem(domain: String, code: Int, english: Bool) -> String? {
        domain == "kLSRErrorDomain" && code == 201 ? dictationOff(english: english) : nil
    }

    /// The recogniser is there but can't listen now (server recognition without a network, Siri and Dictation off).
    static func unavailable(english: Bool) -> String {
        english ? "Speech recognition isn't available right now. Check the network, or turn on Dictation in System Settings › Keyboard."
            : "지금은 음성 인식을 쓸 수 없어요. 네트워크를 확인하거나 시스템 설정 › 키보드에서 받아쓰기를 켜 주세요."
    }
}

/// The older engine's text across its tasks. Each task reports its whole text so far (a guess, then a final one when
/// it ends); a task swapped out at a pause can still finish its last words while the next one already hears. The
/// listener keeps finished text and replaces its guess (ArisRecognizer.onHeard): `update` says what became final, in
/// order, and the guess after it.
struct ArisTaskStitch: Equatable {
    private struct Segment: Equatable {
        /// Text a reset of this task already left behind (the recogniser starting over after a pause).
        var before = ""
        var latest = ""
        var ended = false
        var text: String { ArisTaskStitch.joined([before, latest]) }
    }

    private var segments: [Segment] = []
    /// How many segments from the start have been handed out as final.
    private var handedOut = 0
    /// Any non-empty text was handed out (the next piece starts with a space).
    private var keptAny = false

    /// A new task's segment.
    mutating func begin() -> Int {
        segments.append(Segment())
        return segments.count - 1
    }

    var count: Int { segments.count }

    func isEnded(_ index: Int) -> Bool { segments.indices.contains(index) && segments[index].ended }

    var allEnded: Bool { segments.allSatisfy(\.ended) }

    /// Task `index` reported `text` (`final`: its last). A report after the task ended is ignored.
    mutating func update(_ index: Int, text: String, final: Bool) -> (kept: String, guess: String) {
        guard segments.indices.contains(index), !segments[index].ended else { return (kept: "", guess: guess) }
        // An empty last word from a task that wrote some keeps what it wrote.
        if !(final && text.isEmpty) {
            if Self.looksLikeReset(from: segments[index].latest, to: text) { segments[index].before = segments[index].text }
            segments[index].latest = text
        }
        if final { segments[index].ended = true }
        return handOut()
    }

    /// Task `index` ended without a final text (an error, or no answer in time): its last guess is kept as it is.
    mutating func end(_ index: Int) -> (kept: String, guess: String) {
        guard segments.indices.contains(index), !segments[index].ended else { return (kept: "", guess: guess) }
        segments[index].ended = true
        return handOut()
    }

    /// Every task ended now (the listener stopped and the last ones took too long).
    mutating func endAll() -> (kept: String, guess: String) {
        for index in segments.indices { segments[index].ended = true }
        return handOut()
    }

    /// Everything heard, finished and guessed.
    var whole: String { Self.joined(segments.map(\.text)) }

    private var guess: String {
        let rest = Self.joined(segments[handedOut...].map(\.text))
        return keptAny && !rest.isEmpty ? " " + rest : rest
    }

    private mutating func handOut() -> (kept: String, guess: String) {
        var done: [String] = []
        while handedOut < segments.count, segments[handedOut].ended {
            done.append(segments[handedOut].text)
            handedOut += 1
        }
        let joined = Self.joined(done)
        let kept = keptAny && !joined.isEmpty ? " " + joined : joined
        if !joined.isEmpty { keptAny = true }
        return (kept: kept, guess: guess)
    }

    /// The pieces that have words, a space between them.
    static func joined(_ pieces: [String]) -> String {
        pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The recogniser started over inside one task (on-device recognition after a long pause can drop what it wrote
    /// before): the new text is less than half as many words and doesn't begin as the old one did. A recogniser
    /// changing its mind about the last words keeps the start, so it is never taken for one.
    static func looksLikeReset(from old: String, to new: String) -> Bool {
        let before = words(old), after = words(new)
        guard before.count >= 3, !after.isEmpty, after.count * 2 < before.count else { return false }
        return after.first != before.first
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
    }
}

/// When the older engine swaps its task for a new one. Apple stops a task after about a minute, so a long dictation
/// or hands-free turn is heard as several tasks, the swap made at a pause (never mid-word if there is one) and
/// stitched (ArisTaskStitch). A task that ends by itself while Aris still listens is followed by another at once,
/// unless they keep ending right away (no recogniser to hear with): then it stops trying. Times are in seconds of
/// audio heard, so the tests need no clock.
enum ArisTaskRotation {
    /// From here a pause swaps the task.
    static let earliest = 45.0
    /// Swapped here whatever is said (Apple's limit is about 60 s).
    static let latest = 55.0
    /// A quiet this long is a pause.
    static let pause = 0.35
    /// A chunk below this loudness (RMS of samples in -1...1) is quiet.
    static let quietRMS: Float = 0.012
    /// A task that ends this soon having written nothing ended "at once".
    static let quickEnd = 2.0
    /// Tasks in a row allowed to end at once before it stops trying.
    static let quickEndsAllowed = 3
    /// How long stop() waits for the last tasks' final words.
    static let finishWait = 2.0

    static func shouldRotate(age: Double, quietFor: Double) -> Bool {
        age >= latest || (age >= earliest && quietFor >= pause)
    }

    /// After a task that ended by itself: how many quick ends in a row now, and whether to start another.
    static func afterEnd(quickEnds: Int, age: Double, wroteWords: Bool) -> (quickEnds: Int, restart: Bool) {
        let count = age < quickEnd && !wroteWords ? quickEnds + 1 : 0
        return (quickEnds: count, restart: count < quickEndsAllowed)
    }
}

/// What a listener has heard, whichever engine: finished text plus the recognizer's current guess
/// (ArisRecognizer.onHeard). While waiting for the wake word a finished phrase is forgotten once it was shown (only
/// the current phrase is kept until the name is heard).
struct ArisHeardText: Equatable {
    private(set) var finished = ""
    private(set) var guess = ""
    var waiting = false

    init(waiting: Bool = false) { self.waiting = waiting }

    /// The recognizer's report; returns the text to show (everything so far).
    mutating func take(kept: String, guess: String) -> String {
        finished += kept
        self.guess = guess
        let shown = finished + guess
        if waiting && !kept.isEmpty { finished = "" }
        return shown
    }

    /// The whole utterance, as stop() returns it.
    var whole: String { (finished + guess).trimmingCharacters(in: .whitespacesAndNewlines) }
}
