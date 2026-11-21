//
//  ArisPermissionWaitTests.swift
//  ArisCoreTests
//
//  vmfix3 A2: every wait on the way to macOS's Calendars or Reminders dialog holds the person's answer.
//

import XCTest
@testable import ArisCore

final class ArisPermissionWaitTests: XCTestCase {
    func testTheWaitsNestInsideATurn() {
        XCTAssertGreaterThanOrEqual(ArisPermissionWait.dialog, 60)
        XCTAssertLessThan(ArisPermissionWait.dialog, ArisPermissionWait.request)
        XCTAssertLessThan(ArisPermissionWait.request, ArisPermissionWait.run)
        XCTAssertLessThan(ArisPermissionWait.run, ArisTurnLimits.chat.silence)
        XCTAssertEqual(ArisPermissionWait.requestLimit(asks: false), 20)
    }

    func testOnlyAnAskingCalendarOrTodoRequestWaitsLonger() {
        let asking = Data(#"{"ask":true}"#.utf8)
        XCTAssertTrue(ArisPermissionWait.asks(path: "/aris/events", body: asking))
        XCTAssertTrue(ArisPermissionWait.asks(path: "/aris/todos", body: asking))
        XCTAssertFalse(ArisPermissionWait.asks(path: "/aris/events", body: Data(#"{"ask":"yes"}"#.utf8)))
        XCTAssertFalse(ArisPermissionWait.asks(path: "/aris/permission", body: asking))
        XCTAssertFalse(ArisPermissionWait.asks(path: "/aris/events", body: Data("not json".utf8)))
    }

    func testALateAnswerIsNeverNotRunning() {
        XCTAssertEqual(ArisPermissionWait.reply(status: 504, data: nil, timedOut: false, lineKey: "line")?["line"] as? String, ArisPermissionWait.lateLine)
        XCTAssertEqual(ArisPermissionWait.reply(status: nil, data: nil, timedOut: true, lineKey: "message")?["message"] as? String, ArisPermissionWait.lateLine)
        XCTAssertNil(ArisPermissionWait.reply(status: nil, data: nil, timedOut: false, lineKey: "line"))
        XCTAssertNil(ArisPermissionWait.reply(status: 403, data: nil, timedOut: false, lineKey: "line"))
    }

    func testTheRaceGivesTheAnswerOrNothing() async {
        let quick = await ArisPermissionWait.first(within: 5) { true }
        XCTAssertEqual(quick, true)
        let slow = await ArisPermissionWait.first(within: 0.05) { () async -> Bool in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return true
        }
        XCTAssertNil(slow)
    }
}
