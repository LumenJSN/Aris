//
//  ClaudeHookServer.swift
//  Aris
//
//  Loopback HTTP endpoint that Claude Code's `http` hooks POST to. A hook must never hold Claude Code up: an event
//  with nothing to decide is answered from the server's own queues in about a millisecond (read, check the token,
//  queue the event for the notch, reply) and never waits for the main thread, Reminders, the helper or another
//  connection. Each connection has a queue of its own (ClaudeHookConnection) and every path has a deadline
//  (ClaudeHookHold). Only Claude's PermissionRequest is kept open, and only while the notch shows its card.
//  When Aris quits or the listener fails, every open connection is answered and closed, so a client fails fast.
//

import Foundation
import Network

/// Its listener, its connections and its retries are read and written only on its own queue.
final class ClaudeHookServer: @unchecked Sendable {
    static let port: NWEndpoint.Port = 23350

    let stats = HookStats()

    private let port: NWEndpoint.Port
    private let token: () -> String?
    private let consumer: HookConsumer
    private let limits: HookLimits

    /// Accepts connections and keeps the listener's own state (everything below is read and written only here).
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.claude.hook-server", qos: .userInitiated)
    private let intake = DispatchQueue(label: "com.lumenjsn.aris.claude.hook-intake", qos: .userInitiated)
    private let clock = DispatchQueue(label: "com.lumenjsn.aris.claude.hook-clock", qos: .userInteractive)
    private let deciders: HookDeciders

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HookConnection] = [:]
    private var stopped = false
    /// The port was taken (an older Aris still closing, another notch app): tried again after 1 s, 2, 4, 8 … 5 min
    /// (ClaudeHookRetry), so the hooks come back without a relaunch once it's free.
    private var retries = 0

    /// `token` is asked for each request, so re-running the installer takes effect without a relaunch; none (no
    /// token file) refuses everything.
    init(port: NWEndpoint.Port = ClaudeHookServer.port, token: @escaping () -> String? = { ClaudeHookToken.load() },
         consumer: HookConsumer, limits: HookLimits = .standard) {
        self.port = port
        self.token = token
        self.consumer = consumer
        self.limits = limits
        deciders = HookDeciders(limit: limits.deciding)
    }

    func start() {
        queue.async {
            self.stopped = false
            self.open()
        }
    }

    /// Closes the port and every open connection (the app is quitting): a waiting retry does nothing afterwards, so
    /// a copy of Aris that is just starting finds the port free, and no client is left waiting for an answer.
    func stop() {
        queue.sync {
            stopped = true
            listener?.cancel()
            listener = nil
            closeConnections()
        }
    }

    /// How many connections are open now (the tests' question).
    var openConnections: Int { queue.sync { connections.count } }

    private func open() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        // Local processes only: never reachable from the network.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)

        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            // Assigned before start, so a failure that arrives at once finds it; states are handled only for the
            // listener still in charge (a retry's new one supersedes the old).
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready: self.retries = 0
                case .failed(let error):
                    NSLog("[Claude] hook server failed: \(error)")
                    self.closeConnections()
                    self.retryLater()
                default: break
                }
            }
            listener.start(queue: queue)
        } catch {
            NSLog("[Claude] cannot start hook server on \(port): \(error)")
            retryLater()
        }
    }

    private func retryLater() {
        listener?.cancel()
        listener = nil
        retries += 1
        let wait = ClaudeHookRetry.retryWait(retries)
        NSLog("[Claude] hook server: trying port \(port) again in \(Int(wait)) s")
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, !self.stopped else { return }
            self.open()
        }
    }

    private func accept(_ connection: NWConnection) {
        let context = HookConnection.Context(port: Int(port.rawValue), token: token, consumer: consumer, limits: limits,
                                             stats: stats, intake: intake, clock: clock, deciders: deciders)
        // A serial queue of its own, with no shared queue under it: it gets a thread whenever it has work, however
        // many other connections (or other parts of the app) are busy or blocked.
        let own = DispatchQueue(label: "com.lumenjsn.aris.claude.hook-connection", qos: .userInitiated)
        let handled = HookConnection(connection, context: context, queue: own) { [weak self] closed in
            self?.queue.async { self?.connections[ObjectIdentifier(closed)] = nil }
        }
        connections[ObjectIdentifier(handled)] = handled
        handled.start()
    }

    private func closeConnections() {
        connections.values.forEach { $0.close() }
    }
}
