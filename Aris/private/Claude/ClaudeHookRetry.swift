//
//  ClaudeHookRetry.swift
//  Aris
//
//  How long the hook server waits before trying its port again. The usual reason the port is taken is an older Aris
//  still closing ("Aris 다시 시작" starts the new copy before the old one quits), and that frees within a second or
//  two: so the first wait is one second, then 2, 4, 8 … up to five minutes for a port another app keeps.
//  Foundation only (tested).
//

import Foundation

enum ClaudeHookRetry {
    static let firstWait: TimeInterval = 1
    static let longestWait: TimeInterval = 300

    /// The wait before try number `attempt` (1 is the first retry): 1 s, 2, 4, 8 … capped at five minutes.
    static func retryWait(_ attempt: Int) -> TimeInterval {
        let doublings = min(max(attempt, 1) - 1, 30)
        return min(firstWait * pow(2, Double(doublings)), longestWait)
    }
}
