//
//  ArisCheckoutGuard.swift
//  Shared/Core (aris-agent, tests)
//
//  The payment boundary for Aris's own hands in a browser (twelfth VM run, B3: "Buy the cheapest USB-C cable on Amazon
//  and check out" — after the Aside hand-off failed, the job drove Amazon in Safari through app.open, app.click and
//  app.press). In a turn (or a job) about paying, an act on a browser's page goes at most up to the payment step, as
//  every hand-off's brief does (ArisPaymentBoundary):
//    - a click, choice or command whose words pay or order (ArisPaymentSteps), or one the registry marks as a payment,
//      is refused: the owner presses that button himself;
//    - on a cart, checkout or payment page, or a page whose address couldn't be read (a miss is never looser than a
//      hit), keys are pressed only from a short list that moves around a form (Tab, arrows, Escape); any other key
//      (Return submits) is refused;
//    - every other act asks on its own card, as decision 2 has it.
//  Outside a turn about paying nothing here changes. Only stricter. Pure.
//

import Foundation

enum ArisCheckoutGuard {
    /// Words of a page's address that make it a cart, checkout or payment page (a path segment or a host's first label).
    static let checkoutWords: Set<String> = ["cart", "carts", "basket", "bag", "checkout", "check-out", "buy", "payment", "payments", "pay", "order",
                                             "orders", "purchase", "billing", "spc", "shipping", "placeorder", "place-order"]

    /// The keys a form may be moved through with on such a page; anything else is refused there.
    static let movingKeys: Set<String> = ["tab", "shift+tab", "up", "down", "left", "right", "esc", "escape", "pageup", "pagedown", "home", "end"]

    static let payButtonLine = "결제나 주문 버튼은 Aris가 누르지 않아요. 결제 화면 직전까지만 해 두고, 그 버튼은 직접 눌러 주세요. "
        + "(Aris doesn't press a pay or order button; it goes up to the payment step and you press it yourself.)"
    static let checkoutKeysLine = "결제·주문 화면에서는 칸 사이를 옮기는 키(Tab, 화살표, Esc)만 눌러요. "
        + "(On a cart, checkout or payment page Aris presses only keys that move through the form.)"

    /// Whether an address is a cart, checkout or payment page. Nil (couldn't be read) counts as one.
    static func isCheckout(address: String?) -> Bool {
        guard let address, let url = URL(string: address), let host = url.host?.lowercased() else { return true }
        let segments = url.path.lowercased().split(separator: "/").flatMap { $0.split(whereSeparator: { "._".contains($0) }) }.map(String.init)
        if segments.contains(where: checkoutWords.contains) { return true }
        let first = host.split(separator: ".").first.map(String.init) ?? ""
        return ["checkout", "pay", "payment", "payments", "cart", "order", "secure"].contains(first)
    }

    /// The keys of an app.press are all on the moving list.
    static func onlyMoves(_ keys: String) -> Bool {
        let pressed = keys.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return !pressed.isEmpty && pressed.allSatisfy(movingKeys.contains)
    }

    /// The decision for an act in a browser in a turn about paying, after every other rule. `address`: the page's
    /// address as read now; `words`: the call's target, option, command and the element's label.
    static func decide(_ decided: ArisDecision, facts: ArisCallFacts, payingTurn: Bool, address: String?, words: [String], keys: String?) -> ArisDecision {
        guard payingTurn, facts.browser != nil else { return decided }
        if case .refuse = decided { return decided }
        if facts.registeredPayment || words.contains(where: ArisPaymentSteps.names) { return .refuse(reason: payButtonLine) }
        if facts.capability == "app.press", isCheckout(address: address), !onlyMoves(keys ?? "") { return .refuse(reason: checkoutKeysLine) }
        switch decided {
        case .run, .runWithUndo, .sayThenRun: return .ask
        case .readBackThenAsk, .ask, .refuse: return decided
        }
    }
}
