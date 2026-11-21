import XCTest
@testable import ArisCore

/// The twelfth real-screen VM run, A7 (notes12/actions-full.log 00:36:32–38): "아마존 주문 내역 보여 줘" handed Aside five
/// read-only briefs and every one was refused by the payment rule. The log keeps each brief's first words and its length
/// (‹+N자›); the rest of each is rebuilt here in the same shape (where the log cuts, the tail is ours, marked).
final class ArisRel12PaymentTests: XCTestCase {
    private let request = "아마존 주문 내역 보여 줘"

    /// Recorded prefix, then the rebuilt tail.
    private let recorded: [String] = [
        "Amazon(아마존)에 로그인된 상태로 주문 내역(Orders) 페이지를" + " 열고, 최근 주문들의 주문 날짜, 상품명, 금액, 배송 상태를 확인해서 알려 줘. 아무것도 클릭하지 말고 보기만 해.",
        "Amazon(아마존)에 로그인된 상태로 주문 내역(Orders) 페이지를" + " 열어 최근 주문 목록을 읽고 상품명, 주문 날짜, 배송 상태를 정리해 줘. 읽기만 하고 아무것도 누르지 마.",
        "아마존(Amazon) 사이트에서 내 주문 목록 페이지를 찾아 열고, 최근" + " 주문 각각의 상품명, 주문 날짜, 금액, 배송 상태를 알려 줘. 결제나 주문은 하지 마.",
        "amazon.com 에서 내 계정의 'Your Orders' 페이지를 열고, 최근 주문 각각의 주문 날짜, 상품명, 금액, 배송 상" + "태를 한 줄씩 알려 줘. 아무것도 구매하지 마.",
        "amazon.com 에서 내 계정의 주문 내역(Your Orders) 페" + "이지를 열고 최근 주문 3건의 상품명, 금액, 배송 상태를 알려 줘. 결제나 주문은 하지 마.",
    ]

    func testTheRecordedOrderHistoryBriefsPass() {
        for brief in recorded {
            XCTAssertNotEqual(ArisPaymentBoundary.judge(brief: brief, request: request), .refused, brief)
            XCTAssertNotEqual(ArisPaymentBoundary.judge(brief: brief, request: ""), .refused, brief)
        }
    }

    func testPlainlyReadOnlyWordingsPass() {
        for brief in ["아마존 주문 내역 보여 줘", "쿠팡 주문 내역 확인해 줘", "아마존 주문 내역 알려 줘", "쿠팡에서 최근 주문 배송 조회해 줘", "내 주문 상태 알려 줘",
                      "아마존 영수증 찾아 줘, 지난 주문 영수증", "Show me Your Orders on amazon.com", "check my order status and tell me when it arrives"] {
            XCTAssertNotEqual(ArisPaymentBoundary.judge(brief: brief, request: brief), .refused, brief)
        }
    }

    /// Reading mixed with acting, or a reorder, still refuses: decided per wording.
    func testReadingWithAnActionStillRefuses() {
        for brief in ["주문 내역 페이지를 열고 최근 주문 다시 해 줘", "최근 주문 그대로 한 번 더 넣어 줘", "Your Orders 페이지에서 Buy it again 눌러",
                      "주문 내역(Orders) 열고 첫 번째 주문 취소 버튼 클릭해", "최근 주문 확정해 줘", "Open Your Orders and place the order again",
                      "주문 내역 보고 아무것도 클릭하지 말고 결제해", "내 주문 결제해 줘", "최근 주문 각각 다시 주문해 줘", "주문 목록 보고 재주문해"] {
            XCTAssertEqual(ArisPaymentBoundary.judge(brief: brief, request: ""), .refused, brief)
        }
    }
}
