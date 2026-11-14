//
//  ArisNoticeWords.swift
//  Aris
//
//  The notification cards' own words, Korean and English (the news itself brings its own). Foundation only (tested).
//

import Foundation

enum ArisNoticeWords {
    static func view(english: Bool) -> String { english ? "View" : "보기" }
    static func close(english: Bool) -> String { english ? "Close" : "닫기" }
    static func showLess(english: Bool) -> String { english ? "Show less" : "접기" }
    static func more(_ count: Int, english: Bool) -> String { english ? "+\(count) more" : "+\(count)개 더" }
    /// The title of a problem card made from one of the app's own lines.
    static func needsYou(english: Bool) -> String { english ? "Needs your attention" : "확인이 필요해요" }
    static func asks(english: Bool) -> String { english ? "Has a question" : "질문이 있어요" }
    static func helperDownBody(english: Bool) -> String {
        english ? "Restarting it usually brings it back." : "다시 시작하면 보통 돌아와요."
    }
}
