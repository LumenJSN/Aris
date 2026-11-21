import XCTest
@testable import ArisCore

/// The trust policy, exhaustively: every level × effect × provenance × fully-specified × with and without a matching
/// grant, against the table written out here by hand (not read from the data file); the never-list, kept and dropped;
/// the table's data and the user's changes to it.
final class ArisTrustPolicyTests: XCTestCase {
    private let home = "/Users/user"
    private let web = ArisContentSource(kind: "web", source: "https://evil.example/page")

    /// The table as ARCHITECTURE Part 2 states it, plus the careful and free positions, by hand.
    private func expected(_ level: ArisTrustLevel, _ effect: ArisEffectClass, _ column: ArisCallProvenance.Column, specified: Bool, grant: Bool) -> ArisDecision {
        let say = ArisDecision.sayThenRun(delay: 4)
        let refuseContent = ArisDecision.refuse(reason: ArisTrustPolicy.refusal(effect: effect, provenance: .content(web)))
        if effect == .never { return .refuse(reason: ArisNeverRule.neverEffect.korean) }
        let lifted = grant && level != .careful && column != .content
        switch (effect, column) {
        case (.observe, _): return .run
        case (.changeReversible, .content): return .runWithUndo(announce: true)
        case (.changeReversible, _): return .runWithUndo(announce: false)
        case (.changePermanent, .content): return .ask
        case (.changePermanent, .ownStep):
            if lifted { return .run }
            return level == .free ? say : .ask
        case (.changePermanent, _):
            if lifted { return .run }
            switch level {
            case .careful: return .ask
            case .standard: return say
            case .free: return .run
            }
        case (.outward, .content): return refuseContent
        case (.outward, .ownStep): return lifted ? .run : .ask
        case (.outward, _):
            if lifted { return .run }
            switch level {
            case .careful: return .readBackThenAsk
            case .standard: return specified ? say : .readBackThenAsk
            case .free: return specified ? .run : .readBackThenAsk
            }
        default: return .ask
        }
    }

    private func provenance(_ column: ArisCallProvenance.Column) -> ArisCallProvenance {
        switch column {
        case .ownerSaid: .ownerSaid
        case .ownerEarlier: .ownerEarlier
        case .ownStep: .ownStep
        case .content: .content(web)
        }
    }

    func testEveryCellOfEveryLevelWithAndWithoutAGrant() {
        let call = ArisCallFacts(capability: "mail.send", arguments: [ArisKeyArgument(kind: .recipient, value: "mom@example.com"),
                                                                       ArisKeyArgument(kind: .body, value: "곧 갈게")])
        let grant = ArisStandingGrant(capability: "mail.*", target: .init(kind: .recipient, pattern: "엄마", addresses: ["mom@example.com"]))
        var checked = 0
        for level in ArisTrustLevel.allCases {
            for effect in ArisEffectClass.allCases {
                for column in ArisCallProvenance.Column.allCases {
                    for specified in [false, true] {
                        for withGrant in [false, true] {
                            let context = ArisTrustPolicy.Context(level: level, grants: withGrant ? [grant] : [], home: home)
                            let got = ArisTrustPolicy.decide(call, effect: effect, provenance: provenance(column), specified: specified, context: context)
                            XCTAssertEqual(got, expected(level, effect, column, specified: specified, grant: withGrant),
                                           "\(level) \(effect) \(column) specified=\(specified) grant=\(withGrant)")
                            checked += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(checked, 3 * 5 * 4 * 2 * 2)
    }

    func testAGrantThatDoesNotMatchLiftsNothing() {
        let call = ArisCallFacts(capability: "mail.send", arguments: [ArisKeyArgument(kind: .recipient, value: "boss@example.com")])
        let grants = [
            ArisStandingGrant(capability: "mail.*", target: .init(kind: .recipient, pattern: "엄마", addresses: ["mom@example.com"])),
            ArisStandingGrant(capability: "messages.*", effect: .outward),
            ArisStandingGrant(effect: .changePermanent),
            ArisStandingGrant(capability: "mail.send", effect: .outward, expires: Date(timeIntervalSince1970: 1)),
        ]
        let context = ArisTrustPolicy.Context(grants: grants, home: home)
        XCTAssertEqual(ArisTrustPolicy.decide(call, effect: .outward, provenance: .ownStep, context: context), .ask)
        // A call with two recipients is covered only when both are.
        let both = ArisCallFacts(capability: "mail.send", arguments: [ArisKeyArgument(kind: .recipient, value: "mom@example.com"),
                                                                       ArisKeyArgument(kind: .recipient, value: "boss@example.com")])
        XCTAssertEqual(ArisTrustPolicy.decide(both, effect: .outward, provenance: .ownStep, context: context), .ask)
    }

    func testContentNeverCausesAnOutwardOrPermanentActionWhateverTheTableSays() {
        // A table someone wrote by hand that breaks the rule is refused whole.
        let broken = ArisTrustTable.defaultJSON.replacingOccurrences(of: #""outward":           {"ownerSaid": "sendIfSpecified", "ownerEarlier": "sendIfSpecified", "ownStep": "ask",         "content": "refuse"}"#,
                                                                     with: #""outward":           {"ownerSaid": "sendIfSpecified", "ownerEarlier": "sendIfSpecified", "ownStep": "ask",         "content": "run"}"#)
        XCTAssertNotEqual(broken, ArisTrustTable.defaultJSON)
        XCTAssertNil(ArisTrustTable.parse(Data(broken.utf8)))
        // The user's changes that would break it are dropped; the rest apply.
        let changed = ArisTrustTable.standard.changed(by: ["standard": ["outward": ["content": "run", "ownStep": "readBackThenAsk"],
                                                                        "change-permanent": ["content": "sayThenRun", "ownStep": "run"]]])
        XCTAssertEqual(changed.cell(.standard, .outward, .content), .refuse)
        XCTAssertEqual(changed.cell(.standard, .outward, .ownStep), .readBackThenAsk)
        XCTAssertEqual(changed.cell(.standard, .changePermanent, .content), .ask)
        XCTAssertEqual(changed.cell(.standard, .changePermanent, .ownStep), .run)
        // Even a table built in code that breaks it: the policy checks again.
        var forced = ArisTrustTable.standard
        forced.cells[.free]![.outward]![.content] = .run
        forced.cells[.free]![.changePermanent]![.content] = .run
        let call = ArisCallFacts(capability: "mail.send", arguments: [ArisKeyArgument(kind: .recipient, value: "x@evil.example")])
        let context = ArisTrustPolicy.Context(level: .free, grants: [ArisStandingGrant(effect: .outward)], table: forced, home: home)
        if case .refuse = ArisTrustPolicy.decide(call, effect: .outward, provenance: .content(web), specified: true, context: context) {} else { XCTFail() }
        XCTAssertEqual(ArisTrustPolicy.decide(call, effect: .changePermanent, provenance: .content(web), context: context), .ask)
    }

    func testTheDataFileReadsAndUnknownChangesAreIgnored() {
        XCTAssertEqual(ArisTrustTable.standard.sayDelay, 4)
        XCTAssertEqual(ArisTrustTable.standard.grantsIgnoredAt, [.careful])
        let same = ArisTrustTable.standard.changed(by: ["nope": ["outward": ["ownerSaid": "run"]], "standard": ["never": ["ownerSaid": "run"],
                                                                                                              "outward": ["boss": "run", "ownerSaid": "maybe"]]])
        XCTAssertEqual(same, ArisTrustTable.standard)
        XCTAssertNil(ArisTrustTable.parse(Data("{}".utf8)))
    }

    func testTheReasonForAContentRefusalNamesTheSource() {
        let call = ArisCallFacts(capability: "mail.send", arguments: [ArisKeyArgument(kind: .recipient, value: "x@evil.example")])
        let got = ArisTrustPolicy.decide(call, effect: .outward, provenance: .content(web), context: .init(home: home))
        guard case .refuse(let reason) = got else { return XCTFail() }
        XCTAssertTrue(reason.contains("웹 페이지"), reason)
    }

    func testGrantsAreScopedToFoldersAppsAndTime() {
        let downloads = ArisStandingGrant(effect: .changePermanent, target: .init(kind: .path, pattern: "~/Downloads"))
        let inside = ArisCallFacts(capability: "file.delete", arguments: [ArisKeyArgument(kind: .path, value: "/Users/Downloads/a.pdf")])
        let outside = ArisCallFacts(capability: "file.delete", arguments: [ArisKeyArgument(kind: .path, value: "/Users/Documents/a.pdf")])
        let sneaky = ArisCallFacts(capability: "file.delete", arguments: [ArisKeyArgument(kind: .path, value: "/Users/Downloads/../Documents/a.pdf")])
        let now = Date()
        XCTAssertTrue(downloads.covers(inside, effect: .changePermanent, home: home, now: now))
        XCTAssertFalse(downloads.covers(outside, effect: .changePermanent, home: home, now: now))
        XCTAssertFalse(downloads.covers(sneaky, effect: .changePermanent, home: home, now: now))
        XCTAssertFalse(downloads.covers(inside, effect: .outward, home: home, now: now))
        let soon = ArisStandingGrant(effect: .changePermanent, target: .init(kind: .path, pattern: "~/Downloads"), expires: now.addingTimeInterval(60))
        XCTAssertTrue(soon.covers(inside, effect: .changePermanent, home: home, now: now))
        XCTAssertFalse(soon.covers(inside, effect: .changePermanent, home: home, now: now.addingTimeInterval(61)))
        XCTAssertFalse(ArisStandingGrant(effect: .never).isWellFormed)
        XCTAssertFalse(ArisStandingGrant(effect: .observe).isWellFormed)
        XCTAssertFalse(ArisStandingGrant().isWellFormed)
        XCTAssertFalse(ArisStandingGrant(capability: "*").isWellFormed)
    }
}
