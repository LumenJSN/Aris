// Tests for the side panels' demo mode (ArisPreview `side-demo:on|off`, 2026-11-07 ad session): only sample rows while
// it is on, the real sources back when it is off, nothing kept. That no write reaches Reminders, Canvas, the history
// or the activity log while it is on is side-demo-lint.py's (run.sh), on the models themselves.
import Foundation

func runSideDemoTests() {
    sideDemoSwitchTests()
    sideDemoSampleTests()
    sideDemoEdgeTests()
}

private func sideDemoSwitchTests() {
    typealias W = ArisSideDemoSwitch
    check(W.wanted("side-demo:on") == true && W.wanted(" SIDE-DEMO:OFF ") == false && W.wanted("side-demo") == nil
          && W.wanted("side-demo:maybe") == nil && W.wanted("todo-seed") == nil, "side demo: side-demo:on|off, nothing else")
    var demo = W()
    check(!demo.isOn && demo.samples == nil, "side demo: a launch starts with it off (the real sources)")
    let before = Set(UserDefaults.standard.dictionaryRepresentation().keys)
    check(demo.set(true, now: Date()) && demo.isOn && demo.samples != nil, "side demo: on brings the samples")
    check(!demo.set(true, now: Date()), "side demo: on again changes nothing")
    check(demo.set(false, now: Date()) && !demo.isOn && demo.samples == nil, "side demo: off drops every sample (the panels read their real sources)")
    check(Set(UserDefaults.standard.dictionaryRepresentation().keys) == before, "side demo: on and off store nothing (never outlasts the app)")
}

private func sideDemoSampleTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    // Saturday 2026-11-07 21:50, Orlando.
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 21, minute: 50))!
    let s = ArisSideDemoSamples(now: now, calendar: calendar)
    let prefix = ArisSideDemoSamples.idPrefix
    let ids = s.todos.map(\.id) + s.todos.map(\.listID) + s.deadlines.map(\.id) + s.events.map(\.id) + s.events.map(\.calendar.id)
        + s.activity.map(\.id)
    check(!s.todos.isEmpty && !s.deadlines.isEmpty && !s.events.isEmpty && !s.history.isEmpty && !s.activity.isEmpty
          && ids.allSatisfy { $0.hasPrefix(prefix) }, "side demo: every panel has samples, every one of them marked as the demo's")
    check(s.todos.contains { $0.title == "보고서 초안 쓰기" } && s.events.contains { $0.title == "팀 회의" } && s.events.contains { $0.title == "디자인 리뷰" }
          && s.deadlines.contains { $0.title == "과제 제출" }, "side demo: the agreed sample words")
    check(s.deadlines.allSatisfy { $0.url == nil } && s.events.allSatisfy { $0.url == nil && $0.meetingLink == nil },
          "side demo: no sample links anywhere (a tap opens nothing)")
    let homework = s.deadlines.first { $0.title == "과제 제출" }!
    check(calendar.component(.weekday, from: homework.at) == 6 && homework.at > now && homework.at < now.addingTimeInterval(8 * 86_400),
          "side demo: 과제 제출 is due this coming Friday")
    let report = s.todos.first { $0.title == "보고서 초안 쓰기" }!
    check(report.hasTime && report.due.map { $0 > now && $0 <= now.addingTimeInterval(7200) } == true,
          "side demo: the report draft is due within two hours")
    let meeting = s.events.first { $0.title == "팀 회의" }!
    check(calendar.component(.hour, from: meeting.start) == 15 && meeting.start > now && meeting.end > meeting.start,
          "side demo: 팀 회의 at three, still to come")
    check(s.events.contains { calendar.isDate($0.start, inSameDayAs: now) }, "side demo: today's timetable has something")
    check(zip(s.history, s.history.dropFirst()).allSatisfy { $0.date >= $1.date } && s.history.allSatisfy { $0.date <= now }
          && ArisHistory.sessions(s.history).count >= 2, "side demo: past turns newest first, in more than one session")
    check(ArisActivityTab.todayCount(s.activity, now: now, calendar: calendar) == s.activity.count
          && s.activity.contains { $0.teammate == "claude-code" } && s.activity.contains { $0.undoable },
          "side demo: every 한 일 row is today's, one Claude Code's, one with 되돌리기")
    let undone = ArisActivityTab.markingUndone(s.activity, id: s.activity[0].id)
    check(undone[0].undone && undone.dropFirst().allSatisfy { !$0.undone }, "side demo: a sample's 되돌리기 marks only that row")
}

private func sideDemoEdgeTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    // Five past midnight on a Friday: the next Friday is a week on, and the rows still fall today.
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 0, minute: 5))!
    let s = ArisSideDemoSamples(now: now, calendar: calendar)
    let homework = s.deadlines.first { $0.title == "과제 제출" }!
    check(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: homework.at)).day == 7,
          "side demo (Friday): 과제 제출 is next Friday, not today")
    check(ArisActivityTab.todayCount(s.activity, now: now, calendar: calendar) == s.activity.count
          && s.activity.allSatisfy { $0.date <= now }, "side demo (just after midnight): every 한 일 row is still today's, none in the future")
    let again = ArisSideDemoSamples(now: now, calendar: calendar)
    check(again.history.map(\.id) == s.history.map(\.id), "side demo: the samples keep their ids")
}
