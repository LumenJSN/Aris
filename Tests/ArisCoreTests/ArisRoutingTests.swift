import XCTest
@testable import ArisCore

/// The funnel's pure pieces: whole commands, spoken lengths, level changes, the tier without the router.
final class ArisRoutingTests: XCTestCase {
    // MARK: - Whole commands

    private let volume = ["볼륨", "소리", "음량", "volume", "sound"]
    private let volumeWords = ["올려", "줄여", "낮춰", "키워", "크게", "작게", "조금", "더", "turn", "up", "down", "a", "bit", "set", "to"]

    func testACommandSaidAloneIsWhole() {
        XCTAssertTrue(ArisWholeCommand.isWhole("볼륨 올려", core: volume, words: volumeWords))
        XCTAssertTrue(ArisWholeCommand.isWhole("아리스, 볼륨 좀 올려 줄래", core: volume, words: volumeWords))
        XCTAssertTrue(ArisWholeCommand.isWhole("볼륨좀올려줘", core: volume, words: volumeWords))
        XCTAssertTrue(ArisWholeCommand.isWhole("소리를 조금 줄여 주세요", core: volume, words: volumeWords))
        XCTAssertTrue(ArisWholeCommand.isWhole("please turn the volume down a bit", core: volume, words: volumeWords))
        XCTAssertTrue(ArisWholeCommand.isWhole("볼륨 30으로", core: volume, words: volumeWords, numbers: true))
        XCTAssertTrue(ArisWholeCommand.isWhole("set the volume to 30%", core: volume, words: volumeWords, numbers: true))
    }

    func testAKeywordInsideALongerSentenceIsNot() {
        XCTAssertFalse(ArisWholeCommand.isWhole("엄마가 소리 좀 낮춰 달래", core: volume, words: volumeWords))
        XCTAssertFalse(ArisWholeCommand.isWhole("아이가 소리를 너무 크게 내서 조용히 시키는 법", core: volume, words: volumeWords))
        XCTAssertFalse(ArisWholeCommand.isWhole("잔소리 줄여", core: volume, words: volumeWords))
        XCTAssertFalse(ArisWholeCommand.isWhole("louder music makes me happy", core: ["louder"], words: volumeWords))
        XCTAssertFalse(ArisWholeCommand.isWhole("볼륨 30", core: volume, words: volumeWords), "a number only where numbers are allowed")
        XCTAssertFalse(ArisWholeCommand.isWhole("올려 줘", core: volume, words: volumeWords), "the command's own word must be there")
    }

    // MARK: - Spoken lengths

    func testLengthsWithHalvesAndDecimals() {
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "타이머 25분"), 1_500)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "1시간 30분"), 5_400)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "1시간 반 타이머"), 5_400)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "1시간반"), 5_400)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "5분 반"), 330)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "타이머 1.5시간"), 5_400)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "2.5분 타이머"), 150)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "반 시간 타이머"), 1_800)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "timer for 90 seconds"), 90)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "set a timer for 1.5 hours"), 5_400)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "2 hours and a half"), 9_000)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "half an hour"), 1_800)
        XCTAssertEqual(ArisSpokenDuration.seconds(in: "5 more minutes"), 300)
        XCTAssertNil(ArisSpokenDuration.seconds(in: "타이머"))
        XCTAssertNil(ArisSpokenDuration.seconds(in: "반반 나눠"))
    }

    func testLengthsAreSaidBack() {
        XCTAssertEqual(ArisSpokenDuration.korean(5_400), "1시간 30분")
        XCTAssertEqual(ArisSpokenDuration.korean(330), "5분 30초")
        XCTAssertEqual(ArisSpokenDuration.english(5_400), "1 hour 30 minutes")
        XCTAssertEqual(ArisSpokenDuration.english(60), "1 minute")
        XCTAssertEqual(ArisSpokenDuration.english(90), "1 minute 30 seconds")
    }

    // MARK: - Level changes

    func testAbsoluteNumbersSetTheLevel() {
        XCTAssertEqual(ArisLevelChange.read("볼륨 30", direction: nil), .to(30))
        XCTAssertEqual(ArisLevelChange.read("볼륨 30으로 올려", direction: 1), .to(30))
        XCTAssertEqual(ArisLevelChange.read("set the volume to 40", direction: nil), .to(40))
        XCTAssertEqual(ArisLevelChange.read("볼륨 최대로", direction: nil), .to(100))
        XCTAssertEqual(ArisLevelChange.read("볼륨 최소로 줄여", direction: -1), .to(0))
    }

    func testRelativeRequestsMoveFromTheCurrentLevel() {
        XCTAssertEqual(ArisLevelChange.read("볼륨 10 줄여", direction: -1), .by(-10))
        XCTAssertEqual(ArisLevelChange.read("turn the volume up by 20", direction: 1), .by(20))
        XCTAssertEqual(ArisLevelChange.read("볼륨 두 칸 올려".replacingOccurrences(of: "두", with: "2"), direction: 1), .steps(2))
        XCTAssertEqual(ArisLevelChange.read("볼륨 조금 줄여", direction: -1), .steps(-0.5))
        XCTAssertEqual(ArisLevelChange.read("turn it down a bit", direction: -1), .steps(-0.5))
        XCTAssertEqual(ArisLevelChange.read("많이 올려", direction: 1), .steps(2))
        XCTAssertEqual(ArisLevelChange.read("볼륨 반으로 줄여", direction: -1), .scaled(0.5))
        XCTAssertEqual(ArisLevelChange.read("cut the volume in half", direction: -1), .scaled(0.5))
        XCTAssertNil(ArisLevelChange.read("볼륨 올려", direction: 1), "no amount: the usual step")
        XCTAssertNil(ArisLevelChange.read("더 크게", direction: 1), "더 alone is the usual step")
    }

    func testTargetsStayOnTheScale() {
        XCTAssertEqual(ArisLevelChange.by(-10).target(from: 50, step: 6), 40)
        XCTAssertEqual(ArisLevelChange.steps(-0.5).target(from: 50, step: 6), 47)
        XCTAssertEqual(ArisLevelChange.scaled(0.5).target(from: 50, step: 6), 25)
        XCTAssertEqual(ArisLevelChange.by(30).target(from: 90, step: 6), 100)
        XCTAssertEqual(ArisLevelChange.by(-30).target(from: 10, step: 6), 0)
        XCTAssertEqual(ArisLevelChange.to(30).target(from: 90, step: 6), 30)
    }

    // MARK: - The tier without the router

    func testPlainQuestionsAreQuickAndWorkIsWork() {
        XCTAssertFalse(ArisLocalTier.isWork("오늘 날씨 어때", looksUp: false, pointsAtScreen: false))
        XCTAssertFalse(ArisLocalTier.isWork("what's the capital of france", looksUp: false, pointsAtScreen: false))
        XCTAssertTrue(ArisLocalTier.isWork("프로젝트 어떻게 되고 있어", looksUp: true, pointsAtScreen: false))
        XCTAssertTrue(ArisLocalTier.isWork("이 화면 설명해 줘", looksUp: false, pointsAtScreen: true))
        XCTAssertTrue(ArisLocalTier.isWork("report.pdf 요약해 줘", looksUp: false, pointsAtScreen: false))
        XCTAssertTrue(ArisLocalTier.isWork("이번 주 회의록을 정리해서 팀원들한테 보낼 메일 초안을 세 가지 버전으로 써 주고 제목도 붙여 줘",
                                           looksUp: false, pointsAtScreen: false))
        XCTAssertTrue(ArisLocalTier.isWork("write a short cover letter for a junior developer job at a small startup in orlando please",
                                           looksUp: false, pointsAtScreen: false))
    }
}
