//
//  ArisReachableServices.swift
//  Aris
//
//  The router's list of the services Aris reaches without a browser (ArisServiceReach), from the agent (POST /mcp
//  list). Kept a minute, and forgotten the moment 설정 › 연결된 서비스 saves, removes, turns on or off, or tests one, so a
//  service connected seconds before a request counts for it (the owner, 2026-11-19: the Composio key was saved 26 s
//  before his Canvas request). A slow agent never holds a turn: the last list, or none, is used then.
//

import Foundation

final class ArisReachableServices: @unchecked Sendable {
    static let shared = ArisReachableServices()

    /// A list this young is used as it is.
    static let freshFor: TimeInterval = 60
    /// The longest a turn waits for the agent's list (it answers from memory, on this Mac).
    static let askWithin: TimeInterval = 0.8

    private let lock = NSLock()
    private var known: (reach: ArisServiceReach, at: Date)?

    /// The next turn asks the agent again.
    func forget() { lock.withLock { known = nil } }

    /// What is reachable now: the last list while it is fresh, else asked again; the last known (or none) when the
    /// agent doesn't answer in time.
    func current(now: Date = Date()) async -> ArisServiceReach {
        let last = lock.withLock { known }
        if let last, now.timeIntervalSince(last.at) < Self.freshFor { return last.reach }
        guard let asked = await ArisAgentClient.reachableServices(timeout: Self.askWithin) else { return last?.reach ?? .none }
        lock.withLock { known = (asked, Date()) }
        return asked
    }
}
