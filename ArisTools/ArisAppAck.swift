//
//  ArisAppAck.swift
//  aris-tools
//
//  Whether the Aris app took a request aris-tools handed it through a file and a nudge (`timer`, `board`): the app
//  removes the file once it has read it, so a file still there after a moment means no app took it (it isn't running,
//  or it is stuck), and the command says that instead of "set" or "on the board".
//

import Foundation

enum ArisAppAck {
    /// How long the app has to take a request.
    static let wait: TimeInterval = 3

    /// Whether `file` is gone (the app read it) within `timeout`, looked at every `poll` seconds.
    static func taken(_ file: URL, timeout: TimeInterval = wait, poll: TimeInterval = 0.05) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while FileManager.default.fileExists(atPath: file.path) {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: poll)
        }
        return true
    }

    /// Said when the app didn't take `what` ("the timer", "the board").
    static func notTakenLine(_ what: String) -> String {
        "The Aris app didn't take \(what) within \(Int(wait)) seconds (it may not be running), so it may not have happened. Tell the user; don't say it was done."
    }
}
