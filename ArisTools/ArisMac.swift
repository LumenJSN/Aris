//
//  ArisMac.swift
//  aris-tools
//
//  The Mac actions: music, volume, apps, links, folders, Shortcuts, reminders,
//  calendar events, notes and the calendar app. Programs are started directly
//  (never through a shell) and AppleScript comes only from ArisActions.
//

import AppKit
import EventKit
import Foundation

let calendarFile = arisFolder.appendingPathComponent("calendar.json")

struct CalendarChoice: Codable {
    /// The calendar new events go in (a Google calendar added in macOS, for example).
    var calendar: String?
}

@discardableResult
func run(_ program: String, _ arguments: [String]) -> String {
    let (status, printed, complaint) = runCapturing(program, arguments)
    guard status == 0 else {
        fail(complaint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(program) failed" : complaint)
    }
    return printed.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// The exit status, what it printed and what it complained about, without failing. `limit`: how long it may take
/// (ArisBoundedRun: every AppleScript has one, so a hung app can't hang the turn); past it the status is
/// ArisBoundedRun.timedOutStatus.
func runCapturing(_ program: String, _ arguments: [String], limit: TimeInterval? = nil) -> (status: Int32, printed: String, complaint: String) {
    guard let result = ArisBoundedRun.capture(program, arguments, limit: limit ?? ArisBoundedRun.defaultLimit(for: program)) else {
        fail("couldn't run \(program)")
    }
    return (result.status, result.printed, result.complaint)
}

/// Runs AppleScript against `app`; a failure says what's wrong in words (no permission, not running, didn't answer in
/// time) instead of osascript's "0:52: execution error: … (-1743)". `missing`: what a "can't get that" error means here.
@discardableResult
func appleScript(_ script: String, app: String = "the app", missing: String? = nil) -> String {
    let (status, printed, complaint) = runCapturing("/usr/bin/osascript", ["-e", script])
    if status == ArisBoundedRun.timedOutStatus { fail(ArisBoundedRun.timeoutLine(app: app)) }
    guard status == 0 else { fail(ArisActions.appleScriptProblem(complaint, app: app, missing: missing), fix: ArisToolFix.appleScript(complaint)) }
    return printed.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// The value after `flag` (removed from `words`), if any.
func option(_ flag: String, in words: inout [String]) -> String? {
    guard let index = words.firstIndex(of: flag), index + 1 < words.count else { return nil }
    let value = words[index + 1]
    words.removeSubrange(index...(index + 1))
    return value
}

func music(_ args: [String]) {
    guard let action = args.first.flatMap(ArisActions.Music.init(rawValue:)) else { fail("usage: music play|pause|next|previous [spotify|music]") }
    let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    // Spotify only when this Mac has it: a script for an app that isn't installed puts up a "where is it?" window.
    let spotifyInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
    let app = ArisActions.musicApp(requested: args.dropFirst().first, running: running, spotifyInstalled: spotifyInstalled)
    if let problem = ArisActions.musicProblem(app: app, spotifyInstalled: spotifyInstalled) { fail(problem) }
    appleScript(ArisActions.musicScript(action, app: app), app: app, missing: "\(app) couldn't do that (it may have nothing to play)")
    print("\(app): \(action.rawValue)")
}

func volume(_ args: [String]) {
    guard let argument = args.first, let script = ArisActions.volumeScript(argument) else { fail("usage: volume 0-100|up|down|mute|unmute") }
    // An output with no level or mute the Mac can set (HDMI, DisplayPort) takes the script without an error and
    // changes nothing: that is said, not "volume up" with a 한 일 line (audit platform-1).
    let settings = ArisActions.volumeSettings(appleScript("get volume settings"))
    if let refusal = ArisActions.volumeRefusal(argument, settings) { fail(refusal) }
    // The level before, so "방금 한 거 되돌려" puts it back (QA BUG-18); mute and unmute are logged without one.
    let before = ["mute", "unmute"].contains(argument) ? nil : settings.level
    appleScript(script)
    logActivity("볼륨 \(argument)", undo: before.flatMap { ArisActivity.localUndo(kind: "volume", id: nil, level: $0) ?? nil })
    print("volume \(argument)")
}

/// Sends a message to a number, an email, or a contact's name ("엄마"). The risk gate asks the user first; from the
/// open Claude the agent decides it and sends it (ArisMessageRequest). It goes to the number the user last wrote to (else a
/// mobile one) on the service that conversation uses, and is printed as sent only once Messages' own database shows it
/// sent (ArisMessageSend, audit tools-1).
func message(_ args: [String]) {
    switch messageRouting(args, environment: ProcessInfo.processInfo.environment) {
    case .refused(let why): fail(why)
    case .agent(let to, let text, let turn): askAgentToSend(to: to, text: text, turn: turn)
    case .direct: break
    }
    let who = args[0], text = args.dropFirst().joined(separator: " ")
    let database = ArisMessagesRead.databasePath(home: FileManager.default.homeDirectoryForCurrentUser.path)
    // Without Full Disk Access nothing is known of earlier conversations: iMessage, and the send can't be checked.
    let conversations = (try? ArisMessageSend.threads(path: database)) ?? []
    let handle: String
    if ArisActions.isHandle(who) {
        handle = who
    } else {
        let (status, listed, complaint) = runCapturing("/usr/bin/osascript", ["-e", ArisActions.contactScript(who)], limit: 10)
        if status == ArisBoundedRun.timedOutStatus { fail("\(ArisMessageResult.notSentLead) Contacts didn't answer, so \(who) couldn't be looked up. Nothing was sent.") }
        guard status == 0 else {
            fail("\(ArisMessageResult.notSentLead) " + ArisActions.appleScriptProblem(complaint, app: "Contacts", missing: "Contacts couldn't look up \(who)") + ". Nothing was sent.", fix: ArisToolFix.appleScript(complaint))
        }
        guard let picked = ArisMessageSend.pick(ArisMessageSend.candidates(listed), threads: conversations) else {
            fail("couldn't find exactly one contact named \(who) (none, or more than one): ask who")
        }
        handle = picked.value
    }
    let sent = ArisMessageSend.deliver(handle: handle, service: ArisMessageSend.service(for: handle, threads: conversations)) { service, limit in
        sendAndWatch(handle: handle, text: text, service: service, database: database, limit: limit)
    }
    let result = ArisMessageSend.result(sent.attempt, to: who, service: sent.service)
    if result.ok { logActivity(ArisActSummary.messageSent(to: who), undo: nil) }
    if result.ok { print(result.line) } else { fail(result.line) }
}

/// Hands the message to Messages on `service`, then watches Messages' database for it for at most `limit` seconds.
private func sendAndWatch(handle: String, text: String, service: ArisMessageSend.Service, database: String, limit: TimeInterval) -> ArisMessageSend.Attempt {
    let before = try? ArisMessageSend.lastRow(path: database)
    let (status, _, complaint) = runCapturing("/usr/bin/osascript", ["-e", ArisActions.messageScript(to: handle, text: text, service: service)], limit: 10)
    // Stopped at its limit: Messages may still send it, so the database decides (below), never "not sent".
    if status != 0, status != ArisBoundedRun.timedOutStatus {
        if complaint.contains("-1728") || complaint.contains("-1719") { return .refused }
        if let fix = ArisToolFix.appleScript(complaint) { fail(ArisMessageResult.notAllowed, fix: fix) }
        fail(ArisMessageResult.failed)
    }
    guard let before else { return .unchecked }
    return .watched(ArisMessageSend.watch(limit: limit, read: { (try? ArisMessageSend.sent(path: database, handle: handle, after: before)) ?? nil }))
}

/// The open Claude's message: the agent decides it (the countdown for the user's dictated words, their card otherwise) and
/// sends it on their yes; what it says is printed, as `mcp` and `aside` do.
func askAgentToSend(to: String, text: String, turn: String) -> Never {
    askAgent(route: "message-tool", body: ["turn": turn, "to": to, "text": text])
}

/// A Claude's write, send or thing opened (ArisHandOff): the agent judges it as Codex's same command, asks the user on a
/// card when that says to, and runs it itself; what that printed is printed here.
func askAgentToAct(words: [String], turn: String) -> Never {
    askAgent(route: "action-tool", body: ["turn": turn, "words": words])
}

/// Posts a handed-off call to the agent and ends with its answer: its output printed, its status this program's.
private func askAgent(route: String, body: [String: Any]) -> Never {
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/\(route)") else {
        fail("Aris's agent isn't set up (no token)")
    }
    // A job's card waits ten minutes, a conversation's a minute and the countdown; then the call itself (a send, or a
    // video conversion's few minutes).
    let wait: TimeInterval = 900
    var request = URLRequest(url: url, timeoutInterval: wait)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = wait
    configuration.timeoutIntervalForResource = wait
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var reply: [String: Any]?
    URLSession(configuration: configuration).dataTask(with: request) { data, _, _ in
        if let data { reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + wait + 5)
    guard let reply, let output = reply["output"] as? String else { fail("Aris's agent didn't answer (is it running?)") }
    let status = (reply["status"] as? Int) ?? 1
    if status == 0 { print(output) } else { FileHandle.standardError.write(Data((output + "\n").utf8)) }
    exit(Int32(clamping: status))
}

/// Moves files to the Trash (they can be put back), never deletes them. Every path is checked first, as `move` does:
/// inside the home folder or on an external disk, and never a protected place or a folder holding one (so nothing is
/// trashed if one is refused).
func trash(_ args: [String]) {
    guard !args.isEmpty else { fail("usage: trash <path>…") }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let checked = args.map { path -> String in
        do { return try ArisActivity.checkedPath(absolutePath(path), home: home) } catch {
            fail("won't move \(path) to the Trash: \(error.localizedDescription)")
        }
    }
    for path in checked {
        let url = URL(fileURLWithPath: path)
        do {
            var inTrash: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &inTrash)
            logActivity("휴지통으로: \(url.lastPathComponent)", undo: (inTrash as URL?).map { .restoreFromTrash(trash: $0.path, original: path) })
            print("moved to the Trash: \(url.lastPathComponent)")
        } catch {
            fail("couldn't move \(url.lastPathComponent) to the Trash: \(error.localizedDescription)")
        }
    }
}

func openApp(_ args: [String]) {
    let name = args.joined(separator: " ")
    guard !name.isEmpty, !name.contains("/") else { fail("usage: app <name>") }
    // By the app's file name: `open -a` doesn't know "메모" or "시스템 설정" (ArisAppNames).
    run("/usr/bin/open", ["-a", appOpenName(for: name)])
    print("opened \(name)")
}

func openLink(_ args: [String]) {
    // A web page, or a System Settings pane by its plain link (it only opens the pane: ArisCommandPolicy.isSettingsLink).
    guard args.count == 1, ArisActions.isWebLink(args[0]) || ArisCommandPolicy.isSettingsLink(args[0]) else {
        fail("usage: link https://… | link \"x-apple.systempreferences:<pane>[?<anchor>]\"")
    }
    run("/usr/bin/open", [args[0]])
    print("opened \(args[0])")
}

func openFolder(_ args: [String]) {
    let path = NSString(string: args.joined(separator: " ")).expandingTildeInPath
    var isFolder: ObjCBool = false
    guard !path.contains(".app"), FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else {
        fail("usage: folder <a folder that exists>")
    }
    run("/usr/bin/open", [path])
    print("opened \(path)")
}

func shortcut(_ args: [String]) {
    let name = args.joined(separator: " ")
    guard !name.isEmpty else { fail("usage: shortcut <name>") }
    let printed = run("/usr/bin/shortcuts", ["run", name])
    print(printed.isEmpty ? "ran \(name)" : printed)
}

func remind(_ args: [String]) {
    var words = args
    let at = option("--at", in: &words)
    let due = at.flatMap(ArisActions.moment)
    // A day that doesn't exist (11월 31일) is said as that, never moved into the next month.
    if let at, due == nil { fail(ArisActions.noSuchDay(at) ?? "--at takes \"YYYY-MM-DD HH:MM\"") }
    let text = words.joined(separator: " ")
    guard !text.isEmpty else { fail("usage: remind <text> [--at \"YYYY-MM-DD HH:MM\"]") }
    appleScript(ArisActions.reminderScript(text: text, due: due), app: "Reminders", missing: "Reminders couldn't add it")
    logActivity(ArisActSummary.reminderAdded(text), undo: nil)
    print("reminder added: \(text)" + (due.map { " (due \(ArisActions.stamp($0)))" } ?? ""))
}

func addEvent(_ args: [String]) {
    var words = args
    let startText = option("--start", in: &words)
    guard let start = startText.flatMap(ArisActions.moment) else {
        // A day that doesn't exist (11월 31일) is said as that, never moved into the next month.
        fail(startText.flatMap(ArisActions.noSuchDay) ?? "usage: event <title> --start \"YYYY-MM-DD HH:MM\" [--minutes N] [--calendar name]")
    }
    // The length as asked, or a refusal that says why: never cut or replaced without a word (audit tools-4).
    let minutes: Int
    switch ArisActions.eventLength(option("--minutes", in: &words)) {
    case .minutes(let asked): minutes = asked
    case .invalid(let why): fail(why)
    }
    let saved = (try? Data(contentsOf: calendarFile)).flatMap { try? JSONDecoder().decode(CalendarChoice.self, from: $0) }?.calendar
    let calendar = option("--calendar", in: &words) ?? saved
    let title = words.joined(separator: " ")
    guard !title.isEmpty else { fail("an event needs a title") }
    // The app holds the Calendar grant: it adds the event by EventKit, where only the save itself failing is "not added"
    // (QA BUG-16 inverted, BUG-53 retest). Without the app's grant (or the app), Calendar's own scripting adds it.
    var asked: [String: Any] = ["op": "add", "title": title, "start": startText ?? "", "minutes": minutes]
    if let calendar { asked["calendar"] = calendar }
    if let reply = askEvents(asked), reply["noAccess"] as? Bool != true {
        let line = reply["line"] as? String ?? "no answer"
        guard reply["ok"] as? Bool == true else { fail(line) }
        if let uid = reply["uid"] as? String, !uid.isEmpty { logActivity("일정 추가: \(title)", undo: .deleteEvent(id: uid)) }
        print(line)
        return
    }
    // New events go to the user's default calendar for new events when none is named or saved (QA BUG-16: the first writable
    // one was a calendar he doesn't look at).
    let into = calendar ?? defaultEventCalendar()
    // A retry after a "may have been added": the same title at the same time is already there, and isn't made twice. A
    // look that fails (a slow whose-clause over a big calendar) is no answer: never a reason not to add.
    let (looked, existing, _) = runCapturing("/usr/bin/osascript", ["-e", ArisActions.existingEventScript(title: title, start: start, calendar: into)])
    if looked == 0, Int(existing.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 >= 1 {
        print(ArisActions.eventAlreadyLine(title: title))
        return
    }
    // Only the save itself failing (osascript's error) is "not added"; it fails there, with Calendar's own complaint.
    let printed = appleScript(ArisActions.eventScript(title: title, start: start, minutes: minutes, calendar: into), app: "Calendar")
    // Saved: the made event's own uid and calendar came back. No second read by uid (QA BUG-16 inverted: Calendar's
    // `every event whose uid is …` over a large synced calendar failed or timed out, and a real add was reported as not
    // confirmed, then told as "추가하지 못했어요"). No uid back: maybe added, never "not added".
    guard let made = ArisActions.eventMade(printed) else { fail(ArisActions.eventMaybeLine(title: title, uid: nil, calendar: into)) }
    logActivity("일정 추가: \(title)", undo: .deleteEvent(id: made.uid))
    print(ArisActions.eventAddedLine(title: title, uid: made.uid, calendar: made.calendar, start: start, minutes: minutes))
}

/// The calendar macOS puts new events in (EventKit's default), when aris-tools already may read calendars; nil
/// otherwise (never asked here: Calendar's first writable one is used then, and named in the result).
func defaultEventCalendar() -> String? {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
    return EKEventStore().defaultCalendarForNewEvents?.title
}

func useCalendar(_ args: [String]) {
    let name = args.joined(separator: " ")
    guard !name.isEmpty else { fail("usage: use-calendar <name>") }
    let names = appleScript("tell application \"Calendar\" to get name of calendars").components(separatedBy: ", ")
    guard names.contains(name) else { fail("no calendar called \(name); there are: \(names.joined(separator: ", "))") }
    do {
        try JSONEncoder().encode(CalendarChoice(calendar: name)).write(to: calendarFile, options: .atomic)
    } catch {
        fail("couldn't save: \(error.localizedDescription)")
    }
    logActivity(ArisActSummary.calendarChosen(name), undo: nil)
    print("new events go in \(name)")
}

/// Apple's Calendar (the user left Notion, 2026-11-02): the Mac calendar holds the Google accounts added in macOS.
func openCalendar() {
    run("/usr/bin/open", ["-a", ArisActions.calendarApp])
    print("opened \(ArisActions.calendarApp)")
}
