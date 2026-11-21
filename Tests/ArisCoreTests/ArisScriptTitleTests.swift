// VM run 2, H2: Finder's `osascript … get selection` asked on a card titled "보내기". A shell line whose first program is
// osascript is titled 스크립트 실행 with the script shown whole; the title is presentation only and moves no decision.
import XCTest
@testable import ArisCore

final class ArisScriptTitleTests: XCTestCase {
    private let line = #"osascript -e 'tell application "Finder" to get selection'"#

    private func facts(_ command: String, titled: Bool) -> ArisCallFacts {
        var facts = ArisCallFacts(capability: "shell.run", arguments: [ArisKeyArgument(kind: .command, value: command)])
        facts.scriptTitle = titled
        return facts
    }

    func testAScriptLineIsTitledAsAScriptRunAndShownWhole() {
        let item = ArisAskItem(call: "c", facts: facts(line, titled: true), effect: .outward, decision: .ask, provenance: .ownStep)
        let card = ArisAskPlan.card([item], id: "a", intent: "i", countdown: false, home: "/Users/user")
        XCTAssertTrue(card.title.hasPrefix("스크립트 실행"), card.title)
        XCTAssertFalse(card.title.contains("보내기"))
        XCTAssertTrue((card.full ?? card.detail).contains(line))
        let plain = ArisAskItem(call: "d", facts: facts(line, titled: false), effect: .outward, decision: .ask, provenance: .ownStep)
        XCTAssertTrue(ArisAskPlan.card([plain], id: "b", intent: "i", countdown: false, home: "/Users/user").title.hasPrefix("보내기"))
    }

    func testTheTitleMovesNoDecision() {
        for effect in [ArisEffectClass.observe, .changeReversible, .changePermanent, .outward] {
            for provenance in [ArisCallProvenance.ownerSaid, .ownerEarlier, .ownStep] {
                for level in [ArisTrustLevel.standard, .free] {
                    let context = ArisTrustPolicy.Context(level: level, home: "/Users/user")
                    XCTAssertEqual(ArisTrustPolicy.decide(facts(line, titled: true), effect: effect, provenance: provenance, context: context),
                                   ArisTrustPolicy.decide(facts(line, titled: false), effect: effect, provenance: provenance, context: context))
                }
            }
        }
    }
}
