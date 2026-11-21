import XCTest
@testable import ArisCore

/// jv-fixapp: the countdown's one decision, the endpoint's look armed on every reading, and the cut-off note's turn.
final class ArisCountdownStepTests: XCTestCase {
    private typealias C = ArisCountdownStep
    private let silence = C.Words.silence
    private let yes = C.Words(answer: true, said: true)
    private let no = C.Words(answer: false, said: true)
    private let other = C.Words(answer: nil, said: true)

    /// As the controller asks it: before the microphone closes, then with the final words.
    private func ends(outcome: ArisCardOutcome? = nil, said: Bool? = nil, paused: Bool = false, final: C.Words,
                      current: Bool = true, currentAfter: Bool? = nil) -> C? {
        C.decide(outcome: outcome, said: said, paused: paused, final: nil, current: current)
            ?? C.decide(outcome: outcome, said: said, paused: paused, final: final, current: currentAfter ?? current)
    }

    func testSilenceToTheEndSends() {
        XCTAssertNil(C.decide(outcome: nil, said: nil, paused: false, final: nil, current: true))
        XCTAssertEqual(ends(final: silence), .send)
    }

    func testEveryRow() {
        let rows: [(ArisCardOutcome?, Bool?, Bool, C.Words, Bool, C)] = [
            (nil, nil, false, yes, true, .send),
            (nil, nil, false, no, true, .stop),
            (nil, nil, false, other, true, .pause),
            (nil, true, false, silence, true, .send),
            (nil, false, false, silence, true, .stop),
            (nil, nil, true, silence, true, .pause),
            (nil, nil, true, yes, true, .pause),
            (.answered(true), nil, false, silence, true, .send),
            (.answered(false), true, false, yes, true, .stop),
            (.answered(true), nil, false, silence, false, .send),
            (.covered, nil, false, silence, true, .covered),
            (.cancelled, true, false, yes, true, .turnEnded),
            (nil, true, false, yes, false, .turnEnded),
            (nil, nil, false, silence, false, .turnEnded),
        ]
        for (outcome, said, paused, final, current, step) in rows {
            XCTAssertEqual(ends(outcome: outcome, said: said, paused: paused, final: final, current: current), step,
                           "\(String(describing: outcome)) \(String(describing: said)) \(paused) \(final) \(current)")
        }
        XCTAssertEqual(ends(final: silence, currentAfter: false), .turnEnded)
    }

    func testOnlySendAndStopSettleTheCard() {
        XCTAssertEqual(C.send.sent, true)
        XCTAssertEqual(C.stop.sent, false)
        XCTAssertNil(C.pause.sent)
        XCTAssertNil(C.covered.sent)
        XCTAssertNil(C.turnEnded.sent)
    }
}

final class ArisEndpointStallTests: XCTestCase {
    private typealias S = ArisEndpointDriver.Snapshot
    private func ms(_ value: Int) -> Duration { .milliseconds(value) }

    /// Voice readings every 43 ms up to `stallAt`, then only the looks the driver arms; when it committed (ms).
    private func stalled(at stallAt: Int, words: Bool, score: Float?, complete: Bool) -> Int? {
        var driver = ArisEndpointDriver()
        var last = S(now: .zero)
        func committed(_ effects: [ArisEndpointDriver.Effect]) -> Bool {
            effects.contains { if case .commit = $0 { return true } else { return false } }
        }
        for now in stride(from: 0, through: stallAt, by: 43) {
            last = S(now: ms(now), voiceNow: true, lastVoice: ms(now), lastWords: words ? ms(now) : nil, score: score, complete: complete)
            if committed(driver.observe(last)) { return now }
        }
        var at = last.now
        while let wait = driver.nextLook(last), at < .seconds(200) {
            at += wait + ms(5)
            last = S(now: at, voiceNow: false, lastVoice: last.lastVoice, lastWords: last.lastWords, score: score, complete: complete)
            if committed(driver.observe(last)) { return Int(at / ms(1)) }
        }
        return nil
    }

    private func assertNear(_ value: Int?, _ expected: Int, file: StaticString = #filePath, line: UInt = #line) {
        guard let value else { return XCTFail("never committed", file: file, line: line) }
        XCTAssert(value >= expected && value <= expected + 120, "\(value) vs \(expected)", file: file, line: line)
    }

    func testAVoiceReadingArmsALook() {
        XCTAssertNotNil(ArisEndpointDriver().nextLook(S(now: ms(2000), voiceNow: true, lastVoice: ms(2000), lastWords: ms(1900), score: 0.9, complete: true)))
        var over = ArisEndpointDriver()
        _ = over.finish()
        XCTAssertNil(over.nextLook(S(now: ms(2000))))
    }

    func testAStalledFeedStillEndsTheTurn() {
        assertNear(stalled(at: 2021, words: true, score: 0.9, complete: true), 2521)
        assertNear(stalled(at: 2021, words: true, score: 0.5, complete: true), 4021)
        assertNear(stalled(at: 2021, words: false, score: nil, complete: false), 8000)
        assertNear(stalled(at: 14_964, words: false, score: nil, complete: false), 15_000)
    }
}

final class ArisCutOffNoteTests: XCTestCase {
    func testTheNoteIsTheTurnsOwn() {
        let spoken = ArisTurnID(4), typed = ArisTurnID(5)
        XCTAssertTrue(ArisCutOffNote.applies(cancelled: 1, hearingTurn: spoken, turn: spoken))
        XCTAssertFalse(ArisCutOffNote.applies(cancelled: 1, hearingTurn: spoken, turn: typed))
        XCTAssertFalse(ArisCutOffNote.applies(cancelled: 0, hearingTurn: spoken, turn: spoken))
        XCTAssertFalse(ArisCutOffNote.applies(cancelled: 1, hearingTurn: nil, turn: nil))
    }
}
