//
//  ArisActSummary.swift
//  aris-tools
//
//  The activity log's lines for the acts that had none before the notch's receipt (ArisReceipt, in the app): a message
//  sent, a reminder added, a note saved, a fact remembered or forgotten, the calendar new events go in. Each is
//  "<what>: <which>", as the log's other lines are, and holds a name or a title only, never a message's or a note's
//  body. None of them has an undo. Written only after the act was seen to succeed, so the receipt built from them is
//  true. Foundation only, so the tests check the app reads every one of them.
//

import Foundation

enum ArisActSummary {
    /// A message Messages showed as sent; `who` is the name or number it was asked for.
    static func messageSent(to who: String) -> String { "메시지 보냄: \(who)" }

    static func reminderAdded(_ text: String) -> String { "미리 알림 추가: \(text)" }

    /// A note made in Notes; its title (the first line), when it has one.
    static func noteSaved(_ title: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "메모 저장" : "메모 저장: \(name)"
    }

    static func remembered(_ fact: String) -> String { "기억함: \(fact)" }

    static func forgot(_ count: Int) -> String { "기억 지움: \(count)개" }

    static func calendarChosen(_ name: String) -> String { "기본 캘린더: \(name)" }
}
