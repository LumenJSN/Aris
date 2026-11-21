import XCTest
@testable import ArisCore

/// Ninth VM run, item 3 (cap9/H1-state3.jpg, notes9/H1-timeout-record.jsonl): a replay's step card left unanswered
/// for two minutes was reported as "Stopped at step 2 … you said no (1 step done before it)." and the record line
/// read "답이 없었어요 (no answer in time)" in the English UI. A card nobody answered is not a no.
final class ArisReplayUnansweredTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// "전체 바꾸기" as notes9/final-taught.json has it: open TextEdit, Edit › Select All (⌘A), replace the text.
    private var procedure: ArisTeachProcedure {
        var select = ArisTeachStep(action: .menu, app: "TextEdit", bundle: "com.apple.TextEdit", label: "Select All", menu: ["Edit", "Select All"], keys: "cmd+a")
        select.seen = ArisContentSource(kind: "app", source: "TextEdit")
        return ArisTeachProcedure(name: "전체 바꾸기", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit"), select],
                                  parameters: [], created: start)
    }

    /// Ports whose every call but the first waits for a card that gets `answer` (nil: nobody answered in time).
    private func ports(answer: Bool?) -> ArisMindPorts {
        var ports = ArisMindPorts(
            decide: { calls in calls.map { ArisMindDecided(call: $0, verdict: $0.name == "app_open" ? .run(undo: true, announce: false) : .waits) } },
            ask: { waiting in answer == true ? Set(waiting.map(\.call.id)) : [] },
            execute: { _ in ArisMindResult(text: "done") },
            finish: { _, _, _ in },
            isCurrent: { true })
        ports.unanswered = { _ in answer == nil }
        return ports
    }

    func testACardNobodyAnsweredEndsTheRunAsUnansweredNotAsANo() {
        let plan = ArisTeachReplay.plan(procedure, given: [:], words: "전체 바꾸기 해 줘", run: "49a3243a")
        XCTAssertEqual(ArisTeachReplay.run(plan, ports: ports(answer: nil)), .stopped(at: 1, end: .unanswered, done: 1))
        XCTAssertEqual(ArisTeachReplay.run(plan, ports: ports(answer: false)), .stopped(at: 1, end: .declined, done: 1))
        XCTAssertEqual(ArisTeachReplay.run(plan, ports: ports(answer: true)), .done(steps: 2))
    }

    func testTheAccountSaysThereWasNoAnswerInBothLanguages() {
        let silent = ArisTeachReplay.Outcome.stopped(at: 1, end: .unanswered, done: 1)
        let english = ArisTeachCopy.account(procedure, outcome: silent, english: true)
        XCTAssertEqual(english, "Stopped at step 2, In TextEdit, choose ‘Edit › Select All’: there was no answer, so I didn't do it (1 step done before it).")
        XCTAssertFalse(english.contains("said no"))
        let korean = ArisTeachCopy.account(procedure, outcome: silent, english: false)
        XCTAssertEqual(korean, "2단계 “TextEdit에서 메뉴 ‘Edit › Select All’ 누르기”에서 멈췄어요: 답이 없어서 하지 않았어요 (앞의 1단계는 했어요).")
        XCTAssertFalse(korean.contains("하지 말라고"))
        // His no still reads as his no.
        XCTAssertTrue(ArisTeachCopy.account(procedure, outcome: .stopped(at: 1, end: .declined, done: 1), english: true).contains("you said no"))
        // The run's tag: as after a no (the card's own end takes it away), never ticked.
        XCTAssertFalse(ArisTeachRunEnd.marksTagFailed(silent))
        XCTAssertFalse(ArisTeachRunEnd.completed(silent))
    }

    func testTheRecordLineOfAnUnansweredCardIsInTheUILanguage() {
        XCTAssertEqual(ArisJournalWords.unanswered(english: true), "No answer in time")
        XCTAssertEqual(ArisJournalWords.unanswered(english: false), "답이 없었어요")
        XCTAssertNotEqual(ArisJournalWords.unanswered(english: true), ArisJournalWords.declined(english: true))
    }
}
