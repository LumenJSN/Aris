import XCTest
@testable import ArisCore

/// Tenth VM run, item 7: the quick understanding's time limit per kind of model, and its rest after misses in a row.
final class ArisRouterPatienceTests: XCTestCase {
    func testLimitPerKind() {
        XCTAssertEqual(ArisRouterPatience.limit(.jev), 0.6)
        XCTAssertEqual(ArisRouterPatience.limit(.smallModel), 0.6)
        // A chat model's whole short answer took 1.0-2.2 s warm in the run (median 1.6 s): 600 ms never fits.
        XCTAssertEqual(ArisRouterPatience.limit(.chatModel), 2.5)
        XCTAssertGreaterThan(ArisRouterPatience.appWait(api: true), ArisRouterPatience.limit(.chatModel))
        XCTAssertEqual(ArisRouterPatience.appWait(api: false), 0.6)
    }

    func testRestsAfterMissesInARowAndSaysSoOnce() {
        var rest = ArisRouterRest()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(rest.isResting(route: "api:deepseek", now: start))
        XCTAssertFalse(rest.missed(route: "api:deepseek", now: start))
        XCTAssertFalse(rest.missed(route: "api:deepseek", now: start))
        XCTAssertFalse(rest.isResting(route: "api:deepseek", now: start))
        XCTAssertTrue(rest.missed(route: "api:deepseek", now: start), "the third miss in a row begins the rest: the one log line")
        XCTAssertTrue(rest.isResting(route: "api:deepseek", now: start.addingTimeInterval(ArisRouterRest.restSeconds - 1)))
        XCTAssertFalse(rest.isResting(route: "api:deepseek", now: start.addingTimeInterval(ArisRouterRest.restSeconds)))
    }

    func testAnAnswerClearsTheCount() {
        var rest = ArisRouterRest()
        let now = Date(timeIntervalSince1970: 1_000)
        _ = rest.missed(route: "jev", now: now)
        _ = rest.missed(route: "jev", now: now)
        rest.answered(route: "jev")
        XCTAssertFalse(rest.missed(route: "jev", now: now))
        XCTAssertFalse(rest.missed(route: "jev", now: now))
        XCTAssertFalse(rest.isResting(route: "jev", now: now))
    }

    func testAfterARestOneMoreMissRestsAgain() {
        var rest = ArisRouterRest()
        let start = Date(timeIntervalSince1970: 1_000)
        for _ in 0..<ArisRouterRest.missesBeforeRest { _ = rest.missed(route: "auto", now: start) }
        let later = start.addingTimeInterval(ArisRouterRest.restSeconds + 1)
        XCTAssertFalse(rest.isResting(route: "auto", now: later), "one try after the rest")
        XCTAssertTrue(rest.missed(route: "auto", now: later), "and it rests again at once when that try misses too")
        XCTAssertTrue(rest.isResting(route: "auto", now: later.addingTimeInterval(1)))
    }

    func testAnotherChoiceStartsFresh() {
        var rest = ArisRouterRest()
        let now = Date(timeIntervalSince1970: 1_000)
        for _ in 0..<ArisRouterRest.missesBeforeRest { _ = rest.missed(route: "api:deepseek", now: now) }
        XCTAssertFalse(rest.isResting(route: "jev", now: now), "the owner picked another model: it is asked")
        XCTAssertFalse(rest.missed(route: "jev", now: now))
    }
}
