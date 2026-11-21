//
//  ArisEventKit.swift
//  aris-tools
//
//  `aris-tools event find|delete|change` (its words: ArisEventWords), and the add when the app may use the calendars: asked of the Aris app over
//  POST /aris/events (ArisEventRoute), which holds the Calendar grant. aris-tools never asks for one of its own (QA
//  BUG-53 retest). A missing grant is told by a fixed line naming the app.
//

import Foundation

/// The app's answer to an event request; nil when the app didn't answer (it isn't running). From a turn the user is
/// in front of, the app may ask for Calendars once, after its line of why, and the request waits for that answer
/// (jv-prompts, ArisAppRoute).
func askEvents(_ body: [String: Any]) -> [String: Any]? {
    appRouteReply(path: "/aris/events", body: body, lineKey: "line")
}

/// `event find|delete|change …`.
func eventEdit(_ args: [String]) {
    guard let body = ArisEventWords.body(args) else { fail(ArisEventWords.usage) }
    guard let reply = askEvents(body) else { fail("The Aris app didn't answer, so nothing was found or changed. Tell the user Aris needs to be running.") }
    let line = reply["line"] as? String ?? "no answer"
    guard reply["ok"] as? Bool == true else { fail(line) }
    if args.first != "find" {
        logActivity(args.first == "delete" ? "일정 삭제: \(body["title"] as? String ?? "")" : "일정 변경: \(body["rename"] as? String ?? body["title"] as? String ?? "")", undo: nil)
    }
    print(line)
}

/// Calendar's bundle id: its own scripting is a fallback only, used when Aris may already control it (never asks).
let calendarBundle = "com.apple.iCal"

/// Said when the app didn't answer a calendar request (and Calendar's scripting may not be used instead).
let eventsNoAppLine = "The Aris app didn't answer, so nothing was found or changed. Tell the user Aris needs to be running."

/// Every event calendar's name and the ones new events can go in: from the app's EventKit, else Calendar's own
/// scripting when Aris may already control Calendar; else it fails with what the app said.
func calendarNames() -> (names: [String], writable: [String]?) {
    let reply = askEvents(["op": "calendars"])
    if let reply, reply["noAccess"] as? Bool != true {
        guard reply["ok"] as? Bool == true, let names = reply["names"] as? [String] else { fail(reply["line"] as? String ?? "no answer") }
        return (names, reply["writable"] as? [String])
    }
    guard automationAlreadyGranted(calendarBundle) else { fail(reply?["line"] as? String ?? eventsNoAppLine) }
    let listed = appleScript("tell application \"Calendar\" to get name of calendars", app: "Calendar")
    return (listed.components(separatedBy: ", "), nil)
}

/// The undo of an add: the event Calendar knows by `uid` goes, through the app's EventKit (with the agent's undo
/// grant), else Calendar's own scripting when Aris may already control Calendar.
func removeEvent(uid: String) throws {
    let reply = askEvents(["op": "remove-uid", "uid": uid])
    if let reply, reply["noAccess"] as? Bool != true {
        guard reply["ok"] as? Bool == true else { throw ArisActivity.UndoError(message: reply["line"] as? String ?? "couldn't delete the event") }
        return
    }
    guard automationAlreadyGranted(calendarBundle), let script = ArisActions.deleteEventScript(uid: uid) else {
        throw ArisActivity.UndoError(message: reply?["line"] as? String ?? eventsNoAppLine)
    }
    try ArisActivity.runCalendarScript(script)
}
