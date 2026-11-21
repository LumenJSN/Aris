//
//  ArisPlainAsk.swift
//  Shared/Core (aris-agent, tests)
//
//  Whether the owner's own words plainly ask for an add of what he is pointing at (the eleventh VM run, K1 and K2:
//  "이 문서에 적힌 할 일 미리 알림에 추가해 줘" got the card "시키지 않은 일이라 멈췄어요" because the checker, which is
//  never shown the document, answered unsure). Read only when the checker was unsure, and only to choose which card
//  goes up: an add their words name (the list's kind, an adding verb, and a pointing word) asks on today's card, which
//  shows every item; anything else it was unsure about keeps the stopped card. It never lets a call run. An allowlist
//  of two kinds. Pure.
//

import Foundation

enum ArisPlainAsk {
    /// The checked kinds this is for, by tool, with the words that name where their items go.
    static let places: [String: [String]] = [
        "todo": ["할 일", "할일", "미리 알림", "미리알림", "리마인더", "투두", "to-do", "todo", "to do", "reminder", "task"],
        "event": ["일정", "캘린더", "달력", "calendar", "event", "schedule"],
    ]
    static let adding = ["추가", "넣어", "적어", "등록", "add", "put", "save"]

    static func addsPointedItems(request: String, tool: String, verb: String) -> Bool {
        guard verb == "add", let names = places[tool] else { return false }
        return ArisGrounding.has(names, in: request) && ArisGrounding.has(adding, in: request) && ArisGrounding.points(request)
    }
}
