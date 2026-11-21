import XCTest
@testable import ArisCore

/// A card's spoken answer (jv-voiceyes): the natural answers to "실행할까요?" / "Run it?" are a yes, the whole
/// utterance only; a no or a negation anywhere is never a yes; a lone "어" or "음" and anything longer answer nothing.
final class ArisAnswerWordsTests: XCTestCase {
    static let yes = [
        // As before.
        "네", "응", "예.", "그래", "좋아", "좋아요", "해 줘", "해줘", "보내", "보내 줘", "오케이", "yes", "Yeah sure", "OK", "go ahead", "do it",
        "어 그래", "네 좋아요", "응, 보내",
        // The card asks "실행할까요?" and its button says 허용.
        "실행해", "실행 해", "실행해 줘", "실행해줘", "실행 해 줘", "실행해요", "실행해 주세요",
        "허용", "허용해", "허용 해", "허용해 줘", "허용해줘", "허용해요", "허용해 주세요", "허용이요",
        "진행해", "진행 해", "진행해 줘", "진행해줘", "진행해요", "진행해 주세요",
        "해", "해요", "해 주세요", "어 해", "어, 해", "음 해 줘",
        "응응", "응 응", "네네", "네 네",
        "그렇게 해", "그렇게 해 줘", "그렇게 해줘", "그렇게 해요", "그렇게 해 주세요",
        "해도 돼", "해도 돼요", "해도돼",
        // One or two of them.
        "네 실행해", "응 허용", "그래 해", "응 진행해 줘", "네, 해도 돼요", "어 응 실행해",
        // English.
        "run it", "Run it.", "yes run it", "allow", "allow it", "Allow it!", "proceed", "go for it", "yes please", "please do", "sure, go ahead",
    ]

    static let no = [
        "아니", "아니요", "취소", "그만", "하지 마", "안 돼", "안 해", "no", "Nope", "cancel", "never mind",
        "실행하지 마", "실행 하지 마", "실행하지 마요", "허용 안 해", "허용 안 돼", "허용하지 마", "진행하지 마", "해 줘 말고 취소", "안 해도 돼",
        "해도 안 돼", "응 아니 하지 마", "실행해 아니 취소", "don't run it", "do not run it, stop", "allow it, no cancel", "yes but not now",
    ]

    static let notAnAnswer = [
        "", "어", "음", "어…", "음 어", "잠깐만", "뭐라고?", "what",
        // A negation the card's no words do not name: never a yes.
        "해 줘 말고", "허용하지 않아", "실행 말고", "허용은 싫어",
        // A sentence that only has a yes word in it.
        "아빠한테 보내", "보내고 나서 알려줘", "해당 없어", "실행해 보고 알려 줘", "허용 범위가 뭐야", "진행 상황 알려 줘", "내일로 해", "7시로 해 줘",
        "네 근데 그거", "실행", "진행", "해도 돼?", "해 봐", "허용해도 되는지 모르겠어", "그렇게 해도 되나",
        "run", "run it tomorrow", "allow it for dad", "ok send it to dad instead", "proceed with caution and tell me",
        // Three yes words are a sentence, not a short yes.
        "네 응 그래 해",
    ]

    func testNaturalAnswersToRunItAreYes() {
        for phrase in Self.yes { XCTAssertEqual(ArisAnswerWords.answer(phrase), true, "“\(phrase)” is a yes") }
    }

    func testANoOrNegationAnywhereWins() {
        for phrase in Self.no { XCTAssertEqual(ArisAnswerWords.answer(phrase), false, "“\(phrase)” is a no") }
    }

    func testAnythingElseAnswersNothing() {
        for phrase in Self.notAnAnswer { XCTAssertNil(ArisAnswerWords.answer(phrase), "“\(phrase)” is no answer") }
    }

    /// The trust policy's "always" reading looks for an affirmative inside a sentence: the new short words are not
    /// part of it ("해" is in almost every Korean sentence), so a sentence with "앞으로" never becomes standing consent
    /// by them.
    func testStandingConsentIsNotWidened() {
        XCTAssertNil(ArisAskAnswer.parse("앞으로 그러면 곤란해"))
        XCTAssertNil(ArisAskAnswer.parse("항상 조심해"))
        XCTAssertNil(ArisAskAnswer.parse("앞으로 허용 범위 알려 줘"))
        XCTAssertEqual(ArisAskAnswer.parse("응, 앞으로도 그렇게 해"), .always)
        XCTAssertEqual(ArisAskAnswer.parse("실행해"), .yes)
        XCTAssertEqual(ArisAskAnswer.parse("허용 안 해"), .no)
        XCTAssertEqual(ArisAskAnswer.parse("실행하지 마"), .no)
    }
}
