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
    private static var seenOn = false

    static func parse(_ said: String?) -> Bool? {
        switch said {
        case "on": true
        case "off": false
        default: nil
        }
    }

    /// As a new process sees it; nil when aris-tools couldn't say.
    static func fresh(tools: String, environment: [String: String]) -> Bool? {
        parse(ArisLook.tool(tools, question, environment))
    }

    /// Whether a capture may be tried now (ArisScreenRead.allowed); nil when macOS couldn't be asked.
    static func allowed(tools: String, environment: [String: String]) -> Bool? {
        let known = CGPreflightScreenCaptureAccess() || lock.withLock { seenOn }
        let answer = ArisScreenRead.allowed(known: known) { fresh(tools: tools, environment: environment) }
        if !known, answer == true { lock.withLock { seenOn = true } }
        return answer
    }

    /// A capture just failed: what macOS says now, whatever this process saw before.
    static func afterFailure(tools: String, environment: [String: String]) -> Bool? {
        let answer = fresh(tools: tools, environment: environment)
        if answer == false { lock.withLock { seenOn = false } }
        return answer
    }
}
