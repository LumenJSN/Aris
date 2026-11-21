import XCTest
@testable import ArisCore

/// Third VM run, D6 (aris-vmcheck notes3/dialogs.txt, item 5): Reminders was asked and answered, then reset outside
/// Aris (tccutil); the kept record still said "asked before", so every use said "off, go to Settings" and macOS's own
/// dialog never came again until the record was deleted by hand.
final class ArisVMFix5PermissionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let reminders = ArisPermissionKey(.reminders)
    private let ax = ArisPermissionKey(.accessibility)

    /// The VM's record: asked at first use, answered yes, then saved across launches.
    private func answered(_ answer: ArisPermissionState) -> ArisPermissions {
        let (asked, decision) = ArisPermissions().updating(reminders, to: .init(state: .notAsked)).0.require(reminders, for: .reminders, now: t0)
        XCTAssertEqual(decision, .prompt(reminders, reason: ArisPermissionFeature.reminders.reason(english: false)))
        let after = asked.updating(reminders, to: .init(state: answer)).0
        XCTAssertEqual(after.record(reminders).outcome, answer)
        return ArisPermissions.restored(from: after.saved)
    }

    func testAnAnswerResetOutsideArisIsAskedAgainAtFirstUse() {
        for answer in [ArisPermissionState.granted, .denied] {
            let reset = answered(answer).updating(reminders, to: .init(state: .notAsked)).0
            XCTAssertNil(reset.record(reminders).askedAt, "\(answer)")
            XCTAssertNil(reset.record(reminders).toldOffAt, "\(answer)")
            let (_, decision) = reset.require(reminders, for: .reminders, now: t0.addingTimeInterval(60))
            XCTAssertEqual(decision, .prompt(reminders, reason: ArisPermissionFeature.reminders.reason(english: false)), "\(answer)")
        }
    }

    func testARefusalMacOSStillReportsIsToldAsBefore() {
        let denied = answered(.denied).updating(reminders, to: .init(state: .denied)).0
        let (told, first) = denied.require(reminders, for: .reminders, now: t0)
        if case .tellOff = first {} else { XCTFail("\(first)") }
        XCTAssertEqual(told.require(reminders, for: .reminders, now: t0).1, .doWithout(reminders))
    }

    func testAPaneSwitchThatIsOffKeepsItsRecord() {
        let (asked, _) = ArisPermissions().updating(ax, to: .init(state: .notAsked)).0.require(ax, for: .appControl, now: t0)
        let turnedOff = asked.updating(ax, to: .init(state: .granted)).0.updating(ax, to: .init(state: .notAsked)).0
        XCTAssertEqual(turnedOff.record(ax).askedAt, t0)
    }
}
