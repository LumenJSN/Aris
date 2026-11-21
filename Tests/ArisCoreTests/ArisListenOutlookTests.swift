import XCTest
@testable import ArisCore

/// VM run 2026-11-18, D1: key access given during the first setup left the dictation and circle keys dead until a
/// relaunch, with nothing said. macOS answers the listen check once per process.
final class ArisListenOutlookTests: XCTestCase {
    func testAListenGrantSeenNowStartsTheTaps() {
        XCTAssertEqual(ArisListenOutlook.of(listenNow: true, trustedNow: false, trustedAtLaunch: false), .ready)
        XCTAssertEqual(ArisListenOutlook.of(listenNow: true, trustedNow: true, trustedAtLaunch: true), .ready)
    }

    func testAccessibilityTurnedOnSinceLaunchNeedsAReopen() {
        XCTAssertEqual(ArisListenOutlook.of(listenNow: false, trustedNow: true, trustedAtLaunch: false), .afterRelaunch)
    }

    func testNoGrantOrOneAReopenWouldNotChangeIsNotAllowed() {
        XCTAssertEqual(ArisListenOutlook.of(listenNow: false, trustedNow: false, trustedAtLaunch: false), .notAllowed)
        // Accessibility was on at launch and still no listening: a reopen gives nothing new.
        XCTAssertEqual(ArisListenOutlook.of(listenNow: false, trustedNow: true, trustedAtLaunch: true), .notAllowed)
    }

    func testTheReadingOffersTheReopenOnceForTheDictationKey() {
        let key = ArisPermissionKey(.inputMonitoring)
        let reading = ArisListenOutlook.afterRelaunch.reading(listenState: .notAsked)
        XCTAssertEqual(reading, ArisPermissionReading(state: .granted, needsRelaunch: true))
        let (model, changes) = ArisPermissions().updating(key, to: reading)
        XCTAssertEqual(changes, [.relaunchNeeded(key)])
        XCTAssertFalse(model.ready(.dictationKey))
        let (offered, decision) = model.require(key, for: .dictationKey)
        XCTAssertEqual(decision, .offerRelaunch(key))
        XCTAssertEqual(offered.require(key, for: .dictationKey).1, .doWithout(key))
    }

    func testOtherwiseTheReadingIsWhatMacOSSaid() {
        XCTAssertEqual(ArisListenOutlook.ready.reading(listenState: .notAsked), ArisPermissionReading(state: .granted))
        XCTAssertEqual(ArisListenOutlook.notAllowed.reading(listenState: .denied), ArisPermissionReading(state: .denied))
        XCTAssertEqual(ArisListenOutlook.notAllowed.reading(listenState: .notAsked), ArisPermissionReading(state: .notAsked))
        // Never "allowed" without the listen check saying so in some process.
        XCTAssertEqual(ArisListenOutlook.notAllowed.reading(listenState: .granted), ArisPermissionReading(state: .notAsked))
    }
}
