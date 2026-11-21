import XCTest
@testable import ArisCore

/// The tenth VM run, item 11 (record-full.jsonl 44-45, turns.jsonl 55): "줄 하나 더 넣어 줘 ‘우유’로" typed "우유" after
/// "첫 줄" on the same line ("첫 줄우유") and the model said a line was added. What app.type reports about where the
/// text landed, from the field as read before and after.
final class ArisTypedPlaceTests: XCTestCase {
    func testTextAddedToALineThatWasThereIsSaidSo() {
        XCTAssertEqual(ArisApps.TypedPlace.place(before: "첫 줄", after: "첫 줄우유"), .sameLine(after: "첫 줄"))
        XCTAssertEqual(ArisApps.TypedPlace.place(before: "첫 줄", after: "첫 줄 우유"), .sameLine(after: "첫 줄"))
        XCTAssertEqual(ArisApps.TypedPlace.place(before: "a\n첫 줄", after: "a\n첫 줄우유"), .sameLine(after: "첫 줄"))
        let note = ArisApps.TypedPlace.note(before: "첫 줄", after: "첫 줄우유")
        XCTAssertEqual(note, "it went on the same line, right after “첫 줄” (no new line was started)")
    }

    func testTextOnALineOfItsOwn() {
        XCTAssertEqual(ArisApps.TypedPlace.place(before: "첫 줄", after: "첫 줄\n우유"), .ownLine)
        XCTAssertEqual(ArisApps.TypedPlace.place(before: "첫 줄\n", after: "첫 줄\n우유"), .ownLine)
        XCTAssertEqual(ArisApps.TypedPlace.place(before: "", after: "우유"), .ownLine)
        XCTAssertEqual(ArisApps.TypedPlace.note(before: "첫 줄", after: "첫 줄\n우유"), "it is on a line of its own")
    }

    func testInsideALineAndWhatCannotBeTold() {
        // Before text that was there on the same line.
        XCTAssertEqual(ArisApps.TypedPlace.place(before: "첫 줄", after: "우유첫 줄"), .sameLine(after: ""))
        XCTAssertEqual(ArisApps.TypedPlace.note(before: "첫 줄", after: "우유첫 줄"), "it went on the same line as text that was there (no new line was started)")
        // Something that was there is gone, or nothing was added: not told.
        XCTAssertNil(ArisApps.TypedPlace.place(before: "첫 줄", after: "우유"))
        XCTAssertNil(ArisApps.TypedPlace.place(before: "첫 줄", after: "첫 줄"))
        XCTAssertNil(ArisApps.TypedPlace.note(before: "첫 줄", after: "우유"))
    }

    func testALongLineIsCut() {
        let long = String(repeating: "가", count: 200)
        let note = ArisApps.TypedPlace.note(before: long, after: long + "x") ?? ""
        XCTAssertTrue(note.count < 120, note)
        XCTAssertTrue(note.contains("…"), note)
    }

    func testTheMindIsToldToSayOnlyWhatTheResultSays() {
        XCTAssertTrue(ArisApps.TypedPlace.rule.contains("says where the text landed"))
        XCTAssertTrue(ArisApps.TypedPlace.rule.contains("never say a new line was added"))
        XCTAssertTrue(ArisApps.TypedPlace.rule.contains("wasn't read back"))
    }
}
