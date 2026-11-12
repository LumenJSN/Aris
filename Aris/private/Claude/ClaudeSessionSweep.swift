//
//  ClaudeSessionSweep.swift
//  Aris
//
//  Which listed sessions are over, looked at once a minute (audit claude-1: a finished Codex session and a terminal
//  that was force-closed stayed in the 기록 tab and the closed notch until Aris was restarted). A session ends itself
//  with SessionEnd; the ones that can't are found here:
//   · nothing heard for two hours (the store's own limit, which only ran when another session spoke);
//   · its terminal app was running when Aris last looked and no longer is (an app never seen running is left
//     alone: the terminal named by a hook can be a guess, as with editors built on VS Code);
//   · Codex, which has no SessionEnd hook: resting for 15 minutes after its last turn.
//  A session that was working and has been silent for an hour is shown resting: a long build is quiet for many
//  minutes between two hooks, so the wait is long. Foundation only (tested).
//

import Foundation

enum ClaudeSessionSweep {
    /// Nothing heard for this long: the session is forgotten (also applied whenever an event arrives).
    static let staleAfter: TimeInterval = 2 * 60 * 60
    /// A Codex session that finished its turn and stayed quiet this long is over.
    static let codexRestAfter: TimeInterval = 15 * 60
    /// A session that was working and went silent this long is shown resting.
    static let workingQuietAfter: TimeInterval = 60 * 60
    /// How often the store looks.
    static let every: TimeInterval = 60

    /// What one look leaves: the sessions still listed, and those whose terminal app has been seen running.
    struct Look: Equatable {
        let sessions: [String: ClaudeSession]
        let terminalSeen: Set<String>
    }

    /// The sessions still listed at `now`. `runningApps` holds the bundle ids of the apps running now; nil when that
    /// isn't known, and then no session is dropped for its terminal. `terminalSeen` is the last look's.
    static func swept(_ sessions: [String: ClaudeSession], now: Date, runningApps: Set<String>?, terminalSeen: Set<String> = []) -> Look {
        let terminalRuns = sessions.compactMapValues { session -> Bool? in
            guard let runningApps, let terminal = session.terminal else { return nil }
            return terminal.isRunning(among: runningApps)
        }
        let kept = sessions.compactMapValues { session -> ClaudeSession? in
            let quiet = now.timeIntervalSince(session.lastEvent)
            if quiet >= staleAfter { return nil }
            if terminalRuns[session.id] == false, terminalSeen.contains(session.id) { return nil }
            if session.agent == "codex", isResting(session.state), quiet >= codexRestAfter { return nil }
            if isWorking(session.state), quiet >= workingQuietAfter { return session.with(state: .idle) }
            return session
        }
        let seen = terminalSeen.union(terminalRuns.filter(\.value).keys).intersection(kept.keys)
        return Look(sessions: kept, terminalSeen: seen)
    }

    /// Waiting for the next prompt.
    static func isResting(_ state: ClaudeState) -> Bool {
        state == .idle || state == .happy || state == .sleeping
    }

    /// In the middle of a turn, as far as the last hook said.
    static func isWorking(_ state: ClaudeState) -> Bool {
        state == .thinking || state == .typing || state == .building || state == .juggling
    }
}

extension ClaudeSession {
    /// The same session in another state (its last event's time is kept).
    func with(state: ClaudeState) -> ClaudeSession {
        ClaudeSession(id: id, cwd: cwd, state: state, lastEvent: lastEvent, steps: steps, edit: edit, lastMessage: lastMessage,
                      terminal: terminal, contextPercent: contextPercent, agent: agent)
    }
}

extension TerminalRef {
    static let itermBundle = "com.googlecode.iterm2"
    /// Warp's builds (Stable, Preview) share this start.
    static let warpPrefix = "dev.warp."

    /// Whether the app this terminal lives in is among the running apps' bundle ids.
    func isRunning(among runningApps: Set<String>) -> Bool {
        switch self {
        case .app(let bundle): return runningApps.contains(bundle)
        case .iterm: return runningApps.contains(Self.itermBundle)
        case .warp: return runningApps.contains { $0.hasPrefix(Self.warpPrefix) }
        }
    }
}
