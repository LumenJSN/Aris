import XCTest
@testable import ArisCore

/// The pure reducer: which turn is current, which writes count, how a card's wait ends.
final class ArisKernelStateTests: XCTestCase {
    private func reduce(_ state: ArisKernelState, _ events: ArisEvent...) -> (ArisKernelState, [ArisEffect]) {
        var state = state
        var effects: [ArisEffect] = []
        for event in events {
            let (next, more) = ArisKernelState.reduce(state, event)
            state = next
            effects += more
        }
        return (state, effects)
    }

    func testTurnIdsIncreaseAndTheFirstCancelsNothing() {
        let (one, first) = reduce(ArisKernelState(), .turnOpened(.key))
        XCTAssertEqual(one.current, ArisTurnID(1))
        XCTAssertEqual(first, [])
        let (two, second) = reduce(one, .turnOpened(.typed))
        XCTAssertEqual(two.current, ArisTurnID(2))
        XCTAssertGreaterThan(two.current!, one.current!)
        XCTAssertEqual(second, [.cancelWork(ArisTurnID(1))])
    }

    func testOnlyTheCurrentTurnOrNoTurnMayWrite() {
        let (state, _) = reduce(ArisKernelState(), .turnOpened(.key), .turnOpened(.wake))
        XCTAssertEqual(ArisKernelState.reduce(state, .sessionWrite(from: ArisTurnID(2))).1, [.write])
        XCTAssertEqual(ArisKernelState.reduce(state, .sessionWrite(from: nil)).1, [.write])
        XCTAssertEqual(ArisKernelState.reduce(state, .sessionWrite(from: ArisTurnID(1))).1, [.dropWrite(stale: ArisTurnID(1))])
    }

    func testAnEndedTurnCannotWriteAndAStaleEndChangesNothing() {
        let (open, _) = reduce(ArisKernelState(), .turnOpened(.key), .turnOpened(.key))
        let (stale, staleEffects) = reduce(open, .turnEnded(ArisTurnID(1), .cancelled))
        XCTAssertEqual(stale, open)
        XCTAssertEqual(staleEffects, [])
        let (ended, effects) = reduce(open, .turnEnded(ArisTurnID(2), .cancelled))
        XCTAssertNil(ended.current)
        XCTAssertEqual(effects, [.cancelWork(ArisTurnID(2))])
        XCTAssertFalse(ended.admits(ArisTurnID(2)))
        XCTAssertTrue(ended.admits(nil))
        // The next turn after an end cancels the ended one's leftovers too, by its number.
        XCTAssertEqual(reduce(ended, .turnOpened(.key)).1, [.cancelWork(ArisTurnID(2))])
    }

    func testAnAnswerResumesTheOpenCardOnce() {
        let (shown, _) = reduce(ArisKernelState(), .turnOpened(.key), .cardShown(card: "c", turn: nil))
        let key = ArisCardKey(card: "c", turn: ArisTurnID(1), serial: 1)
        XCTAssertEqual(shown.card, key)
        let (answered, effects) = reduce(shown, .cardAnswered(card: "c", allow: true))
        XCTAssertEqual(effects, [.resumeCard(key, .answered(true))])
        XCTAssertNil(answered.card)
        // A second answer, or one for another card, answers nothing.
        XCTAssertEqual(reduce(answered, .cardAnswered(card: "c", allow: false)).1, [])
        XCTAssertEqual(reduce(shown, .cardAnswered(card: "other", allow: true)).1, [])
    }

    func testTheTurnsEndCancelsItsCardNeverANo() {
        let (shown, _) = reduce(ArisKernelState(), .turnOpened(.key), .cardShown(card: "c", turn: nil))
        let key = ArisCardKey(card: "c", turn: ArisTurnID(1), serial: 1)
        XCTAssertEqual(reduce(shown, .turnEnded(ArisTurnID(1), .cancelled)).1, [.cancelWork(ArisTurnID(1)), .resumeCard(key, .cancelled)])
        XCTAssertEqual(reduce(shown, .turnOpened(.key)).1, [.cancelWork(ArisTurnID(1)), .resumeCard(key, .cancelled)])
    }

    func testANewCardCoversTheOldOneAndTheSameIdShownAgainIsANewWait() {
        let (first, _) = reduce(ArisKernelState(), .turnOpened(.key), .cardShown(card: "c", turn: nil))
        let (second, effects) = reduce(first, .cardShown(card: "c", turn: nil))
        XCTAssertEqual(effects, [.resumeCard(ArisCardKey(card: "c", turn: ArisTurnID(1), serial: 1), .covered)])
        XCTAssertEqual(second.card, ArisCardKey(card: "c", turn: ArisTurnID(1), serial: 2))
    }

    func testAStaleTurnsCardNeverWaits() {
        let (state, _) = reduce(ArisKernelState(), .turnOpened(.key), .turnOpened(.key))
        let (after, effects) = reduce(state, .cardShown(card: "late", turn: ArisTurnID(1)))
        XCTAssertNil(after.card)
        XCTAssertEqual(effects, [.resumeCard(ArisCardKey(card: "late", turn: ArisTurnID(1), serial: 1), .cancelled)])
    }

    func testClosedAndAbandonedCards() {
        let (shown, _) = reduce(ArisKernelState(), .turnOpened(.key), .cardShown(card: "c", turn: nil))
        let key = ArisCardKey(card: "c", turn: ArisTurnID(1), serial: 1)
        let (closed, closing) = reduce(shown, .cardClosed(key))
        XCTAssertNil(closed.card)
        XCTAssertEqual(closing, [])
        XCTAssertEqual(reduce(closed, .cardAnswered(card: "c", allow: true)).1, [])
        XCTAssertEqual(reduce(shown, .cardAbandoned(key)).1, [.resumeCard(key, .cancelled)])
        XCTAssertEqual(reduce(closed, .cardAbandoned(key)).1, [])
    }
}
