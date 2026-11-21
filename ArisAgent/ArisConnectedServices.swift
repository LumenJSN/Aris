//
//  ArisConnectedServices.swift
//  aris-agent
//
//  Whether a service that only some users set up is there, so a brain is given it (and told about it) only then:
//  Aris's own Notion login for Codex (`codex mcp login aris_notion`), and Canvas (a token and a school in
//  ~/.config/aris). Every Codex used to get the Notion server and its prompt, and every prompt the Canvas line,
//  although only the user has either (audit).
//

import Foundation

/// Aris's Notion login, as Codex itself reports it (`codex mcp list --json` with Aris's server named): only its
/// auth state is read, never a token. Asked in the background and kept; never waited on.
enum ArisNotionLink {
    /// Asked again after this long (sooner while it isn't connected, so a fresh login shows up within a minute).
    static let staleAfter: TimeInterval = 600
    static let notConnectedAfter: TimeInterval = 60

    /// Whether Aris's server is logged in, from what `codex mcp list --json` printed: nil when it doesn't say.
    static func connected(inList output: String) -> Bool? {
        guard let list = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [[String: Any]] else { return nil }
        guard let entry = list.first(where: { $0["name"] as? String == "aris_notion" }) else { return false }
        guard let auth = entry["auth_status"] as? String else { return nil }
        return entry["enabled"] as? Bool != false && ["o_auth", "bearer_token"].contains(auth)
    }

    /// Asks Codex now: nil when it couldn't be asked (no Codex: false).
    static func askCodex() -> Bool? {
        guard let codex = ArisReadJudge.executable(.codex) else { return false }
        // node for an npm-installed Codex: the folders Aris knows, then the user's own (ArisLoginPath).
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ArisPrograms.childPath(first: ArisPrograms.knownFolders() + ["/usr/bin", "/bin"], inherited: environment["PATH"])
        let result = ArisSkillProcess.run(codex.path, ["-c", "mcp_servers.aris_notion.url=\"\(ArisCodexDriver.notionURL)\"", "mcp", "list", "--json"],
                                          environment: environment, timeout: 15, maxOutput: 512 * 1_024)
        return result.ok ? connected(inList: result.stdout) : nil
    }

    static let shared = Watch(ask: askCodex)

    /// Whether Codex gets Notion: what Codex last said; until it has said anything, as before (yes).
    static var isConnected: Bool { shared.value() }

    /// Asks now, in the background (the agent's start).
    static func warm() { shared.refresh() }

    /// One yes/no asked in the background and kept; stale answers are asked again, never waited on.
    final class Watch: @unchecked Sendable {
        private let ask: () -> Bool?
        private let lock = NSLock()
        private let queue = DispatchQueue(label: "aris.notion-link", qos: .utility)
        private var known: (connected: Bool, at: Date)?
        /// When Codex last couldn't answer: asked again only after a minute.
        private var failedAt: Date?
        private var running = false

        init(ask: @escaping () -> Bool?) { self.ask = ask }

        /// The last answer (yes before any), asking again in the background when it is stale.
        func value(now: Date = Date()) -> Bool {
            lock.withLock {
                let limit = known?.connected == false ? ArisNotionLink.notConnectedAfter : ArisNotionLink.staleAfter
                let due = known.map { now.timeIntervalSince($0.at) >= limit } ?? true
                if due, failedAt.map({ now.timeIntervalSince($0) >= ArisNotionLink.notConnectedAfter }) ?? true { startLocked() }
                return known?.connected ?? true
            }
        }

        func refresh() { lock.withLock { startLocked() } }

        /// Waits for a running ask (the tests).
        func settle() { queue.sync {} }

        private func startLocked() {
            guard !running else { return }
            running = true
            queue.async { [self] in
                let answer = ask()
                lock.withLock {
                    // A Codex that couldn't answer leaves what was known (and is asked again next time).
                    if let answer { known = (answer, Date()); failedAt = nil } else { failedAt = Date() }
                    running = false
                }
            }
        }
    }
}

/// Canvas is set up when its token and its school are both saved (only their being there is looked at, as
/// `aris-tools brief` does).
enum ArisCanvasSetup {
    static func isSetUp(folder: URL) -> Bool {
        ["canvas-key", "canvas-host"].allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }
}
