//
//  ArisScreenAccess.swift
//  aris-agent
//
//  Whether aris-agent may record the screen, as macOS has it now. A running process is told the same thing for as long
//  as it runs, so an agent that started without the permission said "off" until it was restarted (VM bug 1: every
//  screen answer after the grant; the "Screen Recording is off" card asked the same stale question). Unless this
//  process has already seen it on, the question goes to a new aris-tools process each time (`screen --access`), which
//  macOS answers for aris-agent as of now. Nothing here asks macOS to show anything.
//

import CoreGraphics
import Foundation

enum ArisScreenAccess {
    /// The words aris-tools is started with; it prints "on" or "off" and captures nothing.
    static let question = ["screen", "--access"]

    private static let lock = NSLock()
    /// A fresh check said on since this agent started.
    nonisolated(unsafe) private static var seenOn = false
    /// A capture failed and a fresh check said off: this process's own answer (CGPreflightScreenCaptureAccess, kept by
    /// macOS for the process's life) no longer counts until a fresh check says on again.
    nonisolated(unsafe) private static var revoked = false

    static func parse(_ said: String?) -> Bool? {
        switch said {
        case "on": true
        case "off": false
        default: nil
        }
    }

    /// Whether the answer is known to be on without asking a new process. Pure.
    static func known(preflight: Bool, seenOn: Bool, revoked: Bool) -> Bool { !revoked && (preflight || seenOn) }

    /// As a new process sees it; nil when aris-tools couldn't say.
    static func fresh(tools: String, environment: [String: String]) -> Bool? {
        parse(ArisLook.tool(tools, question, environment))
    }

    /// Whether a capture may be tried now (ArisScreenRead.allowed); nil when macOS couldn't be asked.
    static func allowed(tools: String, environment: [String: String]) -> Bool? {
        let state = lock.withLock { (seenOn, revoked) }
        let isKnown = known(preflight: CGPreflightScreenCaptureAccess(), seenOn: state.0, revoked: state.1)
        let answer = ArisScreenRead.allowed(known: isKnown) { fresh(tools: tools, environment: environment) }
        if !isKnown, answer == true { lock.withLock { seenOn = true; revoked = false } }
        return answer
    }

    /// A capture just failed: what macOS says now, whatever this process saw before (a grant taken back is noticed
    /// here, not cached as on until the agent restarts).
    static func afterFailure(tools: String, environment: [String: String]) -> Bool? {
        let answer = fresh(tools: tools, environment: environment)
        note(failureAnswer: answer)
        return answer
    }

    /// What a fresh check after a failed capture said, kept. Separate for the tests.
    static func note(failureAnswer answer: Bool?) {
        lock.withLock {
            if answer == false { seenOn = false; revoked = true }
            if answer == true { seenOn = true; revoked = false }
        }
    }

    /// The same two questions asked with the agent's own aris-tools and environment, for a caller that doesn't run
    /// brains (the session look; ArisScreenAccess+Live's `now` is the runner's).
    static func nowAsAgent() -> Bool { allowed(tools: ArisAppBundle.toldTools, environment: ProcessInfo.processInfo.environment) == true }
    static func afterFailureAsAgent() -> Bool? { afterFailure(tools: ArisAppBundle.toldTools, environment: ProcessInfo.processInfo.environment) }

    /// The state, for the tests.
    static var remembered: (seenOn: Bool, revoked: Bool) { lock.withLock { (seenOn, revoked) } }
}
