// Tests for the side notches' tabs that can be turned off (ArisSideTab, ArisSideTabChoice): which tabs each side
// shows, the tab that opens when the one asked for is off, what is stored, and the settings rows that switch them.
// Called from main.swift; uses its check().
import Foundation

func runSideTabsTests() {
    sideTabChoiceTests()
    sideTabStoreTests()
    sideTabSettingsTests()
}

private func sideTabChoiceTests() {
    check(ArisSideTabChoice.all(.left) == [.history, .activity, .clipboard, .usage] && ArisSideTabChoice.all(.right) == [.todo, .calendar],
          "side tabs: the left side has four and the right two, in the panels' order")
    check(ArisSideTab.allCases.map(\.title) == ["기록", "한 일", "클립보드", "사용량", "할 일", "캘린더"], "side tabs: each tab's name")
    check(ArisSideTabChoice.shown(.left, hidden: []) == ArisSideTabChoice.all(.left) && ArisSideTabChoice.shown(.right, hidden: []) == ArisSideTabChoice.all(.right),
          "side tabs: nothing turned off shows every tab")
    check(ArisSideTabChoice.shown(.left, hidden: ["clipboard", "usage"]) == [.history, .activity], "side tabs: a tab turned off is left out, the rest keep their order")
    check(ArisSideTabChoice.shown(.right, hidden: ["clipboard", "usage"]) == [.todo, .calendar], "side tabs: the other side's tabs are untouched")
    check(ArisSideTabChoice.shown(.right, hidden: ["todo", "calendar"]).isEmpty && ArisSideTabChoice.shown(.left, hidden: ["todo", "calendar"]).count == 4,
          "side tabs: a side can lose every tab")

    check(ArisSideTabChoice.resolve(.usage, hidden: []) == .usage, "side tabs: a tab that shows opens as asked")
    check(ArisSideTabChoice.resolve(.usage, hidden: ["usage"]) == .history, "side tabs: asking for a tab that is off opens its side's first one")
    check(ArisSideTabChoice.resolve(.history, hidden: ["history", "activity"]) == .clipboard, "side tabs: the first one that shows, not the first of all")
    check(ArisSideTabChoice.resolve(.calendar, hidden: ["calendar", "history"]) == .todo, "side tabs: the fallback stays on the tab's own side")
    check(ArisSideTabChoice.resolve(.todo, hidden: ["todo", "calendar"]) == nil, "side tabs: a side with every tab off opens nothing")
}

private func sideTabStoreTests() {
    check(ArisSideTabChoice.hidden(["usage", "nonsense", "usage", ""]) == ["usage"], "side tabs: what is stored keeps only tabs that exist, each once")
    check(ArisSideTabChoice.toggled([], .usage, shown: false) == ["usage"], "side tabs: turning a tab off stores it")
    check(ArisSideTabChoice.toggled(["usage", "todo"], .usage, shown: true) == ["todo"], "side tabs: turning it back on forgets it")
    check(ArisSideTabChoice.toggled(["usage"], .usage, shown: false) == ["usage"] && ArisSideTabChoice.toggled([], .todo, shown: true).isEmpty,
          "side tabs: the same switch twice changes nothing")
    check(ArisSideTabChoice.stored(["calendar", "usage", "history"]) == ["history", "usage", "calendar"], "side tabs: stored in the tabs' own order")
}

private func sideTabSettingsTests() {
    let fresh = ArisSettingsSnapshot()
    let sections = ArisSettingsBuilder.sections(.notch, fresh)
    let left = sections.first { $0.id == "notch.sideLeft" }, right = sections.first { $0.id == "notch.sideRight" }
    check(left?.rows.map(\.id) == ["notch.tab.history", "notch.tab.activity", "notch.tab.clipboard", "notch.tab.usage"]
          && right?.rows.map(\.id) == ["notch.tab.todo", "notch.tab.calendar"], "side tab settings: a switch for each tab, a section a side")
    check(left?.rows.map(\.title) == ["기록", "한 일", "클립보드", "사용량"] && right?.rows.map(\.title) == ["할 일", "캘린더"],
          "side tab settings: each switch is named as its tab")
    check((left?.rows ?? []).allSatisfy { if case .toggle(_, true, true) = $0.control { true } else { false } }
          && right?.rows.first?.control == .toggle(.sideTab("todo"), true), "side tab settings: a fresh install shows every tab")

    var some = ArisSettingsSnapshot()
    some.hiddenSideTabs = ["clipboard", "calendar"]
    let rows = ArisSettingsBuilder.sections(.notch, some).flatMap(\.rows)
    let row = { (id: String) in rows.first { $0.id == id } }
    check(row("notch.tab.clipboard")?.control == .toggle(.sideTab("clipboard"), false) && row("notch.tab.calendar")?.control == .toggle(.sideTab("calendar"), false)
          && row("notch.tab.usage")?.control == .toggle(.sideTab("usage"), true), "side tab settings: a tab turned off reads as off, the others on")
    let key = { (s: ArisSettingsSnapshot) in ArisSettingsBuilder.sections(.notch, s).flatMap(\.rows).first { $0.id == "notch.clipKey" }?.desc ?? "" }
    check(key(fresh) != key(some) && key(some).contains("꺼져"), "side tab settings: the clipboard shortcut's row says so while its tab is off")
    check(ArisSettingsIndex.search("클립보드").contains { $0.id == "notch.tab.clipboard" } && ArisSettingsIndex.search("사용량").contains { $0.id == "notch.tab.usage" },
          "side tab settings: a search finds a tab's switch")
}
