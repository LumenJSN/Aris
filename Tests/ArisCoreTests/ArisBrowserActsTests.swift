import XCTest
@testable import ArisCore

/// Decision 2 (2026-11-18): a browser window through Aris's own engine. Looks run; every act asks on a card of its own
/// naming the site's host, never covered or kept; a password field is never typed into; a sign-in form only on the
/// owner's words asking to sign in.
final class ArisBrowserActsTests: XCTestCase {
    private let home = "/Users/user"

    private func facts(_ capability: String, page: ArisBrowserPage? = ArisBrowserPage(host: "shop.example", target: "장바구니 담기"),
                       text: String? = nil) -> ArisCallFacts {
        ArisCallFacts(capability: capability, arguments: [ArisKeyArgument(kind: .app, value: "Safari")] + (text.map { [ArisKeyArgument(kind: .body, value: $0)] } ?? []),
                      browser: page)
    }

    private func decide(_ facts: ArisCallFacts, _ effect: ArisEffectClass = .changeReversible, _ provenance: ArisCallProvenance = .ownerSaid,
                        grants: [ArisStandingGrant] = [], level: ArisTrustLevel = .standard) -> ArisDecision {
        ArisTrustPolicy.decide(facts, effect: effect, provenance: provenance, context: .init(level: level, grants: grants, home: home))
    }

    func testBrowsersByNameAndBundle() {
        for app in ["Safari", "Google Chrome", "arc", "com.apple.Safari", "company.thebrowser.Browser", "Firefox", "웨일"] { XCTAssertTrue(ArisBrowserActs.isBrowser(app), app) }
        for app in ["Notes", "Mail", "com.apple.mail", ""] { XCTAssertFalse(ArisBrowserActs.isBrowser(app), app) }
        XCTAssertEqual(ArisBrowserActs.host("https://www.Shop.example/cart?x=1"), "www.shop.example")
        XCTAssertNil(ArisBrowserActs.host("not an address"))
    }

    func testLooksRunAndEveryActAsks() {
        XCTAssertEqual(decide(facts("app.read", page: nil), .observe), .run, "a look at the page: no card")
        for capability in ["app.click", "app.type", "app.press", "app.select", "app.do"] {
            XCTAssertEqual(decide(facts(capability)), .ask, "\(capability) in a browser asks (it ran with its undo)")
            XCTAssertEqual(decide(facts(capability), .changeReversible, .ownerSaid, level: .free), .ask, "at every level")
        }
        let always = ArisStandingGrant(capability: "app.click", effect: .changeReversible, target: .init(kind: .app, pattern: "Safari"))
        XCTAssertEqual(decide(facts("app.click"), .changeReversible, .ownerSaid, grants: [always]), .ask, "no grant covers it")
        // A refusal stays a refusal: content that asks for an outward act on the page.
        guard case .refuse = decide(facts("app.click"), .outward, .content(ArisContentSource(kind: "web", source: "https://shop.example"))) else {
            return XCTFail("content never causes an outward act, in a browser too")
        }
        // Content suggesting a reversible act there: still a card (never run on its own).
        XCTAssertEqual(decide(facts("app.click"), .changeReversible, .content(ArisContentSource(kind: "web", source: "https://shop.example"))), .ask)
    }

    func testPasswordsAndSignIn() {
        let password = ArisBrowserPage(host: "bank.example", target: "비밀번호", secret: true, signIn: true, signInAsked: true)
        guard case .refuse(let typed) = decide(facts("app.type", page: password, text: "hunter2")) else { return XCTFail("never types into a password field") }
        XCTAssertEqual(typed, ArisBrowserActs.secretRefusal)
        XCTAssertEqual(decide(facts("app.click", page: password)), .ask, "clicking into it on their words asking to sign in: a card")
        var unasked = password
        unasked.signInAsked = false
        guard case .refuse = decide(facts("app.click", page: unasked)) else { return XCTFail("a sign-in form without their words asking: refused") }
        let button = ArisBrowserPage(host: "bank.example", target: "로그인", signIn: true, signInAsked: true)
        XCTAssertEqual(decide(facts("app.click", page: button)), .ask)
        guard case .refuse = decide(facts("app.click", page: button), .changeReversible, .ownStep) else {
            return XCTFail("only on his own words: a step Aris chose is refused")
        }
        XCTAssertTrue(ArisBrowserActs.namesSecret("Password") && ArisBrowserActs.namesSecret("비밀번호 입력") && !ArisBrowserActs.namesSecret("Spinner"))
        XCTAssertTrue(ArisBrowserActs.namesSignIn("Sign in") && ArisBrowserActs.namesSignIn("아이디") && !ArisBrowserActs.namesSignIn("장바구니"))
        XCTAssertTrue(ArisBrowserActs.asksForSignIn("네이버에 로그인해 줘") && !ArisBrowserActs.asksForSignIn("장바구니에 담아 줘"))
    }

    func testEachActIsACardOfItsOwnNamingTheHost() {
        var plan = ArisAskPlan()
        let item = { (call: String) in
            ArisAskItem(call: call, facts: self.facts("app.click"), effect: .changeReversible, decision: .ask, provenance: .ownerSaid)
        }
        let planned = plan.plan([item("c1"), item("c2")], intent: "t", home: home)
        XCTAssertEqual(planned.cards.count, 2, "one card per act")
        let card = planned.cards[0]
        XCTAssertEqual(card.title, "누르기 · shop.example")
        XCTAssertTrue(card.detail.hasPrefix("사이트: shop.example · Safari") && card.detail.contains("대상: 장바구니 담기"), card.detail)
        XCTAssertFalse(card.countdown)
        XCTAssertTrue(card.alwaysScope.isEmpty, "never 'always'")
        let yes = plan.answer(card.id, .always, home: home)
        XCTAssertEqual(yes.run, ["c1"])
        XCTAssertTrue(yes.grants.isEmpty, "nothing kept")
        let next = plan.plan([item("c3")], intent: "t", home: home)
        XCTAssertTrue(next.covered.isEmpty && next.cards.count == 1, "the next act on the page asks again")
        let unread = plan.plan([ArisAskItem(call: "c4", facts: facts("app.click", page: ArisBrowserPage()), effect: .changeReversible, decision: .ask,
                                            provenance: .ownerSaid)], intent: "t", home: home).cards[0]
        XCTAssertTrue(unread.detail.hasPrefix("사이트: 주소를 읽지 못했어요"), unread.detail)
    }
}
