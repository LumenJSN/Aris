//
//  ArisBoundedRun.swift
//  aris-tools
//
//  A program run with a time limit, so an app that hangs (Calendar syncing, a permission prompt nobody answers, a
//  missing app's "where is it?" window) can't hang the whole turn: aris-tools stops waiting, ends the child and says
//  so (audit tools-imp-3). Every AppleScript goes through here. Both pipes are read while it runs, so a long answer
//  never fills one and stalls it. Pure apart from the child it starts, so the tests run it against /bin/sleep.
//

import Foundation

enum ArisBoundedRun {
    /// How long one AppleScript may take. Less than the agent waits for aris-tools, so the reason is said, not
    /// "didn't answer".
    static let appleScriptLimit: TimeInterval = 30

    /// The exit status reported for a child stopped at its limit (as timeout(1) does).
    static let timedOutStatus: Int32 = 124

    struct Result: Equatable {
        let status: Int32
        let printed: String
        let complaint: String
        var timedOut: Bool { status == ArisBoundedRun.timedOutStatus }
    }

    /// How long a shortcut may run: minutes of work are fine, but one waiting on a prompt nobody sees can't hang the turn
    /// forever (the brain's own command limit is two minutes, so this is said first).
    static let shortcutLimit: TimeInterval = 110
    /// How long one Spotlight search (`find`) may take; what it found by then is kept.
    static let spotlightLimit: TimeInterval = 20

    /// The limit a program gets when the caller names none: AppleScript, a shortcut and a Spotlight search each have
    /// one; anything else runs to its end.
    static func defaultLimit(for program: String) -> TimeInterval? {
        switch (program as NSString).lastPathComponent {
        case "osascript": appleScriptLimit
        case "shortcuts": shortcutLimit
        case "mdfind": spotlightLimit
        default: nil
        }
    }

    /// What is said when a shortcut was stopped at its limit. It may have done part of its work, so it is never called
    /// done or not done, and never to be run again unasked.
    static func shortcutStoppedLine(_ name: String, limit: TimeInterval = shortcutLimit) -> String {
        "The shortcut \"\(name)\" was still running after \(Int(limit)) seconds (it may be waiting on a prompt), so it was stopped. " +
            "Whatever it did before that stays done and isn't known: don't run it again, and tell the user to check."
    }

    /// The note under a search Spotlight hadn't finished in time: the matches are the ones found by then.
    static func spotlightStoppedNote(limit: TimeInterval = spotlightLimit) -> String {
        "(Spotlight was still searching after \(Int(limit)) seconds: these are the matches it found by then, there may be more.)"
    }

    /// Runs `program` and waits at most `limit` seconds (nil: until it ends). Past the limit the child is ended and the
    /// status is `timedOutStatus`. Nil when it couldn't be started at all.
    /// `atLimit`: asked once, when the limit is reached with the child still running, with the seconds waited: how much
    /// longer the same child may go on (a script macOS is still asking the owner about: ArisPermissionWait), or nil to
    /// stop it now. The child is never started again.
    static func capture(_ program: String, _ arguments: [String], limit: TimeInterval?) -> Result? {
        ArisOrigin.refuseUnlessStillAllowed()
        return capture(program, arguments, limit: limit, atLimit: nil)
    }

    static func capture(_ program: String, _ arguments: [String], limit: TimeInterval?, atLimit: ((TimeInterval) -> TimeInterval?)?) -> Result? {
        // A script sent to an app, a capture: looked at again when this command has been waiting (ArisOrigin+Recheck).
        ArisOrigin.refuseUnlessStillAllowed()
        // ArisExactProcess, not Process: Foundation decomposes Korean in arguments (audit nfd-argv-1).
        let process = ArisExactProcess()
        let output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        guard (try? process.run()) != nil else { return nil }
        let printed = Collected(), complaint = Collected()
        let reading = DispatchGroup()
        for (pipe, into) in [(output, printed), (errors, complaint)] {
            reading.enter()
            DispatchQueue.global().async {
                into.set(pipe.fileHandleForReading.readDataToEndOfFile())
                reading.leave()
            }
        }
        if let limit {
            let started = Date()
            var deadline = started.addingTimeInterval(limit)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning, let more = atLimit?(Date().timeIntervalSince(started)), more > 0 {
                deadline = Date().addingTimeInterval(more)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            }
            if process.isRunning {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.2)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                _ = reading.wait(timeout: .now() + 1)
                return Result(status: timedOutStatus, printed: printed.text, complaint: complaint.text)
            }
        }
        process.waitUntilExit()
        _ = reading.wait(timeout: .now() + 5)
        return Result(status: process.terminationStatus, printed: printed.text, complaint: complaint.text)
    }

    /// What is said when an app didn't answer its AppleScript in time. The request may still have gone through (the
    /// app can finish it later), so it is never called done and never "not done".
    static func timeoutLine(app: String, limit: TimeInterval = appleScriptLimit) -> String {
        "\(app) didn't answer within \(Int(limit)) seconds (it may be stuck, or waiting on a permission prompt). " +
            "Whether the request went through isn't known: don't repeat it, and tell the user to check \(app)."
    }

    /// A child's output, handed across threads.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ value: Data) { lock.withLock { data = value } }
        var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
    }
}
