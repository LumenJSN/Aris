//
//  ArisConfirmWords.swift
//  Aris
//
//  The confirm card's own words in the UI's language (VM run, bug 4: "취소 / 허용" under an English card on an English
//  Mac): its buttons, their tooltips, 전체 보기, and the hints under a value the user is changing. The card's title and
//  details are made by the agent in the language of the request; these are the app's buttons, so they follow the Mac
//  like every other button. The yes button's special words come from the agent in either language (Aside's 설치 and
//  로그인 cards) and are drawn in the UI's. Foundation only (tested).
//

import Foundation

enum ArisConfirmWords {
    static func cancel(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("취소", "Cancel", english: english) }
    static func noHelp(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("아니 (N)", "No (N)", english: english) }
    static func yesHelp(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("응 (Y)", "Yes (Y)", english: english) }

    /// The yes button: the agent's special word when it sent one, 보내기 for a card with a recipient, else 허용.
    static func allow(_ label: String?, sends: Bool, english: Bool = ArisUIWords.english) -> String {
        switch label {
        case "설치", "Install": return ArisUIWords.text("설치", "Install", english: english)
        case "로그인", "Sign in": return ArisUIWords.text("로그인", "Sign in", english: english)
        default: return sends ? ArisUIWords.text("보내기", "Send", english: english) : ArisUIWords.text("허용", "Allow", english: english)
        }
    }

    /// Under a long card: the whole text, or the short one again.
    static func whole(expanded: Bool, english: Bool = ArisUIWords.english) -> String {
        expanded ? ArisUIWords.text("줄여 보기", "Show less", english: english) : ArisUIWords.text("전체 보기", "Show all", english: english)
    }

    /// Under a value that can't be used as it is typed.
    static func refused(time: Bool, english: Bool = ArisUIWords.english) -> String {
        time ? ArisUIWords.text("2026-11-06 18:00처럼 적어 주세요", "Write it like 2026-11-06 18:00", english: english)
             : ArisUIWords.text("이 값으로는 할 수 없어요", "It can't be done with this value", english: english)
    }

    /// Before the value as it first was, struck through.
    static func was(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("원래 ", "Was ", english: english) }
    static func editHelp(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("눌러서 고치기", "Click to change it", english: english) }
}
