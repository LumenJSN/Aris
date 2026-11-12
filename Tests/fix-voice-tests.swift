// Tests for the voice audit of 2026-11-10 (qa/audit-1110/voice.json): the pure rules behind each fix, the sentence
// reader with a fake voice, and where a rule can only be wired in a file the tests can't compile (the controller, the
// listener, the speaker), a check that the wiring is there. Called from main.swift; uses its check().
import Foundation

func runFixVoiceTests() {
    micInterruptionTests()
    dictationEndTests()
    dictationPressRefusalTests()
    wakeHandOverTests()
    wakeStartFailureTests()
    wakeRetryTests()
    handsFreeCapTests()
    longTurnTests()
    hearingLocaleTests()
    transcriptScriptTests()
    voiceFallbackTests()
    cloudBreakerTests()
    answerVoiceTests()
    voiceWiringTests()
    final class Done: @unchecked Sendable { var value = false }
    let done = Done()
    Task { @MainActor in
        await sentenceReaderTests()
        done.value = true
    }
    while !done.value { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

// MARK: - voice-1: the microphone changes mid-dictation

private func micInterruptionTests() {
    check(ArisMicInterruption.outcome(dictating: true, heardWords: true, heardVoice: true) == .typeDictation,
          "voice-1: the microphone changes mid-dictation with words said -> they are typed, as if the key was let go")
    check(ArisMicInterruption.outcome(dictating: true, heardWords: false, heardVoice: false) == .endDictation,
          "voice-1: the microphone changes mid-dictation with nothing said -> it ends with the reason")
    check(ArisMicInterruption.outcome(dictating: true, heardWords: true, heardVoice: false) == .typeDictation
          && ArisMicInterruption.outcome(dictating: true, heardWords: false, heardVoice: true) == .typeDictation,
          "voice-1: words written by the recogniser, or voice alone, are both something to type")
    var everATurn = false
    for words in [false, true] {
        for voice in [false, true] {
            let outcome = ArisMicInterruption.outcome(dictating: true, heardWords: words, heardVoice: voice)
            if outcome == .endTurn || outcome == .failTurn { everATurn = true }
        }
    }
    check(!everATurn, "voice-1: a dictation is never handed on as a turn for the AI, whatever was heard")
    check(ArisMicInterruption.outcome(dictating: false, heardWords: true, heardVoice: true) == .endTurn
          && ArisMicInterruption.outcome(dictating: false, heardWords: false, heardVoice: true) == .failTurn,
          "voice-1: a turn with Aris is as before: its words go on, nothing heard fails with a reason")
    check(ArisMicInterruption.dictationLine.contains("받아쓰기") && ArisMicInterruption.dictationLine.contains("마이크"),
          "voice-1: the dictation's line says what stopped and why")
}

// MARK: - voice-10: a quiet microphone's words are still typed

private func dictationEndTests() {
    check(ArisDictationEnd.saidSomething(heardVoice: false, wroteWords: true),
          "voice-10: words the recogniser wrote are typed even when the level never counted as voice")
    check(ArisDictationEnd.saidSomething(heardVoice: true, wroteWords: false),
          "voice-10: voice without live words still goes to the second listen")
    check(!ArisDictationEnd.saidSomething(heardVoice: false, wroteWords: false),
          "voice-10: no voice and no words -> nothing said")
}

// MARK: - voice-9: the right ⌥ while Aris is busy

private func dictationPressRefusalTests() {
    typealias Press = ArisDictationPress
    check(Press.decide(turn: .speaking, training: false, lastTyped: false, lastTyping: false) == .interrupt,
          "voice-9: while Aris reads an answer out -> it stops and the dictation starts")
    check(Press.decide(turn: .failed, training: false, lastTyped: false, lastTyping: false) == .interrupt,
          "voice-9: while a failure line is up -> it closes and the dictation starts")
    check(Press.decide(turn: .failed, training: false, lastTyped: false, lastTyping: true) == .interrupt,
          "voice-9: after \"입력하지 못했어요\" the press starts a dictation; it is not queued and then dropped")
    check(Press.decide(turn: .thinking, training: false, lastTyped: false, lastTyping: false) == .refuse(.thinking),
          "voice-9: while the AI works -> not now, with the reason")
    check(Press.decide(turn: .listening, training: false, lastTyped: false, lastTyping: false) == .refuse(.listening),
          "voice-9: while Aris hears a request -> not now, with the reason")
    check(Press.decide(turn: .asking, training: false, lastTyped: false, lastTyping: false) == .refuse(.asking),
          "voice-9: while a confirm card waits -> not now, with the reason (Aris's question is never talked over)")
    check(Press.decide(turn: .speaking, training: true, lastTyped: false, lastTyping: false) == .refuse(.training),
          "voice-9: while the wake word is trained -> not now, with the reason")
    let reasons: [Press.Why] = [.training, .listening, .thinking, .asking]
    check(reasons.allSatisfy { !$0.line.isEmpty && $0.line.contains("받아쓰기") } && Set(reasons.map(\.line)).count == reasons.count,
          "voice-9: every refusal has its own line that names dictation")
    check(reasons.allSatisfy { $0.line.count <= 30 }, "voice-9: a refusal's line fits one tag")
    check(Press.decide(turn: .speaking, training: false, lastTyped: true, lastTyping: false) == .replaceTyped
          && Press.decide(turn: .thinking, training: false, lastTyped: false, lastTyping: true) == .queue,
          "voice-9: the last dictation's own states are as before (\"넣었어요\" is replaced, typing is waited for)")
    check(Press.refusalLinger >= .seconds(2) && Press.refusalLinger <= .seconds(4), "voice-9: the reason stays long enough to read")
}

// MARK: - voice-2: woken by a sure voice before the recogniser started

private func wakeHandOverTests() {
    var sure = ArisWakeHandOver()
    sure.beginTurn()
    check(!sure.startsWaiting(asked: true),
          "voice-2: beginTurn() before start() (a sure voice) -> start() does not put the listener back to waiting")
    var usual = ArisWakeHandOver()
    check(usual.startsWaiting(asked: true), "voice-2: start() first (the recogniser checks the phrase) -> it waits for the name")
    usual.beginTurn()
    check(usual.turnBegan && !usual.startsWaiting(asked: true), "voice-2: ... and once the name is heard it is a turn's listener")
    check(!ArisWakeHandOver().startsWaiting(asked: false), "voice-2: a key-press turn never waits")

    // The listener's own two fields, driven in the order a sure wake drives them: phrases kept, recording whole.
    struct Listener {
        var handOver = ArisWakeHandOver()
        var waiting = false
        var rolling = false
        var finished = ""
        mutating func start(waitingForWakeWord: Bool) {
            waiting = handOver.startsWaiting(asked: waitingForWakeWord)
            rolling = waiting
        }
        mutating func beginTurn() {
            handOver.beginTurn()
            waiting = false
            rolling = false
        }
        mutating func take(_ text: String) {
            finished += text
            if waiting { finished = "" }
        }
    }
    var listener = Listener()
    listener.beginTurn()
    listener.start(waitingForWakeWord: true)
    listener.take("아리스, 내일 날씨 알려줘")
    check(!listener.waiting && !listener.rolling && listener.finished == "아리스, 내일 날씨 알려줘",
          "voice-2: a sure wake keeps the finished phrase and a whole recording")

    check(ArisWakeHandOver.lead(recordedSeconds: 1.8, sinceTurnBegan: .milliseconds(300)) == .milliseconds(1500),
          "voice-2: the recording made before the turn began is what is recorded less the time since")
    check(ArisWakeHandOver.lead(recordedSeconds: 0, sinceTurnBegan: .milliseconds(300)) == .zero
          && ArisWakeHandOver.lead(recordedSeconds: 0.1, sinceTurnBegan: .seconds(2)) == .zero,
          "voice-2: the lead is never negative")
}

// MARK: - voice-7: the wake word's recogniser can't start

private func wakeStartFailureTests() {
    check(ArisWakeStartFailure.after(isTurnListener: true, isWakeListener: false) == .failTurn,
          "voice-7: Aris already woke on a recogniser that can't start -> the turn fails with the reason")
    check(ArisWakeStartFailure.after(isTurnListener: false, isWakeListener: true) == .dropCheck,
          "voice-7: still checking the phrase -> nothing wakes Aris into that recogniser")
    check(ArisWakeStartFailure.after(isTurnListener: false, isWakeListener: false) == .nothing,
          "voice-7: another check or turn has the microphone -> left alone")
    let line = ArisStartFailure.line(ArisFailure(message: "음성 인식 모델을 준비하는 중이에요."), timedOut: false, abandoned: false)
    check(line?.contains("음성 인식 모델을 준비하는 중이에요.") == true, "voice-7: the failed turn's line carries the reason")
}

// MARK: - voice-11: the wake word's microphone couldn't open

private func wakeRetryTests() {
    var restarts = 0
    var delays: [Duration] = []
    for _ in 0..<9 {
        restarts = ArisAudioQuiet.wakeRestarts(afterFailedOpen: restarts)
        delays.append(ArisAudioQuiet.wakeRestartDelay(restarts: restarts))
    }
    check(delays.first == .seconds(1), "voice-11: a microphone that couldn't open is tried again a second later")
    check(zip(delays, delays.dropFirst()).allSatisfy { $0 <= $1 } && delays.last == ArisAudioQuiet.longestWakeRestart,
          "voice-11: ... then after a growing pause, a minute apart at most, for as long as it takes")
    check(ArisAudioQuiet.wakeRestarts(after: restarts, ranFor: .seconds(40)) == 1,
          "voice-11: once it opened and ran, the count starts again")
}

// MARK: - voice-4: the hands-free cap and give-up

private func handsFreeCapTests() {
    check(ArisTalkKey.mustEnd(sinceStart: ArisTalkKey.longestTurn, heardWords: true),
          "voice-4: at the cap the turn ends with no grace moment, even mid-word")
    check(!ArisTalkKey.mustEnd(sinceStart: ArisTalkKey.longestTurn - .seconds(1), heardWords: true),
          "voice-4: before the cap a turn with words ends only on a pause")
    check(ArisTalkKey.mustEnd(sinceStart: ArisTalkKey.longestWaitForWords, heardWords: false),
          "voice-4: no word at all in the longest wait -> over, whatever the room sounds like")
    check(!ArisTalkKey.mustEnd(sinceStart: ArisTalkKey.waitForWords + .seconds(1), heardWords: false),
          "voice-4: just past the give-up the grace moment may still hold (a voice that began at second 7)")
    check(ArisTalkKey.longestWaitForWords > ArisTalkKey.waitForWords && ArisTalkKey.longestWaitForWords <= .seconds(20),
          "voice-4: the forced give-up comes after the usual one, and soon")
    // The room never goes quiet: every look past the give-up says "heard enough", and the forced end comes.
    var ended: Duration?
    var now = Duration.zero
    while now < .seconds(60), ended == nil {
        now += .milliseconds(800)
        let enough = ArisTalkKey.heardEnough(sinceStart: now, sinceLastWords: nil, sinceLastVoice: .milliseconds(50))
        if enough, ArisTalkKey.mustEnd(sinceStart: now, heardWords: false) { ended = now }
    }
    check(ended.map { $0 <= .seconds(16) } == true, "voice-4: music with no words ends the turn within sixteen seconds, not never")
    check(ArisTalkKey.longestTurn >= .seconds(120) && Double(ArisTalkKey.longestTurn.components.seconds) < ArisLongTurn.recordedSeconds,
          "voice-imp-3: a hands-free turn may run for minutes, and always fits the recording")
}

// MARK: - voice-5, voice-imp-3: turns longer than Whisper's window

private func longTurnTests() {
    let rate = 16_000.0
    check(ArisLongTurn.isWhole(recorded: Int(rate * 45), sampleRate: rate),
          "voice-5: a 45-second turn is recorded whole (it used to stop at 30 s)")
    check(!ArisLongTurn.isWhole(recorded: ArisLongTurn.recordedLimit(sampleRate: rate), sampleRate: rate),
          "voice-5: a turn that outran the recording is not whole -> Whisper's text of its start is never used")

    let short = [Float](repeating: 0.1, count: Int(rate * 12))
    check(ArisLongTurn.windows(of: short, sampleRate: rate) == [0..<short.count], "voice-imp-3: a turn that fits is one window, as before")
    check(ArisLongTurn.windows(of: [], sampleRate: rate).isEmpty, "voice-imp-3: nothing recorded -> no window")
    let exact = [Float](repeating: 0.1, count: Int(rate * 30))
    check(ArisLongTurn.windows(of: exact, sampleRate: rate).count == 1, "voice-imp-3: exactly 30 s is still one window")

    // 70 s of speech with a short pause at 27.0–27.4 s and another at 55.0–55.4 s.
    var long = [Float](repeating: 0.3, count: Int(rate * 70))
    for index in Int(rate * 27.0)..<Int(rate * 27.4) { long[index] = 0 }
    for index in Int(rate * 55.0)..<Int(rate * 55.4) { long[index] = 0 }
    let windows = ArisLongTurn.windows(of: long, sampleRate: rate)
    check(windows.count == 3, "voice-imp-3: 70 s is read in three windows")
    check(windows.first?.lowerBound == 0 && windows.last?.upperBound == long.count
          && zip(windows, windows.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound },
          "voice-imp-3: the windows cover the whole turn, in order, with no gap and no overlap")
    check(windows.allSatisfy { Double($0.count) <= rate * ArisLongTurn.windowSeconds },
          "voice-imp-3: no window is longer than Whisper reads")
    let firstCut = Double(windows[0].upperBound) / rate, secondCut = Double(windows[1].upperBound) / rate
    check((27.0...27.4).contains(firstCut) && (55.0...55.4).contains(secondCut),
          "voice-imp-3: each window ends in the pause near its end, so no word is cut in half")
    let steady = [Float](repeating: 0.3, count: Int(rate * 40))
    let steadyWindows = ArisLongTurn.windows(of: steady, sampleRate: rate)
    check(steadyWindows.count == 2 && Double(steadyWindows[0].count) >= rate * (ArisLongTurn.windowSeconds - ArisLongTurn.cutSearchSeconds),
          "voice-imp-3: with no pause to cut at, a window still ends within its last five seconds")

    check(ArisLongTurn.joined(["Chrome 열고 지난주 회의록 찾아서 요약해 줘 그리고", " 보내지는 말고 초안만 만들어 줘 "])
          == "Chrome 열고 지난주 회의록 찾아서 요약해 줘 그리고 보내지는 말고 초안만 만들어 줘",
          "voice-5: the end of a long instruction is kept (\"보내지는 말고 초안만\")")
    check(ArisLongTurn.joined(["메일 초안 써 줘", "시청해 주셔서 감사합니다.", "", "제목은 회의 일정으로"]) == "메일 초안 써 줘 제목은 회의 일정으로",
          "voice-imp-3: a window Whisper filled with its silence phrase, or with nothing, is left out")

    let first = Duration.seconds(3)
    check(ArisLongTurn.whisperTimeout(samples: Int(rate * 20), sampleRate: rate, first: first) == first,
          "voice-imp-3: a turn that fits one window waits for Whisper as long as before")
    check(ArisLongTurn.whisperTimeout(samples: Int(rate * 45), sampleRate: rate, first: first) == .seconds(5)
          && ArisLongTurn.whisperTimeout(samples: Int(rate * 75), sampleRate: rate, first: first) == .seconds(7),
          "voice-imp-3: each further window gives Whisper two seconds more")
    check(ArisLongTurn.whisperTimeout(samples: Int(rate * 300), sampleRate: rate, first: first) == ArisLongTurn.longestTimeout,
          "voice-imp-3: however long the turn, Aris never waits more than twelve seconds for Whisper")
    check(ArisLongTurn.readsDuringGrace(seconds: 29) && !ArisLongTurn.readsDuringGrace(seconds: 31),
          "voice-imp-3: Whisper reads ahead during the grace moment only while the turn fits one window")
}

// MARK: - voice-6: which language Apple's recogniser listens in

private func hearingLocaleTests() {
    let supported = ["ko-KR", "en-US", "en-GB", "ja-JP", "zh-CN", "zh-TW", "fr-FR", "de-DE", "es-ES"]
    func pick(_ chosen: [String], byUser: Bool, system: [String], supported list: [String] = supported) -> String {
        ArisHearingLocale.pick(chosen: chosen, chosenByUser: byUser, system: system, supported: list)
    }
    check(pick(ArisLanguages.defaults, byUser: false, system: ["ko-KR"]) == "ko-KR",
          "voice-6: a Korean Mac with the languages untouched is heard in Korean, as before")
    check(pick(ArisLanguages.defaults, byUser: false, system: ["en-US"]) == "en-US",
          "voice-6: an English Mac with the languages untouched is heard in English, not written as Hangul")
    check(pick(ArisLanguages.defaults, byUser: false, system: ["en-GB", "fr-FR"]) == "en-GB",
          "voice-6: ... in its own region's English when the recogniser has it")
    check(pick(ArisLanguages.defaults, byUser: false, system: ["en-US", "ko-KR"]) == "ko-KR"
          && pick(ArisLanguages.defaults, byUser: false, system: ["en-KR"]) == "ko-KR",
          "voice-6: a Mac with Korean among its languages, or an English system in Korea, stays Korean until told otherwise")
    check(pick(["en"], byUser: true, system: ["ko-KR"]) == "en-US",
          "voice-6: English alone turned on -> English, whatever the system's language")
    check(pick(["ko", "en"], byUser: true, system: ["en-US"]) == "ko-KR",
          "voice-6: the user's own order is taken: Korean first stays Korean on an English Mac")
    check(pick(["ja", "en"], byUser: true, system: ["ko-KR"]) == "ja-JP", "voice-6: the first language turned on is the recogniser's")
    check(pick(["zh-Hant", "en"], byUser: true, system: ["en-US"]) == "zh-TW" && pick(["zh-Hans"], byUser: true, system: []) == "zh-CN",
          "voice-6: Traditional and Simplified Chinese get their own recognisers")
    check(pick(["sw", "en"], byUser: true, system: ["ko-KR"]) == "en-US",
          "voice-6: a language the recogniser doesn't have -> the next one turned on")
    check(pick(["sw"], byUser: true, system: ["en-US"]) == "ko-KR" && pick([], byUser: false, system: []) == "ko-KR",
          "voice-6: nothing usable -> Korean, as before")
    check(pick(ArisLanguages.defaults, byUser: false, system: ["en-US"], supported: ["ko_KR", "en_US"]) == "en_US",
          "voice-6: the recogniser's own spelling of the locale is what comes back")
    check(pick(ArisLanguages.defaults, byUser: false, system: ["en-US"], supported: ["ko-KR"]) == "ko-KR",
          "voice-6: before the recogniser's list is known (Korean alone) nothing changes")
    check(pick(ArisLanguages.defaults, byUser: false, system: ["it-IT", "en-US"], supported: ["ko-KR", "en-US"]) == "en-US",
          "voice-6: the system's first language the recogniser has")
    check(ArisHearingLocale.wanted(chosen: ["ko", "en"], chosenByUser: false, system: ["en-US", "en-GB", "fr-FR"]) == ["en-US", "fr-FR", "ko"],
          "voice-6: each language is tried once, the system's first")
    check(pick(ArisLanguages.defaults, byUser: false, system: ["sw-KE"]) == "en-US",
          "voice-6: a Mac in a language the recogniser doesn't have, languages untouched -> English before Korean")

    check(ArisHearingLocale.hints(vocabulary: ["Notion"], locale: "en-US", waitingForWakeWord: true) == ["Notion", "Aris"],
          "voice-6: an English recogniser checking for the wake word is told to expect \"Aris\"")
    check(ArisHearingLocale.hints(vocabulary: ["Notion"], locale: "ko-KR", waitingForWakeWord: true) == ["Notion"]
          && ArisHearingLocale.hints(vocabulary: ["Notion"], locale: "en-US", waitingForWakeWord: false) == ["Notion"],
          "voice-6: the Korean recogniser, and any turn's, gets the vocabulary as it is")
}

private func transcriptScriptTests() {
    func pick(_ whisper: String, _ apple: String, languages: [String] = ArisLanguages.defaults, recognizer: String = "ko-KR") -> String {
        ArisTranscript.pick(whisper: whisper, apple: apple, heardVoice: true, voiceFrames: 40, loudest: 0.5, languages: languages, recognizer: recognizer)
    }
    check(pick("Chrome 열어 줘", "크롬 열어 줘") == "Chrome 열어 줘" && pick("내일 날씨 알려 줘", "내일 날씨 알려줘") == "내일 날씨 알려줘",
          "voice-6: Korean and English as before: Whisper for English words, Apple for all-Korean speech")
    check(pick("明日の天気を教えて", "아시타노 텐키오 오시에테", languages: ["ko", "ja"]) == "明日の天気を教えて",
          "voice-6: Japanese turned on -> Whisper's Japanese, not Apple's Hangul of it")
    check(pick("明日の天気を教えて", "내일 날씨 알려줘") == "내일 날씨 알려줘",
          "voice-6: Japanese not turned on -> Whisper misreading Korean as Japanese never wins")
    check(pick("Какая погода завтра", "카카야 파고다 자프트라", languages: ["ko", "ru"]) == "Какая погода завтра",
          "voice-6: Russian turned on -> Whisper's Cyrillic")
    check(pick("내일 날씨 알려 줘", "nail nalshi allyeojwo", languages: ["en", "ko"], recognizer: "en-US") == "내일 날씨 알려 줘",
          "voice-6: an English recogniser with Korean turned on -> Whisper's Korean")
    check(pick("What's the weather tomorrow", "What's the weather tomorrow?", languages: ["en"], recognizer: "en-US") == "What's the weather tomorrow?",
          "voice-6: English heard by an English recogniser -> Apple's own text stands")
    check(ArisScript.used(in: "3 km 남았어요") == [.hangul, .latin] && ArisScript.used(in: "A 안") == [.hangul],
          "voice-6: Latin counts from a word of two letters")
    check(ArisScript.writing("ja") == [.kana, .han] && ArisScript.writing("zh-Hant") == [.han] && ArisScript.writing("en-US") == [.latin]
          && ArisScript.writing("ko-KR") == [.hangul], "voice-6: each language's scripts, by any spelling of its code")
}

// MARK: - voice-8: ElevenLabs drops out mid-answer

private func voiceFallbackTests() {
    typealias Fallback = ArisVoiceFallback
    check(Fallback.afterFailure(attempt: 1, playedOfSentence: false, playedAnything: false, lastSentenceBroke: false) == .systemVoice,
          "voice-8: nothing has played yet -> the system voice at once (as before)")
    check(Fallback.afterFailure(attempt: 1, playedOfSentence: false, playedAnything: true, lastSentenceBroke: false) == .retry,
          "voice-8: one dropped request mid-answer -> asked for once more (as before)")
    check(Fallback.afterFailure(attempt: 2, playedOfSentence: false, playedAnything: true, lastSentenceBroke: false) == .systemVoice,
          "voice-8: a sentence that failed twice -> the system voice reads it and the rest; nothing is skipped in silence")
    check(Fallback.afterFailure(attempt: 1, playedOfSentence: true, playedAnything: true, lastSentenceBroke: false) == .skipSentence,
          "voice-8: a sentence that broke off part-way is not repeated")
    check(Fallback.afterFailure(attempt: 1, playedOfSentence: false, playedAnything: true, lastSentenceBroke: true) == .systemVoice,
          "voice-8: after a sentence broke off, the next one failing means the connection is down: no second wait")

    // A whole answer with the network gone after the second sentence: who reads what.
    var read: [String] = []
    var lastBroke = false
    var handedOver = false
    let answer = ["첫 문장.", "둘째 문장.", "셋째 문장.", "넷째 문장."]
    sentences: for (index, sentence) in answer.enumerated() {
        if handedOver {
            read.append("system:" + sentence)
            continue
        }
        for attempt in 1...2 {
            let works = index < 2
            if works {
                read.append("cloud:" + sentence)
                lastBroke = false
                continue sentences
            }
            switch Fallback.afterFailure(attempt: attempt, playedOfSentence: false, playedAnything: index > 0, lastSentenceBroke: lastBroke) {
            case .retry: continue
            case .skipSentence:
                lastBroke = true
                continue sentences
            case .systemVoice:
                handedOver = true
                read.append("system:" + sentence)
                continue sentences
            }
        }
    }
    check(read == ["cloud:첫 문장.", "cloud:둘째 문장.", "system:셋째 문장.", "system:넷째 문장."],
          "voice-8: every sentence of the answer is read, the rest by the system voice")
}

// MARK: - voice-imp-4: ElevenLabs failing

private func cloudBreakerTests() {
    let start = ContinuousClock.now
    var breaker = ArisCloudBreaker()
    check(breaker.mayTry(at: start), "voice-imp-4: ElevenLabs is asked while nothing has gone wrong")
    breaker.failed(at: start)
    check(breaker.mayTry(at: start + .seconds(1)), "voice-imp-4: one failure is a hiccup: asked again")
    breaker.failed(at: start + .seconds(1))
    check(!breaker.mayTry(at: start + .seconds(2)) && !breaker.mayTry(at: start + .seconds(100)),
          "voice-imp-4: two failures in a row -> the Mac's own voice and recognisers at once, for a few minutes")
    check(breaker.mayTry(at: start + .seconds(1) + ArisCloudBreaker.firstPause), "voice-imp-4: after two minutes ElevenLabs gets one try")
    breaker.failed(at: start + .seconds(130))
    check(!breaker.mayTry(at: start + .seconds(130 + 239)) && breaker.mayTry(at: start + .seconds(130 + 240)),
          "voice-imp-4: a try that fails again doubles the pause")
    for step in 0..<6 { breaker.failed(at: start + .seconds(1000 + step)) }
    check(breaker.mayTry(at: start + .seconds(1005) + ArisCloudBreaker.longestPause), "voice-imp-4: the pause is never longer than ten minutes")
    breaker.succeeded()
    check(breaker.mayTry(at: start + .seconds(1006)) && breaker.failures == 0, "voice-imp-4: one success and it is trusted again")
    breaker.failed(at: start + .seconds(1007))
    breaker.succeeded()
    breaker.failed(at: start + .seconds(1008))
    check(breaker.mayTry(at: start + .seconds(1009)), "voice-imp-4: failures with a success between them never open it")
    check(ArisCloudBreaker.counts(status: nil) && [401, 402, 429, 500, 503].allSatisfy { ArisCloudBreaker.counts(status: $0) },
          "voice-imp-4: no answer, a refused key, no credit, too many requests and server errors count against ElevenLabs")
    check(![400, 404, 422].contains { ArisCloudBreaker.counts(status: $0) },
          "voice-imp-4: a request turned down for its own words or voice says nothing about the next one")
    check(ArisElevenLabs.Failure(message: "ElevenLabs didn't answer").status == nil && ArisElevenLabs.Failure(message: "x", status: 401).status == 401,
          "voice-imp-4: an ElevenLabs failure carries the status it was answered with, if any")
}

// MARK: - voice-imp-1: the system voice, sentence by sentence

private func answerVoiceTests() {
    var korean = ArisAnswerVoice()
    let first = korean.language(for: "확인해 볼게요.", among: ["ko", "en"])
    let aside = korean.language(for: "OK.", among: ["ko", "en"])
    check(first == "ko-KR" && aside == "ko-KR", "voice-imp-1: a Korean answer keeps its Korean voice through an all-English sentence")
    var english = ArisAnswerVoice()
    check(english.language(for: "One moment.", among: ["ko", "en"]) == "en-US", "voice-imp-1: an English answer is read by an English voice")
}

@MainActor
private func sentenceReaderTests() async {
    func settle() async { for _ in 0..<20 { await Task.yield() } }

    // voice-imp-1: each sentence is said when it arrives, not when the answer is complete.
    var said: [String] = []
    let (stream, feed) = AsyncStream.makeStream(of: String.self)
    let reading = Task { @MainActor in
        await ArisSentenceReader.read(then: stream, isCurrent: { true }) { said.append($0) }
    }
    feed.yield("확인해 볼게요.")
    await settle()
    check(said == ["확인해 볼게요."], "voice-imp-1: the first sentence is said while the answer is still being written")
    feed.yield("내일은 맑아요.")
    await settle()
    check(said == ["확인해 볼게요.", "내일은 맑아요."], "voice-imp-1: ... and each next one as it arrives, in order")
    feed.finish()
    await reading.value
    check(said.count == 2, "voice-imp-1: the reading ends with the answer")

    // voice-3: stopped while the answer was still being written; the turn then closes the stream.
    var late: [String] = []
    var current = true
    let (stopped, stoppedFeed) = AsyncStream.makeStream(of: String.self)
    let abandoned = Task { @MainActor in
        await ArisSentenceReader.read(then: stopped, isCurrent: { current }) { late.append($0) }
    }
    stoppedFeed.yield("확인해 볼게요.")
    await settle()
    current = false // speaker.stop(): the pill was clicked, or a new turn began
    stoppedFeed.yield("이건 버려진 답이에요.")
    stoppedFeed.finish()
    await abandoned.value
    check(late == ["확인해 볼게요."], "voice-3: after a stop nothing of the abandoned answer is said, however much of it arrives")

    var never: [String] = []
    let (unheard, unheardFeed) = AsyncStream.makeStream(of: String.self)
    unheardFeed.yield("확인해 볼게요.")
    unheardFeed.finish()
    await ArisSentenceReader.read(first: ["먼저."], then: unheard, isCurrent: { false }) { never.append($0) }
    check(never.isEmpty, "voice-3: a reading that was stopped before its first word says nothing at all")

    // voice-8: the system voice picks the answer up where ElevenLabs left it.
    let (answer, answerFeed) = AsyncStream.makeStream(of: String.self)
    ["하나.", "둘.", "셋.", "넷."].forEach { answerFeed.yield($0) }
    var cloud: [String] = []
    let cloudVoice = Task { @MainActor in
        for await sentence in answer {
            if sentence == "둘." { break } // ElevenLabs gave up on this one
            cloud.append(sentence)
        }
    }
    await cloudVoice.value
    var system: [String] = []
    answerFeed.yield("다섯.")
    answerFeed.finish()
    await ArisSentenceReader.read(first: ["둘."], then: answer, isCurrent: { true }) { system.append($0) }
    check(cloud == ["하나."] && system == ["둘.", "셋.", "넷.", "다섯."],
          "voice-8: the sentence ElevenLabs gave up on and every one after it are read by the next voice, none twice")
}

// MARK: - The wiring, in files the tests can't compile

private func voiceWiringTests() {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private/Aris").standardized
    func source(_ name: String) -> String { (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    func part(_ text: String, from start: String, to end: String) -> String {
        guard let from = text.range(of: start), let to = text.range(of: end, range: from.upperBound..<text.endIndex) else { return "" }
        return String(text[from.lowerBound..<to.lowerBound])
    }
    let controller = source("ArisController.swift")
    let interrupted = part(controller, from: "listener.onInterrupted = {", to: "/// Hands-free: send what you said")
    let dictationAt = interrupted.range(of: "if self.dictation == .listening { return self.dictationInterrupted() }")?.lowerBound
    let turnAt = interrupted.range(of: "self.stopListening()")?.lowerBound
    check(dictationAt != nil && turnAt != nil && dictationAt! < turnAt!,
          "voice-1: the microphone-changed handler asks about dictation before it ends the turn with the words")
    let handsFree = part(controller, from: "func listenHandsFree()", to: "func stopListening()")
    let capAt = handsFree.range(of: "ArisTalkKey.mustEnd(")?.lowerBound, graceAt = handsFree.range(of: "heldUpByGrace(")?.lowerBound
    check(capAt != nil && graceAt != nil && capAt! < graceAt!, "voice-4: the cap and give-up are checked before the grace moment")
    let stop = part(controller, from: "func stopListening()", to: "func secondListen(")
    check(stop.contains("listener.secondListenSamples") && !stop.contains("listener.recordedSamples"),
          "voice-5: a turn's second listen takes the recording only when it holds the whole turn")
    check(controller.contains("static var locale: Locale { ArisHearing.locale }") && !controller.contains("Locale(identifier: \"ko-KR\")"),
          "voice-6: the recogniser's language is no longer fixed to Korean")
    check(controller.contains("languages: Defaults[.arisLanguages], recognizer: Self.locale.identifier"),
          "voice-6: the transcript is picked knowing the languages turned on and the recogniser's")

    let dictation = source("ArisController+Dictation.swift")
    let finish = part(dictation, from: "func finishDictation()", to: "func dictationInterrupted()")
    check(finish.contains("ArisDictationEnd.saidSomething(heardVoice: lastVoiceAt != nil, wroteWords: lastWordsAt != nil)"),
          "voice-10: a dictation is typed when either voice or words were heard")
    let interruptedDictation = part(dictation, from: "func dictationInterrupted()", to: "private func lingerAfterDictation")
    check(interruptedDictation.contains("finishDictation()") && !interruptedDictation.contains("stopListening()") && !interruptedDictation.contains("answer("),
          "voice-1: an interrupted dictation is finished as a dictation, never answered")
    let start = part(dictation, from: "func startDictation()", to: "func lockDictation()")
    check(start.contains("ArisDictationState.shared.refuse(why)") && start.contains("case .interrupt:"),
          "voice-9: a press Aris can't take says why, and one over its voice stops it")

    let listener = source("ArisListener.swift")
    let listenerStart = part(listener, from: "func start(locale: Locale", to: "static func prepareSpeechAssets")
    check(listenerStart.contains("waiting = handOver.startsWaiting(asked: waitingForWakeWord)") && listenerStart.contains("recording.reset(rolling: waiting)"),
          "voice-2: start() keeps a listener that already began its turn out of the waiting state")
    check(part(listener, from: "func beginTurn()", to: "func stop() async").contains("handOver.beginTurn()"), "voice-2: beginTurn() is remembered")

    let wake = source("ArisController+Wake.swift")
    let check7 = part(wake, from: "func checkWakeWord(", to: "func stopWaitingForWakeWord()")
    check(check7.contains("ArisWakeStartFailure.after(isTurnListener: self.listener === listener, isWakeListener: self.wakeListener === listener)"),
          "voice-7: a recogniser that can't start is acted on, not only logged")
    let detector = part(wake, from: "func startDetector(", to: "// MARK: - Interrupting")
    check(detector.contains("ArisAudioQuiet.wakeRestarts(afterFailedOpen: Self.wakeRestarts)") && detector.contains("restartDetectorSoon(after:"),
          "voice-11: a wake microphone that couldn't open is tried again")
    check(part(wake, from: "func wake(_ listener: ArisListener", to: "listenHandsFree()\n    }").contains("ArisWakeHandOver.lead("),
          "voice-2: the recording's lead is taken again once the recogniser has started")

    let countdown = source("ArisController+Countdown.swift")
    let countdownCatch = part(countdown, from: "countdown: couldn't listen", to: "countdownStarted = Date()")
    check(countdownCatch.contains("await listener.stop()") && countdownCatch.contains("level = 0"),
          "voice-12: a countdown that couldn't listen closes its listener before it asks with the buttons")

    let speaker = source("ArisSpeaker.swift")
    let streamed = part(speaker, from: "func speak(sentences: AsyncStream<String>) async", to: "func duck()")
    check(streamed.contains("guard let key = Self.cloudKey() else { return await speakWithSystemVoice(then: sentences, of: mine) }"),
          "voice-3, voice-imp-1: without ElevenLabs the answer goes to the sentence reader, bound to this speak()")
    check(streamed.contains("ArisVoiceFallback.afterFailure(") && streamed.contains("speakWithSystemVoice(first: failed, then: voices, of: mine)"),
          "voice-8: a sentence ElevenLabs gives up on is handed, with the rest, to the system voice")
    check(speaker.contains("isCurrent: { mine == self.generation && !Task.isCancelled }"),
          "voice-3: the system voice reads on only while its speak() is the current one")
    check(speaker.contains("ArisCloudHealth.voice.mayTry(at: .now)") && source("ArisController+Scribe.swift").contains("ArisCloudHealth.listening.mayTry(at: .now)"),
          "voice-imp-4: the voice and the listening both ask whether ElevenLabs may be tried now")
    check(source("ArisWhisper.swift").contains("ArisLongTurn.windows(of: samples, sampleRate: Self.sampleRate)"),
          "voice-imp-3: Whisper reads a long turn window by window")
}
