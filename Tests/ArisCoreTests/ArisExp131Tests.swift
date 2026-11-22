//
//  ArisExp131Tests.swift
//
//  jv-exp131: the thirteenth VM run's Experimental-mode defects, the pure rules (the wiring and the replays of the
//  run's own record through the real gate are in tests/exp131-tests.swift).
//

import XCTest
@testable import ArisCore

/// Item 1: an undo takes what their words name, never another kind silently (record-full.jsonl 23:27:48, 23:30:25).
final class ArisExp131UndoTests: XCTestCase {
    private let home = "/Users/admin"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The run's entries, as the record had them at 23:27:48: a taught run's typed line, a Trash and a rename (both kept in
    /// the activity log, `logged`), the Trash already undone through the log at 23:25:57.
    private func entries() -> (typed: ArisRecordEntry, trash: ArisRecordEntry, rename: ArisRecordEntry) {
        var typed = ArisRecordEntry.call(at: now.addingTimeInterval(-253), session: "teach-b2d6bd60", task: nil, capability: "app.type", effect: .changeReversible,
                                         provenance: .ownStep, decision: .runWithUndo(announce: false),
                                         arguments: [.init(kind: .app, value: "TextEdit"), .init(kind: .body, value: " 우유")], result: "typed", ok: true,
                                         undo: .textInserted(app: "TextEdit", element: "{}", before: ""))
        typed.session = "teach-b2d6bd60"
        var trash = ArisRecordEntry.call(at: now.addingTimeInterval(-230), session: "claude-7d2fde40232f5292", task: nil, capability: "aris.file_trash",
                                         effect: .changeReversible, provenance: .ownerSaid, decision: .runWithUndo(announce: false),
                                         arguments: [.init(kind: .path, value: "~/Desktop/X13/sub/초안13.txt")], result: "moved to the Trash", ok: true, undo: nil)
        trash.logged = ["b9d0d872-e1e2-43c3-957f-ecc05b3dd5a7"]
        var rename = ArisRecordEntry.call(at: now.addingTimeInterval(-92), session: "claude-7d2fde40232f5292", task: nil, capability: "aris.file_rename",
                                          effect: .changeReversible, provenance: .ownerSaid, decision: .runWithUndo(announce: false),
                                          arguments: [.init(kind: .path, value: "~/Desktop/v13/rename-me.txt")], result: "renamed", ok: true, undo: nil)
        rename.logged = ["80562578-e411-4e07-8819-e0f437087d32"]
        return (typed, trash, rename)
    }

    private func decide(_ entries: [ArisRecordEntry], named: ArisUndoKind?, approved: Bool = false, planned: [String]? = nil,
                        loggedUndone: Set<String> = ["b9d0d872-e1e2-43c3-957f-ecc05b3dd5a7"]) -> ArisUndoScope.Verdict {
        ArisUndoScope.decide(id: nil, count: 1, state: ArisRecordState(entries),
                             caller: ArisUndoCaller(session: "claude-5ce38bde15bc7c9f", provenance: .ownerSaid, approved: approved, named: named, planned: planned),
                             context: .init(level: .standard, home: home, now: now), loggedUndone: loggedUndone)
    }

    func testTheWordsNameTheKind() {
        XCTAssertEqual(ArisUndoKind.named(in: "방금 이름 바꾼 거 되돌려 줘"), .rename)
        XCTAssertEqual(ArisUndoKind.named(in: "응, 파일 이름 바꾼 것도 되돌려 줘"), .rename)
        XCTAssertEqual(ArisUndoKind.named(in: "아까 넣은 모레 11시 13분 치과 일정 되돌려 줘"), .event)
        XCTAssertEqual(ArisUndoKind.named(in: "휴지통에 버린 거 되돌려"), .trash)
        XCTAssertEqual(ArisUndoKind.named(in: "방금 입력한 글 되돌려"), .typing)
        XCTAssertEqual(ArisUndoKind.named(in: "이 창 옮긴 거 되돌려 줘"), .window)
        XCTAssertEqual(ArisUndoKind.named(in: "undo the rename"), .rename)
        XCTAssertNil(ArisUndoKind.named(in: "방금 거 되돌려"))
        XCTAssertNil(ArisUndoKind.named(in: "undo that"))
    }

    func testEachEntryIsOfItsKindFromAnAllowlist() {
        let (typed, trash, rename) = entries()
        XCTAssertEqual(ArisUndoKind.of(typed), .typing)
        XCTAssertEqual(ArisUndoKind.of(trash), .trash)
        XCTAssertEqual(ArisUndoKind.of(rename), .rename)
        let other = ArisRecordEntry.call(session: "s", task: nil, capability: "shell.run", effect: .changeReversible, provenance: .ownerSaid,
                                         decision: .run, arguments: [], result: nil, ok: true, undo: .fileCreated(path: "/Users/admin/x"))
        XCTAssertNil(ArisUndoKind.of(other), "a kind not on the list is none, never one he named")
    }

    func testTheRenameHeNamedIsUndoneNotTheOlderTypedLine() {
        let (typed, trash, rename) = entries()
        let verdict = decide([typed, trash, rename], named: .rename)
        XCTAssertEqual(verdict.ids, [rename.id], "23:27:48: the rename, never the taught typing step")
        XCTAssertFalse(verdict.decision.waitsForOwner, "the newest and of his kind: no card")
        XCTAssertTrue(verdict.line.contains("rename-me.txt"))
    }

    func testAPlainUndoTakesTheNewestOverallAndSkipsWhatTheLogUndid() {
        let (typed, trash, rename) = entries()
        XCTAssertEqual(decide([typed, trash, rename], named: nil).ids, [rename.id])
        XCTAssertEqual(decide([typed, trash], named: nil).ids, [typed.id], "the Trash undone through the log is not taken again")
        XCTAssertEqual(decide([typed, trash], named: nil, loggedUndone: []).ids, [trash.id], "a logged change counts as one that can be undone")
    }

    func testAKindThatIsntThereIsSaidAndTheNewestIsOfferedOnACard() {
        let (typed, trash, rename) = entries()
        let verdict = decide([typed, trash, rename], named: .trash)
        XCTAssertEqual(verdict.ids, [rename.id])
        XCTAssertTrue(verdict.decision.waitsForOwner, "never undone silently: a card")
        XCTAssertTrue(verdict.line.contains("휴지통에 넣은 것은 기록에 없어요") && verdict.line.contains("rename-me.txt"), verdict.line)
    }

    func testAnOlderEntryOfHisKindAsksOnACardThatNamesIt() {
        let (typed, trash, rename) = entries()
        let verdict = decide([typed, trash, rename], named: .typing)
        XCTAssertEqual(verdict.ids, [typed.id])
        XCTAssertEqual(verdict.decision, .ask)
        XCTAssertTrue(verdict.line.contains("TextEdit"), verdict.line)
        // His yes on that card: exactly what it named, and nothing when the record changed since.
        XCTAssertEqual(decide([typed, trash, rename], named: .typing, approved: true, planned: [typed.id]).ids, [typed.id])
        XCTAssertEqual(decide([typed, trash, rename], named: .typing, approved: true, planned: [typed.id]).decision, .runWithUndo(announce: false))
        if case .refuse = decide([trash, rename], named: .typing, approved: true, planned: [typed.id]).decision {} else { XCTFail("a vanished entry is refused") }
    }

    func testOnlyAllowlistedLoggedCallsCanBeUndone() {
        var made = ArisRecordEntry.call(session: "s", task: nil, capability: "aris.aris", effect: .changePermanent, provenance: .ownerSaid,
                                        decision: .run, arguments: [], result: "event deleted", ok: true, undo: nil)
        made.logged = ["cf32545a-2d13-446a-b9e0-ea1ffe65f8d3"]
        XCTAssertFalse(ArisUndoScope.canUndo(made), "a log line of a capability not on the list is never taken back from here")
        XCTAssertTrue(ArisUndoScope.canUndo(entries().rename))
    }
}

/// Item 4: an aris-tools act is titled as itself, and words aris-tools would refuse never get a card.
final class ArisExp131ToolWordsTests: XCTestCase {
    func testAnEventDeleteIsTitledAndMalformedWordsAreRefusedFirst() {
        XCTAssertEqual(ArisToolWords.title(["event", "delete", "--id", "X", "--title", "치과", "--start", "2026-11-23 11:13"]), "일정 지우기")
        XCTAssertEqual(ArisToolWords.title(["event", "change", "--id", "X"]), "일정 바꾸기")
        XCTAssertNil(ArisToolWords.title(["event", "치과", "--start", "2026-11-23 11:13"]))
        XCTAssertNil(ArisToolWords.usageRefusal(["event", "delete", "--id", "X", "--title", "치과", "--start", "2026-11-23 11:13"]))
        XCTAssertNil(ArisToolWords.usageRefusal(["event", "change", "--id", "X", "--title", "치과", "--start", "2026-11-23 11:13", "--to", "2026-11-23 12:00"]))
        XCTAssertNotNil(ArisToolWords.usageRefusal(["event", "delete", "--id", "E4D92EFC"]), "23:40:58: a delete by id alone")
        XCTAssertNotNil(ArisToolWords.usageRefusal(["event", "delete", "치과", "--start", "2026-11-23 11:13"]))
        XCTAssertNil(ArisToolWords.usageRefusal(["event", "find", "--from", "2026-11-23"]), "a read is never refused here")
    }

    func testTheCardTakesTheActionsOwnTitle() {
        var facts = ArisCallFacts(capability: "aris.aris", arguments: [])
        facts.actionTitle = ArisToolWords.title(["event", "delete", "--id", "X", "--title", "치과", "--start", "2026-11-23 11:13"])
        let item = ArisAskItem(call: "c", facts: facts, effect: .changePermanent, decision: .sayThenRun(delay: 4), provenance: .ownerSaid)
        XCTAssertEqual(ArisAskPlan.verb(item), "일정 지우기")
        XCTAssertTrue(ArisAskPlan.title([item]).hasPrefix("일정 지우기"))
    }
}
