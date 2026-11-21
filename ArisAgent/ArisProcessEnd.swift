//
//  ArisProcessEnd.swift
//  aris-agent
//
//  Ending a child process for good, with its process group (the tools it started). SIGTERM first, as before; a child
//  that ignores it (a `claude -p` mid-tool, a Codex app-server whose MCP servers hang) is killed after a short grace,
//  so a stopped turn never leaves a process burning CPU behind it.
//

import Foundation

enum ArisProcessEnd {
    /// Seconds between SIGTERM and SIGKILL.
    static let defaultGrace: TimeInterval = 5

    /// Catches SIGTERM (launchd's stop) on `queue`. A real handler rather than SIG_IGN: an ignored signal is inherited
    /// across a bare exec, while a handler is reset to the default disposition in the child. (Foundation's Process
    /// spawns with every signal reset to its default anyway, as the tests verify, so children always honour
    /// terminate().) The dispatch source then delivers the signal to `handler`.
    nonisolated(unsafe) private static var termination: [DispatchSourceSignal] = []

    /// SIGTERM (launchd's stop) and SIGINT (a terminal's ^C) both: the helper stops its children, then exits.
    static func catchTermination(on queue: DispatchQueue, _ handler: @escaping () -> Void) {
        termination = [SIGTERM, SIGINT].map { number in
            signal(number) { _ in }
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler(handler: handler)
            source.resume()
            return source
        }
    }

    /// The child and its process group (what it started: ArisProcessGroup), SIGTERM first, SIGKILL after `grace` to
    /// whatever of the group is left.
    static func end(_ process: Process, grace: TimeInterval = defaultGrace) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        let since = ArisProcessGroup.info(pid).flatMap { $0.group == pid ? $0.started : nil }
        process.terminate()
        if let since { ArisProcessGroup.signal(pid, since: since, SIGTERM) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) {
            if let since { ArisProcessGroup.signal(pid, since: since, SIGKILL) }
            guard process.isRunning, process.processIdentifier == pid else { return }
            kill(pid, SIGKILL)
        }
    }
}
