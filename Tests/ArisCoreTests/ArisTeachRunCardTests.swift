import XCTest
@testable import ArisCore

/// The run's one card and the short spoken questions (jv-quick).
final class ArisTeachRunCardTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let bundle = "com.apple.TextEdit"

    private func menu(_ path: [String], keys: String? = nil) -> ArisTeachStep {
        var step = ArisTeachStep(action: .menu, app: "TextEdit", bundle: bundle, label: path.last, menu: path)
        step.keys = keys
        return step
    }

    private func typed(_ place: ArisTeachStep.Place, startsLine: Bool = false) -> ArisTeachStep {
        var step = ArisTeachStep(action: .type, app: "TextEdit", bundle: bundle, target: "First Text View 칸", role: "textArea",
                                 label: ArisTeachGeneralise.bodyLabel, parameter: "p1")
        step.place = place
        step.startsLine = startsLine
        return step
    }

    private func procedure(_ name: String, _ steps: [ArisTeachStep], example: String? = nil) -> ArisTeachProcedure {
        ArisTeachProcedure(name: name, steps: steps,
                           parameters: example.map { [ArisTeachParameter(key: "p1", label: ArisTeachGeneralise.bodyLabel, example: $0, app: "TextEdit", fromApp: false)] } ?? [],
                           created: start)
    }

    private var replaceAll: ArisTeachProcedure {
        procedure("전체 바꾸기", [ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle), menu(["Edit", "Select All"], keys: "cmd+a"), typed(.all)],
                  example: "Replaced all")
    }

    private var addLine: ArisTeachProcedure {
        procedure("줄 추가", [ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle), menu(["Edit", "Select All"], keys: "cmd+a"), typed(.end, startsLine: true)],
                  example: "Added line")
    }

    private func plan(_ made: ArisTeachProcedure, given: [String: String] = [:]) -> ArisTeachReplay.Plan {
        ArisTeachReplay.plan(made, given: given, words: "\(made.name) 해 줘", run: "c1")
    }

    // MARK: - The one card

    func testTheCardNamesTheProcedureAndListsEveryStepAsItWillBeDone() {
        let made = replaceAll, plan = plan(made, given: ["p1": "회의는 3시"])
        let marks: [ArisTeachRunPass.Mark] = [.runs, .covered, .asksAgain]
        let korean = ArisTeachCopy.runCard(made, plan: plan, marks: marks, english: false)
        XCTAssertEqual(korean.card.title, "‘전체 바꾸기’ 3단계 할까요?")
        XCTAssertEqual(korean.card.detail.components(separatedBy: "\n"), [
            "저장한 단계 ‘전체 바꾸기’ 그대로예요.",
            "1. TextEdit 열기",
            "2. TextEdit에서 메뉴 ‘Edit › Select All’ 누르기",
            "3. TextEdit의 ‘본문’ 내용을 지우고 ‘회의는 3시’ 넣기 (원래 내용은 지워져요, 할 때마다 물어봐요)",
            "",
            "허용하면 위 단계를 이대로 한 번 해요. 달라지는 게 있으면 멈추고 다시 물어봐요.",
        ])
        XCTAssertNil(korean.card.full)
        XCTAssertTrue(korean.fields.isEmpty)
        let english = ArisTeachCopy.runCard(made, plan: plan, marks: marks, english: true)
        XCTAssertEqual(english.card.title, "Run “전체 바꾸기”, 3 steps?")
        XCTAssertEqual(english.card.detail.components(separatedBy: "\n"), [
            "From your saved steps “전체 바꾸기”.",
            "1. Open TextEdit",
            "2. In TextEdit, choose ‘Edit › Select All’",
            "3. In TextEdit, replace everything in the document's text with ‘회의는 3시’ (what was there is erased; asks each time)",
            "",
            "Allow runs these steps as shown, once. If anything differs, it stops and asks again.",
        ])
        // Each step's words are the step card's own.
        let described = ArisTeachReplay.described(made, plan: plan, english: false)
        for (index, call) in plan.calls.enumerated() {
            XCTAssertTrue(korean.card.detail.contains("\(index + 1). " + (described[call!.id]?.line ?? "?")))
        }
    }

    func testAStepThatAsksAgainIsMarkedPlainly() {
        let made = procedure("보고", [ArisTeachStep(action: .open, app: "TextEdit", bundle: bundle), menu(["Edit", "Select All"], keys: "cmd+a"),
                                    ArisTeachStep(action: .click, app: "TextEdit", bundle: bundle, target: "Send 버튼", role: "button", label: "Send")])
        let marks: [ArisTeachRunPass.Mark] = [.runs, .covered, .asksAgain]
        XCTAssertTrue(ArisTeachCopy.runCard(made, plan: plan(made), marks: marks, english: false).card.detail
            .contains("3. TextEdit에서 ‘Send’ 버튼 누르기 — 이 단계 전에 다시 물어봐요"))
        XCTAssertTrue(ArisTeachCopy.runCard(made, plan: plan(made), marks: marks, english: true).card.detail
            .contains("3. In TextEdit, press ‘Send’ — asks again before this step"))
        // A step with no mark known asks again (a miss is never less strict).
        XCTAssertTrue(ArisTeachCopy.runCard(made, plan: plan(made), marks: [.runs], english: false).card.detail.contains("Select All’ 누르기 — 이 단계 전에 다시 물어봐요"))
    }

    func testATypedStepsCardSaysAloudThatTextIsErasedWhenItTurnsOutToBe() {
        let made = addLine
        for english in [true, false] {
            let card = ArisTeachCopy.stepCard(made, at: 2, values: ["p1": "x"], ownerGave: ["p1"], english: english)
            XCTAssertEqual(card.spoken, english ? "“줄 추가”, step 3?" : "‘줄 추가’ 3단계, 할까요?")
            XCTAssertEqual(card.spokenErases, english ? "“줄 추가” step 3 erases TextEdit’s text. OK?" : "‘줄 추가’ 3단계, TextEdit 글이 지워져요. 할까요?")
            XCTAssertLessThanOrEqual(card.spokenErases?.count ?? 0, ArisTeachCopy.spokenLimit)
            XCTAssertNil(ArisTeachCopy.stepCard(made, at: 1, values: ["p1": "x"], english: english).spokenErases, "only typing can erase")
        }
    }

    func testARecordedValueIsSaidToBeReadFromTheApp() {
        let made = addLine
        let card = ArisTeachCopy.runCard(made, plan: plan(made), marks: [.runs, .covered, .runs], english: false).card
        // A value that looked typed by them is never said as read from the app (eleventh VM run, item 5).
        XCTAssertTrue(card.detail.hasPrefix("저장한 단계 ‘줄 추가’ 그대로예요. 넣는 글(‘↵Added line’)은 보여 주실 때의 지난번 값이에요. 이번에 말씀하신 값은 아니에요.\n"), card.detail)
        let his = ArisTeachCopy.runCard(made, plan: plan(made, given: ["p1": "내 글"]), marks: [.runs, .covered, .runs], english: false).card
        XCTAssertTrue(his.detail.hasPrefix("저장한 단계 ‘줄 추가’ 그대로예요.\n"), his.detail)
    }

    func testAValueHisWordsDidNotGiveIsAskedOnTheSameCard() {
        let made = addLine
        let missing = ArisTeachReplay.missing(made, given: [:])
        for english in [true, false] {
            let asked = ArisTeachCopy.runCard(made, plan: plan(made), marks: [.runs, .covered, .runs], missing: missing, english: english)
            let old = ArisTeachCopy.valuesCard(made, missing: missing, english: english)
            XCTAssertEqual(asked.fields.map(\.key), old.fields.map(\.key))
            XCTAssertEqual(asked.fields.map(\.value), old.fields.map(\.value))
            // The card's text ends with its fields' own lines, so everything above them is drawn as its note.
            let fields = asked.fields.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            XCTAssertTrue(asked.card.detail.hasSuffix("\n" + fields), asked.card.detail)
            XCTAssertNil(asked.card.full)
            // The values card's own notes: last time's value as a suggestion only (eleventh VM run, T2), and the new line.
            XCTAssertTrue(asked.card.detail.contains(english ? "Suggestion, last time's text: ‘Added line’ (not used unless you write it in)."
                                                             : "제안: 지난번 본문 ‘Added line’ (칸에 적어야 들어가요)."), asked.card.detail)
            XCTAssertEqual(asked.fields.map(\.value), [""])
            XCTAssertTrue(asked.card.detail.contains(english ? "It goes on a new line (↵)." : "새 줄(↵)에 넣어요."), asked.card.detail)
            // The step that types it shows the field, not a value he may still change.
            XCTAssertTrue(asked.card.detail.contains(english ? "‘↵[text]’ in the document's text, on a new line (the value in the field below)"
                                                             : "‘↵[본문]’ 넣기 (아래 칸의 값)"), asked.card.detail)
            // No recorded value is said as what will be typed: only as the suggestion.
            XCTAssertEqual(asked.card.detail.components(separatedBy: "Added line’").count, 2, "no recorded value is said as what will be typed")
        }
    }

    func testALongProcedureShowsItsFirstStepsAndTheWholeOnShowAll() {
        let steps = (1...14).map { menu(["Format", "Command \($0)"]) }
        let made = procedure("긴 것", steps)
        let card = ArisTeachCopy.runCard(made, plan: plan(made), marks: Array(repeating: .covered, count: 14), english: false).card
        XCTAssertTrue(card.detail.contains("10. ") && !card.detail.contains("11. ") && card.detail.contains("… 외 4단계"), card.detail)
        XCTAssertTrue(card.full?.contains("14. TextEdit에서 메뉴 ‘Format › Command 14’ 누르기") == true)
        XCTAssertTrue(card.full?.hasSuffix("달라지는 게 있으면 멈추고 다시 물어봐요.") == true && card.detail.hasSuffix("달라지는 게 있으면 멈추고 다시 물어봐요."))
        // With a value to fill in, the card has no "show all": every step is on it.
        let long = procedure("긴 것", steps + [typed(.end)], example: "x")
        let asked = ArisTeachCopy.runCard(long, plan: plan(long), marks: Array(repeating: .covered, count: 15), missing: ArisTeachReplay.missing(long, given: [:]), english: false)
        XCTAssertTrue(asked.card.detail.contains("14. ") && asked.card.detail.contains("15. ") && asked.card.full == nil)
    }

    func testOneStepIsOneCard() {
        let made = procedure("전체 선택", [menu(["Edit", "Select All"], keys: "cmd+a")])
        XCTAssertEqual(ArisTeachCopy.runCard(made, plan: plan(made), marks: [.covered], english: false).card.title, "‘전체 선택’ 1단계 할까요?")
        XCTAssertEqual(ArisTeachCopy.runCard(made, plan: plan(made), marks: [.covered], english: true).card.title, "Run “전체 선택”, 1 step?")
    }

    // MARK: - Short spoken questions

    func testTheRunsQuestionIsShort() {
        let made = replaceAll
        XCTAssertEqual(ArisTeachCopy.runCard(made, plan: plan(made), marks: [], english: false).spoken, "‘전체 바꾸기’ 3단계, 할까요?")
        XCTAssertEqual(ArisTeachCopy.runCard(made, plan: plan(made), marks: [], english: true).spoken, "Run “전체 바꾸기”, 3 steps?")
    }

    func testAStepsQuestionIsShortAndStillSaysWhatItErasesOrSends() {
        let made = replaceAll, plan = plan(made, given: ["p1": "회의는 3시"])
        func spoken(_ index: Int, english: Bool) -> String { ArisTeachCopy.stepCard(made, at: index, values: plan.values, ownerGave: plan.ownerGave, english: english).spoken }
        XCTAssertEqual(spoken(1, english: false), "‘전체 바꾸기’ 2단계, 할까요?")
        XCTAssertEqual(spoken(1, english: true), "“전체 바꾸기”, step 2?")
        XCTAssertEqual(spoken(2, english: false), "‘전체 바꾸기’ 3단계, TextEdit 글이 지워져요. 할까요?")
        XCTAssertEqual(spoken(2, english: true), "“전체 바꾸기” step 3 erases TextEdit’s text. OK?")
        let sends = procedure("보고", [ArisTeachStep(action: .click, app: "Mail", bundle: "com.apple.mail", target: "보내기 버튼", role: "button", label: "보내기"),
                                     menu(["File", "Move to Trash"])])
        XCTAssertEqual(ArisTeachCopy.stepCard(sends, at: 0, values: [:], english: false).spoken, "‘보고’ 1단계, ‘보내기’ 눌러요. 할까요?")
        XCTAssertEqual(ArisTeachCopy.stepCard(sends, at: 0, values: [:], english: true).spoken, "“보고” step 1 presses ‘보내기’. OK?")
        XCTAssertEqual(ArisTeachCopy.stepCard(sends, at: 1, values: [:], english: false).spoken, "‘보고’ 2단계, ‘Move to Trash’ 눌러요. 할까요?")
    }

    func testEverySpokenQuestionIsBounded() {
        let name = String(repeating: "아주 긴 이름 ", count: 30)
        let label = String(repeating: "Delete everything now ", count: 20)
        var replace = typed(.all)
        replace.app = String(repeating: "LongAppName", count: 10)
        let made = procedure(name, [replace, ArisTeachStep(action: .click, app: "Mail", bundle: "com.apple.mail", target: "x", role: "button", label: label),
                                    menu(["Edit", "Select All"])], example: "x")
        for english in [true, false] {
            for index in made.steps.indices {
                let spoken = ArisTeachCopy.stepCard(made, at: index, values: ["p1": "x"], english: english).spoken
                XCTAssertLessThanOrEqual(spoken.count, ArisTeachCopy.spokenLimit, spoken)
            }
            let run = ArisTeachCopy.runCard(made, plan: plan(made), marks: [], english: english).spoken
            XCTAssertLessThanOrEqual(run.count, ArisTeachCopy.spokenLimit, run)
            // Cut short, the erasing and the pressing are still said.
            XCTAssertTrue(ArisTeachCopy.stepCard(made, at: 0, values: ["p1": "x"], english: english).spoken.contains(english ? "erases" : "지워져요"))
            XCTAssertTrue(ArisTeachCopy.stepCard(made, at: 1, values: [:], english: english).spoken.contains(english ? "presses ‘Delete" : "‘Delete"))
        }
        XCTAssertEqual(ArisTeachCopy.spokenLimit, 60)
    }
}
