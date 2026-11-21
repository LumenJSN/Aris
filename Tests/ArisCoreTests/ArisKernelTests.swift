import XCTest
@testable import ArisCore

/// The runner: turn scopes, the write guard, card waits as continuations, the event ring.
@MainActor
final class ArisKernelTests: XCTestCase {
    func testTheScopeRidesIntoTasksAndOutsideClearsIt() async {
        let kernel = ArisKernel()
        let id = kernel.openTurn(.key)
        let inner = await ArisTurnScope.within(id) { await Task { ArisTurnScope.current }.value }
        XCTAssertEqual(inner, id)
        let outside = ArisTurnScope.within(id) { ArisTurnScope.outside { ArisTurnScope.current } }
        XCTAssertNil(outside)
        XCTAssertNil(ArisTurnScope.current)
    }

    func testACancelledOlderTurnFinishingLateCannotWrite() async {
        let kernel = ArisKernel()
        var cancelled: [ArisTurnID] = []
        kernel.cancelWork = { cancelled.append($0) }
        var shown = "idle"
        func write(_ value: String) { if kernel.admitsWrite(from: ArisTurnScope.current) { shown = value } }
        let old = kernel.openTurn(.key)
        let gate = AsyncStream<Void>.makeStream()
        let late = Task { await ArisTurnScope.within(old) {
            for await _ in gate.stream { break }
            write("old turn's late answer")
        } }
        let new = kernel.openTurn(.typed)
        ArisTurnScope.within(new) { write("new turn") }
        gate.continuation.yield()
        await late.value
        XCTAssertEqual(shown, "new turn")
        XCTAssertEqual(cancelled, [old])
        XCTAssertEqual(kernel.ring.stages(of: old).map(\.name), ["opened:key", "write-dropped"])
    }

    func testAnAnswerResumesTheWaitAtOnce() async {
        let kernel = ArisKernel()
        let id = kernel.openTurn(.key)
        let key = kernel.showCard("c", turn: id)
        let waiting = Task { await kernel.waitForCard(key, tick: .seconds(60)) { false } }
        await Task.yield()
        XCTAssertTrue(kernel.answerCard("c", allow: true))
        let outcome = await waiting.value
        XCTAssertEqual(outcome, .answered(true))
        XCTAssertFalse(kernel.answerCard("c", allow: false), "a showing is answered once")
    }

    func testAnAnswerBeforeTheWaitIsKept() async {
        let kernel = ArisKernel()
        let key = kernel.showCard("c", turn: kernel.openTurn(.key))
        kernel.answerCard("c", allow: false)
        let outcome = await kernel.waitForCard(key, tick: .seconds(60)) { false }
        XCTAssertEqual(outcome, .answered(false))
    }

    func testTheTurnsEndResumesTheWaitCancelled() async {
        let kernel = ArisKernel()
        let id = kernel.openTurn(.key)
        let key = kernel.showCard("c", turn: id)
        let waiting = Task { await kernel.waitForCard(key, tick: .seconds(60)) { false } }
        await Task.yield()
        kernel.endTurn(id, .cancelled)
        let outcome = await waiting.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testANewTurnResumesTheWaitCancelled() async {
        let kernel = ArisKernel()
        let key = kernel.showCard("c", turn: kernel.openTurn(.key))
        let waiting = Task { await kernel.waitForCard(key, tick: .seconds(60)) { false } }
        await Task.yield()
        _ = kernel.openTurn(.wake)
        let outcome = await waiting.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testTheCheckEndsTheWaitWithoutAnOutcomeAndTheShowingStaysOpen() async {
        let kernel = ArisKernel()
        let key = kernel.showCard("c", turn: kernel.openTurn(.key))
        let outcome = await kernel.waitForCard(key, tick: .milliseconds(5)) { true }
        XCTAssertNil(outcome)
        XCTAssertTrue(kernel.isWaiting(key))
        kernel.closeCard(key)
        XCTAssertFalse(kernel.isWaiting(key))
        XCTAssertFalse(kernel.answerCard("c", allow: true))
    }

    func testAWaitOfOneTickReturnsNothingYetAndAnAnswerStillCutsItShort() async {
        let kernel = ArisKernel()
        let key = kernel.showCard("c", turn: kernel.openTurn(.key))
        let none = await kernel.waitForCard(key, atMost: .milliseconds(5))
        XCTAssertNil(none)
        let started = ContinuousClock.now
        let waiting = Task { await kernel.waitForCard(key, atMost: .seconds(60)) }
        await Task.yield()
        kernel.answerCard("c", allow: true)
        let outcome = await waiting.value
        XCTAssertEqual(outcome, .answered(true))
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
    }

    func testCancellingTheWaiterEndsTheShowing() async {
        let kernel = ArisKernel()
        let key = kernel.showCard("c", turn: kernel.openTurn(.key))
        let waiting = Task { await kernel.waitForCard(key, tick: .seconds(60)) { false } }
        await Task.yield()
        waiting.cancel()
        let outcome = await waiting.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertFalse(kernel.isWaiting(key))
    }

    func testTheRingKeepsTheNewestEntries() {
        var ring = ArisEventRing(capacity: 2)
        for origin in [ArisTurnOrigin.key, .typed, .wake] {
            ring.append(.init(at: 0, turn: nil, event: .turnOpened(origin), effects: []))
        }
        XCTAssertEqual(ring.entries.map(\.event), [.turnOpened(.typed), .turnOpened(.wake)])
    }

    func testATurnsStagesAreTimed() {
        let kernel = ArisKernel()
        var now = 10.0
        kernel.clock = { now }
        let id = kernel.openTurn(.key)
        now = 11
        _ = kernel.showCard("c", turn: id)
        now = 12
        kernel.answerCard("c", allow: true)
        now = 13
        kernel.endTurn(id, .dismissed)
        XCTAssertEqual(kernel.ring.stages(of: id), [
            .init(name: "opened:key", at: 10), .init(name: "card:c", at: 11),
            .init(name: "answered:c:yes", at: 12), .init(name: "ended:dismissed", at: 13),
        ])
    }
}
