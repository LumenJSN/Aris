//
//  ArisMind10cTests.swift
//  ArisCoreTests
//
//  Tenth VM run, items 6 and 8. 6: an AppleScript that waits on macOS's own Automation dialog ("Aris wants to control
//  Notes") is given the owner's time to answer instead of being called failed at 30 s (the note was made after Allow).
//  8: a click names an element that was read (its id, or its exact name), never a description of one.
//

import XCTest
@testable import ArisCore

final class ArisMind10cTests: XCTestCase {
    // MARK: - 6: the Automation dialog

    func testTheAppsAScriptDrivesAreReadFromIt() {
        XCTAssertEqual(ArisPermissionWait.scriptTargets(#"tell application "Notes" to make new note with properties {body:"x"}"#), ["com.apple.Notes"])
        XCTAssertEqual(ArisPermissionWait.scriptTargets("tell application \"Finder\"\nget selection\nend tell"), ["com.apple.finder"])
        XCTAssertEqual(ArisPermissionWait.scriptTargets(#"tell application "System Events" to restart"#), ["com.apple.systemevents"])
        XCTAssertEqual(ArisPermissionWait.scriptTargets(#"tell application id "com.example.app" to activate"#), ["com.example.app"])
        // Two apps in one script: both, once each, in the order they come.
        XCTAssertEqual(ArisPermissionWait.scriptTargets(#"tell application "Safari" to get URL of front document"# + "\n" + #"tell application "Safari" to activate"# + "\n" + #"tell application "Mail" to activate"#),
                       ["com.apple.Safari", "com.apple.mail"])
        // No app is driven: nothing to wait on.
        XCTAssertEqual(ArisPermissionWait.scriptTargets("get volume settings"), [])
        // A name inside the text a script carries is not a target.
        XCTAssertEqual(ArisPermissionWait.scriptTargets(#"tell application "Notes" to make new note with properties {body:"tell application \"Mail\" to quit"}"#), ["com.apple.Notes"])
        // An app that isn't on the list is named as it was written, for the live lookup.
        XCTAssertEqual(ArisPermissionWait.scriptTargets(#"tell application "Things3" to show quick entry panel"#), ["name:Things3"])
    }

    func testAScriptWaitsLongerOnlyWhileMacOSIsAsking() {
        // The dialog is up (never answered): the rest of the owner's time.
        XCTAssertEqual(ArisPermissionWait.automationExtension(states: [.notAsked], waited: 30), ArisPermissionWait.dialog - 30)
        XCTAssertEqual(ArisPermissionWait.automationExtension(states: [.granted, .notAsked], waited: 10), ArisPermissionWait.dialog - 10)
        // Allowed, refused or not known: the app is slow or stuck, not waiting on him.
        XCTAssertNil(ArisPermissionWait.automationExtension(states: [.granted], waited: 30))
        XCTAssertNil(ArisPermissionWait.automationExtension(states: [.denied], waited: 30))
        XCTAssertNil(ArisPermissionWait.automationExtension(states: [.unknown], waited: 30))
        XCTAssertNil(ArisPermissionWait.automationExtension(states: [], waited: 30))
        // His time is one cap, however the wait was split.
        XCTAssertNil(ArisPermissionWait.automationExtension(states: [.notAsked], waited: ArisPermissionWait.dialog))
        XCTAssertNil(ArisPermissionWait.automationExtension(states: [.notAsked], waited: ArisPermissionWait.dialog + 5))
        // The whole wait stays inside a chat turn's silence limit.
        XCTAssertLessThan(ArisPermissionWait.dialog + 15, ArisTurnLimits.chat.silence)
    }

    func testWhatIsSaidWhenTheWaitRanOut() {
        // Still asking: never "failed", never "done", never to be repeated; he is told to answer the dialog.
        let asking = ArisPermissionWait.automationTimeoutLine(app: "Notes", states: [.notAsked], waited: 90) ?? ""
        XCTAssertTrue(asking.contains("macOS is still asking"))
        XCTAssertTrue(asking.contains("Notes"))
        XCTAssertTrue(asking.contains("don't repeat it"))
        XCTAssertTrue(asking.contains("may still go through"))
        XCTAssertFalse(asking.lowercased().contains("failed"))
        XCTAssertFalse(asking.contains("isn't running"))
        // Not asking: nil, and the caller keeps its own "didn't answer" line.
        XCTAssertNil(ArisPermissionWait.automationTimeoutLine(app: "Notes", states: [.granted], waited: 30))
        XCTAssertNil(ArisPermissionWait.automationTimeoutLine(app: "Notes", states: [.unknown], waited: 30))
        // Refused while it waited: said as refused, nothing was done.
        let refused = ArisPermissionWait.automationTimeoutLine(app: "Notes", states: [.denied], waited: 40)
        XCTAssertEqual(refused.map { $0.contains("isn't allowed to control Notes") }, true)
    }

    func testTheHelperLetsAScriptingRunWaitForTheDialog() {
        XCTAssertEqual(ArisPermissionWait.scriptRunLimit(argv: ["note", "장보기"]), ArisPermissionWait.run)
        XCTAssertEqual(ArisPermissionWait.scriptRunLimit(argv: ["music", "play"]), ArisPermissionWait.run)
        XCTAssertEqual(ArisPermissionWait.scriptRunLimit(argv: ["power", "restart"]), ArisPermissionWait.run)
        XCTAssertNil(ArisPermissionWait.scriptRunLimit(argv: ["weather", "Orlando"]))
        XCTAssertNil(ArisPermissionWait.scriptRunLimit(argv: []))
        // The calendar's and the to-do list's own wait is as it was.
        XCTAssertEqual(ArisPermissionWait.runLimit(argv: ["event", "x"]), ArisPermissionWait.run)
        XCTAssertNil(ArisPermissionWait.runLimit(argv: ["note", "x"]))
    }

    // MARK: - 8: a click names what was read

    private let page = """
    [e1] toolbar
    [e7] button “Share” (disabled)
    [e12] link “역사”
    [e13] link “역사” (selected)
    [e20] link “특징”
    [e21] staticText “고양이는 식육목 고양이과의 포유류이다.”
    [e30] textField “검색” = “고양이”
    [e31] button “Pay now”
    """

    func testAReadsLinesAreParsedBack() {
        let seen = ArisApps.Grounding.lines(page)
        XCTAssertEqual(seen.count, 8)
        XCTAssertEqual(seen[0], ArisApps.Grounding.Seen(id: "e1", role: "toolbar", label: ""))
        XCTAssertEqual(seen[1], ArisApps.Grounding.Seen(id: "e7", role: "button", label: "Share"))
        XCTAssertEqual(seen[3], ArisApps.Grounding.Seen(id: "e13", role: "link", label: "역사"))
        XCTAssertEqual(seen[6], ArisApps.Grounding.Seen(id: "e30", role: "textField", label: "검색"))
        // The lines a real element prints are read back as that element.
        let element = ArisApps.ReadElement(id: "elem_44", role: "link", label: "문단을 편집")
        XCTAssertEqual(ArisApps.Grounding.lines(element.line()), [ArisApps.Grounding.Seen(id: "e44", role: "link", label: "문단을 편집")])
        // Text that isn't a read's line is nothing.
        XCTAssertEqual(ArisApps.Grounding.lines("press e99 now\n[oops\n"), [])
    }

    func testAReadsResultNamesItsAppAndElements() {
        let result = #"{"channel":"ax","data":{"app":"Safari","part":"all","shown":2,"text":"[e12] link “역사”\n[e20] link “특징”","total":2,"window":"고양이"},"did":"read","effect":"observe","ok":true}"#
        let read = ArisApps.Grounding.read(result)
        XCTAssertEqual(read?.app, "Safari")
        XCTAssertEqual(read?.elements.map(\.id), ["e12", "e20"])
        // A failure, another call's result, or text that only looks like one: nothing was read.
        XCTAssertNil(ArisApps.Grounding.read(#"{"did":"couldn't read Safari's window","ok":false}"#))
        XCTAssertNil(ArisApps.Grounding.read("[e12] link “역사”"))
        XCTAssertNil(ArisApps.Grounding.read(#"{"data":{"app":"Safari","text":"[e12] link “역사”"},"ok":false}"#))
    }

    func testAClickIsGroundedOnlyInWhatWasRead() {
        let seen = ArisApps.Grounding.lines(page)
        func grounded(_ target: String) -> Bool { ArisApps.Grounding.check(target: target, app: "Safari", seen: seen) == nil }
        // Its id, as the read printed it.
        XCTAssertTrue(grounded("e20"))
        XCTAssertTrue(grounded("[e20]"))
        XCTAssertTrue(grounded("[e20] link “특징”"))
        // Its exact name, with or without its role and quotes.
        XCTAssertTrue(grounded("특징"))
        XCTAssertTrue(grounded("“특징”"))
        XCTAssertTrue(grounded("link “특징”"))
        XCTAssertTrue(grounded("link 특징"))
        XCTAssertTrue(grounded("역사"))
        // A taught step's exact mark names the same label.
        XCTAssertTrue(grounded("=Pay now"))
        // The tenth run's target: a description. Refused, with what to do.
        let why = ArisApps.Grounding.check(target: "the “역사” link in the 목차 (table of contents) sidebar", app: "Safari", seen: seen)
        XCTAssertNotNil(why)
        XCTAssertEqual(why.map { $0.contains("Read") && $0.contains("exact name") && $0.contains("Nothing was pressed") }, true)
        // Near is not exact: case, a part of the name, another role, an id that wasn't read.
        XCTAssertFalse(grounded("pay now"))
        XCTAssertFalse(grounded("Pay"))
        XCTAssertFalse(grounded("button “특징”"))
        XCTAssertFalse(grounded("e99"))
        XCTAssertFalse(grounded("역사 링크"))
        XCTAssertFalse(grounded(""))
        // Nothing read (or not known): never less strict than a read that doesn't hold it.
        XCTAssertNotNil(ArisApps.Grounding.check(target: "e20", app: "Safari", seen: nil))
        XCTAssertNotNil(ArisApps.Grounding.check(target: "특징", app: "Safari", seen: []))
        // The refusal never repeats more than a little of what the model wrote.
        let long = ArisApps.Grounding.check(target: String(repeating: "가", count: 500), app: "Safari", seen: seen) ?? ""
        XCTAssertLessThan(long.count, 500)
    }

    func testAnExactNameIsFoundBeforeAnyDescriptionIsScored() {
        let elements = [
            ArisApps.ReadElement(id: "elem_1", role: "link", label: "역사"),
            ArisApps.ReadElement(id: "elem_2", role: "link", label: "역사와 문화"),
            ArisApps.ReadElement(id: "elem_3", role: "button", label: "역사 편집"),
        ]
        XCTAssertEqual(ArisApps.Read.locate("역사", in: elements), .one(elements[0]))
        XCTAssertEqual(ArisApps.Read.locate("link “역사”", in: elements), .one(elements[0]))
        XCTAssertEqual(ArisApps.Read.locate("[e3] button “역사 편집”", in: elements), .one(elements[2]))
        // Two with the same exact name: asked, never picked.
        let twice = elements + [ArisApps.ReadElement(id: "elem_4", role: "link", label: "역사")]
        if case .several(let many) = ArisApps.Read.locate("역사", in: twice) { XCTAssertEqual(Set(many.map(\.id)), ["elem_1", "elem_4"]) } else { XCTFail("picked one of two") }
    }

    func testAReadCanBeNarrowedToWhatIsLookedFor() {
        let elements = [
            ArisApps.ReadElement(id: "elem_1", role: "link", label: "역사", actionable: true),
            ArisApps.ReadElement(id: "elem_2", role: "staticText", label: "", value: "고양이의 역사는 길다"),
            ArisApps.ReadElement(id: "elem_3", role: "link", label: "특징", actionable: true),
            ArisApps.ReadElement(id: "elem_4", role: "button", label: "History", actionable: true),
        ]
        XCTAssertEqual(ArisApps.Read.matching("역사", in: elements).map(\.id), ["elem_1", "elem_2"])
        XCTAssertEqual(ArisApps.Read.matching("history", in: elements).map(\.id), ["elem_4"])
        // Nothing asked for: everything.
        XCTAssertEqual(ArisApps.Read.matching("  ", in: elements).count, 4)
        XCTAssertEqual(ArisApps.Read.matching(nil, in: elements).count, 4)
        XCTAssertEqual(ArisApps.Read.matching("없는 말", in: elements), [])
    }
}
