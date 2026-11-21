import XCTest
@testable import ArisCore

/// jv-perms: the permission model's states, ask-once, degrade paths, grants made in System Settings, relaunch offers,
/// the setup list for every combination of chosen features, and the pane watch.
final class ArisPermissionsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let mic = ArisPermissionKey(.microphone)
    private let ax = ArisPermissionKey(.accessibility)
    private let screen = ArisPermissionKey(.screenRecording)
    private let disk = ArisPermissionKey(.fullDiskAccess)
    private let desktop = ArisPermissionKey(.desktopFolder)
    private let music = ArisPermissionKey.automation("com.apple.Music")

    private func model(_ states: [ArisPermissionKey: ArisPermissionState]) -> ArisPermissions {
        states.reduce(ArisPermissions()) { $0.updating($1.key, to: ArisPermissionReading(state: $1.value)).0 }
    }

    // MARK: Catalog

    func testEveryPermissionHasAnExactSettingsLink() {
        for permission in ArisPermission.allCases {
            XCTAssertTrue(permission.paneLink.hasPrefix("x-apple.systempreferences:"), permission.rawValue)
        }
        XCTAssertEqual(ArisPermission.accessibility.paneLink, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertEqual(ArisPermission.inputMonitoring.paneLink, "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        XCTAssertEqual(ArisPermission.loginItem.paneLink, "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    func testEveryFeatureSaysWhyInBothLanguages() {
        for feature in ArisPermissionFeature.allCases {
            XCTAssertFalse(feature.needs.isEmpty, feature.rawValue)
            XCTAssertFalse(feature.reason(english: false).isEmpty)
            XCTAssertTrue(feature.reason(english: true).hasSuffix("."), feature.rawValue)
            XCTAssertEqual(feature.needs.contains(.automation), !feature.automationTargets.isEmpty, feature.rawValue)
        }
    }

    func testReadingTheScreenNeedsNoScreenRecording() {
        XCTAssertEqual(ArisPermissionFeature.screenText.needs, [.accessibility])
        XCTAssertFalse(ArisPermissionFeature.appControl.needs.contains(.screenRecording))
        XCTAssertTrue(ArisPermissionFeature.screenPicture.needs.contains(.screenRecording))
    }

    // MARK: require: every state

    func testGrantedProceeds() {
        let (next, decision) = model([mic: .granted]).require(mic, for: .talk, now: t0)
        XCTAssertEqual(decision, .proceed)
        XCTAssertNil(next.record(mic).askedAt)
    }

    func testNotAskedPromptKindAsksOnceWithTheReason() {
        let start = model([mic: .notAsked])
        let (asked, first) = start.require(mic, for: .talk, now: t0)
        XCTAssertEqual(first, .prompt(mic, reason: ArisPermissionFeature.talk.reason(english: false)))
        XCTAssertEqual(asked.record(mic).askedAt, t0)
        // The dialog was closed without an answer: asked once already, so the second time it is told, not asked.
        let (told, second) = asked.require(mic, for: .talk, now: t0)
        XCTAssertEqual(second, .tellOff(mic, link: ArisPermission.microphone.paneLink, reason: ArisPermissionFeature.talk.reason(english: false)))
        let (_, third) = told.require(mic, for: .talk, now: t0)
        XCTAssertEqual(third, .doWithout(mic))
    }

    func testNotAskedPaneKindOpensThePaneOnce() {
        let (asked, decision) = model([ax: .notAsked]).require(ax, for: .appControl, english: true, now: t0)
        XCTAssertEqual(decision, .openPane(ax, link: ArisPermission.accessibility.paneLink, reason: ArisPermissionFeature.appControl.reason(english: true)))
        if case .openPane = asked.require(ax, for: .appControl, now: t0).1 { XCTFail("the pane opened twice") }
    }

    func testDeniedIsToldOnceThenDoneWithout() {
        let start = model([ArisPermissionKey(.calendars): .denied])
        let key = ArisPermissionKey(.calendars)
        let (told, first) = start.require(key, for: .calendar, now: t0)
        guard case .tellOff(key, let link, _) = first else { return XCTFail("\(first)") }
        XCTAssertEqual(link, ArisPermission.calendars.paneLink)
        XCTAssertEqual(told.require(key, for: .calendar, now: t0).1, .doWithout(key))
    }

    func testOnUseKindsSayWhyAndLetMacOSAsk() {
        let (asked, decision) = model([desktop: .notAsked]).require(desktop, for: .fileActions, now: t0)
        XCTAssertEqual(decision, .proceedAfterSaying(desktop, reason: ArisPermissionFeature.fileActions.reason(english: false)))
        // Unknown (a target app that isn't running) is the same: macOS asks at the first Apple Event.
        XCTAssertEqual(ArisPermissions().require(music, for: .music, now: t0).1, .proceedAfterSaying(music, reason: ArisPermissionFeature.music.reason(english: false)))
        XCTAssertEqual(asked.updating(desktop, to: .init(state: .granted)).0.require(desktop, for: .fileActions).1, .proceed)
    }

    func testAppleEventOnlyFeaturesNameOneAppAndSayWhyOnceAtFirstUse() {
        // jv-prompts: Notes, a contact lookup and System Events' restart / shut down / log out have no other way in.
        XCTAssertEqual(ArisPermissionFeature.notes.automationTargets, ["com.apple.Notes"])
        XCTAssertEqual(ArisPermissionFeature.findContact.automationTargets, ["com.apple.AddressBook"])
        XCTAssertEqual(ArisPermissionFeature.power.automationTargets, ["com.apple.systemevents"])
        let notes = ArisPermissionKey.automation("com.apple.Notes")
        let (asked, first) = model([notes: .notAsked]).require(.notes, now: t0)
        XCTAssertEqual(first, .proceedAfterSaying(notes, reason: ArisPermissionFeature.notes.reason(english: false)))
        XCTAssertNotNil(asked.record(notes).askedAt)
        XCTAssertEqual(asked.updating(notes, to: .init(state: .granted)).0.require(.notes).1, .proceed)
        // Refused in macOS's dialog: told once, then done without.
        let (told, off) = asked.updating(notes, to: .init(state: .denied)).0.require(.notes, now: t0)
        XCTAssertEqual(off, .tellOff(notes, link: ArisPermission.automation.paneLink, reason: ArisPermissionFeature.notes.reason(english: false)))
        XCTAssertEqual(told.require(.notes).1, .doWithout(notes))
    }

    func testUnknownPaneKindIsTriedNotAsked() {
        // Full Disk Access before the helper answered: the read itself says what it lacked.
        XCTAssertEqual(ArisPermissions().require(disk, for: .messagesRead, now: t0).1, .proceed)
    }

    func testFullDiskAccessStandsInForTheFolders() {
        let m = model([disk: .granted, desktop: .notAsked])
        XCTAssertEqual(m.require(desktop, for: .fileActions).1, .proceed)
        XCTAssertTrue(m.ready(.fileActions))
    }

    func testFeatureRequireStopsAtTheFirstMissing() {
        let m = model([mic: .granted, ArisPermissionKey(.speechRecognition): .notAsked, ax: .notAsked])
        let (next, decision) = m.require(.dictation, now: t0)
        guard case .prompt(let key, _) = decision else { return XCTFail("\(decision)") }
        XCTAssertEqual(key, ArisPermissionKey(.speechRecognition))
        XCTAssertNil(next.record(ax).askedAt)
        XCTAssertEqual(model([mic: .granted, ArisPermissionKey(.speechRecognition): .granted]).require(.talk).1, .proceed)
    }

    func testAutomationIsOneKeyPerTarget() {
        let keys = ArisPermissions().keys(for: .music)
        XCTAssertEqual(keys, [.automation("com.apple.Music"), .automation("com.spotify.client")])
        XCTAssertEqual(music.description, "automation:com.apple.Music")
    }

    // MARK: Readings

    func testGrantInSystemSettingsIsNoticedAndClearsTheTelling() {
        let (told, _) = model([ax: .denied]).require(ax, for: .appControl, now: t0)
        let (granted, changes) = told.updating(ax, to: .init(state: .granted))
        XCTAssertEqual(changes, [.granted(ax)])
        XCTAssertNil(granted.record(ax).toldOffAt)
        // Switched off again later: told again, once.
        let (off, offChanges) = granted.updating(ax, to: .init(state: .denied))
        XCTAssertEqual(offChanges, [.refused(ax)])
        if case .tellOff = off.require(ax, for: .appControl, now: t0).1 {} else { XCTFail("not told again") }
    }

    func testSameReadingTwiceChangesNothing() {
        let m = model([mic: .granted])
        XCTAssertEqual(m.updating(mic, to: .init(state: .granted)).1, [])
        XCTAssertEqual(m.updating(mic, to: .unknown).0.state(mic), .granted)
    }

    func testAskOutcomeIsRecorded() {
        let (asked, _) = model([mic: .notAsked]).require(mic, for: .talk, now: t0)
        XCTAssertEqual(asked.updating(mic, to: .init(state: .denied)).0.record(mic).outcome, .denied)
        XCTAssertEqual(asked.updating(mic, to: .init(state: .granted)).0.record(mic).outcome, .granted)
    }

    func testScreenRecordingGrantThatNeedsARelaunchIsOfferedOnce() {
        let (waiting, changes) = model([screen: .notAsked]).updating(screen, to: .init(state: .granted, needsRelaunch: true))
        XCTAssertEqual(changes, [.relaunchNeeded(screen)])
        XCTAssertFalse(waiting.satisfied(screen))
        let (offered, decision) = waiting.require(screen, for: .screenPicture, now: t0)
        XCTAssertEqual(decision, .offerRelaunch(screen))
        XCTAssertEqual(offered.require(screen, for: .screenPicture, now: t0).1, .doWithout(screen))
        XCTAssertEqual(offered.updating(screen, to: .init(state: .granted, needsRelaunch: true)).1, [])
        // After the relaunch the fresh reading is plain granted.
        let (after, afterChanges) = offered.relaunched().updating(screen, to: .init(state: .granted))
        XCTAssertEqual(afterChanges, [.granted(screen)])
        XCTAssertEqual(after.require(screen, for: .screenPicture).1, .proceed)
    }

    func testRelaunchIsNeverOfferedForAPermissionMacOSAppliesLive() {
        let (m, changes) = ArisPermissions().updating(ax, to: .init(state: .granted, needsRelaunch: true))
        XCTAssertEqual(changes, [.granted(ax)])
        XCTAssertTrue(m.satisfied(ax))
    }

    func testRecordsSurviveARelaunchStatesDoNot() {
        let (asked, _) = model([mic: .notAsked]).require(mic, for: .talk, now: t0)
        let restored = ArisPermissions.restored(from: asked.saved)
        XCTAssertEqual(restored.record(mic).askedAt, t0)
        XCTAssertEqual(restored.state(mic), .unknown)
        XCTAssertEqual(ArisPermissions.restored(from: Data("junk".utf8)), ArisPermissions())
        // Asked before the relaunch, still not on: told, not asked again.
        if case .tellOff = restored.updating(mic, to: .init(state: .notAsked)).0.require(mic, for: .talk).1 {} else { XCTFail() }
    }

    func testALineToldByAFeatureCountsAsToldUntilTheSwitchIsOn() {
        let told = model([screen: .notAsked]).notingToldOff(screen, at: t0)
        XCTAssertEqual(told.record(screen).toldOffAt, t0)
        XCTAssertEqual(told.notingToldOff(screen, at: t0.addingTimeInterval(9)).record(screen).toldOffAt, t0)
        XCTAssertNil(told.updating(screen, to: .init(state: .granted)).0.record(screen).toldOffAt)
        XCTAssertEqual(ArisPermissions().notingRelaunchOffered(screen, at: t0).record(screen).relaunchOfferedAt, t0)
    }

    // MARK: Setup list

    func testNothingChosenNothingAsked() {
        XCTAssertEqual(ArisPermissionSetup.list(for: [], in: ArisPermissions()), [])
        XCTAssertNil(ArisPermissionSetup.next(for: [], in: ArisPermissions()))
    }

    func testSetupListForEveryCombinationOfChosenFeatures() {
        // The list depends on a choice only through what the chosen features need: one feature for each distinct set
        // of needs, and every subset of those, is every combination there is.
        var seen: Set<[ArisPermission]> = []
        let features = ArisPermissionFeature.allCases.filter { seen.insert($0.needs).inserted }
        XCTAssertGreaterThanOrEqual(features.count, 12)
        let fresh = model(Dictionary(uniqueKeysWithValues: ArisPermission.allCases.map { (ArisPermissionKey($0), ArisPermissionState.notAsked) }))
        for mask in 0..<(1 << features.count) {
            let chosen = Set(features.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
            let list = ArisPermissionSetup.list(for: chosen, in: fresh)
            let needed = Set(chosen.flatMap { f in f.needs.filter { !f.askedAtFirstUse.contains($0) } }).filter { ArisPermissionSetup.order.contains($0) }
            XCTAssertEqual(Set(list.map(\.permission)), needed, "\(chosen)")
            XCTAssertEqual(list.map(\.permission), ArisPermissionSetup.order.filter(needed.contains))
            for line in list {
                XCTAssertTrue(line.features.allSatisfy { chosen.contains($0) && $0.needs.contains(line.permission) && !$0.askedAtFirstUse.contains(line.permission) })
            }
            // Never on the list: what macOS asks at a first touch, and open at login.
            XCTAssertFalse(list.contains { $0.permission.ask == .onUse || $0.permission.ask == .consent })
            // Walking it: one run of dialogs, then each pane once, then done.
            var m = fresh, steps = 0
            while let step = ArisPermissionSetup.next(for: chosen, in: m) {
                steps += 1
                switch step {
                case .prompts(let all):
                    XCTAssertEqual(steps, 1, "dialogs come first, all from one button")
                    m = m.updating(all.map { (ArisPermissionKey($0), ArisPermissionReading(state: .granted)) }).0
                case .pane(let permission):
                    XCTAssertNotEqual(permission.ask, .prompt)
                    m = m.updating(ArisPermissionKey(permission), to: .init(state: .granted)).0
                }
                XCTAssertLessThanOrEqual(steps, 12)
            }
            XCTAssertEqual(steps, ArisPermissionSetup.steps(for: chosen, in: fresh), "\(chosen)")
            XCTAssertTrue(ArisPermissionSetup.done(for: chosen, in: m))
        }
    }

    func testDefaultChoiceIsThreeSteps() {
        let chosen: Set<ArisPermissionFeature> = [.talk, .appControl, .screenText]
        let fresh = model([mic: .notAsked, ArisPermissionKey(.speechRecognition): .notAsked, ax: .notAsked])
        XCTAssertEqual(ArisPermissionSetup.next(for: chosen, in: fresh), .prompts([.microphone, .speechRecognition]))
        XCTAssertEqual(ArisPermissionSetup.steps(for: chosen, in: fresh), 2)
        XCTAssertFalse(ArisPermissionSetup.list(for: chosen, in: fresh).contains { $0.permission == .screenRecording })
        XCTAssertEqual(ArisPermissionSetup.list(for: chosen.union([.circleGesture]), in: fresh).map(\.permission),
                       [.microphone, .speechRecognition, .accessibility, .inputMonitoring])
    }

    func testTheCircleGestureAsksForScreenRecordingAtItsFirstUseNotInTheSetup() {
        XCTAssertEqual(ArisPermissionFeature.circleGesture.askedAtFirstUse, [.screenRecording])
        XCTAssertTrue(ArisPermissionFeature.allCases.filter { $0 != .circleGesture }.allSatisfy { $0.askedAtFirstUse.isEmpty })
        let fresh = model([screen: .notAsked, ArisPermissionKey(.inputMonitoring): .granted])
        // The setup with the gesture on (its default) asks nothing about the screen.
        XCTAssertFalse(ArisPermissionSetup.list(for: [.talk, .circleGesture], in: fresh).contains { $0.permission == .screenRecording })
        XCTAssertNil(ArisPermissionSetup.next(for: [.circleGesture], in: fresh))
        // A picture of the screen chosen on its own still lists it.
        XCTAssertEqual(ArisPermissionSetup.next(for: [.screenPicture], in: fresh), .pane(.screenRecording))
    }

    func testARefusedDialogBecomesItsPane() {
        let m = model([mic: .denied, ArisPermissionKey(.speechRecognition): .granted])
        XCTAssertEqual(ArisPermissionSetup.next(for: [.talk], in: m), .pane(.microphone))
        XCTAssertEqual(ArisPermissionSetup.steps(for: [.talk], in: m), 1)
    }

    func testAGrantWaitingForARelaunchKeepsTheSetupOpen() {
        let m = model([screen: .notAsked]).updating(screen, to: .init(state: .granted, needsRelaunch: true)).0
        XCTAssertEqual(ArisPermissionSetup.next(for: [.screenPicture], in: m), .pane(.screenRecording))
    }

    // MARK: Pane watch

    func testPaneWatchPollsUntilGrantedOrTimedOut() {
        let watch = ArisPaneWatch().opened(ax, at: t0)
        XCTAssertTrue(watch.isWatching)
        let (due, kept) = watch.due(at: t0.addingTimeInterval(5), in: model([ax: .notAsked]))
        XCTAssertEqual(due, [ax])
        XCTAssertTrue(kept.isWatching)
        XCTAssertEqual(watch.due(at: t0.addingTimeInterval(5), in: model([ax: .granted])).0, [])
        let (late, gone) = watch.due(at: t0.addingTimeInterval(ArisPaneWatch.window + 1), in: model([ax: .notAsked]))
        XCTAssertEqual(late, [])
        XCTAssertFalse(gone.isWatching)
    }
}
