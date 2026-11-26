//
//  ArisTimerCommand.swift
//  aris-tools
//
//  `aris-tools timer 25`, `timer 25 --focus`, `timer pomodoro`, `timer stop`: the notch's own timer (the ring in
//  the closed notch), not a reminder. Writes aris/timer.json and nudges the app (com.lumenjsn.aris.timer); it is told
//  as set only once the app answered that it took it (ArisAppAck).
//

import Foundation

private let timerFile = arisFolder.appendingPathComponent("timer.json")

func timer(_ args: [String]) {
    var words = args
    let focus = words.contains("--focus")
    words.removeAll { $0 == "--focus" }
    let entry: [String: Any]
    switch words.first?.lowercased() {
    case "stop", "cancel", "off":
        entry = ["action": "stop"]
    case "pomodoro":
        entry = ["action": "pomodoro"]
    case let first?:
        guard let minutes = Double(first), minutes > 0, minutes <= 24 * 60 else {
            fail("usage: timer <minutes> [--focus] | timer pomodoro | timer stop")
        }
        entry = ["action": "start", "seconds": Int(minutes * 60), "focus": focus]
    case nil:
        fail("usage: timer <minutes> [--focus] | timer pomodoro | timer stop")
    }
    let taken: Bool
    do { taken = try postTimer(entry) } catch {
        fail("couldn't set the timer: \(error.localizedDescription)")
    }
    // Only a request the app took is told as done (its answer for this request: ArisAppAck).
    guard taken else { fail(ArisAppAck.notTakenLine("the timer")) }
    // Logged, so "방금 한 거 되돌려" takes the latest change (QA BUG-18): a timer set is stopped again; a stop is final.
    // A countdown by its length ("타이머: 5분"), never the bare number given (seventeenth VM run, M2u).
    let stopping = entry["action"] as? String == "stop"
    let logged = (entry["seconds"] as? Int).map { "타이머: " + ArisTimerLog.length(seconds: $0) } ?? "타이머: \(words.first ?? "")"
    logActivity(stopping ? "타이머 끔" : logged, undo: stopping ? nil : .stopTimer)
    switch entry["action"] as? String {
    case "stop": print("timer stopped")
    case "pomodoro": print("pomodoro started: 25 minutes focus, 5 minutes break")
    default: print("timer set for \(words[0]) minutes")
    }
}

/// Hands the notch's timer one action (start, pomodoro, stop): written for the app, which is told at once. True once
/// the app answered that it took it (ArisAppAck).
func postTimer(_ entry: [String: Any]) throws -> Bool {
    try ArisAppAck.handOver(entry, to: timerFile, nudge: "com.lumenjsn.aris.timer")
}
