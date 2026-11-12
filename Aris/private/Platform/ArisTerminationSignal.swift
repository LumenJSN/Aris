//
//  ArisTerminationSignal.swift
//  Aris
//
//  SIGTERM (`kill`, an installer, launchd) quits Aris the way the menu's Quit does. It used to do nothing at all (VM
//  run 2026-11-10, bug 7): the app links the bundled MediaRemoteAdapter.framework, whose load-time initializer takes
//  SIGINT and SIGTERM for itself with a handler that only stops the main run loop. In the adapter's own Perl process
//  that ends it; in an app the run loop is simply run again, so the signal was swallowed and only `kill -9` worked.
//  Aris now takes SIGTERM back after launch: a normal quit on the main thread, and if the process is still here a few
//  seconds later (a main thread that is stuck, a quit that something put off), it exits anyway.
//  Foundation only (tested by sending the test process a real SIGTERM).
//

import Foundation

enum ArisTerminationSignal {
    /// How long a normal quit gets before the process exits regardless.
    static let grace: TimeInterval = 4

    nonisolated(unsafe) private static var source: DispatchSourceSignal?

    /// From now on a SIGTERM calls `handler` on `queue` (not the main queue: it must run even while the main thread is
    /// stuck). A handler function rather than SIG_IGN, which a child process would inherit across a bare exec; the
    /// dispatch source then delivers the signal. Replaces whatever handler a library installed before.
    static func watch(on queue: DispatchQueue = .global(qos: .userInitiated), _ handler: @escaping @Sendable () -> Void) {
        source?.cancel()
        signal(SIGTERM) { _ in }
        let watching = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        watching.setEventHandler(handler: handler)
        watching.resume()
        source = watching
    }

    /// SIGTERM is the system's own again: it ends the process at once.
    static func unwatch() {
        source?.cancel()
        source = nil
        signal(SIGTERM, SIG_DFL)
    }

    /// What a SIGTERM does: `quit` on the main thread now, and `force` after `grace` (which never runs when the quit
    /// ended the process first).
    static func quit(grace: TimeInterval = grace, quit: @escaping @MainActor @Sendable () -> Void, force: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async { quit() }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + grace, execute: force)
    }
}
