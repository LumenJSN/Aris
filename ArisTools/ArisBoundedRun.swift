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

    /// The limit a program gets when the caller names none: AppleScript always has one; anything else runs to its end
    /// (a shortcut may rightly take minutes).
    static func defaultLimit(for program: String) -> TimeInterval? {
        (program as NSString).lastPathComponent == "osascript" ? appleScriptLimit : nil
    }

    /// Runs `program` and waits at most `limit` seconds (nil: until it ends). Past the limit the child is ended and the
    /// status is `timedOutStatus`. Nil when it couldn't be started at all.
    static func capture(_ program: String, _ arguments: [String], limit: TimeInterval?) -> Result? {
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
            let deadline = Date().addingTimeInterval(limit)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
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
