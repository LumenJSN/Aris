import XCTest
@testable import ArisCore

final class ArisSwitchesTests: XCTestCase {
    func testOnlyTrueOfAKnownSwitchTurnsItOn() {
        XCTAssertEqual(ArisSwitchSet.from(["arisCore2": true, "arisTeach": "true", "arisOther": true]), ArisSwitchSet([.core2]))
        XCTAssertNil(ArisSwitchSet.from("arisCore2"))
        XCTAssertEqual(ArisSwitchSet.from([String: Any]()), ArisSwitchSet())
    }

    func testTheWireNamesEverySwitch() {
        XCTAssertEqual(ArisSwitchSet([.teach]).json, ["arisCore2": false, "arisTeach": true])
    }

    func testTheEnvironmentRoundTrips() {
        let both = ArisSwitchSet([.core2, .teach])
        XCTAssertEqual(both.environmentValue, "arisCore2,arisTeach")
        XCTAssertEqual(ArisSwitchSet.from(environment: both.environmentValue), both)
        XCTAssertNil(ArisSwitchSet().environmentValue)
        XCTAssertEqual(ArisSwitchSet.from(environment: nil), ArisSwitchSet())
        XCTAssertEqual(ArisSwitchSet.from(environment: "arisCore2, nonsense"), ArisSwitchSet([.core2]))
    }

    func testChanged() {
        XCTAssertEqual(ArisSwitchSet([.core2]).changed(from: ArisSwitchSet([.teach])), [.core2, .teach])
        XCTAssertTrue(ArisSwitchSet([.core2]).changed(from: ArisSwitchSet([.core2])).isEmpty)
    }
}
