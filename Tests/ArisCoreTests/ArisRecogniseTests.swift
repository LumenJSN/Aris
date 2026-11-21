import XCTest
@testable import ArisCore

/// jv-stt: who hears a turn and in what order, the hint list, and each cloud engine's request and replies (from
/// messages shaped as the vendors' docs give them).
final class ArisHearPlanTests: XCTestCase {
    func testStoredChoiceAndWhatNothingStoredMeans() {
        XCTAssertEqual(ArisHearEngine.chosen(stored: "soniox", cloudSwitch: nil), .soniox)
        XCTAssertEqual(ArisHearEngine.chosen(stored: "openai-stt", cloudSwitch: false), .openai)
        XCTAssertEqual(ArisHearEngine.chosen(stored: nil, cloudSwitch: nil), .auto)
        XCTAssertEqual(ArisHearEngine.chosen(stored: nil, cloudSwitch: true), .auto)
        XCTAssertEqual(ArisHearEngine.chosen(stored: "deepgram", cloudSwitch: nil), .auto, "an id this build can't use reads as Automatic")
        XCTAssertEqual(ArisHearEngine.chosen(stored: nil, cloudSwitch: false), .whisper, "the old Scribe switch turned off keeps hearing on the Mac")
    }

    func testAutomaticTriesEveryCloudEngineWithAKeyInOrder() {
        let all = ArisHearPlan.make(choice: .auto, keys: [.openai, .scribe, .soniox])
        XCTAssertEqual(all.cloud, [.scribe, .soniox, .openai])
        XCTAssertEqual(all.live, .scribe)
        XCTAssertTrue(all.whisper)
        XCTAssertTrue(all.notes.isEmpty)
        XCTAssertEqual(all.after(.scribe), [.soniox, .openai])
        XCTAssertEqual(all.after(.openai), [])
        XCTAssertEqual(all.after(nil), [.scribe, .soniox, .openai])

        let none = ArisHearPlan.make(choice: .auto, keys: [])
        XCTAssertEqual(none.cloud, [])
        XCTAssertNil(none.live)
        XCTAssertTrue(none.notes.isEmpty, "Automatic skips what isn't set up without a word")

        let onlyOpenAI = ArisHearPlan.make(choice: .auto, keys: [.openai])
        XCTAssertEqual(onlyOpenAI.cloud, [.openai])
        XCTAssertNil(onlyOpenAI.live, "OpenAI reads the recording afterwards: nothing streams")
    }

    func testAChosenEngineWithoutItsKeyIsSaidAndTheMacListens() {
        let plan = ArisHearPlan.make(choice: .soniox, keys: [.scribe])
        XCTAssertEqual(plan.cloud, [], "another engine's key is never used in its place")
        XCTAssertTrue(plan.whisper)
        XCTAssertEqual(plan.notes.count, 1)
        XCTAssertTrue(plan.notes[0].contains("Soniox") && plan.notes[0].contains("no key"))
    }

    func testARestingEngineIsSkippedAndSaid() {
        let plan = ArisHearPlan.make(choice: .auto, keys: [.scribe, .soniox], resting: [.scribe])
        XCTAssertEqual(plan.cloud, [.soniox])
        XCTAssertEqual(plan.live, .soniox)
        XCTAssertTrue(plan.notes.contains { $0.contains("ElevenLabs Scribe") && $0.contains("resting") })
    }

    func testOnThisMacChoices() {
        let whisper = ArisHearPlan.make(choice: .whisper, keys: [.scribe, .soniox, .openai])
        XCTAssertEqual(whisper.cloud, [])
        XCTAssertTrue(whisper.whisper)
        let apple = ArisHearPlan.make(choice: .apple, keys: [.scribe])
        XCTAssertEqual(apple.cloud, [])
        XCTAssertFalse(apple.whisper)
    }

    func testFallbacksShareOneShortLimit() {
        XCTAssertEqual(ArisHearPlan.fallbackTime(spent: .zero), ArisHearPlan.fallbackBudget)
        XCTAssertEqual(ArisHearPlan.fallbackTime(spent: .milliseconds(2500)), .milliseconds(1500))
        XCTAssertNil(ArisHearPlan.fallbackTime(spent: .milliseconds(3800)), "too little left to be worth a request")
        XCTAssertNil(ArisHearPlan.fallbackTime(spent: .seconds(5)))
    }

    func testKeyNames() {
        XCTAssertEqual(ArisHearEngine.cloud.map(\.keyName), ["elevenlabs-key", "soniox-key", "openai-key"])
        XCTAssertNil(ArisHearEngine.whisper.keyName)
    }
}

final class ArisHearHintsTests: XCTestCase {
    func testOrderOnceEachAndBounded() {
        let sources = ArisHearHints.Sources(owner: "민준", words: ["Notion", "노션", "aris"], lessons: ["출근 준비"],
                                            runningApps: ["Xcode", "notion"], installedApps: ["Safari", "Xcode", "Figma"])
        XCTAssertEqual(ArisHearHints.build(sources, bounds: .init(count: 50, length: 20)),
                       ["Aris", "아리스", "민준", "Notion", "노션", "출근 준비", "Xcode", "Safari", "Figma"])
        XCTAssertEqual(ArisHearHints.build(sources, bounds: .init(count: 4, length: 20)), ["Aris", "아리스", "민준", "Notion"])
    }

    func testATermTooLongOrEmptyIsLeftOutNeverCut() {
        let sources = ArisHearHints.Sources(assistant: [], words: ["  ", "가나다라마바사아자차카타파하가나다라마바사아자", "Visual   Studio Code", "…", "line\nbreak"])
        XCTAssertEqual(ArisHearHints.build(sources, bounds: .scribe), ["Visual Studio Code"])
        XCTAssertEqual(ArisHearHints.Bounds.scribe, .init(count: 50, length: 20))
    }

    func testManyAppsNeverPushOutTheOwnersWords() {
        let apps = (1...300).map { "App \($0)" }
        let hints = ArisHearHints.build(.init(words: ["깃허브", "Vercel"], installedApps: apps), bounds: .scribe)
        XCTAssertEqual(hints.count, 50)
        XCTAssertEqual(Array(hints.prefix(4)), ["Aris", "아리스", "깃허브", "Vercel"])
    }

    func testLessonNamesAreReadWithoutTheirSteps() {
        let json = #"[{"id":"1","name":"출근 준비","steps":[{"words":["Secret label"]}]},{"name":"주간 보고"},{"steps":[]},"junk"]"#
        XCTAssertEqual(ArisHearHints.lessonNames(in: Data(json.utf8)), ["출근 준비", "주간 보고"])
        XCTAssertEqual(ArisHearHints.lessonNames(in: Data("not json".utf8)), [])
        XCTAssertEqual(ArisHearHints.lessonNames(in: nil), [])
    }
}

final class ArisScribeWireTests: XCTestCase {
    private func value(_ items: [URLQueryItem], _ name: String) -> [String] { items.filter { $0.name == name }.compactMap(\.value) }

    func testSeveralLanguagesAreHeardEachInItsOwnScript() {
        let items = ArisScribeWire.query(languages: ["ko", "en"], keyterms: ["Aris", "Notion"], sampleRate: 16_000)
        XCTAssertEqual(value(items, "model_id"), ["scribe_v3_live"])
        XCTAssertEqual(value(items, "audio_format"), ["pcm_16000"])
        XCTAssertEqual(value(items, "commit_strategy"), ["manual"])
        XCTAssertEqual(value(items, "language_code"), ["ko"])
        XCTAssertEqual(value(items, "secondary_languages"), ["en"])
        XCTAssertEqual(value(items, "multilang_mode"), ["true"])
        XCTAssertEqual(value(items, "keyterms"), ["Aris", "Notion"])
        XCTAssertEqual(value(items, "include_language_detection"), ["true"])
    }

    func testOneLanguageIsNotMultilingualAndNoLanguageIsLeftToScribe() {
        let one = ArisScribeWire.query(languages: ["en"], keyterms: [], sampleRate: 16_000)
        XCTAssertEqual(value(one, "language_code"), ["en"])
        XCTAssertTrue(value(one, "multilang_mode").isEmpty && value(one, "secondary_languages").isEmpty && value(one, "keyterms").isEmpty)
        let none = ArisScribeWire.query(languages: [], keyterms: [], sampleRate: 16_000)
        XCTAssertTrue(value(none, "language_code").isEmpty)
        XCTAssertEqual(value(none, "multilang_mode"), ["true"], "no language chosen: Scribe works it out, each in its own script")
    }

    func testKeytermsAreKeptWithinWhatRealtimeTakes() {
        let many = (1...80).map { "term\($0)" } + ["this keyterm is far too long for scribe"]
        let sent = value(ArisScribeWire.query(languages: ["ko"], keyterms: ["this keyterm is far too long for scribe"] + many, sampleRate: 16_000), "keyterms")
        XCTAssertEqual(sent.count, 50)
        XCTAssertTrue(sent.allSatisfy { $0.count <= 20 })
    }

    func testMessages() {
        XCTAssertEqual(ArisScribeWire.event(#"{"message_type":"session_started","session_id":"s1"}"#), .started)
        XCTAssertEqual(ArisScribeWire.event(#"{"message_type":"partial_transcript","text":"깃허브에 push"}"#), .partial("깃허브에 push"))
        XCTAssertEqual(ArisScribeWire.event(#"{"message_type":"committed_transcript","text":"GitHub에 push 해줘"}"#), .committed("GitHub에 push 해줘"))
        XCTAssertEqual(ArisScribeWire.event(#"{"message_type":"committed_transcript_with_timestamps","text":"x","language_code":"kor","words":[]}"#),
                       .timestamps(language: "kor"))
        XCTAssertEqual(ArisScribeWire.event(#"{"message_type":"committed_transcript_with_timestamps","text":"x","language_code":""}"#), .timestamps(language: nil))
        XCTAssertEqual(ArisScribeWire.event(#"{"message_type":"commit_throttled","error":"wait"}"#), .throttled)
        XCTAssertEqual(ArisScribeWire.event(#"{"message_type":"auth_error","error":"bad key"}"#), .failed("auth_error"))
        XCTAssertEqual(ArisScribeWire.event(#"{"message_type":"invalid_request","error":"keyterms: too long"}"#), .failed("invalid_request"))
        XCTAssertEqual(ArisScribeWire.event(#"{"message_type":"diarized_transcript","words":[]}"#), .other)
        XCTAssertNil(ArisScribeWire.event("not json"))
    }
}

final class ArisSonioxWireTests: XCTestCase {
    func testStartRequestCarriesNoKeyAndTakesBothLanguages() throws {
        let start = ArisSonioxWire.start(languages: ["ko", "en"], terms: ["Aris", "Vercel"], sampleRate: 16_000)
        XCTAssertEqual(start["model"] as? String, "stt-rt-v6")
        XCTAssertEqual(start["audio_format"] as? String, "pcm_s16le")
        XCTAssertEqual(start["sample_rate"] as? Int, 16_000)
        XCTAssertEqual(start["num_channels"] as? Int, 1)
        XCTAssertEqual(start["language_hints"] as? [String], ["ko", "en"])
        XCTAssertEqual(start["enable_language_identification"] as? Bool, true)
        XCTAssertEqual((start["context"] as? [String: Any])?["terms"] as? [String], ["Aris", "Vercel"])
        XCTAssertNil(start["api_key"], "the key goes with the connection (Authorization), never in the start message")
        XCTAssertNil(start["language_hints_strict"], "hints, not a restriction: another language is still heard")
        XCTAssertNil(ArisSonioxWire.start(languages: [], terms: [], sampleRate: 16_000)["context"])
        XCTAssertNil(ArisSonioxWire.start(languages: [], terms: [], sampleRate: 16_000)["language_hints"])
    }

    func testTokensFoldIntoTheTurn() {
        var turn = ArisSonioxWire.Transcript()
        XCTAssertEqual(turn.take(#"{"tokens":[{"text":"깃","is_final":false,"language":"ko"}],"final_audio_proc_ms":0,"total_audio_proc_ms":200}"#), .words)
        XCTAssertEqual(turn.text, "깃")
        XCTAssertEqual(turn.take(#"{"tokens":[{"text":"GitHub","is_final":true,"language":"en"},{"text":"에","is_final":true,"language":"ko"},{"text":" pu","is_final":false,"language":"en"}]}"#), .words)
        XCTAssertEqual(turn.text, "GitHub에 pu", "final tokens are kept, the non-final tail is replaced each time")
        XCTAssertEqual(turn.take(#"{"tokens":[{"text":" push","is_final":true,"language":"en"},{"text":" 해","is_final":true,"language":"ko"},{"text":"줘","is_final":true,"language":"ko"},{"text":"<end>","is_final":true}]}"#), .words)
        XCTAssertEqual(turn.text, "GitHub에 push 해줘")
        XCTAssertEqual(turn.language, "ko", "the language most of it was in")
        XCTAssertEqual(turn.take(#"{"tokens":[],"final_audio_proc_ms":1560,"total_audio_proc_ms":1680,"finished":true}"#), .finished)
        XCTAssertEqual(turn.text, "GitHub에 push 해줘")
    }

    func testAnErrorNamesItsTypeOnlyAndMarkersAreNotWords() {
        var turn = ArisSonioxWire.Transcript()
        XCTAssertEqual(turn.take(#"{"tokens":[],"error_code":401,"error_type":"unauthenticated","error_message":"Incorrect API key provided.","request_id":"r"}"#),
                       .failed("unauthenticated (401)"))
        XCTAssertEqual(turn.take("junk"), .ignored)
        XCTAssertEqual(turn.take(#"{"tokens":[{"text":"<fin>","is_final":true},{"text":"안녕","is_final":true,"translation_status":"translation"}]}"#), .words)
        XCTAssertEqual(turn.text, "")
    }
}

final class ArisOpenAITranscribeWireTests: XCTestCase {
    func testWavIsSixteenBitMono() {
        let wav = ArisOpenAITranscribeWire.wav([0, 1, -1], sampleRate: 16_000)
        XCTAssertEqual(wav.count, 44 + 6)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<16], as: UTF8.self), "WAVEfmt ")
        XCTAssertEqual(Array(wav[22..<28]), [1, 0, 0x80, 0x3E, 0, 0], "one channel, 16000 Hz")
        XCTAssertEqual(Array(wav.suffix(6)), [0, 0, 0xFF, 0x7F, 0x01, 0x80])
        XCTAssertEqual(ArisPCM16.data([0, 1, -1, 2]), Data([0, 0, 0xFF, 0x7F, 0x01, 0x80, 0xFF, 0x7F]))
    }

    func testTheFormNamesTheModelBothLanguagesAndTheKeywords() {
        let body = ArisOpenAITranscribeWire.body(wav: Data([1, 2, 3]), languages: ["ko", "en"], keywords: ["Aris", "깃허브"], boundary: "B")
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"model\"\r\n\r\ngpt-transcribe\r\n"))
        XCTAssertTrue(text.contains("name=\"languages[]\"\r\n\r\nko\r\n") && text.contains("name=\"languages[]\"\r\n\r\nen\r\n"))
        XCTAssertTrue(text.contains("name=\"keywords[]\"\r\n\r\nAris\r\n") && text.contains("name=\"keywords[]\"\r\n\r\n깃허브\r\n"))
        XCTAssertTrue(text.contains("name=\"file\"; filename=\"turn.wav\"\r\nContent-Type: audio/wav\r\n\r\n"))
        XCTAssertTrue(text.hasSuffix("--B--\r\n"))
        XCTAssertFalse(text.contains("name=\"language\"\r\n"), "no single language: both are possible")
    }

    func testReplies() {
        let ok = #"{"text":" GitHub에 push 해줘 ","languages":[{"code":"ko"},{"code":"en"}],"usage":{"type":"duration","seconds":3}}"#
        XCTAssertEqual(ArisOpenAITranscribeWire.heard(status: 200, data: Data(ok.utf8)), .success(ArisHeard(text: "GitHub에 push 해줘", language: "ko")))
        XCTAssertEqual(ArisOpenAITranscribeWire.heard(status: 200, data: Data(#"{"text":""}"#.utf8)), .success(ArisHeard(text: "", language: nil)))
        let refused = #"{"error":{"message":"Incorrect API key provided: sk-abc***xyz.","type":"invalid_request_error","code":"invalid_api_key"}}"#
        XCTAssertEqual(ArisOpenAITranscribeWire.heard(status: 401, data: Data(refused.utf8)), .failure(.init(note: "401 invalid_api_key")),
                       "the provider's message can quote the key: only its code is kept")
        XCTAssertEqual(ArisOpenAITranscribeWire.heard(status: 500, data: Data("oops".utf8)), .failure(.init(note: "500")))
        XCTAssertEqual(ArisOpenAITranscribeWire.heard(status: 200, data: Data("oops".utf8)), .failure(.init(note: "unreadable reply")))
    }
}

final class ArisHearScoreTests: XCTestCase {
    func testCharacterErrorRate() {
        XCTAssertEqual(ArisHearScore.cer(expected: "GitHub에 push 해줘", heard: "github에 push 해줘."), 0)
        XCTAssertEqual(ArisHearScore.cer(expected: "노션 열어줘", heard: "로션 열어줘"), 0.2, accuracy: 0.0001)
        XCTAssertEqual(ArisHearScore.cer(expected: "가나다", heard: ""), 1)
        XCTAssertEqual(ArisHearScore.cer(expected: "", heard: "뭐"), 1)
        XCTAssertEqual(ArisHearScore.cer(expected: "", heard: ""), 0)
        XCTAssertEqual(ArisHearScore.cer(expected: "ab", heard: "abcdef"), 2, "more wrong than there was to hear is over 100%")
    }
}

final class ArisTurnRecogniserTests: XCTestCase {
    private final class FakeLive: ArisLiveHearing, @unchecked Sendable {
        let engine = ArisHearEngine.soniox
        var onText: (@MainActor (String) -> Void)?
        var calls: [String] = []
        func start() { calls.append("start") }
        func append(_ samples: [Float]) { calls.append("append \(samples.count)") }
        func finish(timeout: Duration) async -> ArisHeard? { calls.append("finish"); return ArisHeard(text: "노션 열어줘", language: "ko") }
        func cancel() { calls.append("cancel") }
    }

    func testAStreamingEngineReadsARecordingAsOneSession() async {
        let live = FakeLive()
        let request = ArisHearRequest(languages: ["ko", "en"], hints: ["Aris"])
        let recogniser = ArisStreamedRecording(engine: .soniox) { asked in
            XCTAssertEqual(asked, request)
            return live
        }
        let heard = await recogniser.transcribe([0, 0, 0], request: request, timeout: .seconds(1))
        XCTAssertEqual(heard, ArisHeard(text: "노션 열어줘", language: "ko"))
        XCTAssertEqual(live.calls, ["start", "append 3", "finish"])
        let none = await ArisStreamedRecording(engine: .scribe) { _ in nil }.transcribe([0], request: request, timeout: .seconds(1))
        XCTAssertNil(none, "no key, no session: no answer, and the next engine reads it")
    }

    func testRepairIsOnWithAutomaticUntilTheOwnerSaysOtherwise() {
        XCTAssertTrue(ArisHearRepairSetting.isOn(stored: nil, choice: .auto))
        XCTAssertFalse(ArisHearRepairSetting.isOn(stored: nil, choice: .scribe))
        XCTAssertFalse(ArisHearRepairSetting.isOn(stored: nil, choice: .whisper))
        XCTAssertFalse(ArisHearRepairSetting.isOn(stored: false, choice: .auto))
        XCTAssertTrue(ArisHearRepairSetting.isOn(stored: true, choice: .soniox))
    }
}
