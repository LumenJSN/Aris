//
//  ArisFleetLive.swift
//  aris-agent
//
//  The live parts of the fleet's calls (ArisFleetCalls): Claude Code's own list (`claude agents --json`) with each
//  session's host (its process, ArisSessionHost.classify) and branch (its HEAD file, read only); the app's fleet and its
//  "no" to a request (POST /aris/sessions, the shared token); Escape where a session lives (the same reach and checks as
//  a send: its process, its proven place, the desktop lock); SIGTERM to a session's own process. Nothing here decides.
//

import AppKit
import Darwin
import Foundation

enum ArisFleetLive {
    static var deps: ArisFleetDeps {
        ArisFleetDeps(listing: listing, fleet: fleet, deny: deny, interrupt: interrupt, terminate: { pid in kill(pid, SIGTERM) == 0 },
                      isFolder: isFolder)
    }

    static func isFolder(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }

    static func listing() -> (rows: [ArisFleetListing], complete: Bool)? {
        guard let entries = ArisSessionLive.agents() else { return nil }
        let rows = entries.map { entry -> ArisFleetListing in
            var row = ArisFleetListing(session: entry.sessionId, pid: entry.pid, cwd: entry.cwd)
            row.started = entry.started.map { Date(timeIntervalSince1970: $0) }
            row.title = entry.name
            row.background = entry.background
            row.status = entry.status
            row.branch = ArisFleetGit.branch(of: entry.cwd, read: { try? String(contentsOfFile: $0, encoding: .utf8) }, isFolder: isFolder)
            row.reach = reach(entry)
            return row
        }
        return (rows, true)
    }

    /// Where the session lives, from its process (as a send would find it).
    static func reach(_ entry: ArisSessionAgents.Entry) -> ArisFleetReach? {
        guard let row = ArisSessionLive.anyRow(entry.pid) else { return nil }
        let app = ArisSessionLive.hostApp(of: entry.pid)
        let host = ArisSessionHost.classify(environment: row.terminal, tty: row.tty, hostBundle: app?.bundleIdentifier, hostName: app?.localizedName,
                                            background: entry.background)
        return fleetReach(host)
    }

    static func fleetReach(_ host: ArisSessionHost) -> ArisFleetReach {
        switch host {
        case .tmux: return ArisFleetReach(kind: .tmux)
        case .screen: return ArisFleetReach(kind: .screen)
        case .wezterm: return ArisFleetReach(kind: .wezterm)
        case .kitty: return ArisFleetReach(kind: .kitty)
        case .iterm: return ArisFleetReach(kind: .iterm)
        case .terminalApp: return ArisFleetReach(kind: .terminal)
        case .warp: return ArisFleetReach(kind: .warp)
        case .editor: return ArisFleetReach(kind: .editorTerminal, app: host.name)
        case .window: return ArisFleetReach(kind: .window, app: host.name)
        case .claudeDesktop: return ArisFleetReach(kind: .claudeApp)
        case .editorPanel: return ArisFleetReach(kind: .editorPanel, app: host.name)
        case .background: return ArisFleetReach(kind: .background)
        case .unsupported: return ArisFleetReach(kind: .unsupported, app: host.name)
        }
    }

    static func json(_ row: ArisFleetListing) -> [String: Any] {
        var object: [String: Any] = ["session": row.session, "pid": Int(row.pid), "cwd": row.cwd, "background": row.background]
        if let started = row.started { object["started"] = started.timeIntervalSince1970 }
        if let title = row.title { object["title"] = title }
        if let status = row.status { object["status"] = status }
        if let branch = row.branch { object["branch"] = branch }
        if let reach = row.reach { object["reach"] = ["kind": reach.kind.rawValue, "app": reach.app ?? ""] }
        return object
    }

    static func fleet(_ rows: [ArisFleetListing], complete: Bool) -> ArisFleet? {
        guard let reply = ArisSessionLive.post(["op": "fleet", "listing": rows.map(json), "complete": complete]), reply["ok"] as? Bool == true,
              let object = reply["fleet"], let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return ArisFleet.decoded(data)
    }

    static func deny(_ session: String, _ fingerprint: String) -> Bool {
        ArisSessionLive.post(["op": "deny", "session": session, "fingerprint": fingerprint])?["ok"] as? Bool == true
    }

    /// Escape in the session's own place, found and proven as a send finds it; nothing anywhere else.
    static func interrupt(_ session: ArisLiveSession, _ turn: ArisDesktopTurn) -> ArisSessionStop? {
        guard turn.live else { return .gone }
        let deps = ArisSessionLive.deps
        guard deps.hold(turn) else { return .lockBusy }
        defer { deps.release(turn) }
        let process: ArisSessionProcess
        switch ArisSessionLive.process(session) {
        case .none: return .notRunning
        case .many: return .manyProcesses
        case .found(let found): process = found
        }
        guard process.foreground else { return .shellInFront }
        let target: ArisSessionTarget
        switch ArisSessionLive.focus(session, process) {
        case .failure(let why): return why
        case .success(let proven): target = proven
        }
        defer { ArisSessionLive.finish(target) }
        return ArisSessionLive.escape(target)
    }
}
