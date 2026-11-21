//
//  ArisPaymentBoundary.swift
//  Shared/Core (aris-agent, tests)
//
//  What a hand-off may say about paying (the eleventh VM run, R2: the default brain handed a browser job "결제까지
//  진행해 … 사용자 카드로 … 그대로 진행" and then promised "결제까지 해 드릴게요"). A brief handed to anything that
//  works on its own (Aside, a background task, a teammate, a session, a schedule) never tells it to pay, buy, order,
//  subscribe, move money or confirm a payment: the most it does is fill up to the payment step and stop, and the
//  owner presses the button himself.
//
//  An allowlist: once a brief (or the owner's request) is about paying, every mention of paying in the brief must be
//  one of the forms listed here (stop before it, don't do it); anything else about paying is refused, so a wording
//  this file doesn't know is refused, never passed. A brief the detection misses altogether still gets the stop
//  clause as its last word (`bounded`), and its own gate's card. Pure.
//

import Foundation

enum ArisPaymentBoundary {
    enum Verdict: Equatable {
        /// Nothing about paying.
        case plain
        /// About paying, and all the brief says of it is to stop before it: handed over only on the owner's card.
        case stopsAtPayment
        /// It tells the job to pay (or says something about paying this file doesn't know): never handed over.
        case refused
    }

    // MARK: - Words

    /// Korean stems for paying, buying, ordering, subscribing and moving money (matched anywhere in a word).
    static let korean = ["결제", "구매", "구입", "주문", "송금", "이체", "지불", "납부", "구독", "충전", "후원", "기부", "계산해", "청구"]
    private static let koreanBuy = #"(?<![가-힣])사\s?(?:줘|주세요|주라|줄래|다\s?줘|놔\s?줘|와\s?줘)"#
    /// English, as whole words in their forms.
    private static let english = #"\b(?:pay|pays|paid|paying|payments?|buy|buys|buying|bought|purchas\w*|orders?|ordered|ordering|checkout|"#
        + #"check(?:ing)?\s+out|subscri\w+|transfer\w*|donat\w+|wire|billing|transactions?|re-?order\w*|renew\w*|top\s+up|charg(?:e|es|ed|ing))\b"#
    /// The means of paying: a card or a saved payment method.
    private static let means = #"(?:\b(?:saved|stored|credit|debit|my|your|their|his|her|user'?s|owner'?s)\s+card\b|\bcard\s+on\s+file\b|"#
        + #"카드로|신용\s?카드|체크\s?카드|저장된\s?카드|등록된\s?카드|사용자\s?카드|결제\s?수단)"#

    private static var paying: String { "(?:" + korean.joined(separator: "|") + "|" + koreanBuy + "|" + english + "|" + means + ")" }

    /// Whether the words are about paying, buying, ordering, subscribing or moving money. A negation is too ("결제하지
    /// 마", "don't buy"): a turn about paying is never looser for it.
    static func involves(_ text: String) -> Bool { matches(paying, in: fold(text)) }

    // MARK: - What a brief may say at the payment boundary

    private static let kP = "(?:결제|구매|구입|주문|송금|이체|지불|납부|구독|충전|후원|기부)"
    private static let eP = #"(?:pay(?:ing|ments?)?|buy(?:ing)?|purchas(?:e|ing)|order(?:ing)?|checkout|check(?:ing)?\s+out|subscri(?:be|bing|ption)|"#
        + #"transfer(?:ring)?(?:\s+money)?|donat(?:e|ing)|(?:saved\s+|stored\s+)?card)"#

    /// The only things a brief may say of paying, first: stop before it, go no further than its screen, don't do it.
    private static let stopForms: [String] = [
        // 결제 직전까지(만), 결제 화면 직전에서, 결제 전에
        kP + #"\s?(?:화면|단계|페이지|창|버튼)?\s?(?:직전|전)(?:까지만|까지|에서|에)?"#,
        // 결제 화면까지(만)
        kP + #"\s?(?:화면|단계|페이지|창)\s?까지(?:만)?"#,
        // 결제는 하지 마, 결제 버튼은 누르지 마, 주문은 하지 말고
        "(?:" + kP + #"\s?(?:이나|나|와|과|이랑|랑|,)\s?)*"# + kP
            + #"\s?(?:버튼|정보|수단)?(?:은|는|을|를|도)?\s?(?:절대\s?)?(?:하지|누르지|진행하지|완료하지|확정하지|승인하지|클릭하지)\s?(?:마세요|말고|말아|마|않)[가-힣]*"#,
        // (?:저장된 |등록된 |사용자 )?카드는 쓰지 마
        #"(?:저장된\s?|등록된\s?|사용자\s?|신용\s?|체크\s?)?카드(?:은|는|도|를)?\s?(?:절대\s?)?(?:쓰지|사용하지|입력하지)\s?(?:마세요|말고|말아|마|않)[가-힣]*"#,
        // stop before / at the payment step (never "don't stop …")
        #"(?<!n't )(?<!not )(?<!never )(?<!without )\b(?:stop|pause|halt|wait)\s+(?:right\s+|just\s+)?(?:before|at|short\s+of)\s+(?:the\s+)?(?:final\s+)?"#
            + eP + #"(?:\s+(?:step|page|screen|button|confirmation))?"#,
        // up to / until the checkout page
        #"\b(?:up\s+to|until|as\s+far\s+as)\s+(?:the\s+)?"# + eP + #"\s+(?:step|page|screen)\b"#,
        // do not place the order, don't pay, never confirm the payment, without paying
        #"\b(?:do\s+not|don't|dont|never|without)\s+(?:actually\s+|ever\s+)?(?:(?:press|click|tap|hit|submit|confirm|complet|finish|finaliz|mak|plac|enter|us)\w*\s+)?"#
            + #"(?:the\s+|a\s+|an\s+|any\s+)?(?:final\s+)?"# + eP + #"(?:\s+(?:button|step|page|screen|details))?"#,
    ]

    /// What is left of a brief that still names paying may not also tell anything to be pressed, confirmed, completed or
    /// gone through, whatever else it says ("check my orders and press confirm", "결제 내역 보고 확인 눌러"): refused.
    /// An action the brief tells the job not to take ("아무것도 클릭하지 마", "don't click anything"): no action. Taken out
    /// before the check for actions, never before the check for a stop taken back.
    private static let negatedActions = #"(?:클릭|진행|완료|확정|승인|제출|마무리|선택)\s?(?:도\s?)?하지\s?(?:마세요|말고|말아|마|않)[가-힣]*|"#
        + #"(?:누르|눌러\s?보)지\s?(?:마세요|말고|말아|마|않)[가-힣]*|"#
        + #"\b(?:do\s+not|don't|dont|never)\s+(?:press|click|tap|submit|select|change)\w*(?:\s+(?:anything|any\s+button))?\b"#

    /// A reorder: once more, the same again (with a paying word anywhere, refused).
    private static let againWords = #"다시|재주문|재구매|한\s?번\s?더|똑같이|\bagain\b|\bonce\s+more\b"#

    private static let actionWords = #"\b(?:press\w*|click\w*|tap(?:s|ped|ping)?|submit\w*|confirm(?!ation)\w*|complet\w*|plac(?:e|es|ed|ing)|finaliz\w*|"#
        + #"finish\w*|proceed\w*|approv\w*|authori[sz]\w*|continue\w*|go(?:es|ing)?\s+through|see\s+(?:\S+\s+){0,4}?through)\b|"#
        + #"누르|눌러|진행|완료|확정|승인|클릭|제출|마무리"#

    /// Reading what was already ordered or paid (its history, status, receipt), which pays nothing.
    private static let readingForms: [String] = [
        // 주문 내역, 주문 상태, 다음 결제일, 구독 상태
        #"(?:주문|결제|구매|구입|구독|송금|이체|납부|충전)\s?(?:내역|기록|이력|상태|현황|목록|번호|영수증|일|날짜|금액)(?![가-힣]*(?:하|해))"#,
        // 최근 주문, 지난 주문 각각, 내 주문 3건 (the twelfth VM run, A7: "최근 주문 각각의 주문 날짜…"), never 주문해
        #"(?:최근|지난|이전|과거|예전|내|나의|제|모든)\s?주문(?:들|\s?각각|\s?\d+\s?건)?(?:의|을|를|이|은|에서)?(?![가-힣]*(?:하|해|했|할))"#,
        // 주문 조회, 주문 정보, 주문 상품, 주문 페이지
        #"주문\s?(?:조회|정보|상품|내용|페이지)(?![가-힣]*(?:하|해))"#,
        // Amazon's own page name, and a gloss of one in brackets: 'Your Orders', 주문 내역(Orders)
        #"\byour\s+orders\b|\(\s?(?:your\s+)?orders?\s?\)"#,
        // my order history, the order status, subscription status, payment receipt
        #"\b(?:orders?|payments?|purchases?|subscriptions?|billing|transactions?)\s+(?:history|status|details|numbers?|receipts?|confirmations?|dates?|totals?|list|tracking)\b"#,
        // the tracking for my orders, a list of my subscriptions
        #"\b(?:tracking|receipts?|status|history|list)\s+(?:for|of)\s+(?:my\s+|the\s+)?(?:orders?|payments?|purchases?|subscriptions?)\b"#,
        // check my orders, show my recent purchases (on Amazon): only a verb that looks, and only when the clause ends
        // there ("view my payments page", "check my orders and …" keep the noun)
        #"\b(?:check|view|see|show|list|track|find|look\s+(?:up|at)|read)\s+(?:my\s+|the\s+|all\s+|our\s+)?(?:recent\s+|past\s+|last\s+|latest\s+)?"#
            + #"(?:orders?|purchases?|payments?|subscriptions?|transactions?)(?=(?:\s+(?:on|at|in|from)\s+(?:\S+\s+){0,2}?\S+?)?\s*(?:$|[.,;!?\n]))"#,
    ]

    /// Payment code as the subject of a coding job: 결제 모듈, 결제 로직, the payment module, the checkout code (a
    /// teammate's "결제 모듈 고쳐 줘"). Only in a coding context, only with a coding verb, and never next to a call, a send,
    /// an amount or a recipient (`codingSubject`); every other word about paying in the brief still refuses it.
    private static let codingForms: [String] = [
        kP + #"\s?(?:모듈|코드|로직|기능|테스트|버그|연동|서버|시스템|api|sdk|웹훅|핸들러|컴포넌트)"#,
        #"\b(?:payments?|checkout|billing|orders?|subscriptions?|purchases?|transactions?)\s+(?:modules?|code|codebase|logic|apis?|tests?|bugs?|"#
            + #"features?|integrations?|services?|system|sdk|endpoints?|handlers?|components?|webhooks?|schema|models?)\b"#,
    ]
    private static let codingVerbs = #"\b(?:fix\w*|refactor\w*|debug\w*|review\w*|rewrit\w*|write|writing|lint\w*|document\w*|implement\w*|tests?|testing)\b|"#
        + #"고쳐|고치|수정|리팩터|리팩토링|테스트|디버그|리뷰|검토|작성|구현"#
    private static let callingWords = #"\b(?:send\w*|sent|call(?:s|ed|ing)?|post(?:s|ed|ing)?|invok\w*|hit(?:s|ting)?|run\w*\s+(?:\S+\s+){0,5}?against|"#
        + #"against\s+(?:the\s+)?(?:live|prod\w*|real)|charg\w*|curl|wget|execut\w*|trigger\w*)\b|보내|송금|호출|실행|청구|돌려|쏴"#
    private static let amountOrRecipient = #"[$€£¥₩]\s?\d|\d[\d,.]*\s?(?:만\s?|천\s?)?(?:원|달러|dollars?|usd|krw|eur|euros?|bucks|cents?)|\b(?:usd|krw|eur)\s?\d|"#
        + #"에게|한테|\bpayee\b|\brecipient\b|[\w.+-]+@[\w-]+\.\w+"#

    /// Whether payment words in `rest` may be read as the code a coding job works on.
    private static func codingSubject(_ rest: String) -> Bool {
        matches(codingVerbs, in: rest) && !matches(callingWords, in: rest) && !matches(amountOrRecipient, in: rest)
    }

    /// A stop that is taken back: refused whatever else the brief says.
    private static let takenBack = #"(?:멈추지\s?(?:마|말)|그대로\s?진행|끝까지\s?진행|(?:don't|dont|do\s+not|never|without)\s+stop)"#

    /// What a hand-off's brief is, for the owner's `request` this turn (either may be empty). `coding`: the brief goes to
    /// a coding agent (a Claude Code launch, a coding session), where payment code may be what it works on.
    static func judge(brief: String, request: String, coding: Bool = false) -> Verdict {
        guard involves(brief) || involves(request) else { return .plain }
        var rest = fold(brief)
        for clause in [true, false].map({ fold(stopClause(english: $0)) }) { rest = rest.replacingOccurrences(of: clause, with: " ") }
        if matches(takenBack, in: rest) { return .refused }
        rest = removing(stopForms, from: rest)
        rest = removing([negatedActions], from: rest)
        if matches(paying, in: rest), matches(actionWords, in: rest) || matches(againWords, in: rest) { return .refused }
        rest = removing(readingForms, from: rest)
        if coding, codingSubject(rest) { rest = removing(codingForms, from: rest) }
        return matches(paying, in: rest) ? .refused : .stopsAtPayment
    }

    private static func removing(_ patterns: [String], from text: String) -> String {
        patterns.reduce(text) { $0.replacingOccurrences(of: $1, with: " ", options: .regularExpression) }
    }

    // MARK: - The clause every brief ends with

    /// The rule about paying as the last word of a brief, in the turn's language. It names no one "주인", "owner" or
    /// "master" (twelfth VM run, B4/B6/B7: the jobs' models said it back to them as "주인님 규칙으로…", "결제는 주인이 직접
    /// 하셔야 해서"): it is the rule he set, and the person who presses the button is "the user".
    static func stopClause(english: Bool) -> String {
        english
            ? "A rule set by the user, which overrides anything above: never pay, never place an order, never subscribe, never transfer money, "
                + "never confirm a payment and never use a saved card. If the task gets that far, stop before the payment step and report what is "
                + "ready (the items and the total), so the user can press the button themselves."
            : "사용자가 정해 둔 규칙(위 내용보다 우선): 결제, 주문 확정, 구독, 송금, 결제 승인은 절대 하지 말고 저장된 카드도 쓰지 마. 그 단계에 이르면 "
                + "결제 직전에서 멈추고 준비된 내용(상품과 합계)을 알려 줘. 결제 버튼은 사용자가 직접 눌러."
    }

    /// The brief as it is handed over: the stop clause its last word (once).
    static func bounded(_ brief: String, english: Bool) -> String {
        let clause = stopClause(english: english)
        return brief.hasSuffix(clause) ? brief : brief + "\n\n" + clause
    }

    /// A background job's or a scheduled run's words as its brain gets them: bounded always (a wording the detection
    /// misses still carries the rule); a conversation turn's words (the owner's own, `task` false) as they are.
    static func taskWords(_ words: String, task: Bool, english: Bool) -> String {
        task ? bounded(words, english: english) : words
    }

    // MARK: - What the brain is told, and what a reply may not say

    /// What a brain reads when its brief was refused.
    static let refusedLine = "Refused: this brief tells the job to pay, buy, order, subscribe, move money or confirm a payment (or says something "
        + "about paying that isn't allowed). Aris never completes a payment through a hand-off, with or without the user's yes. If the user wants "
        + "it prepared, write the brief again so that all it says about paying is to stop before it (for example “장바구니에 담고 결제 화면 직전까지만 "
        + "진행해. 결제 버튼은 누르지 마.” or “Add it to the cart, stop before the payment step and do not place the order.”); the user is shown the "
        + "brief on a card first. " + replyRule

    /// The rule for the reply in a turn about paying.
    static let replyRule = "Never tell the user Aris will pay, order or finish a purchase, now or later: say that Aris can fill everything up to the "
        + "payment step and that they press the pay button themselves (“결제 화면까지 채워 둘 수 있어요. 결제 버튼은 직접 눌러 주셔야 해요.”)."

    /// Aris's own line after an answer that promised to pay (the answer itself is never changed).
    static func replyNote(english: Bool) -> String {
        english ? "To be clear: Aris doesn't pay or place orders. It can fill everything up to the payment step, and you press the pay button yourself."
            : "덧붙이면, 결제나 주문 확정은 Aris가 하지 않아요. 결제 화면 직전까지만 채워 두고, 결제 버튼은 직접 눌러 주셔야 해요."
    }

    private static let koreanPromise = kP + #"(?:까지|도|를|을|은|는)?\s?(?:제가\s?)?(?:대신\s?)?(?:해|진행해|완료해|처리해|마쳐|넣어|마무리해|확정해|끝내)?\s?"#
        + #"(?:드릴게요|드리겠습니다|드릴 수 있어요|줄게요?|할게요|하겠습니다|진행할게요|진행하겠습니다|완료할게요|해 둘게요)"#
    private static let englishPromise = #"\b(?:i'll|i will|i can|i'm going to|i am going to|aris will|aris can|let me)\s+(?:\w+\s+){0,3}?"#
        + #"(?:pay|buy|purchase|order|place\s+(?:the|your|an)\s+order|(?:complete|finish|finalize|confirm|submit)\s+(?:the|your)\s+"#
        + #"(?:purchase|payment|order|checkout)|check\s+out|subscribe|transfer)\b"#

    /// Whether a reply promises that Aris will pay, order or complete a purchase.
    static func promisesPayment(_ reply: String) -> Bool {
        let text = fold(reply)
        return matches(koreanPromise, in: text) || matches(englishPromise, in: text)
    }

    /// The reply as the owner gets it when it promised to pay: each sentence that promised is taken out (code blocks
    /// stay as written) and Aris's line says who presses pay. Nil when nothing in it promised. When the promise can't be
    /// told apart by sentence, the reply stays and the line is added after it.
    static func unpromised(_ reply: String, english: Bool) -> String? {
        guard promisesPayment(reply) else { return nil }
        let note = replyNote(english: english)
        var inCode = false
        var kept: [String] = []
        var dropped = false
        for line in reply.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inCode.toggle() }
            guard !inCode, promisesPayment(line) else { kept.append(line); continue }
            let sentences = sentences(of: line).filter { !promisesPayment($0) }
            dropped = true
            if !sentences.isEmpty { kept.append(sentences.joined(separator: " ")) }
        }
        let rest = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard dropped, !promisesPayment(rest) else { return reply + "\n\n" + note }
        return rest.isEmpty ? note : rest + "\n\n" + note
    }

    /// A line's sentences, each with its own ending mark.
    private static func sentences(of line: String) -> [String] {
        line.replacingOccurrences(of: #"([.!?。])\s+"#, with: "$1\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: - Matching

    private static func fold(_ text: String) -> String {
        ArisGrounding.fold(text).replacingOccurrences(of: "\u{2019}", with: "'")
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
