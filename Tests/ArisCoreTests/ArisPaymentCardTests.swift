import XCTest
@testable import ArisCore

/// Decision 1 (2026-11-18): a payment the capability registry marks is no longer refused for being a payment. It asks
/// on a card of its own every time: what is paid, to whom, how much, every argument in full; a yes covers that one
/// step; never remembered, never a grant, never a countdown. Every other refusal stays, and so does the old rule for a
/// call that only carries an amount or a payee.
final class ArisPaymentCardTests: XCTestCase {
    private let home = "/Users/user"
    private let pay = [ArisKeyArgument(kind: .amount, value: "30000원"), ArisKeyArgument(kind: .payee, value: "쿠팡")]

    private func decide(_ provenance: ArisCallProvenance, level: ArisTrustLevel = .standard, grants: [ArisStandingGrant] = [],
                        table: ArisTrustTable = .standard, specified: Bool = true, speaker: ArisTurnSpeaker = .notChecked) -> ArisDecision {
        ArisTrustPolicy.decide(ArisCallFacts(capability: "shop.pay", arguments: pay, registeredPayment: true), effect: .outward, provenance: provenance, specified: specified,
                               ownerNamed: [.amount, .payee], speaker: speaker,
                               context: .init(level: level, grants: grants, table: table, home: home))
    }

    func testAPaymentAlwaysAsksAndIsNeverRefusedOutright() {
        for level in ArisTrustLevel.allCases {
            for provenance in [ArisCallProvenance.ownerSaid, .ownerEarlier, .ownStep] {
                XCTAssertEqual(decide(provenance, level: level), .ask, "\(level) \(provenance): a card, never a run, never a countdown")
            }
        }
        // The owner named nothing: before, the never-list refused it; now it is asked.
        let bare = ArisTrustPolicy.decide(ArisCallFacts(capability: "shop.pay", arguments: pay, registeredPayment: true), effect: .outward,
                                          provenance: .ownStep, context: .init(home: home))
        XCTAssertEqual(bare, .ask)
    }

    func testOnlyAPaymentTheRegistryMarksMoves() {
        // An amount and a payee on a capability the registry doesn't mark: the old rule, unchanged.
        let unmarked = ArisCallFacts(capability: "note.create", arguments: pay)
        guard case .refuse = ArisTrustPolicy.decide(unmarked, effect: .outward, provenance: .ownStep, context: .init(home: home)) else {
            return XCTFail("an unmarked call with an amount and payee the owner didn't name stays refused")
        }
        XCTAssertEqual(ArisTrustPolicy.decide(unmarked, effect: .outward, provenance: .ownerSaid, specified: true, ownerNamed: [.amount, .payee],
                                              context: .init(home: home)), .sayThenRun(delay: 4), "named, it follows its row as before")
        // A payment-looking call that runs a never-list command is refused, marked or not.
        for marked in [false, true] {
            let facts = ArisCallFacts(capability: "shell.run", arguments: pay + [ArisKeyArgument(kind: .command, value: "rm -rf ~")], registeredPayment: marked)
            guard case .refuse = ArisTrustPolicy.decide(facts, effect: .changePermanent, provenance: .ownerSaid, ownerNamed: [.amount, .payee],
                                                        context: .init(home: home)) else { return XCTFail("a never-list command stays refused (marked: \(marked))") }
            let reach = ArisCallFacts(capability: "shell.run", arguments: pay + [ArisKeyArgument(kind: .command, value: "cat ~/.ssh/id_ed25519")],
                                      registeredPayment: marked)
            guard case .refuse = ArisTrustPolicy.decide(reach, effect: .observe, provenance: .ownerSaid, context: .init(home: home)) else {
                return XCTFail("a never-list reach stays refused (marked: \(marked))")
            }
        }
    }

    func testAPaymentTheCardCannotShowExactlyIsRefused() {
        func decided(_ arguments: [ArisKeyArgument]) -> ArisDecision {
            ArisTrustPolicy.decide(ArisCallFacts(capability: "shop.pay", arguments: arguments, registeredPayment: true), effect: .outward,
                                   provenance: .ownerSaid, context: .init(home: home))
        }
        guard case .refuse = decided(pay + [ArisKeyArgument(kind: .amount, value: "1원")]) else { return XCTFail("two amounts are refused") }
        guard case .refuse = decided(pay + [ArisKeyArgument(kind: .payee, value: "다른 곳")]) else { return XCTFail("two payees are refused") }
        guard case .refuse = decided([ArisKeyArgument(kind: .amount, value: "1원"), ArisKeyArgument(kind: .recipient, value: "someone")] + pay.suffix(1)) else {
            return XCTFail("a recipient beside the payee is a second payee")
        }
        let long = String(repeating: "가", count: 200)
        guard case .refuse = decided([pay[0], ArisKeyArgument(kind: .payee, value: long)]) else { return XCTFail("a 200-character payee is refused, never cut") }
        XCTAssertEqual(decided(pay + [ArisKeyArgument(kind: .amount, value: "30000원")]), .ask, "the same amount twice is one amount")
    }

    func testNoGrantNoTableAndNoVoiceMakesAPaymentRunOnItsOwn() {
        let grant = ArisStandingGrant(capability: "shop.pay", effect: .outward)
        let payee = ArisStandingGrant(effect: .outward, target: .init(kind: .payee, pattern: "쿠팡"))
        XCTAssertEqual(decide(.ownerSaid, grants: [grant, payee]), .ask, "a standing grant never covers a payment")
        XCTAssertEqual(decide(.ownerSaid, level: .free, grants: [grant]), .ask)
        let loose = ArisTrustTable.standard.changed(by: ["standard": ["outward": ["ownerSaid": "run", "ownStep": "run"]]])
        XCTAssertEqual(decide(.ownerSaid, table: loose), .ask, "a table the user loosens doesn't make a payment run")
        XCTAssertEqual(decide(.ownStep, table: loose), .ask)
        XCTAssertEqual(decide(.ownerSaid, speaker: .unverified), .ask)
    }

    func testContentNeverCausesAPayment() {
        guard case .refuse = decide(.content(ArisContentSource(kind: "web", source: "https://shop.example"))) else {
            return XCTFail("a payment content suggested is refused, as every outward act")
        }
        // The rest of the never-list still holds for a payment.
        let toKeys = ArisCallFacts(capability: "shop.pay", arguments: pay + [ArisKeyArgument(kind: .path, value: "~/.ssh/id_ed25519")], registeredPayment: true)
        guard case .refuse = ArisTrustPolicy.decide(toKeys, effect: .outward, provenance: .ownerSaid, context: .init(home: home)) else {
            return XCTFail("the never-list is still read first")
        }
    }

    // MARK: - The card

    private func item(_ call: String, _ arguments: [ArisKeyArgument], named: Set<ArisKeyArgument.Kind> = [.amount, .payee],
                      readFrom: ArisContentSource? = nil) -> ArisAskItem {
        ArisAskItem(call: call, facts: ArisCallFacts(capability: "shop.pay", arguments: arguments, registeredPayment: true), effect: .outward, decision: .ask,
                    provenance: .ownerSaid, ownerNamed: named, readFrom: readFrom)
    }

    func testEachPaymentIsACardOfItsOwnThatReadsItBack() {
        var plan = ArisAskPlan()
        let send = ArisAskItem(call: "m", facts: ArisCallFacts(capability: "mail.send", arguments: [.init(kind: .recipient, value: "엄마")]),
                               effect: .outward, decision: .ask, provenance: .ownStep)
        let planned = plan.plan([item("p1", pay), item("p2", pay), send], intent: "turn", home: home)
        XCTAssertEqual(planned.cards.count, 3, "two payments, two cards; the send on its own")
        let card = planned.cards[0]
        XCTAssertEqual(card.calls, ["p1"])
        XCTAssertFalse(card.countdown, "never a countdown")
        XCTAssertTrue(card.alwaysScope.isEmpty, "never 'always'")
        XCTAssertEqual(card.title, "결제 · 쿠팡 · 30000원")
        XCTAssertTrue(card.detail.contains("받는 곳: 쿠팡") && card.detail.contains("금액: 30000원"))
        XCTAssertTrue(card.detail.contains("이번 결제 한 번만"))
        XCTAssertEqual(card.spoken, "쿠팡에 30000원 결제할까요?")
    }

    func testAYesCoversThatOneStepOnly() {
        var plan = ArisAskPlan()
        let first = plan.plan([item("p1", pay)], intent: "turn", home: home)
        let yes = plan.answer(first.cards[0].id, .always, home: home)
        XCTAssertEqual(yes.run, ["p1"])
        XCTAssertTrue(yes.grants.isEmpty, "a yes, even 'always', is never kept")
        let again = plan.plan([item("p2", pay)], intent: "turn", home: home)
        XCTAssertTrue(again.covered.isEmpty, "the same payment again in the same turn asks again")
        XCTAssertEqual(again.cards.count, 1)
        XCTAssertEqual(plan.answer(again.cards[0].id, .no, home: home).refused, ["p2"], "no answer, or no, runs nothing")
    }

    func testTheCardSaysWhatItCouldNotReadAndWhereItWasRead() {
        var plan = ArisAskPlan()
        let page = ArisContentSource(kind: "web", source: "https://shop.example/checkout")
        let card = plan.plan([item("p", [.init(kind: .payee, value: "쿠팡")], named: [], readFrom: page)], intent: "t", home: home).cards[0]
        XCTAssertTrue(card.detail.contains("금액: 읽지 못했어요"), card.detail)
        XCTAssertTrue(card.detail.contains("웹 페이지 https://shop.example/checkout에서 읽은 거예요"), card.detail)
        let partly = plan.plan([item("r", pay, named: [.payee], readFrom: page)], intent: "t", home: home).cards[0]
        XCTAssertTrue(partly.detail.contains("에서 읽은 거예요"), "the note is there when any value came from what he pointed at")
        let own = plan.plan([item("q", pay, named: [])], intent: "t", home: home).cards[0]
        XCTAssertTrue(own.detail.contains("받는 곳·금액은 직접 말씀하지 않으셨어요"), own.detail)
    }

    func testTheCardShowsEveryArgumentInFull() {
        var plan = ArisAskPlan()
        let payee = String(repeating: "나", count: 110) + "끝"
        let arguments = [ArisKeyArgument(kind: .payee, value: payee), ArisKeyArgument(kind: .amount, value: "12,345,678원"),
                         ArisKeyArgument(kind: .url, value: "https://shop.example/checkout?id=7"), ArisKeyArgument(kind: .path, value: "/Users/a.pdf"),
                         ArisKeyArgument(kind: .command, value: "pay --now")]
        let card = plan.plan([item("p", arguments)], intent: "t", home: home).cards[0]
        let joined = card.detail.replacingOccurrences(of: "\n", with: "")
        XCTAssertTrue(joined.contains(payee), "a long payee is wrapped, never cut")
        XCTAssertTrue(card.title.contains(payee) && card.title.contains("12,345,678원"))
        for value in ["12,345,678원", "https://shop.example/checkout?id=7", "/Users/a.pdf", "pay --now"] {
            XCTAssertTrue(card.detail.contains(value), value)
        }
        XCTAssertTrue(card.detail.split(separator: "\n").allSatisfy { $0.count <= ArisAskPlan.lineLength })
    }

    func testTheRegistrysPaymentWords() {
        for words in ["결제하기", "바로 구매", "Buy now", "Place your order", "Checkout", "송금", "Pay"] { XCTAssertTrue(ArisPaymentSteps.names(words), words) }
        for words in ["Payroll report", "보내기", "Order history", "Display", "Replay", "Subscribe to newsletter", ""] { XCTAssertFalse(ArisPaymentSteps.names(words), words) }
    }

    // MARK: - Where the amount came from

    func testAnAmountReadFromWhatTheOwnerPointsAtAsksAndSaysSo() {
        let invoice = ArisContentSource(kind: "web", source: "https://bills.example/invoice/7")
        var tracker = ArisProvenanceTracker(world: ArisWorldFacts(focus: ArisFocusObject(source: invoice, text: "청구서: 한전 전기요금 48,200원"), home: home))
        tracker.ownerTurn("이거 결제해 줘")
        let arguments = [ArisKeyArgument(kind: .amount, value: "48,200원"), ArisKeyArgument(kind: .payee, value: "한전")]
        let verdict = tracker.provenance(capability: "shop.pay", effect: .outward, arguments: arguments)
        XCTAssertEqual(verdict.provenance, .ownerSaid, "the owner asked to pay what he points at")
        XCTAssertEqual(verdict.readFrom, invoice)
        XCTAssertFalse(verdict.ownerNamed.contains(.amount))
        XCTAssertEqual(ArisTrustPolicy.decide(ArisCallFacts(capability: "shop.pay", arguments: arguments, registeredPayment: true), effect: .outward,
                                              provenance: verdict.provenance, context: .init(home: home)), .ask)
        // The same amount in content he didn't point at: content's, refused.
        var unpointed = ArisProvenanceTracker(world: ArisWorldFacts(home: home))
        unpointed.ownerTurn("결제 좀 해 줘")
        unpointed.toolResult("청구서: 한전 전기요금 48,200원", source: ArisContentSource(kind: "mail", source: "mail: 청구서"))
        let read = unpointed.provenance(capability: "shop.pay", effect: .outward, arguments: arguments)
        XCTAssertNotNil(read.provenance.source)
        guard case .refuse = ArisTrustPolicy.decide(ArisCallFacts(capability: "shop.pay", arguments: arguments, registeredPayment: true), effect: .outward,
                                                    provenance: read.provenance, context: .init(home: home)) else {
            return XCTFail("an amount from content the owner didn't point at is refused")
        }
    }
}
