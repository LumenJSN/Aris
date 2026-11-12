// Acceptance tests for the clean-room calendar (cleanroom-specs/09-calendar.md).
import AppKit
import EventKit
import Foundation

@MainActor
func runCalendarTests() async {
    selectionTests()
    meetingLinkTests()
    deepLinkTests()
    reminderDateTests()
    mergeTests()
    changeGateTests()
    await storeTests()
}

private func selectionTests() {
    let ids: Set<String> = ["a", "b", "c"]
    var selection = ArisCalendarSelection.all
    check(selection.contains("a"), "calendar selection: all includes every calendar")
    selection = selection.setting("b", on: false, among: ids)
    check(selection == .selected(["a", "c"]), "calendar selection: from all, turning one off keeps the others")
    selection = selection.setting("b", on: true, among: ids)
    check(selection == .selected(["a", "b", "c"]), "calendar selection: re-selecting every calendar keeps the explicit list")
    selection = ArisCalendarSelection.selected([]).setting("a", on: true, among: ids)
    check(selection == .selected(["a"]) && !selection.contains("b"), "calendar selection: picking from none")
    check(ArisCalendarSelection.all.setting("a", on: true, among: ids) == .all, "calendar selection: on while all stays all")

    let decoder = JSONDecoder()
    let all = try? decoder.decode(ArisCalendarSelection.self, from: Data(#"{"all":{}}"#.utf8))
    let some = try? decoder.decode(ArisCalendarSelection.self, from: Data(#"{"selected":{"_0":["x","y"]}}"#.utf8))
    check(all == .all && some == .selected(["x", "y"]), "calendar selection: the stored JSON shapes decode")
    let encoded = (try? JSONEncoder().encode(ArisCalendarSelection.selected(["z"]))).flatMap { String(data: $0, encoding: .utf8) }
    check(encoded == #"{"selected":{"_0":["z"]}}"#, "calendar selection: encodes the same shape: \(encoded ?? "nil")")

    let defaults = UserDefaults(suiteName: testSuiteName("aris-calendar-tests"))!
    defaults.removePersistentDomain(forName: testSuiteName("aris-calendar-tests"))
    check(ArisCalendarSelection.load(from: defaults) == .all, "calendar selection: nothing stored -> all")
    ArisCalendarSelection.selected(["q"]).save(to: defaults)
    check(defaults.string(forKey: ArisCalendarSelection.key) == #"{"selected":{"_0":["q"]}}"#
          && ArisCalendarSelection.load(from: defaults) == .selected(["q"]), "calendar selection: saved as a JSON string and read back")
    defaults.set("garbage", forKey: ArisCalendarSelection.key)
    check(ArisCalendarSelection.load(from: defaults) == .all, "calendar selection: unreadable -> all")
    defaults.removePersistentDomain(forName: testSuiteName("aris-calendar-tests"))
}

private func meetingLinkTests() {
    let zoom = URL(string: "https://acme.zoom.us/j/123")!
    check(ArisMeetingLink.provider(for: zoom) == .zoom, "meeting: a subdomain of zoom.us matches")
    check(ArisMeetingLink.provider(for: URL(string: "https://notzoom.us/j/1")!) == nil, "meeting: notzoom.us does not")
    check(ArisMeetingLink.provider(for: URL(string: "https://MEET.Google.com/abc")!) == .googleMeet, "meeting: hosts match case-insensitively")
    check(ArisMeetingLink.provider(for: URL(string: "zoommtg://zoom.us/join")!) == nil, "meeting: only http and https")
    check(ArisMeetingLink.provider(for: URL(string: "https://teams.live.com/x")!) == .teams
          && ArisMeetingLink.provider(for: URL(string: "https://meet.jit.si/room")!) == .jitsi
          && ArisMeetingLink.provider(for: URL(string: "https://whereby.com/r")!) == .whereby
          && ArisMeetingLink.provider(for: URL(string: "https://x.webex.com/m")!) == .webex
          && ArisMeetingLink.provider(for: URL(string: "https://zoomgov.com/j/2")!) == .zoom
          && ArisMeetingLink.provider(for: URL(string: "https://hangouts.google.com/c")!) == .googleMeet,
          "meeting: every provider's hosts")
    let byURL = ArisMeetingLink.find(url: zoom, location: nil, notes: "Join https://meet.google.com/xyz")
    check(byURL?.url == zoom && byURL?.provider == .zoom, "meeting: the URL field beats the notes")
    let fromLocation = ArisMeetingLink.find(url: URL(string: "https://example.com/agenda"), location: "Room 4 / https://meet.google.com/aaa-bbb",
                                            notes: "https://acme.zoom.us/j/9")
    check(fromLocation?.provider == .googleMeet, "meeting: an unrelated URL field is skipped, location comes before notes")
    let fromNotes = ArisMeetingLink.find(url: nil, location: "Cafe", notes: "Docs: https://docs.example.com then https://teams.microsoft.com/l/meetup")
    check(fromNotes?.provider == .teams, "meeting: unrelated links in the notes are ignored")
    check(ArisMeetingLink.find(url: nil, location: nil, notes: "see https://example.org") == nil, "meeting: nothing guessed")
    let link = ArisMeetingLink(provider: .webex, url: URL(string: "https://a.webex.com/m")!)
    let round = (try? JSONEncoder().encode(link)).flatMap { try? JSONDecoder().decode(ArisMeetingLink.self, from: $0) }
    check(round == link, "meeting: the link is Codable")
}

private func info(_ id: String = "cal", reminders: Bool = false) -> ArisCalendarInfo {
    ArisCalendarInfo(id: id, account: "iCloud", title: "Home", color: .systemBlue, isSubscribed: false, isReminderList: reminders)
}

private func event(_ id: String, start: Date, end: Date? = nil, allDay: Bool = false, recurring: Bool = false, detached: Bool = false,
                   kind: ArisEventKind = .event(.accepted)) -> ArisCalendarEvent {
    ArisCalendarEvent(id: id, start: start, end: end ?? start, title: id, location: nil, notes: nil, url: nil,
                      isAllDay: allDay, kind: kind, calendar: info(), participants: [], timeZone: nil, hasRecurrence: recurring,
                      isDetached: detached, priority: nil, meetingLink: nil)
}

private func deepLinkTests() {
    let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00:00 UTC
    let uuid = "6A1F3C2E-0B7D-4E59-9C1A-2F4B8D6E0A13"
    check(event(uuid, start: start).calendarAppURL()?.absoluteString == "ical://ekevent/\(uuid)?method=show&options=more",
          "deep link: the calendar item identifier (a plain UUID); a one-off event has no date part")
    check(event(uuid, start: start, recurring: true).calendarAppURL()?.absoluteString
          == "ical://ekevent/2026-01-01T00:00:00+0000/\(uuid)?method=show&options=more", "deep link: a recurring timed event, in UTC")
    check(event(uuid, start: start, detached: true).calendarAppURL()?.absoluteString
          == "ical://ekevent/2026-01-01T00:00:00+0000/\(uuid)?method=show&options=more", "deep link: a detached occurrence keeps its date")
    let local = DateFormatter()
    local.locale = Locale(identifier: "en_US_POSIX")
    local.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    local.timeZone = .current
    check(event(uuid, start: start, allDay: true, recurring: true).calendarAppURL()?.absoluteString
          == "ical://ekevent/\(local.string(from: start))/\(uuid)?method=show&options=more", "deep link: a recurring all-day event, in local time")
    check(event("ABC:123", start: start).calendarAppURL()?.absoluteString == "ical://ekevent/ABC%3A123?method=show&options=more",
          "deep link: the id is percent-encoded for a path (: becomes %3A)")
    check(event("id with space", start: start).calendarAppURL()?.absoluteString == "ical://ekevent/id%20with%20space?method=show&options=more",
          "deep link: the id is percent-encoded")
    check(event("R-1", start: start, kind: .reminder(completed: false)).calendarAppURL()?.absoluteString == "x-apple-reminderkit://remcdreminder/R-1",
          "deep link: a reminder opens in Reminders")
    let now = start.addingTimeInterval(1800)
    check(event("e", start: start, end: start.addingTimeInterval(3600)).status(at: now) == .inProgress
          && event("e", start: now.addingTimeInterval(60)).status(at: now) == .upcoming
          && event("e", start: start, end: start.addingTimeInterval(60)).status(at: now) == .ended, "event: upcoming / in progress / ended")
    check(ArisEventKind.birthday.isBirthday && ArisEventKind.reminder(completed: true).isReminder && ArisEventKind.event(.maybe).isEvent
          && !ArisEventKind.birthday.isReminder, "event: kind helpers")
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    check(ArisCalendarEvent.spansWholeDays(start: start, end: start.addingTimeInterval(86_400), calendar: utc)
          && ArisCalendarEvent.spansWholeDays(start: start, end: start.addingTimeInterval(2 * 86_400), calendar: utc)
          && !ArisCalendarEvent.spansWholeDays(start: start, end: start.addingTimeInterval(82_800), calendar: utc)
          && !ArisCalendarEvent.spansWholeDays(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(86_400), calendar: utc)
          && !ArisCalendarEvent.spansWholeDays(start: start, end: start, calendar: utc),
          "event: a timed event from midnight to midnight counts as all-day")
    check(ArisParticipant.displayName(name: nil, address: URL(string: "mailto:kim@example.com")!) == "kim@example.com"
          && ArisParticipant.displayName(name: "mailto:lee@example.com", address: URL(string: "mailto:x@y")!) == "lee@example.com"
          && ArisParticipant.displayName(name: "Alex", address: URL(string: "mailto:p@example.com")!) == "Alex"
          && ArisParticipant.displayName(name: "", address: URL(string: "mailto:e@example.com")!) == "e@example.com",
          "event: participant names drop the mailto: prefix")
    check(ArisCalendarInfo.account(sourceType: .local, calendarType: .local, title: "On My Mac") == "기타"
          && ArisCalendarInfo.account(sourceType: .subscribed, calendarType: .subscription, title: "Subscribed") == "기타"
          && ArisCalendarInfo.account(sourceType: .birthdays, calendarType: .birthday, title: "Other") == "기타"
          && ArisCalendarInfo.account(sourceType: .calDAV, calendarType: .calDAV, title: "iCloud") == "iCloud",
          "calendar: local, subscribed and birthday calendars are listed under 기타")
    check(ArisAttendance.accepted < ArisAttendance.maybe && ArisAttendance.maybe < ArisAttendance.pending
          && ArisAttendance.pending < ArisAttendance.declined && ArisAttendance.declined < ArisAttendance.unknown, "event: attendance sorts")
}

private func reminderDateTests() {
    let seoul = TimeZone(identifier: "Asia/Seoul")!, newYork = TimeZone(identifier: "America/New_York")!
    var timed = DateComponents(year: 2026, month: 3, day: 5, hour: 9, minute: 30)
    timed.timeZone = seoul
    let t = ArisReminderDate.resolve(timed, fallback: newYork, local: seoul)
    check(t?.allDay == false && t?.start == Date(timeIntervalSince1970: 1_772_670_600) && t?.end == Date(timeIntervalSince1970: 1_772_722_800),
          "reminder date: a timed reminder in its own zone (09:30 Seoul), shown to the end of its local day")
    let noZone = DateComponents(year: 2026, month: 3, day: 5, hour: 9, minute: 30)
    let n = ArisReminderDate.resolve(noZone, fallback: newYork, local: newYork)
    check(n?.start == Date(timeIntervalSince1970: 1_772_721_000) && n?.end == Date(timeIntervalSince1970: 1_772_773_200),
          "reminder date: no zone -> the reminder's zone (09:30 New York), to the end of the local day")
    var dateOnly = DateComponents(year: 2026, month: 3, day: 5)
    dateOnly.timeZone = newYork
    let d = ArisReminderDate.resolve(dateOnly, fallback: newYork, local: seoul)
    check(d?.allDay == true && d?.start == Date(timeIntervalSince1970: 1_772_636_400) && d?.end == Date(timeIntervalSince1970: 1_772_722_800),
          "reminder date: date only -> all day in the local zone (Seoul here, not the reminder's New York), to the end of that day")

    // The window rule: a reminder belongs in [from, to) when it is due inside it.
    let today = Date(timeIntervalSince1970: 1_772_722_800), tomorrow = today.addingTimeInterval(86_400)
    let yesterday = today.addingTimeInterval(-86_400)
    check(!ArisReminderDate.isDue(yesterday, from: today, to: tomorrow), "reminder window: an all-day reminder due yesterday doesn't show today")
    check(!ArisReminderDate.isDue(today.addingTimeInterval(-60), from: today, to: tomorrow), "reminder window: nor one due last night")
    check(ArisReminderDate.isDue(today, from: today, to: tomorrow) && ArisReminderDate.isDue(today.addingTimeInterval(3600), from: today, to: tomorrow),
          "reminder window: one due today does, from the window's opening")
    check(!ArisReminderDate.isDue(tomorrow, from: today, to: tomorrow), "reminder window: one due tomorrow doesn't")
    check(ArisReminderDate.resolve(DateComponents(hour: 3), fallback: seoul) == nil, "reminder date: no day -> nothing")
}

private func mergeTests() {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let merged = ArisCalendarEvent.merged([event("b", start: base.addingTimeInterval(60)), event("c", start: base.addingTimeInterval(120))],
                                          [event("a", start: base), event("r", start: base.addingTimeInterval(90), kind: .reminder(completed: false))])
    check(merged.map(\.id) == ["a", "b", "r", "c"], "events: events and reminders are merged by start date")
}

private func changeGateTests() {
    var gate = ArisChangeGate()
    check(gate.changed() && !gate.changed() && !gate.changed(), "store changes: a burst schedules one reload")
    gate.reloaded()
    check(gate.changed(), "store changes: after the reload the next change schedules again")
    check(ArisChangeGate.delay == .seconds(2), "store changes: the reload waits 2 s")
}

@MainActor
private final class FakeSource: ArisCalendarSource {
    var status: [EKEntityType: EKAuthorizationStatus] = [.event: .fullAccess, .reminder: .denied]
    var calendarsAsked = 0
    var lists: [ArisCalendarInfo] = [info("work"), info("home")]
    var stored: [ArisCalendarEvent] = []
    var queriedCalendars: [String] = []
    var granted = true
    var requests = 0

    func authorization(for type: EKEntityType) -> EKAuthorizationStatus { status[type] ?? .notDetermined }
    func requestFullAccess(to type: EKEntityType) async -> Bool {
        requests += 1
        status[type] = granted ? .fullAccess : .denied
        return granted
    }
    func calendars(for type: EKEntityType) async -> [ArisCalendarInfo] {
        calendarsAsked += 1
        return type == .event ? lists : []
    }
    func events(from: Date, to: Date, calendars: [String]) async -> [ArisCalendarEvent] {
        queriedCalendars = calendars
        return stored.filter { $0.start >= from && $0.start < to }
    }
    func reminders(from: Date, to: Date, lists: [String]) async -> [ArisCalendarEvent] { [] }
}

@MainActor
private func storeTests() async {
    let defaults = UserDefaults(suiteName: testSuiteName("aris-calendar-store-tests"))!
    defaults.removePersistentDomain(forName: testSuiteName("aris-calendar-store-tests"))
    let source = FakeSource()
    // Inside today whatever the time is now: the store's "upcoming" window is today's start + 1 day.
    let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)
    source.stored = [event("later", start: now.addingTimeInterval(7200)), event("soon", start: now.addingTimeInterval(600)),
                     event("far", start: now.addingTimeInterval(10 * 86_400))]
    let store = ArisCalendarStore(source: source, defaults: defaults, watchChanges: false)
    check(store.eventCalendars.isEmpty && source.calendarsAsked == 0, "calendar store: nothing loaded before it's asked")
    let upcoming = await store.upcomingEvents(days: 1)
    check(source.calendarsAsked > 0 && store.eventCalendars.count == 2, "calendar store: a first question loads the calendars")
    check(upcoming.map(\.id) == ["soon", "later"] && Set(source.queriedCalendars) == ["work", "home"],
          "calendar store: upcoming events of the selected calendars, in order")
    let revision = store.revision
    await store.setSelected(store.eventCalendars[0], false)
    check(!store.isSelected(store.eventCalendars[0]) && store.isSelected(store.eventCalendars[1]) && store.revision != revision,
          "calendar store: turning a calendar off is kept and bumps the revision")
    check(ArisCalendarSelection.load(from: defaults) == .selected(["home"]), "calendar store: the selection is saved")
    _ = await store.events(from: now, to: now.addingTimeInterval(86_400))
    check(source.queriedCalendars == ["home"], "calendar store: queries use only the selected calendars")
    check(store.selectedCalendarIDs == ["home"], "calendar store: selected ids")

    source.status[.event] = .writeOnly
    await store.checkAccess()
    check(await store.upcomingEvents(days: 1).isEmpty, "calendar store: write-only access reads nothing")

    let fresh = FakeSource()
    fresh.status[.event] = .notDetermined
    let asking = ArisCalendarStore(source: fresh, defaults: defaults, watchChanges: false)
    await asking.loadIfAuthorized()
    check(fresh.requests == 0, "calendar store: loading never prompts")
    await asking.checkAccess()
    check(fresh.requests == 1 && asking.access == .fullAccess && !asking.eventCalendars.isEmpty,
          "calendar store: checking when undecided asks once and loads on a yes")
    defaults.removePersistentDomain(forName: testSuiteName("aris-calendar-store-tests"))
}

private final class Flag: @unchecked Sendable { var done = false }

/// The harness's top level is synchronous: run the async calendar tests on the main actor and spin the run loop.
func runCalendarTestsBlocking() {
    let flag = Flag()
    Task { @MainActor in
        await runCalendarTests()
        flag.done = true
    }
    while !flag.done { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}
