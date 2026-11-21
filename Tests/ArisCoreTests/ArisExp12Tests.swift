import XCTest
@testable import ArisCore

/// jv-exp12: the twelfth VM run's Experimental-mode defects (Core 2 on), the pure rules. The recorded calls are
/// replayed through the real judge and gate in tests/exp12-tests.swift.
final class ArisExp12Tests: XCTestCase {
    private let home = "/Users/user"

    private func handOff(_ call: String, brief: String, decision: ArisDecision = .ask, english: Bool = false) -> ArisAskItem {
        var facts = ArisCallFacts(capability: "aris.aside_task", arguments: [])
        facts.handOff = ArisHandOffFacts(target: "브라우저 도우미 Aside에게 맡기기", spoken: "Aside에게 이 일을 맡길까요?", text: brief, english: english)
        return ArisAskItem(call: call, facts: facts, effect: .outward, decision: decision, provenance: .ownStep)
    }

    /// cap12/B1-card1.jpg, B1-showall.jpg: "보내기" over "보내기", "aris.aside_task" and "항상".
    func testAHandOffCardShowsTheBriefItsTargetAndNeverAlways() {
        var plan = ArisAskPlan(makeID: { "trust-h" })
        let brief = "아마존에서 에어팟 프로를 장바구니에 담고 결제 화면 직전까지만 진행해.\n\n" + ArisPaymentBoundary.stopClause(english: false)
        let (cards, covered) = plan.plan([handOff("a", brief: brief)], intent: "t", home: home)
        XCTAssertTrue(covered.isEmpty)
        XCTAssertEqual(cards.count, 1)
        let card = cards[0]
        XCTAssertEqual(card.title, "브라우저 도우미 Aside에게 맡기기")
        XCTAssertTrue(card.detail.contains("아마존에서 에어팟 프로를 장바구니에 담고"), card.detail)
        XCTAssertTrue(card.detail.contains(ArisPaymentBoundary.stopClause(english: false).prefix(30)), "the rule that goes out is on the card: \(card.detail)")
        let all = card.title + card.detail + (card.full ?? "") + card.spoken
        XCTAssertFalse(all.contains("aris."), "no internal id: \(all)")
        XCTAssertFalse(all.contains("‘항상’이라고 하시면"), "never offers always: \(all)")
        XCTAssertTrue(card.alwaysScope.isEmpty)
        XCTAssertFalse(card.countdown)
        // "Yes, always" keeps nothing, and a yes covers no later hand-off.
        XCTAssertTrue(plan.answer("trust-h", .always, home: home).grants.isEmpty)
        let later = plan.plan([handOff("b", brief: brief)], intent: "t", home: home)
        XCTAssertTrue(later.covered.isEmpty)
        XCTAssertEqual(later.cards.count, 1)
        // A hand-off said first (a countdown) is asked on its own card all the same: its words are read, not counted down.
        let said = plan.plan([handOff("c", brief: "날씨 알려 줘", decision: .sayThenRun(delay: 4))], intent: "t", home: home).cards
        XCTAssertEqual(said.map(\.countdown), [false])
        XCTAssertTrue(said.first?.detail.contains("날씨 알려 줘") == true)
    }

    func testAHandOffCardInEnglishAndALongBriefIsShownWhole() {
        var plan = ArisAskPlan(makeID: { "trust-e" })
        let long = String(repeating: "Find the cheapest cable and add it to the cart. ", count: 12) + "END-OF-BRIEF"
        let card = plan.plan([handOff("a", brief: long, english: true)], intent: "t", home: home).cards[0]
        XCTAssertTrue(card.detail.replacingOccurrences(of: "\n", with: "").contains(long.replacingOccurrences(of: "\n", with: "")), "never cut: \(card.detail)")
        XCTAssertTrue(card.detail.contains(ArisHandOffCard.textLead(english: true)))
        XCTAssertTrue(card.detail.contains(ArisHandOffCard.onceLine(english: true)))
    }

    /// The fallback of "always" never shows a capability's id (cap12/B1-showall.jpg: "보내기 · aris.aside_task").
    func testAlwaysScopeNeverShowsAnInternalID() {
        let item = ArisAskItem(call: "x", facts: ArisCallFacts(capability: "aris.send_message", arguments: []), effect: .outward, decision: .ask,
                               provenance: .ownStep)
        let scope = ArisAskPlan.alwaysScope([item], home: home)
        XCTAssertFalse(scope.joined().contains("aris."), scope.joined())
    }

    /// B4, B6, B7 ("주인님 규칙으로…", "결제는 주인이 직접 하셔야 해서"): the rule appended to every brief named the
    /// owner "주인"/"owner", and the jobs' models said it back to them. No rule text calls him that.
    func testTheRuleNeverCallsHimOwnerOrMaster() {
        for english in [false, true] {
            let clause = ArisPaymentBoundary.stopClause(english: english)
            for word in ["주인", "master", "Master", "owner", "Owner"] { XCTAssertFalse(clause.contains(word), "\(word) in \(clause)") }
            // Still the same rule: it is a stop, and a brief carrying it is judged as before.
            XCTAssertEqual(ArisPaymentBoundary.judge(brief: "장바구니에 담고 결제 화면 직전까지만 진행해.\n\n" + clause, request: "에어팟 사 줘"), .stopsAtPayment)
            XCTAssertEqual(ArisPaymentBoundary.judge(brief: "결제까지 진행해.\n\n" + clause, request: "에어팟 사 줘"), .refused)
            XCTAssertEqual(ArisPaymentBoundary.bounded("x", english: english), "x\n\n" + clause)
        }
        for line in [ArisPaymentBoundary.refusedLine, ArisPaymentBoundary.replyRule, ArisPaymentBoundary.replyNote(english: false), ArisPaymentBoundary.replyNote(english: true)] {
            XCTAssertFalse(line.contains("주인"), line)
        }
    }
    // MARK: - 2a: Aris's own hands in a browser, in a turn about paying (record-full 01:49:09–01:50:25)

    private func browserAct(_ capability: String, target: String) -> ArisCallFacts {
        ArisCallFacts(capability: capability, arguments: [.init(kind: .app, value: "Safari")], browser: ArisBrowserPage(host: "www.amazon.com", target: target))
    }

    func testInATurnAboutPayingAPayButtonIsNeverPressedAndACheckoutPageTakesOnlyMovingKeys() {
        let product = "https://www.amazon.com/dp/B0000/ref=sr_1_1", checkout = "https://www.amazon.com/gp/buy/spc/handlers/display.html"
        // The recorded press on the product page ("See options" click, then app.press): each asks; a pay button is refused.
        XCTAssertEqual(ArisCheckoutGuard.decide(.runWithUndo(announce: false), facts: browserAct("app.click", target: "See options"), payingTurn: true, address: product,
                                                words: ["See options"], keys: nil), .ask)
        for label in ["Place your order", "Buy Now", "결제하기", "주문하기"] {
            if case .refuse = ArisCheckoutGuard.decide(.ask, facts: browserAct("app.click", target: label), payingTurn: true, address: checkout,
                                                       words: [label], keys: nil) {} else { XCTFail(label) }
        }
        if case .refuse = ArisCheckoutGuard.decide(.ask, facts: browserAct("app.press", target: ""), payingTurn: true, address: checkout, words: [], keys: "return") {} else {
            XCTFail("Return on a checkout page")
        }
        // An unread address is a checkout page (a miss is never looser than a hit).
        if case .refuse = ArisCheckoutGuard.decide(.ask, facts: browserAct("app.press", target: ""), payingTurn: true, address: nil, words: [], keys: "enter") {} else {
            XCTFail("Enter on an unread page")
        }
        XCTAssertEqual(ArisCheckoutGuard.decide(.runWithUndo(announce: false), facts: browserAct("app.press", target: ""), payingTurn: true, address: checkout, words: [], keys: "tab"), .ask)
        XCTAssertEqual(ArisCheckoutGuard.decide(.ask, facts: browserAct("app.press", target: ""), payingTurn: true, address: product, words: [], keys: "return"), .ask)
        // Outside a turn about paying, and outside a browser, nothing changes.
        XCTAssertEqual(ArisCheckoutGuard.decide(.ask, facts: browserAct("app.click", target: "Buy Now"), payingTurn: false, address: checkout, words: ["Buy Now"], keys: nil), .ask)
        let textEdit = ArisCallFacts(capability: "app.click", arguments: [.init(kind: .app, value: "TextEdit")])
        XCTAssertEqual(ArisCheckoutGuard.decide(.runWithUndo(announce: false), facts: textEdit, payingTurn: true, address: nil, words: ["결제"], keys: nil), .runWithUndo(announce: false))
        XCTAssertTrue(ArisCheckoutGuard.isCheckout(address: "https://www.coupang.com/vp/cart") && !ArisCheckoutGuard.isCheckout(address: product))
    }
    // MARK: - 5: a reply about later work is built from what was scheduled (history.json, job 4854C40C)

    func testAReplyNeverPromisesLaterWorkNothingWasScheduledFor() {
        let b6 = "내일 아침 9시에 쿠팡에서 휴지 주문하라고 알림을 걸어 뒀어요. 결제는 주인이 직접 하셔야 해서, 9시에 장바구니까지 준비해 두고 결제 직전에서 멈출게요."
        let checked = ArisLaterPromise.checked(b6, scheduled: false, korean: true)
        XCTAssertEqual(checked, "내일 아침 9시에 쿠팡에서 휴지 주문하라고 알림을 걸어 뒀어요. " + ArisLaterPromise.line(korean: true))
        XCTAssertEqual(ArisLaterPromise.checked(b6, scheduled: true, korean: true), b6, "a schedule was added: the promise may be true")
        XCTAssertEqual(ArisLaterPromise.checked("I set a reminder for 9 am. I'll fill the cart at 9 am and stop before paying.", scheduled: false, korean: false),
                       "I set a reminder for 9 am. " + ArisLaterPromise.line(korean: false))
        for plain in ["알림을 걸어 뒀어요.", "다 했어요. 되돌릴 수 있어요.", "결제 화면까지 채워 둘 수 있어요."] {
            XCTAssertEqual(ArisLaterPromise.checked(plain, scheduled: false, korean: true), plain)
        }
    }
    // MARK: - 6, 7: a taught run's cards (notes12/L2-taught.json; cap12/M2-card1.jpg)

    /// notes12/L2-taught.json, as the VM's recorder saved it on c158b146.
    static let savedL2 = """
    [{"changed":"2026-11-21T01:27:27Z","created":"2026-11-21T01:27:27Z","id":"91EBC188-37C7-44F3-AF28-DC172F20DDB5","name":"줄 추가",
      "parameters":[{"app":"TextEdit","example":"Added line","fromApp":false,"key":"p1","label":"본문"}],"skipped":0,
      "steps":[{"action":"open","app":"TextEdit","bundle":"com.apple.TextEdit"},
               {"action":"type","app":"TextEdit","bundle":"com.apple.TextEdit","fromApp":false,"label":"본문","parameter":"p1","place":"end",
                "role":"textArea","seen":{"kind":"app","source":"TextEdit"},"startsLine":true,"target":"First Text View 칸"}]},
     {"changed":"2026-11-21T01:28:20Z","created":"2026-11-21T01:28:20Z","id":"D550D9EC-D5D9-4814-B45A-A2BEF31A0220","name":"메모 쓰기",
      "parameters":[{"app":"TextEdit","example":"Memo buy bread","fromApp":false,"key":"p1","label":"본문"}],"skipped":0,
      "steps":[{"action":"open","app":"TextEdit","bundle":"com.apple.TextEdit"},
               {"action":"type","app":"TextEdit","bundle":"com.apple.TextEdit","fromApp":false,"label":"본문","parameter":"p1","place":"end",
                "role":"textArea","seen":{"kind":"app","source":"TextEdit"},"startsLine":true,"target":"First Text View 칸"}]}]
    """

    static func saved() -> [ArisTeachProcedure] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ArisTeachProcedure].self, from: Data(savedL2.utf8))) ?? []
    }

    /// cap12/M2-card1.jpg: "2. TextEdit의 ‘본문’에 새 줄로 ↵[본문] 넣기 (직접 입력한 것 같아요: ‘Memo buy bread’)" for "메모 써 줘: 모레 회의 자료".
    func testTheUpFrontCardShowsTheValueThatWillBeTyped() throws {
        let procedures = Self.saved()
        let addLine = try XCTUnwrap(procedures.first), memo = try XCTUnwrap(procedures.last)
        for english in [false, true] {
            let card = ArisTaughtClash.card(addLine, clash: nil, values: ["p1": "우유"], english: english)
            XCTAssertTrue(card.detail.contains("우유"), card.detail)
            XCTAssertFalse(card.detail.contains("Added line") || card.detail.contains("[본문]") || card.detail.contains("[text]"), card.detail)
            let clash = ArisTaughtClash.card(memo, clash: ArisTaughtClash.builtIn(for: memo.name), values: ["p1": "모레 회의 자료"], english: english)
            XCTAssertTrue(clash.detail.contains("모레 회의 자료") && !clash.detail.contains("Memo buy bread"), clash.detail)
        }
        // A value he didn't give stays a blank to fill, never last time's or the example as if it were his.
        let blank = ArisTaughtClash.card(addLine, clash: nil, values: [:], english: false)
        XCTAssertTrue(blank.detail.contains("[본문]"), blank.detail)
    }

    /// The clash card said "아니요를 누르면 메모 앱으로 해요" over a 취소 button: the text names the button there is.
    func testTheClashCardNamesItsOwnButton() throws {
        let memo = try XCTUnwrap(Self.saved().last)
        let clash = ArisTaughtClash.builtIn(for: memo.name)
        let korean = ArisTaughtClash.card(memo, clash: clash, english: false).detail
        XCTAssertTrue(korean.contains("취소를 누르면") && !korean.contains("아니요를 누르면"), korean)
        let english = ArisTaughtClash.card(memo, clash: clash, english: true).detail
        XCTAssertTrue(english.contains("Cancel:"), english)
    }

    /// The value card's suggestion is the value used last time; only with none, the example he showed, said as that.
    func testTheValueCardSuggestsLastTimesValue() throws {
        let addLine = try XCTUnwrap(Self.saved().first)
        let missing = addLine.parameters
        let last = ArisTeachCopy.valuesCard(addLine, missing: missing, last: ["p1": "우유"], english: false).card.detail
        XCTAssertTrue(last.contains("지난번") && last.contains("우유") && !last.contains("Added line"), last)
        // Never run since he showed it: the value he showed then.
        let none = ArisTeachCopy.valuesCard(addLine, missing: missing, last: [:], english: false).card.detail
        XCTAssertTrue(none.contains("제안: 지난번 본문 ‘Added line’"), none)
        let english = ArisTeachCopy.valuesCard(addLine, missing: missing, last: ["p1": "milk"], english: true).card.detail
        XCTAssertTrue(english.contains("Suggestion, last time's text: ‘milk’") && !english.contains("Added line"), english)
    }
}
