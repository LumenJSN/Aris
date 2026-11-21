import XCTest
@testable import ArisCore

/// The spoken-reference resolver (jv-fleet): a large table of Korean and English references against one fleet.
final class ArisFleetResolverTests: XCTestCase {
    let home = "/Users/p"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func session(_ number: Int, _ folder: String, _ state: ArisFleetState, tool: ArisFleetTool = .claudeCode, request: String? = nil,
                 message: String? = nil, started: TimeInterval, active: TimeInterval? = nil) -> ArisFleetSession {
        ArisFleetSession(id: "id-\(number)", tool: tool, number: number, pid: nil, folder: "/Users/p/Desktop/" + folder, branch: nil,
                         firstRequest: request, title: nil, state: state, lastTool: nil,
                         lastMessage: message.map { ArisFleetText(text: $0, source: "test") }, pending: nil,
                         startedAt: t0.addingTimeInterval(started), lastActive: t0.addingTimeInterval(active ?? started), starter: .user,
                         reach: ArisFleetReach(kind: .tmux))
    }

    var fleet: ArisFleet {
        ArisFleet(sessions: [
            session(1, "aris-jv-world", .working, request: "interruption policy 만들기", started: 0, active: 50),
            session(2, "altswitch", .idle, request: "fix the tab order tests", message: "All green.", started: 10, active: 400),
            session(3, "aris-jv-fleet", .waitingPermission, started: 20, active: 300),
            session(4, "site", .working, tool: .codex, request: "랜딩 페이지 디자인 수정", started: 30, active: 200),
            session(5, "boring-notch", .failed, started: 40, active: 100),
            session(6, "old", .gone, started: 50),
        ])
    }

    enum Want: Equatable { case one(Int), several([Int]), ask([Int]), none }

    func want(_ resolution: ArisFleetResolution) -> Want {
        switch resolution {
        case .one(let s): return .one(s.number)
        case .several(let list): return .several(list.map(\.number))
        case .ask(_, let list): return .ask(list.map(\.number))
        case .none: return .none
        }
    }

    func testTheTable() {
        let table: [(String, Want)] = [
            // Numbers.
            ("3", .one(3)), ("3번", .one(3)), ("3번한테", .one(3)), ("3번 세션", .one(3)), ("삼번", .one(3)), ("삼 번", .one(3)),
            ("세 번째", .one(3)), ("세번째 거", .one(3)), ("첫번째", .one(1)), ("다섯 번째", .one(5)), ("오번", .one(5)),
            ("number three", .one(3)), ("number 3", .one(3)), ("#3", .one(3)), ("no. 3", .one(3)), ("the third one", .one(3)),
            ("session 2", .one(2)), ("Number Two", .one(2)), ("9번", .none), ("number 6", .none),
            // Folders, in Latin and in Hangul.
            ("altswitch", .one(2)), ("the one in altswitch", .one(2)), ("altswitch에서", .one(2)), ("알트스위치", .one(2)),
            ("알트스위치 쪽", .one(2)), ("알트스위치에서 하는 애", .one(2)), ("site", .one(4)), ("사이트", .one(4)),
            ("아리스 하는 애", .ask([1, 3])), ("aris", .ask([1, 3])), ("jv-world", .one(1)), ("월드", .one(1)), ("플릿", .one(3)),
            ("아리스 월드", .one(1)), ("aris-jv-fleet", .one(3)), ("보링 노치", .one(5)), ("the one in boring", .one(5)),
            ("boring notch", .one(5)), ("~/Desktop/altswitch", .one(2)),
            // What it works on.
            ("the one fixing the tests", .one(2)), ("테스트 고치는 애", .one(2)), ("tab order", .one(2)),
            ("디자인 고치는 거", .one(4)), ("랜딩 페이지", .one(4)), ("interruption policy", .one(1)),
            // Its state.
            ("막힌 애", .ask([3, 5])), ("the stuck one", .ask([3, 5])), ("권한 기다리는 애", .one(3)),
            ("the one waiting for permission", .one(3)), ("에러 난 애", .one(5)), ("the one that failed", .one(5)),
            ("방금 끝난 애", .one(2)), ("the one that finished", .one(2)),
            // The tool.
            ("코덱스", .one(4)), ("codex", .one(4)), ("the codex one", .one(4)), ("클로드", .ask([1, 2, 3, 5])),
            // All of them.
            ("다들", .several([1, 2, 3, 4, 5])), ("all of them", .several([1, 2, 3, 4, 5])), ("전부", .several([1, 2, 3, 4, 5])),
            ("everyone", .several([1, 2, 3, 4, 5])), ("막힌 애들 다", .several([3, 5])), ("all the claude ones", .several([1, 2, 3, 5])),
            // The last one.
            ("마지막 거", .one(5)), ("the last one", .one(5)), ("방금 띄운 애", .one(5)), ("이번에 띄운 애", .one(5)), ("the newest", .one(5)),
            // Nothing fits, or it isn't said which.
            ("xyz", .none), ("the one in nowhere", .none), ("old", .none), ("", .ask([1, 2, 3, 4, 5])), ("그거", .ask([3, 5])),
            // An id after a question.
            ("id-4", .one(4)),
        ]
        for (reference, expected) in table {
            XCTAssertEqual(want(ArisFleetResolver.resolve(reference, in: fleet, home: home, english: false)), expected, reference)
        }
    }

    func testThatOneIsTheOneWaitingWhenOnlyOneWaits() {
        var one = fleet
        one.sessions = one.sessions.filter { $0.number != 5 }
        XCTAssertEqual(want(ArisFleetResolver.resolve("that one", in: one, home: home, english: true)), .one(3))
        XCTAssertEqual(want(ArisFleetResolver.resolve("걔", in: one, home: home, english: false)), .one(3))
    }

    func testTheQuestionAndLinesNameNumbersAndFolders() {
        guard case .ask(let question, _) = ArisFleetResolver.resolve("아리스 하는 애", in: fleet, home: home, english: false) else { return XCTFail() }
        XCTAssertEqual(question, "1번 aris-jv-world, 3번 aris-jv-fleet 중 어느 쪽이요?")
        guard case .ask(let english, _) = ArisFleetResolver.resolve("aris", in: fleet, home: home, english: true) else { return XCTFail() }
        XCTAssertEqual(english, "Which one: number 1 (aris-jv-world), number 3 (aris-jv-fleet)?")
        guard case .none(let line) = ArisFleetResolver.resolve("9번", in: fleet, home: home, english: false) else { return XCTFail() }
        XCTAssertTrue(line.hasPrefix("지금 9번 세션은 없어요."), line)
        guard case .none(let empty) = ArisFleetResolver.resolve("3번", in: ArisFleet(), home: home, english: false) else { return XCTFail() }
        XCTAssertEqual(empty, "지금 돌고 있는 코딩 세션이 없어요.")
    }

    func testNumbersInWords() {
        XCTAssertEqual(ArisFleetWords.number(in: "3번한테 테스트부터 돌리라고 해"), 3)
        XCTAssertNil(ArisFleetWords.number(in: "aris-jv-3"))
        XCTAssertNil(ArisFleetWords.number(in: "v2 branch"))
        XCTAssertNil(ArisFleetWords.number(in: "이번에"))
        XCTAssertNil(ArisFleetWords.number(in: "세 번 해 봐"), "세 번 is three times")
        XCTAssertEqual(ArisFleetWords.number(in: "십이번"), 12)
        XCTAssertEqual(ArisFleetWords.number(in: "이십일번"), 21)
        XCTAssertEqual(ArisFleetWords.sinoNumber("십"), 10)
    }

    func testSounds() {
        XCTAssertEqual(ArisFleetWords.skeleton("아리스"), ArisFleetWords.skeleton("aris"))
        XCTAssertEqual(ArisFleetWords.skeleton("알트스위치"), ArisFleetWords.skeleton("altswitch"))
        XCTAssertEqual(ArisFleetWords.skeleton("플릿"), ArisFleetWords.skeleton("fleet"))
        XCTAssertTrue(ArisFleetWords.soundsAlike("자비스", "jarvis"))
        XCTAssertFalse(ArisFleetWords.soundsAlike("아리스", "site"))
        XCTAssertFalse(ArisFleetWords.soundsAlike("가", "k"))
    }
}
