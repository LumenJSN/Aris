import XCTest
@testable import ArisCore

/// The eleventh VM run, K1 and K2 (aris-vmcheck/notes11/actions-full.log:24-37): "이 문서에 적힌 할 일 미리 알림에 추가해
/// 줘" and "이거 할 일에 추가해 줘" each got the card "시키지 않은 일이라 멈췄어요" when the checker answered unsure.
final class ArisPlainAskTests: XCTestCase {
    func testTheRecordedRequestsPlainlyAskForTheAdd() {
        XCTAssertTrue(ArisPlainAsk.addsPointedItems(request: "이 문서에 적힌 할 일 미리 알림에 추가해 줘", tool: "todo", verb: "add"))
        XCTAssertTrue(ArisPlainAsk.addsPointedItems(request: "이거 할 일에 추가해 줘", tool: "todo", verb: "add"))
        XCTAssertTrue(ArisPlainAsk.addsPointedItems(request: "Add the to-dos in this document to my reminders", tool: "todo", verb: "add"))
        XCTAssertTrue(ArisPlainAsk.addsPointedItems(request: "이 메일에 나온 회의 일정 캘린더에 넣어 줘", tool: "event", verb: "add"))
    }

    func testAnythingElseIsNotPlainlyAsked() {
        // Another kind of act than the one their words name; no pointing; no list named; a verb that isn't an add.
        XCTAssertFalse(ArisPlainAsk.addsPointedItems(request: "이 문서에 적힌 할 일 미리 알림에 추가해 줘", tool: "event", verb: "add"))
        XCTAssertFalse(ArisPlainAsk.addsPointedItems(request: "이 문서에 적힌 할 일 미리 알림에 추가해 줘", tool: "message", verb: "send"))
        XCTAssertFalse(ArisPlainAsk.addsPointedItems(request: "이 문서 요약해 줘", tool: "todo", verb: "add"))
        XCTAssertFalse(ArisPlainAsk.addsPointedItems(request: "이거 해 줘", tool: "todo", verb: "add"))
        XCTAssertFalse(ArisPlainAsk.addsPointedItems(request: "할 일 추가해 줘", tool: "todo", verb: "add"))
        XCTAssertFalse(ArisPlainAsk.addsPointedItems(request: "이거 할 일에서 빼 줘", tool: "todo", verb: "remove"))
        XCTAssertFalse(ArisPlainAsk.addsPointedItems(request: "", tool: "todo", verb: "add"))
    }
}
