//
//  ArisSideTab.swift
//  Aris
//
//  The side notches' tabs, and which of them show: each can be turned off in settings (노치 · 사이드 노치), and a
//  side with every tab off never comes out. What is stored is the tabs turned off, so a tab added later shows until
//  it is turned off too. A tab turned off also stops what runs behind it (ArisSideTabWork). Foundation only (tested).
//

import Foundation

enum ArisSideEdge: String, CaseIterable { case left, right }

/// In each panel's order, the left side's first.
enum ArisSideTab: String, CaseIterable, Equatable {
    case history, activity, clipboard, usage, todo, calendar

    var edge: ArisSideEdge {
        switch self {
        case .history, .activity, .clipboard, .usage: .left
        case .todo, .calendar: .right
        }
    }

    var title: String {
        switch self {
        case .history: "기록"
        case .activity: "한 일"
        case .clipboard: "클립보드"
        case .usage: "사용량"
        case .todo: "할 일"
        case .calendar: "캘린더"
        }
    }

    /// Its name on the panel's own tabs, in the UI's language (`title` stays Korean: the settings window looks it up
    /// in its catalog).
    func name(english: Bool = ArisUIWords.english) -> String {
        switch self {
        case .history: ArisUIWords.text("기록", "History", english: english)
        case .activity: ArisUIWords.text("한 일", "Activity", english: english)
        case .clipboard: ArisUIWords.text("클립보드", "Clipboard", english: english)
        case .usage: ArisUIWords.text("사용량", "Usage", english: english)
        case .todo: ArisUIWords.text("할 일", "To-dos", english: english)
        case .calendar: ArisUIWords.text("캘린더", "Calendar", english: english)
        }
    }

    /// Its SF Symbol, in the panel's tabs and on its switch in settings.
    var symbol: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .activity: "checklist.checked"
        case .clipboard: "doc.on.clipboard"
        case .usage: "gauge.with.dots.needle.50percent"
        case .todo: "checklist"
        case .calendar: "calendar"
        }
    }
}

enum ArisSideTabChoice {
    /// The preference's name: the raw values of the tabs turned off.
    static let preferenceKey = "arisSideHiddenTabs"

    static func all(_ edge: ArisSideEdge) -> [ArisSideTab] { ArisSideTab.allCases.filter { $0.edge == edge } }

    static func shown(_ edge: ArisSideEdge, hidden: Set<String>) -> [ArisSideTab] {
        all(edge).filter { !hidden.contains($0.rawValue) }
    }

    /// The tab that opens when `wanted` is asked for: itself while it shows, else its side's first tab that does;
    /// nil when its side has none.
    static func resolve(_ wanted: ArisSideTab, hidden: Set<String>) -> ArisSideTab? {
        let tabs = shown(wanted.edge, hidden: hidden)
        return tabs.contains(wanted) ? wanted : tabs.first
    }

    /// What was stored, as the tabs turned off: only tabs that exist.
    static func hidden(_ stored: [String]) -> Set<String> {
        Set(stored.filter { ArisSideTab(rawValue: $0) != nil })
    }

    static func toggled(_ hidden: Set<String>, _ tab: ArisSideTab, shown: Bool) -> Set<String> {
        shown ? hidden.subtracting([tab.rawValue]) : hidden.union([tab.rawValue])
    }

    /// What to store, in the tabs' own order.
    static func stored(_ hidden: Set<String>) -> [String] {
        ArisSideTab.allCases.map(\.rawValue).filter(hidden.contains)
    }
}

/// What runs behind the tabs only while its tab shows: a tab turned off does none of it.
enum ArisSideTabWork {
    /// The 사용량 tab's reads of every plan's limits, every few minutes.
    static func pollsUsage(hidden: Set<String>) -> Bool { !hidden.contains(ArisSideTab.usage.rawValue) }

    /// The settings window lists the AI services from the same reads. With the tab off (so no timer) it gets one read
    /// when it comes up, unless the last read is fresher than a timer's would be (`every` apart).
    static func readsUsageOnce(hidden: Set<String>, lastRead: Date?, now: Date, every: TimeInterval) -> Bool {
        guard !pollsUsage(hidden: hidden) else { return false }
        guard let lastRead else { return true }
        return now.timeIntervalSince(lastRead) >= every
    }

    /// How old the last read may be before opening the 사용량 tab reads again.
    static let usageFreshFor: TimeInterval = 60

    /// Opening the 사용량 tab reads the limits again unless they were read within the last minute (the timer's reads
    /// are three minutes apart, so the tab could open on numbers that old).
    static func readsUsageOnOpen(lastRead: Date?, now: Date) -> Bool {
        guard let lastRead else { return true }
        return now.timeIntervalSince(lastRead) >= usageFreshFor
    }

    /// The 사용량 tab is in front of an open left panel.
    static func showsUsage(open: Set<ArisSideEdge>, leftTab: ArisSideTab) -> Bool { open.contains(.left) && leftTab == .usage }

    /// The 클립보드 tab's shortcut (⌃⌥V). A shortcut Aris holds is taken from every app even when it opens nothing, so
    /// with the tab off Aris lets go of it and the key reaches the app in front.
    static func takesClipboardKey(hidden: Set<String>) -> Bool { !hidden.contains(ArisSideTab.clipboard.rawValue) }

    /// The right side's shortcut (할 일, 캘린더), likewise: Aris holds it only while that side has a tab left to open.
    static func takesRightKey(hidden: Set<String>) -> Bool { !ArisSideTabChoice.shown(.right, hidden: hidden).isEmpty }
}

/// The menu-bar menu's side panel items: one for each side that has a tab left on, the left first. The right side has
/// its own (it could be opened from the menu only when the left had every tab off).
enum ArisSideMenu {
    static func sides(hidden: Set<String>) -> [ArisSideEdge] {
        ArisSideEdge.allCases.filter { !ArisSideTabChoice.shown($0, hidden: hidden).isEmpty }
    }

    /// `open`: that side's panel is open now: the item then closes it and says so (third VM run: it said "Open the
    /// side panel" while the panel was open, and choosing it did nothing).
    static func title(_ edge: ArisSideEdge, open: Bool = false, english: Bool = ArisUIWords.english) -> String {
        switch (edge, open) {
        case (.left, false): ArisUIWords.text("사이드 패널 열기", "Open the side panel", english: english)
        case (.right, false): ArisUIWords.text("오른쪽 사이드 패널 열기", "Open the right side panel", english: english)
        case (.left, true): ArisUIWords.text("사이드 패널 닫기", "Close the side panel", english: english)
        case (.right, true): ArisUIWords.text("오른쪽 사이드 패널 닫기", "Close the right side panel", english: english)
        }
    }

    /// What choosing the item does.
    enum Act: Equatable { case open, close }
    static func act(open: Bool) -> Act { open ? .close : .open }

    /// The hover popover's first line, in three parts so the key stands out: Korean puts the key first ("⌃⌥V 로
    /// 열기", "클릭 해서 열기"), English the verb ("Open with ⌃⌥V", "Open with a click").
    static func openHint(byKey: Bool, english: Bool = ArisUIWords.english) -> (lead: String, key: String, tail: String) {
        if english { return ("Open with", byKey ? "⌃⌥V" : "a click", "") }
        return ("", byKey ? "⌃⌥V" : "클릭", byKey ? "로 열기" : "해서 열기")
    }
}
