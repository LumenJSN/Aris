import XCTest
@testable import ArisCore

/// The app's World on its way to the helper (jv-mind2): what the app sends comes back the same, every value is
/// checked and cut, and the helper's trust facts take the app's contacts and nicknames while what is in front is its own
/// reading first.
final class ArisWorldWireTests: XCTestCase {
    func testRoundTrip() {
        let payload = ArisWorldWire.Payload(frontApp: "Messages", frontBundle: "com.apple.MobileSMS",
                                            contacts: [.init(name: "엄마", aliases: ["어머니"], addresses: ["mom@example.com", "+82 10-1234-5678"])],
                                            apps: ["Safari": ["사파리"]])
        let object = ArisWorldWire.encode(payload)
        let data = try? JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(ArisWorldWire.decode(data.flatMap { try? JSONSerialization.jsonObject(with: $0) }), payload)
    }

    func testValuesAreCheckedAndCut() {
        let raw: [String: Any] = ["frontApp": "Mail\u{202E}", "contacts": [["name": "  "], ["name": "민수\n", "addresses": [1, "ms@example.com"]],
                                                                       ["name": String(repeating: "가", count: 500)]],
                                  "apps": ["": ["x"], "Notes": ["메모", 3]]]
        let payload = ArisWorldWire.decode(raw)
        XCTAssertEqual(payload?.frontApp, "Mail")
        XCTAssertEqual(payload?.contacts, [.init(name: "민수", addresses: ["ms@example.com"])])
        XCTAssertEqual(payload?.apps, ["Notes": ["메모"]])
        XCTAssertNil(ArisWorldWire.decode("not an object"))
        let many = (0..<5_000).map { ["name": "c\($0)"] }
        XCTAssertEqual(ArisWorldWire.decode(["contacts": many])?.contacts.count, ArisWorldWire.mostContacts)
    }

    func testAppAliasesTurnAround() {
        XCTAssertEqual(ArisWorldWire.apps(fromAliases: ["사파리": "Safari", "크롬": "Google Chrome", "웹": "Safari"]),
                       ["Safari": ["사파리", "웹"], "Google Chrome": ["크롬"]])
    }

    func testFactsTakeTheAppsContactsAndTheHelpersFront() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let app = ArisWorldWire.Payload(frontApp: "Mail", frontBundle: "com.apple.mail", contacts: [.init(name: "엄마", addresses: ["mom@example.com"])],
                                        apps: ["Safari": ["사파리"]])
        var live = ArisWorldSnapshot()
        live.frontApp = .init(name: "Notes", bundleID: "com.apple.Notes", pid: 9)
        let both = ArisMindWorld.facts(live: live, app: app, appAt: now, now: now, home: "/Users/p")
        XCTAssertEqual(both.frontApp, "Notes")
        XCTAssertEqual(both.contacts.map(\.name), ["엄마"])
        XCTAssertEqual(both.apps["Safari"], ["사파리"])
        // No reading of its own: the app's front while fresh, then nothing.
        XCTAssertEqual(ArisMindWorld.facts(live: nil, app: app, appAt: now, now: now.addingTimeInterval(60), home: "/Users/p").frontApp, "Mail")
        XCTAssertNil(ArisMindWorld.facts(live: nil, app: app, appAt: now, now: now.addingTimeInterval(600), home: "/Users/p").frontApp)
        // No app World: exactly what the helper had before (its own front only).
        let alone = ArisMindWorld.facts(live: live, app: nil, appAt: nil, now: now, home: "/Users/p")
        XCTAssertEqual(alone, ArisMindWorld.facts(live, home: "/Users/p"))
    }

    func testTheFocusLiesOverTheWire() {
        let wire = ArisWorldFacts(contacts: [.init(name: "엄마")], apps: ["Safari": ["사파리"]], frontApp: "Notes", home: "/Users/p")
        let page = ArisFocusObject(source: ArisContentSource(kind: "web", source: "example.com"))
        let merged = ArisMindWorld.facts(wire, focus: ArisWorldFacts(frontApp: "Safari", focus: page))
        XCTAssertEqual(merged.focus, page)
        XCTAssertEqual(merged.frontApp, "Safari")
        XCTAssertEqual(merged.contacts, wire.contacts)
        XCTAssertEqual(ArisMindWorld.facts(wire, focus: ArisWorldFacts()), wire)
    }
}
