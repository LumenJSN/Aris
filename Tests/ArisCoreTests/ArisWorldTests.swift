import XCTest
@testable import ArisCore

/// The world's snapshot (one value folded from each source's changes), the interruption policy as a table, the brief's
/// conditions and the deadline of a to-do without a time.
final class ArisWorldTests: XCTestCase {
    private typealias I = ArisInterruption

    // MARK: - Snapshot

    func testReadValuesArePublishedOnlyWhenTheyChange() {
        let app = ArisWorldSnapshot.App(name: "Xcode", bundleID: "com.apple.dt.Xcode", pid: 42)
        let (one, first) = ArisWorldSnapshot.reduce(ArisWorldSnapshot(), .frontApp(app))
        XCTAssertTrue(first)
        XCTAssertEqual(one.frontApp, app)
        XCTAssertFalse(ArisWorldSnapshot.reduce(one, .frontApp(app)).publish)
        let route = ArisWorldSnapshot.AudioRoute(output: .bluetoothHeadset, outputName: "AirPods", inputName: "AirPods")
        let (two, routed) = ArisWorldSnapshot.reduce(one, .audioRoute(route))
        XCTAssertTrue(routed)
        XCTAssertFalse(ArisWorldSnapshot.reduce(two, .audioRoute(route)).publish)
        XCTAssertFalse(ArisWorldSnapshot.reduce(two, .calendar([])).publish)
    }

    func testSystemNoticesArePublishedEachTimeTheyCome() {
        // A lock whose unlock never came, or a second unlock: each observer used to hear every one, so each is published.
        let (locked, _) = ArisWorldSnapshot.reduce(ArisWorldSnapshot(), .screenLocked(true))
        XCTAssertTrue(locked.locked && locked.screenAway)
        XCTAssertTrue(ArisWorldSnapshot.reduce(locked, .screenLocked(true)).publish)
        let (unlocked, _) = ArisWorldSnapshot.reduce(locked, .screenLocked(false))
        XCTAssertTrue(ArisWorldSnapshot.reduce(unlocked, .screenLocked(false)).publish)
        XCTAssertTrue(ArisWorldSnapshot.reduce(unlocked, .displays([])).publish)
        XCTAssertTrue(ArisWorldSnapshot.reduce(unlocked, .audioDevices).publish)
        let (asleep, _) = ArisWorldSnapshot.reduce(unlocked, .systemWillSleep)
        XCTAssertTrue(asleep.screenAway)
        XCTAssertFalse(ArisWorldSnapshot.reduce(asleep, .systemDidWake).0.screenAway)
        let (dark, _) = ArisWorldSnapshot.reduce(unlocked, .displaysAsleep(true))
        XCTAssertTrue(dark.screenAway)
    }

    func testAnotherFrontAppForgetsTheWindowTitle() {
        var world = ArisWorldSnapshot()
        world.frontApp = .init(name: "Notes", bundleID: nil, pid: 1)
        world.windowTitle = "Diary"
        XCTAssertNil(ArisWorldSnapshot.reduce(world, .frontApp(.init(name: "Mail", bundleID: nil, pid: 2))).0.windowTitle)
    }

    func testVoiceIsNewsOnlyWhenTheGateMoves() {
        let (talking, opened) = ArisWorldSnapshot.reduce(ArisWorldSnapshot(), .userVoice(talking: true, at: 10))
        XCTAssertTrue(opened)
        let (still, again) = ArisWorldSnapshot.reduce(talking, .userVoice(talking: true, at: 11))
        XCTAssertFalse(again)
        XCTAssertEqual(still.userVoiceAt, 11)
        XCTAssertTrue(ArisWorldSnapshot.reduce(still, .userVoice(talking: false, at: 12)).publish)
    }

    func testUserSpeakingHoldsAMomentAfterTheVoiceAndNotForever() {
        var world = ArisWorldSnapshot()
        XCTAssertFalse(world.userSpeaking(now: 100))
        world.userTalking = true
        world.userVoiceAt = 100
        XCTAssertTrue(world.userSpeaking(now: 130))
        XCTAssertFalse(world.userSpeaking(now: 100 + ArisWorldSnapshot.talkingStaleAfter + 1), "a gate stuck open stops counting")
        world.userTalking = false
        world.userVoiceAt = 200
        XCTAssertTrue(world.userSpeaking(now: 200.5))
        XCTAssertFalse(world.userSpeaking(now: 201.5))
    }

    func testChatterStaysOutOfTheRing() {
        XCTAssertTrue(ArisWorldChange.userVoice(talking: true, at: 1).isChatter)
        XCTAssertTrue(ArisWorldChange.claude(.init(name: "PreToolUse", sessionId: "s", at: .now)).isChatter)
        XCTAssertFalse(ArisWorldChange.claude(.init(name: "Stop", sessionId: "s", at: .now)).isChatter)
        XCTAssertFalse(ArisWorldChange.screenLocked(true).isChatter)
    }

    func testAWorldEventChangesNoTurn() {
        let (open, _) = ArisKernelState.reduce(ArisKernelState(), .turnOpened(.key))
        let (next, effects) = ArisKernelState.reduce(open, .world(.screenLocked(true)))
        XCTAssertEqual(next, open)
        XCTAssertEqual(effects, [])
    }

    func testOutputKinds() {
        XCTAssertEqual(ArisAudioOutputKind.of(transport: .builtIn, dataSource: "ispk", hasInput: true), .builtIn)
        XCTAssertEqual(ArisAudioOutputKind.of(transport: .builtIn, dataSource: "hdpn", hasInput: false), .wiredHeadphones)
        XCTAssertEqual(ArisAudioOutputKind.of(transport: .bluetooth, dataSource: nil, hasInput: true), .bluetoothHeadset)
        XCTAssertEqual(ArisAudioOutputKind.of(transport: .bluetooth, dataSource: nil, hasInput: false), .bluetoothSpeaker)
        XCTAssertEqual(ArisAudioOutputKind.of(transport: .other, dataSource: nil, hasInput: false), .other)
        XCTAssertEqual(ArisAudioOutputKind.allCases.filter(\.isHeadphones), [.wiredHeadphones, .bluetoothHeadset])
    }

    // MARK: - Interruption policy, as a table

    /// The moments of the table.
    private static let moments: [(String, I.Moment)] = [
        ("free", I.Moment()),
        ("locked", I.Moment(screenAway: true)),
        ("in a call", I.Moment(inCall: true)),
        ("user speaking", I.Moment(userSpeaking: true)),
        ("Aris speaking", I.Moment(arisSpeaking: true)),
        ("other audio", I.Moment(otherAudio: true)),
        ("headphones", I.Moment(headphones: true)),
        ("quiet", I.Moment(mayMakeSound: false)),
    ]

    /// Each kind as its callers ask (ArisNoticeRoute.want): urgency, a question waiting, a line to say.
    private static let wants: [I.Want] = [
        I.Want(kind: .answer, urgency: .normal, spoken: true),
        I.Want(kind: .jobDone, urgency: .normal, spoken: true),
        I.Want(kind: .teammateAsks, urgency: .normal, needsAnswer: true, spoken: true),
        I.Want(kind: .deadline, urgency: .high),
        I.Want(kind: .timer, urgency: .high),
        I.Want(kind: .brief, urgency: .low),
        I.Want(kind: .update, urgency: .low),
        I.Want(kind: .news, urgency: .low),
        I.Want(kind: .problem, urgency: .normal, spoken: true),
    ]

    /// Expected decision for each kind, in the order of `moments`.
    private static let table: [I.Kind: [I.Decision]] = [
        //              free     locked          call              user speaking                Aris speaking                other    headphones quiet
        .answer:       [.speak, .hold(.unlock), .show,            .hold(.userStopsSpeaking), .hold(.arisStopsSpeaking), .speak, .speak, .show],
        .jobDone:      [.speak, .hold(.unlock), .hold(.callEnds), .hold(.userStopsSpeaking), .hold(.arisStopsSpeaking), .speak, .speak, .show],
        .teammateAsks: [.speak, .hold(.unlock), .show,            .hold(.userStopsSpeaking), .hold(.arisStopsSpeaking), .speak, .speak, .show],
        .deadline:     [.show,  .hold(.unlock), .show,            .hold(.userStopsSpeaking), .hold(.arisStopsSpeaking), .show,  .show,  .show],
        .timer:        [.show,  .hold(.unlock), .show,            .hold(.userStopsSpeaking), .hold(.arisStopsSpeaking), .show,  .show,  .show],
        .brief:        [.show,  .hold(.unlock), .hold(.callEnds), .hold(.userStopsSpeaking), .hold(.arisStopsSpeaking), .show,  .show,  .show],
        .update:       [.show,  .hold(.unlock), .hold(.callEnds), .hold(.userStopsSpeaking), .hold(.arisStopsSpeaking), .show,  .show,  .show],
        .news:         [.show,  .hold(.unlock), .hold(.callEnds), .hold(.userStopsSpeaking), .hold(.arisStopsSpeaking), .show,  .show,  .show],
        .problem:      [.speak, .hold(.unlock), .hold(.callEnds), .hold(.userStopsSpeaking), .hold(.arisStopsSpeaking), .speak, .speak, .show],
    ]

    func testTheTable() {
        XCTAssertEqual(Set(Self.wants.map(\.kind)), Set(I.Kind.allCases))
        for want in Self.wants {
            let row = Self.table[want.kind]!
            for (index, (name, moment)) in Self.moments.enumerated() {
                XCTAssertEqual(I.decide(want, moment), row[index], "\(want.kind) when \(name)")
            }
        }
    }

    func testLowNewsWithALineDoesNotPauseTheMusic() {
        let low = I.Want(kind: .news, urgency: .low, spoken: true)
        XCTAssertEqual(I.decide(low, I.Moment()), .speak)
        XCTAssertEqual(I.decide(low, I.Moment(otherAudio: true)), .show)
        XCTAssertEqual(I.decide(I.Want(kind: .jobDone, spoken: true), I.Moment(otherAudio: true)), .speak, "the baseline: music pauses for it")
    }

    func testTheOrderOfHolds() {
        let job = I.Want(kind: .jobDone, spoken: true)
        XCTAssertEqual(I.decide(job, I.Moment(screenAway: true, inCall: true, userSpeaking: true)), .hold(.unlock))
        XCTAssertEqual(I.decide(job, I.Moment(inCall: true, userSpeaking: true, arisSpeaking: true)), .hold(.userStopsSpeaking))
        XCTAssertEqual(I.decide(job, I.Moment(inCall: true, arisSpeaking: true)), .hold(.arisStopsSpeaking))
        XCTAssertEqual(I.decide(I.Want(kind: .jobDone, empty: true), I.Moment()), .drop)
    }

    func testTheMomentFromTheSnapshot() {
        var world = ArisWorldSnapshot()
        world.locked = true
        world.otherAppRecording = "Zoom"
        world.audio = .init(output: .wiredHeadphones, outputName: nil, inputName: nil)
        world.arisSpeaking = true
        world.otherAudioPlaying = true
        world.userTalking = true
        world.userVoiceAt = 5
        let moment = I.moment(world, now: 6, mayMakeSound: false)
        XCTAssertEqual(moment, I.Moment(screenAway: true, inCall: true, userSpeaking: true, arisSpeaking: true, otherAudio: true,
                                        headphones: true, mayMakeSound: false))
    }

    // MARK: - The brief

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testTheBriefsFactsAndWhetherItHasNews() {
        let now = at(18, 8)
        let none = ArisBriefCheck.facts(agent: ["weather": ["temp": 3, "rain": 10], "dueCount": 0], eventStarts: [at(18, 7), at(19, 9)],
                                        now: now, calendar: calendar)
        XCTAssertEqual(none, .init(eventsLaterToday: 0, dueThisWeek: 0, announcements: 0, rainChance: 10))
        XCTAssertFalse(ArisBriefCheck.hasNews(none), "sun, nothing later today, nothing due: nothing to tell")
        XCTAssertTrue(ArisBriefCheck.hasNews(.init(eventsLaterToday: 1)))
        XCTAssertTrue(ArisBriefCheck.hasNews(.init(dueThisWeek: 2)))
        XCTAssertTrue(ArisBriefCheck.hasNews(.init(announcements: 1)))
        XCTAssertTrue(ArisBriefCheck.hasNews(.init(rainChance: 60)))
        let busy = ArisBriefCheck.facts(agent: ["due": [["at": "2026-11-19T17:00:00Z"]], "dueCount": 3, "announcements": 2],
                                        eventStarts: [at(18, 13)], now: now, calendar: calendar)
        XCTAssertEqual(busy, .init(eventsLaterToday: 1, dueThisWeek: 3, announcements: 2, rainChance: nil))
        XCTAssertEqual(ArisBriefCheck.facts(agent: [:], eventStarts: [], now: now, calendar: calendar), .init())
    }

    func testTheBriefsSteps() {
        let news = ArisBriefCheck.Facts(eventsLaterToday: 1)
        XCTAssertEqual(ArisBriefCheck.step(isDue: false, facts: news, moment: I.Moment()), .notDue)
        XCTAssertEqual(ArisBriefCheck.step(isDue: true, facts: .init(), moment: I.Moment()), .nothingToTell)
        XCTAssertEqual(ArisBriefCheck.step(isDue: true, facts: .init(), moment: I.Moment(inCall: true)), .nothingToTell)
        XCTAssertEqual(ArisBriefCheck.step(isDue: true, facts: news, moment: I.Moment()), .show)
        XCTAssertEqual(ArisBriefCheck.step(isDue: true, facts: news, moment: I.Moment(otherAudio: true)), .show, "it is silent: music plays on")
        XCTAssertEqual(ArisBriefCheck.step(isDue: true, facts: news, moment: I.Moment(inCall: true)), .wait(.callEnds))
        XCTAssertEqual(ArisBriefCheck.step(isDue: true, facts: news, moment: I.Moment(userSpeaking: true)), .wait(.userStopsSpeaking))
        XCTAssertEqual(ArisBriefCheck.step(isDue: true, facts: news, moment: I.Moment(screenAway: true)), .wait(.unlock))
    }

    // MARK: - Deadlines

    func testATimedToDoIsDueAtItsTime() {
        let due = at(20, 15, 30)
        XCTAssertEqual(ArisDeadlineDate.deadline(due, hasTime: true, calendar: calendar), due)
        XCTAssertTrue(ArisDeadlineDate.mayAlert(due, hasTime: true, now: at(19, 16), calendar: calendar))
    }

    func testAWholeDayToDoIsDueAtTheEndOfItsDay() {
        // EventKit gives a day without a time as that day's midnight.
        let due = at(20, 0)
        let deadline = ArisDeadlineDate.deadline(due, hasTime: false, calendar: calendar)
        XCTAssertEqual(deadline, at(20, 23, 59))
        XCTAssertFalse(ArisDeadlineDate.mayAlert(due, hasTime: false, now: at(19, 0), calendar: calendar), "no alert a day early")
        XCTAssertFalse(ArisDeadlineDate.mayAlert(due, hasTime: false, now: at(19, 23, 59), calendar: calendar))
        XCTAssertTrue(ArisDeadlineDate.mayAlert(due, hasTime: false, now: at(20, 0), calendar: calendar))
        // Measured from the end of the day, the 3 h alert comes at 20:59 on the day itself, not at 21:00 the evening before.
        let threeHours = deadline.addingTimeInterval(-3 * 3_600)
        XCTAssertEqual(threeHours, at(20, 20, 59))
    }

    func testAWholeDayToDoAcrossADaylightSavingChange() {
        // 2026-11-01 is the day the clocks go back in Orlando (25 hours long).
        let due = at(1, 0)
        XCTAssertEqual(ArisDeadlineDate.deadline(due, hasTime: false, calendar: calendar), at(1, 23, 59))
    }
}
