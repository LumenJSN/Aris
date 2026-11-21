import XCTest
@testable import ArisCore

/// jv-hearing: the endpoint policy (table), the driver's event sequences, the speculative turn with a fake helper, the
/// second listen's budget and the stage clock.
final class ArisEndpointPolicyTests: XCTestCase {
    private func ms(_ value: Int) -> Duration { .milliseconds(value) }

    private func decide(voice: Int?, words: Int? = 300, score: Float?, complete: Bool, hanging: Bool = false, start: Int = 4000) -> ArisEndpointDecision {
        ArisEndpointPolicy.decide(ArisEndpointInput(sinceStart: ms(start), sinceVoice: voice.map(ms), sinceWords: words.map(ms), score: score,
                                                    complete: complete, hanging: hanging)).decision
    }

    func testEveryCaseSpeculatesThenCommitsAtItsThresholds() {
        let table: [(ArisEndpointCase, Float?, Bool, Bool, Int, Int)] = [
            (.confident, 0.9, true, false, 250, 500),
            (.finishedVoice, 0.9, false, false, 800, 2000),
            (.unsure, 0.5, true, false, 1400, 2000),
            (.midThought, 0.1, false, false, 3000, 3600),
            (.midThoughtWordsFinished, 0.1, true, false, 2000, 2600),
            (.hanging, 0.9, true, true, 3000, 3600),
            (.noScoreComplete, nil, true, false, 900, 1500),
            (.noScore, nil, false, false, 1400, 2000),
        ]
        for (endCase, score, complete, hanging, plausible, firm) in table {
            XCTAssertEqual(ArisEndpointPolicy.endCase(score: score, complete: complete, hanging: hanging), endCase)
            XCTAssertEqual(decide(voice: plausible - 10, score: score, complete: complete, hanging: hanging), .keepListening, "\(endCase)")
            XCTAssertEqual(decide(voice: plausible, score: score, complete: complete, hanging: hanging), .plausibleEnd, "\(endCase)")
            XCTAssertEqual(decide(voice: firm - 10, score: score, complete: complete, hanging: hanging), .plausibleEnd, "\(endCase)")
            XCTAssertEqual(decide(voice: firm, score: score, complete: complete, hanging: hanging), .firmEnd, "\(endCase)")
            let row = ArisEndpointPolicy.row(endCase)
            // Nobody is cut off sooner than before: every firm end is at or after the old one.
            XCTAssertGreaterThanOrEqual(row.firm.voice, row.before, "\(endCase)")
        }
        XCTAssertLessThan(ArisEndpointPolicy.row(.confident).plausible.voice, ArisEndpointPolicy.row(.confident).before)
    }

    func testTheCapsComeFirstAndNoWordsWaits() {
        XCTAssertEqual(decide(voice: 0, words: 0, score: 0.1, complete: false, start: 180_000), .firmEnd)
        XCTAssertEqual(decide(voice: 0, words: nil, score: nil, complete: false, start: 15_000), .firmEnd)
        XCTAssertEqual(decide(voice: 100, words: nil, score: nil, complete: false, start: 7000), .keepListening)
        XCTAssertEqual(decide(voice: 100, words: nil, score: nil, complete: false, start: 8000), .plausibleEnd)
        XCTAssertEqual(decide(voice: 600, words: nil, score: nil, complete: false, start: 8000), .firmEnd)
        XCTAssertEqual(decide(voice: 100, words: 3000, score: nil, complete: false), .firmEnd, "a loud room still ends on the words clock")
    }

    func testTheTimerLooksAgainWhenTheNextThresholdIsDue() {
        XCTAssertEqual(ArisEndpointPolicy.untilChange(ArisEndpointInput(sinceStart: ms(4000), sinceVoice: ms(100), sinceWords: ms(100), score: 0.9, complete: true)), ms(150))
    }
}

final class ArisEndpointDriverTests: XCTestCase {
    private func ms(_ value: Int) -> Duration { .milliseconds(value) }
    private typealias S = ArisEndpointDriver.Snapshot

    private func quiet(_ driver: inout ArisEndpointDriver, _ from: Int, _ to: Int, voice: Int, score: Float?, complete: Bool) -> [ArisEndpointDriver.Effect] {
        stride(from: from, through: to, by: 43).flatMap {
            driver.observe(S(now: ms($0), lastVoice: ms(voice), lastWords: ms(voice - 100), score: score, complete: complete))
        }
    }

    func testAConfidentPauseSpeculatesThenCommits() {
        var driver = ArisEndpointDriver()
        XCTAssertEqual(quiet(&driver, 3000, 3600, voice: 3000, score: 0.9, complete: true), [.speculate(id: 1), .commit(id: 1)])
    }

    func testVoiceInTheWindowCancelsAndAClickDoesNot() {
        var driver = ArisEndpointDriver()
        XCTAssertEqual(quiet(&driver, 3000, 4500, voice: 3000, score: 0.5, complete: false), [.speculate(id: 1)])
        XCTAssertEqual(driver.observe(S(now: ms(4550), voiceNow: true, lastVoice: ms(4550))), [])
        let resumed = [4600, 4643, 4686].flatMap { driver.observe(S(now: ms($0), voiceNow: true, lastVoice: ms($0))) }
        XCTAssertEqual(resumed, [.cancel(id: 1)])
        XCTAssertEqual(driver.phase, .listening)
        XCTAssertEqual(quiet(&driver, 6000, 6600, voice: 6000, score: 0.9, complete: true), [.speculate(id: 2), .commit(id: 2)])
    }

    func testAStepCommitsAtOnceAndCannotBeCancelled() {
        var driver = ArisEndpointDriver()
        _ = quiet(&driver, 3000, 3260, voice: 3000, score: 0.9, complete: true)
        XCTAssertEqual(driver.reply(.output, id: 1), [])
        XCTAssertEqual(driver.reply(.action, id: 1), [.commit(id: 1)])
        XCTAssertEqual(driver.observe(S(now: ms(3300), voiceNow: true, lastVoice: ms(3300))), [])
    }
}

@MainActor
final class ArisSpeculativeTurnTests: XCTestCase {
    private func ms(_ value: Int) -> Duration { .milliseconds(value) }

    func testResumedSpeechCancelsTheRequestAndTheTurnTakesTheNextOne() async throws {
        var asked: [String] = [], commits: [Int?] = [], terminated = 0
        var feeds: [AsyncStream<String>.Continuation] = []
        var words = "내일 날씨"
        let turn = ArisSpeculativeTurn<String, String>(hooks: .init(
            finalWords: { _ in words },
            requestKey: { "brain:\($0)" },
            ask: { words, _ in
                asked.append(words)
                let (stream, feed) = AsyncStream.makeStream(of: String.self)
                feed.onTermination = { reason in if case .cancelled = reason { Task { @MainActor in terminated += 1 } } }
                feeds.append(feed)
                return stream
            },
            kind: { $0.hasPrefix("delta:") ? .output : .inert },
            commit: { commits.append($0) }))
        func pause(_ from: Int, _ to: Int, voice: Int) async throws {
            for now in stride(from: from, through: to, by: 43) {
                turn.observe(.init(now: ms(now), lastVoice: ms(voice), lastWords: ms(voice - 100), score: 0.9, complete: true))
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await pause(3000, 3260, voice: 3000)
        XCTAssertEqual(asked, ["내일 날씨"])
        for now in [3280, 3323, 3366, 3409] { turn.observe(.init(now: ms(now), voiceNow: true, lastVoice: ms(now))) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(turn.requestsCancelled, 1)
        XCTAssertEqual(terminated, 1)
        words = "내일 날씨 알려주고 우산도"
        try await pause(5000, 5600, voice: 5000)
        XCTAssertEqual(commits, [2])
        let committed = await turn.committedWords()
        XCTAssertEqual(committed, "내일 날씨 알려주고 우산도")
        feeds[1].yield("delta:비")
        feeds[1].finish()
        var replies: [String] = []
        if let held = turn.takeRequest(for: "brain:\(committed ?? "")") { for await reply in held { replies.append(reply) } }
        XCTAssertEqual(replies, ["delta:비"])
        XCTAssertEqual(asked.count, 2)
    }

    func testALateSecondListenGoesToLate() async throws {
        var late: [String] = []
        let quick = await ArisSecondPass.within(.milliseconds(300)) { "scribe" }
        XCTAssertEqual(quick, "scribe")
        let slow = await ArisSecondPass.within(.milliseconds(30), {
            try? await Task.sleep(for: .milliseconds(150))
            return "whisper"
        }, late: { late.append($0) })
        XCTAssertNil(slow)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(late, ["whisper"])
    }
}

final class ArisLateWordsAndClockTests: XCTestCase {
    func testLateWordsReplaceOnlyBeforeTheRequestIsSent() {
        var before = ArisLateWords()
        before.wentOn(with: "내일 날시")
        XCTAssertTrue(before.arrived("내일 날씨"))
        XCTAssertEqual(before.send("내일 날시"), "내일 날씨")
        var after = ArisLateWords()
        after.wentOn(with: "내일 날시")
        XCTAssertEqual(after.send("내일 날시"), "내일 날시")
        XCTAssertFalse(after.arrived("내일 날씨"))
    }

    func testTheClockGivesTheTargetsGaps() {
        var clock = ArisStageClock()
        let start = ContinuousClock.now
        clock.begin(at: start)
        clock.mark(.voiceEnd, at: start.advanced(by: .milliseconds(2000)))
        clock.mark(.requestSent, at: start.advanced(by: .milliseconds(2300)))
        clock.mark(.firstAudio, at: start.advanced(by: .milliseconds(3100)))
        XCTAssertEqual(clock.fields()["speechEndToRequestMs"], 300)
        XCTAssertEqual(clock.fields()["speechEndToAudioMs"], 1100)
    }

    func testTheGateLetsOnlyPlainQuestionsGoEarly() {
        XCTAssertNil(ArisSpeculationGate.block(.init(words: "내일 날씨 알려줘", plainBrainPath: true)))
        XCTAssertEqual(ArisSpeculationGate.block(.init(words: "이거 기억해 줘", plainBrainPath: true)), .helperWords)
        XCTAssertEqual(ArisSpeculationGate.block(.init(words: "타이머 5분", plainBrainPath: false)), .notPlain)
    }
}
