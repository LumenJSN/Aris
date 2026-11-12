//
//  ArisHelperClient.swift
//  Aris
//
//  The app's connection to the XPC helper. One connection, made on first use and kept while it lives; when it is
//  interrupted or invalidated the next call connects again. Calls never throw: a transport failure is recorded and
//  the call returns false / nil.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "xpc")

/// Hands a reply back exactly once, whichever of the reply or the error handler comes first.
private final class ArisReplyOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }

    func resume(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

actor ArisHelperClient {
    static let shared = ArisHelperClient {
        let connection = NSXPCConnection(serviceName: ArisHelperName.service)
        connection.setCodeSigningRequirement(ArisXPCTrust.requirement(peer: ArisXPCTrust.helperId))
        return connection
    }

    private let connect: @Sendable () -> NSXPCConnection
    private var connection: NSXPCConnection?
    private var generation = 0
    private(set) var isAvailable = true
    private(set) var lastError: String?

    init(connect: @escaping @Sendable () -> NSXPCConnection) {
        self.connect = connect
    }

    // MARK: Calls

    func restartArisAgent() async -> Bool {
        await call(false) { service, done in service.restartAgent { done($0) } }
    }

    /// Makes this app's own helper the one that runs (ArisAgentInstall). A transport failure is a failed install.
    func installArisAgent() async -> ArisAgentInstallOutcome {
        ArisAgentInstallOutcome(word: await call("failed:xpc") { service, done in service.installAgent { done($0) } })
    }

    func setScreenBrightness(_ level: Float) async -> Bool {
        await call(false) { service, done in service.setScreenBrightness(level) { done($0) } }
    }

    func adjustScreenBrightness(by delta: Float) async -> Float? {
        await call(nil) { service, done in service.adjustScreenBrightness(by: delta) { done($0?.floatValue) } }
    }

    // MARK: Connection

    private func call<Value: Sendable>(_ fallback: Value,
                                       _ body: @escaping (ArisHelperService, @escaping @Sendable (Value) -> Void) -> Void) async -> Value {
        let (current, generation) = liveConnection()
        let value: Value = await withCheckedContinuation { continuation in
            let once = ArisReplyOnce(continuation)
            let proxy = current.remoteObjectProxyWithErrorHandler { [weak self] error in
                once.resume(fallback)
                Task { await self?.failed(error.localizedDescription, generation: generation) }
            }
            guard let service = proxy as? ArisHelperService else {
                once.resume(fallback)
                return
            }
            body(service) { once.resume($0) }
        }
        return value
    }

    private func liveConnection() -> (NSXPCConnection, Int) {
        if let connection { return (connection, generation) }
        generation += 1
        let made = connect()
        let mine = generation
        made.remoteObjectInterface = ArisHelperName.interface()
        made.interruptionHandler = { [weak self] in Task { await self?.dropped("interrupted", generation: mine) } }
        made.invalidationHandler = { [weak self] in Task { await self?.dropped("invalidated", generation: mine) } }
        made.resume()
        connection = made
        isAvailable = true
        return (made, mine)
    }

    /// Only the current connection's handlers count; a stale one's are ignored.
    private func dropped(_ reason: String, generation: Int) {
        guard generation == self.generation, connection != nil else { return }
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        connection = nil
        isAvailable = false
        lastError = "helper unavailable (\(reason))"
        log.notice("XPC helper \(reason, privacy: .public)")
    }

    private func failed(_ message: String, generation: Int) {
        lastError = message
        log.error("XPC call failed: \(message, privacy: .public)")
        dropped("error", generation: generation)
    }
}
