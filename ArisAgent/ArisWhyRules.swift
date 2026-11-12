//
//  ArisWhyRules.swift
//  aris-agent
//
//  The gate's reasons in the user's words, with what they can do instead. No reason is made up here: each rule is found by
//  the reason the gate itself recorded (ArisRiskPolicy.neverReason, the drivers' own refusals, ArisEscalation's and
//  ArisReadGate's fixed lines), and says what ArisRefusalWords tells the AI about the same refusal: the English is
//  that file's own wording turned to "you", the Korean says the same thing. The two hard lines (money, a mail) are
//  said in the gate's own Korean line, so they stay true when that line changes. A reason this doesn't know is not
//  explained: the answer quotes it as recorded. Foundation only (tested).
//

import Foundation

/// One rule in plain words: why it stopped the action, and what the user can do instead (nil when there is nothing to do).
struct ArisWhyRule: Equatable {
    let why: String
    let instead: String?
}

enum ArisWhyRules {
    /// How the gates' reasons begin when a refusal only follows the user's own answer (ArisRefusalWords.afterUsersNo and
    /// .afterChangedCard are these same words).
    static let afterUsersNo = "the user already said no"
    static let afterChangedCard = "the user's changed card"

    private struct Known {
        /// Any of these in the gate's reason (lower case) names the rule.
        let marks: [String]
        let korean: ArisWhyRule
        let english: ArisWhyRule
    }

    private static let known: [Known] = [
        Known(marks: ["names aris's own token or keys"],
              korean: ArisWhyRule(why: "Aris의 열쇠나 토큰을 건드리는 명령은 절대 하지 않아요", instead: nil),
              english: ArisWhyRule(why: "Aris never runs a command that names its own token or keys", instead: nil)),
        Known(marks: ["never-list command", "never-list for this command"],
              korean: ArisWhyRule(why: "Mac을 망가뜨릴 수 있는 명령(sudo, 홈 폴더 지우기 같은 것)은 여쭤보지도 않고 안 하게 돼 있어요", instead: "꼭 필요하면 터미널에서 직접 실행해 주세요."),
              english: ArisWhyRule(why: "it is on Aris's never-list (sudo, wiping the home folder and the like)", instead: "If you really need it, run it yourself in Terminal.")),
        Known(marks: ["computer use in a browser", ArisRiskPolicy.browserRefusal],
              korean: ArisWhyRule(why: "브라우저 안의 일은 화면을 직접 누르지 않고 Aside에게 맡기게 돼 있어요", instead: "웹사이트에서 할 일이라고 말씀해 주시면 Aside로 해요."),
              english: ArisWhyRule(why: "computer use is never used in a web browser (website work goes to Aside)", instead: "Ask for it as website work and Aside does it.")),
        Known(marks: ["system settings"],
              korean: ArisWhyRule(why: "그 시스템 설정(개인정보, 사용자, 암호)은 직접 바꾸시게 돼 있어요", instead: "시스템 설정에서 직접 바꿔 주세요."),
              english: ArisWhyRule(why: "that System Settings pane (privacy, users, passwords) is yours to change", instead: "Change it yourself in System Settings.")),
        Known(marks: ["computer use is never in"],
              korean: ArisWhyRule(why: "그 앱(터미널, 코드 편집기, 비밀번호 앱, AI와 자동화 앱)은 화면을 대신 다루지 않게 돼 있어요", instead: "그 앱 안의 일은 직접 해 주세요."),
              english: ArisWhyRule(why: "computer use is never used in that app (terminals, password stores and the like)", instead: "That app's work is yours to do.")),
        Known(marks: ["protected place"],
              korean: ArisWhyRule(why: "보호된 곳(Aris 자신의 폴더, 열쇠가 든 폴더)의 파일은 바꾸지 않게 돼 있어요", instead: nil),
              english: ArisWhyRule(why: "files in a protected place (Aris's folder, key folders) are never changed", instead: nil)),
        Known(marks: ["calendar or reminders driven by keys"],
              korean: ArisWhyRule(why: "캘린더와 미리 알림은 화면을 눌러서가 아니라 Aris의 일정 도구로만 바꾸게 돼 있어요", instead: "일정이나 미리 알림을 말로 다시 부탁해 주세요."),
              english: ArisWhyRule(why: "Calendar and Reminders are changed only with Aris's own event tool", instead: "Ask again for the event or reminder in words.")),
        Known(marks: [afterUsersNo],
              korean: ArisWhyRule(why: "그 요청에서 이미 ‘아니요’ 하신 카드가 있어서, 그 뒤로 여쭤봐야 하는 일은 더 하지 않았어요", instead: "다시 말씀해 주시면 새로 여쭤볼게요."),
              english: ArisWhyRule(why: "you had already said no to a card in that request, so nothing more was asked", instead: "Ask again and it asks afresh.")),
        Known(marks: [afterChangedCard],
              korean: ArisWhyRule(why: "카드에서 고쳐 주신 대로 이미 한 일이라 한 번 더 하지 않았어요", instead: nil),
              english: ArisWhyRule(why: "it was already done the way you changed it on the card, so it wasn't run twice", instead: nil)),
        Known(marks: ["hands-free"],
              korean: ArisWhyRule(why: "키나 이름 없이 들린 말(핸즈프리)로는 보내거나 지우거나 밖으로 나가는 일을 하지 않게 돼 있어요", instead: "키를 누르거나 이름을 불러서 다시 말씀해 주세요."),
              english: ArisWhyRule(why: "on a hands-free turn Aris doesn't send, delete or reach outside", instead: "Hold the key or say the name and ask again.")),
        Known(marks: ["after outside text"],
              korean: ArisWhyRule(why: "바깥 글을 읽은 대화에서는 그 일을 하지 않게 돼 있어요", instead: "새 대화를 시작해서 다시 말씀해 주세요."),
              english: ArisWhyRule(why: "that isn't done in a conversation that has read outside content", instead: "Start a new conversation and ask again.")),
    ]

    /// The rule behind the gate's reason, in plain words; nil when the reason isn't one this knows.
    static func plain(_ reason: String, korean: Bool) -> ArisWhyRule? {
        if let line = hardLine(reason, korean: korean) { return line }
        let lowered = reason.lowercased()
        if let rule = known.first(where: { $0.marks.contains { lowered.contains($0.lowercased()) } }) { return korean ? rule.korean : rule.english }
        if let read = ArisReadWhy.allCases.first(where: { ArisReadGate.status($0) == reason }) { return readRule(read, korean: korean) }
        return nil
    }

    /// Money and a mail (ArisEscalation's hard lines): the gate's own Korean line is the rule, as it stands today. In
    /// English, the words ArisRefusalWords tells the AI: money always; a mail only for the line this was written
    /// against (should that line change, the Korean line is quoted instead of an English that may no longer be true).
    private static func hardLine(_ reason: String, korean: Bool) -> ArisWhyRule? {
        if reason == ArisEscalation.moneyReason {
            return korean ? ArisWhyRule(why: reason, instead: "그 부분은 직접 해 주세요.")
                : ArisWhyRule(why: "Aris never pays, orders, subscribes or moves money", instead: "That part is yours to do.")
        }
        guard reason == ArisEscalation.mailReason else { return nil }
        if korean { return ArisWhyRule(why: reason, instead: nil) }
        return ArisWhyRule(why: mailInEnglish[reason] ?? "the gate's rule for mail: “\(reason)”", instead: nil)
    }

    /// The mail line in English, by the Korean line it says: the one of this tree, and the one the gate policy rewrite
    /// brings (ArisGateWords.lines has the same English for it).
    private static let mailInEnglish = [
        "메일은 초안까지만": "a mail is written as a draft only; sending it is yours",
        "내용을 카드에 다 보여 줄 수 없는 메일은 보내지 않아요": "I don't send a mail I can't show in full on the card",
    ]

    /// A read the judge blocked (ArisReadGate): the notch's own line in Korean; in English what the AI is told
    /// (ArisReadWhy.brain), said to the user.
    private static func readRule(_ why: ArisReadWhy, korean: Bool) -> ArisWhyRule {
        let told = why.brain.replacingOccurrences(of: "the user's", with: "your").replacingOccurrences(of: "the user", with: "you")
        return korean ? ArisWhyRule(why: "읽기를 막았어요 (\(why.notch))", instead: "꼭 필요한 읽기라면 무엇을 읽을지 콕 집어 다시 말씀해 주세요.")
            : ArisWhyRule(why: "a read was blocked: " + told, instead: "If you need that read, ask again and name exactly what to read.")
    }
}
