import XCTest
@testable import ArisCore

/// The eleventh VM run, P11 (aris-vmcheck/notes11/actions-full.log:11-12, cap11/P11-wait35.jpg): `aris-tools note` on the
/// default path. macOS's Automation dialog was up for about 35 s; the script was stopped at 30 s, the note was made
/// once he allowed it, and the reply said "Notes가 30초 안에 응답하지 않았어요". The look at the limit had not read
/// "not asked" while the dialog was up, so the script got no more time.
final class ArisAutomationLateTests: XCTestCase {
    private typealias W = ArisPermissionWait

    func testAScriptSentWhileMacOSWasAskingWaitsWhateverTheLookSaysNow() {
        // As recorded: never answered when the script went; at 30 s macOS's answer can't be read.
        XCTAssertEqual(W.automationExtension(before: [.notAsked], states: [.unknown], waited: 30), W.dialog - 30)
        XCTAssertEqual(W.automationExtension(before: [.notAsked], states: [], waited: 30), W.dialog - 30)
        XCTAssertEqual(W.automationExtension(before: [.notAsked], states: [.notAsked], waited: 30), W.dialog - 30)
        // Allowed in the meantime: the same script gets a short while to finish, never more than his time.
        XCTAssertEqual(W.automationExtension(before: [.notAsked], states: [.granted], waited: 30), W.grace)
        XCTAssertEqual(W.automationExtension(before: [.notAsked], states: [.granted], waited: W.dialog - 5), 5)
        // Refused: stopped now. His time used up: stopped.
        XCTAssertNil(W.automationExtension(before: [.notAsked], states: [.denied], waited: 30))
        XCTAssertNil(W.automationExtension(before: [.notAsked], states: [.unknown], waited: W.dialog))
        // Nothing was being asked when it went: a slow or stuck app is stopped at its limit as before.
        XCTAssertNil(W.automationExtension(before: [.granted], states: [.unknown], waited: 30))
        XCTAssertNil(W.automationExtension(before: [.granted], states: [.granted], waited: 30))
        XCTAssertNil(W.automationExtension(before: [], states: [.unknown], waited: 30))
        XCTAssertEqual(W.automationExtension(before: [.granted], states: [.notAsked], waited: 30), W.dialog - 30)
    }

    func testWhatIsSaidAtTheEndIsNeverThatTheAppDidNotAnswer() {
        // Sent while macOS was asking, and still not finished: not known, never repeated, never "Notes didn't answer".
        let unknown = W.automationTimeoutLine(app: "Notes", before: [.notAsked], states: [.unknown], waited: 90) ?? ""
        XCTAssertTrue(unknown.contains("macOS was asking") && unknown.contains("don't repeat it") && unknown.contains("isn't known"), unknown)
        XCTAssertFalse(unknown.contains("didn't answer within"))
        XCTAssertEqual(W.automationTimeoutLine(app: "Notes", before: [.notAsked], states: [.granted], waited: 50), unknown.replacingOccurrences(of: "90 seconds", with: "50 seconds"))
        XCTAssertEqual(W.automationTimeoutLine(app: "Notes", before: [.notAsked], states: [.notAsked], waited: 90), W.automationTimeoutLine(app: "Notes", states: [.notAsked], waited: 90))
        XCTAssertEqual(W.automationTimeoutLine(app: "Notes", before: [.notAsked], states: [.denied], waited: 40), W.automationTimeoutLine(app: "Notes", states: [.denied], waited: 40))
        XCTAssertNil(W.automationTimeoutLine(app: "Notes", before: [.granted], states: [.granted], waited: 30))
    }

    func testReadingBackDecidesWhatIsSaidOfALateScript() {
        XCTAssertEqual(W.lateOutcome(found: true), .done)
        XCTAssertEqual(W.lateOutcome(found: false), .unknown)
        XCTAssertEqual(W.lateOutcome(found: nil), .unknown)
        XCTAssertTrue(W.lateDoneNote.contains("reading it back"))
    }

    func testTheNoteIsFoundOnlyWhenItIsThisOne() {
        let sent = Date(timeIntervalSince1970: 1_000_000)
        let notes = [(title: "회의 안건 정리", modified: sent.addingTimeInterval(36)), (title: "장보기", modified: sent.addingTimeInterval(-600))]
        XCTAssertTrue(ArisNoteLate.exists(notes, titled: "회의 안건 정리", since: sent))
        XCTAssertFalse(ArisNoteLate.exists(notes, titled: "장보기", since: sent), "an older note of that name is not this one")
        XCTAssertFalse(ArisNoteLate.exists(notes, titled: "없는 메모", since: sent))
        XCTAssertFalse(ArisNoteLate.exists(notes, titled: " ", since: sent))
    }
}
