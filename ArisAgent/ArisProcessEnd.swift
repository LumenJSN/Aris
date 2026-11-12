//
//  ArisProcessEnd.swift
//  aris-agent
//
//  Ending a child process for good. SIGTERM first, as before; a child that ignores it (a `claude -p` mid-tool, a Codex
//  app-server whose MCP servers hang) is killed after a short grace, so a stopped turn never leaves a process
//  burning CPU behind it.
//

import Foundation

enum ArisProcessEnd {
    /// Seconds between SIGTERM and SIGKILL.
    static let defaultGrace: TimeInterval = 5

    /// Catches SIGTERM (launchd's stop) on `queue`. A real handler rather than SIG_IGN: an ignored signal is inherited
    /// across a bare exec, while a handler is reset to the default disposition in the child. (Foundation's Process
    /// spawns with every signal reset to its default anyway, as the tests verify, so children always honour
    /// terminate().) The dispatch source then delivers the signal to `handler`.
    nonisolated(unsafe) private static var termination: DispatchSourceSignal?

    static func catchTermination(on queue: DispatchQueue, _ handler: @escaping () -> Void) {
        signal(SIGTERM) { _ in }
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        source.setEventHandler(handler: handler)
        source.resume()
        termination = source
    }

    static func end(_ process: Process, grace: TimeInterval = defaultGrace) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) {
            guard process.isRunning, process.processIdentifier == pid else { return }
            kill(pid, SIGKILL)
        }
    }
}
