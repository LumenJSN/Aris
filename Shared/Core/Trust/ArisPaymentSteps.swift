//
//  ArisPaymentSteps.swift
//  Shared/Core (aris-agent, tests)
//
//  Decision 1 (2026-11-18): which steps the capability registry marks as payments, so they ask on a card of their
//  own every time (ArisTrustPolicy.payment): a button, menu item or command whose words pay, buy, order, check out,
//  donate or move money ("결제하기", "Buy now", "Place your order", "송금"); "subscribe" alone is not one (a newsletter's
//  box, a channel). Matched on folded words: a
//  Korean word anywhere, an English one as a whole word. Pure.
//

import Foundation

enum ArisPaymentSteps {
    static let korean = ["결제", "구매", "구입", "주문하기", "주문 하기", "주문 완료", "주문완료", "주문 확정", "송금", "이체", "지불", "납부", "후원하기",
                         "기부하기", "바로 구매", "바로구매", "충전하기"]
    static let english = ["pay", "pay now", "payment", "buy", "buy now", "purchase", "complete purchase", "checkout", "check out", "place order",
                          "place your order", "order now", "submit order", "confirm order", "confirm payment", "donate", "send money",
                          "transfer money", "top up"]

    /// Whether the words of a step (a button's label, a menu path, a command's name) are a payment.
    static func names(_ text: String) -> Bool {
        let folded = ArisGrounding.fold(text)
        guard !folded.isEmpty else { return false }
        if korean.contains(where: { folded.contains($0) }) { return true }
        let spaced = " " + folded.map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce("") { $0 + String($1) }
            .split(separator: " ").joined(separator: " ") + " "
        return english.contains { spaced.contains(" " + $0 + " ") }
    }
}
