import XCTest
@testable import ArisCore

/// Tenth VM run, items 3 and 4: words that stand for content somewhere else, and the language of Aris's own lines.
final class ArisMind10aTests: XCTestCase {
    // MARK: - References to other content

    func testTheRecordedHijackIsAReference() {
        // turns.jsonl line 62: taken by the local to-do rule as a to-do called "이 문서에 적힌 미리 알림에".
        XCTAssertTrue(ArisContentReference.inSentence("이 문서에 적힌 할 일 미리 알림에 추가해 줘"))
        XCTAssertTrue(ArisContentReference.inArgument("이 문서에 적힌 미리 알림에"))
    }

    func testContentHeldSomewhereElse() {
        for words in ["여기 있는 거 할 일에 추가해 줘", "선택한 문장 할 일에 추가해 줘", "화면에 보이는 일정 할 일에 넣어 줘", "방금 말한 거 미리 알림에 추가해 줘",
                      "메일에 나온 마감들 할 일에 추가해 줘", "선택한 파일 열어 줘", "이 페이지에 있는 노래 틀어 줘", "그 메일에 적혀 있는 번호",
                      "add the tasks in this email to my reminders", "add what you just said to my to-do list", "open the selected file",
                      "open the link on this page", "remind me about the meeting mentioned above", "put everything on this page on my to-do list",
                      "add the highlighted text to my reminders", "Add The Tasks In This Email"] {
            XCTAssertTrue(ArisContentReference.inSentence(words), words)
            XCTAssertTrue(ArisContentReference.inArgument(words), words)
        }
    }

    func testAPlainRequestIsNoReference() {
        for words in ["내일 우유 사기 할 일에 추가해 줘", "할 일에 우유 사기 추가해 줘", "계산기 열어 줘", "볼륨 30으로 해 줘", "지금 몇 시야?", "방금 거 되돌려 줘",
                      "5분 타이머 맞춰 줘", "add buy milk to my to-do list", "remind me to call mom tomorrow", "open Safari", "set the volume to 30",
                      "할 일 목록에 우유 추가해 줘", "문서 정리하기 할 일에 추가해 줘", "remind me to file the taxes"] {
            XCTAssertFalse(ArisContentReference.inSentence(words), words)
        }
    }

    func testAPointingWordInWhatARuleWouldTake() {
        for words in ["이거", "그 보고서 검토", "여기 청소", "저 사람한테 전화", "that", "that report for Kim", "reply to this email", "send it to mom", "them",
                      "everything", "the thing above", "send it to Kim", "It needs a reply", "call that guy about the fence", "그 회의 자료 준비"] {
            XCTAssertTrue(ArisContentReference.inArgument(words), words)
        }
        for words in ["내일 우유 사기", "우유 사기", "이번 주 장보기", "그림 그리기", "저녁 준비", "이사 준비", "buy milk", "call mom this weekend",
                      "pay rent this month", "Safari", "계산기", "italian homework", "thesis draft",
                      "IT support ticket", "this week's report", "이거저거 정리하기"] {
            XCTAssertFalse(ArisContentReference.inArgument(words), words)
        }
    }

    // MARK: - The language of Aris's own lines

    func testAReplyFollowsTheRequest() {
        for uiEnglish in [true, false] {
            for words in ["지금 몇 시야?", "볼륨 30으로 해 줘", "방금 거 되돌려 줘", "Safari 열어 줘", "내일 우유 사기 할 일에 추가해 줘", "ㅇㅇ"] {
                XCTAssertTrue(ArisReplyLanguage.korean(request: words, uiEnglish: uiEnglish), words)
            }
            for words in ["what time is it", "set the volume to 30", "undo that", "open Safari", "add buy milk to my to-do list"] {
                XCTAssertFalse(ArisReplyLanguage.korean(request: words, uiEnglish: uiEnglish), words)
            }
        }
    }

    func testARequestThatShowsNoLanguageFollowsTheUI() {
        for words in ["", "30", "?!", "  "] {
            XCTAssertTrue(ArisReplyLanguage.korean(request: words, uiEnglish: false), words)
            XCTAssertFalse(ArisReplyLanguage.korean(request: words, uiEnglish: true), words)
        }
    }

    func testTheTurnsWordsDecideUntilTheNextTurn() {
        ArisReplyLanguage.heard("지금 몇 시야?")
        XCTAssertTrue(ArisReplyLanguage.korean(uiEnglish: true))
        ArisReplyLanguage.heard("what time is it")
        XCTAssertFalse(ArisReplyLanguage.korean(uiEnglish: false))
        // No turn (a button pressed): the UI's language.
        ArisReplyLanguage.heard(nil)
        XCTAssertTrue(ArisReplyLanguage.korean(uiEnglish: false))
        XCTAssertFalse(ArisReplyLanguage.korean(uiEnglish: true))
    }
}
