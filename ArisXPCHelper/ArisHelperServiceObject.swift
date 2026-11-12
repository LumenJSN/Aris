//
//  ArisHelperServiceObject.swift
//  Aris
//
//  The helper's side of ArisHelperService: one object per app connection. The agent restart runs launchctl with
//  ArisAgentKickstart's fixed arguments only, and the install (ArisAgentInstaller) builds everything from this
//  helper's own place in the app; nothing the app sends reaches a command line or a file.
//

import Foundation

/// Runs a program and hands back its exit status, or nil when it couldn't be started or ran too long. Never blocks
/// the caller's queue.
typealias ArisProcessRunner = (_ executable: String, _ arguments: [String], _ done: @escaping @Sendable (Int32?) -> Void) -> Void

/// Calls `done` once, whichever of the exit or the timeout comes first.
private final class ArisExitOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done: (@Sendable (Int32?) -> Void)?

    init(_ done: @escaping @Sendable (Int32?) -> Void) { self.done = done }

    func finish(_ status: Int32?) {
        lock.lock()
        let pending = done
        done = nil
        lock.unlock()
        pending?(status)
    }
}

enum ArisAgentRestart {
    /// How long launchctl may take before the restart counts as failed (and launchctl is stopped).
    static let timeout: TimeInterval = 15

    /// The user's real home (the helper is not sandboxed), where the agent's LaunchAgent file is.
    static var realHome: String {
        getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    }

    /// Restarts the agent. When launchctl ran and refused the kickstart, the agent's LaunchAgent is not loaded (a
    /// failed install, a bootout): it is loaded then, if its file exists, and the answer is that load's. The file's
    /// path is built here from the real home; nothing the app sends is part of either command.
    static func run(using runner: @escaping ArisProcessRunner, uid: uid_t = getuid(), home: String = realHome,
                    plistExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                    mayKickstart: () -> Bool = { true },
                    reply: @escaping @Sendable (Bool) -> Void) {
        nonisolated(unsafe) let runner = runner
        // A kickstart within ten seconds of the last one would leave the helper down until launchd's wait is over:
        // the one already sent is the restart.
        guard mayKickstart() else { return reply(true) }
        runner(ArisAgentKickstart.launchctl, ArisAgentKickstart.arguments(uid: uid)) { status in
            if status == 0 { return reply(true) }
            guard status != nil, plistExists(ArisAgentKickstart.plistPath(home: home)) else { return reply(false) }
            runner(ArisAgentKickstart.launchctl, ArisAgentKickstart.bootstrapArguments(uid: uid, home: home)) { reply($0 == 0) }
        }
    }

    static func liveRunner(timeout: TimeInterval) -> ArisProcessRunner {
        { executable, arguments, done in
            let once = ArisExitOnce(done)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in once.finish(finished.terminationStatus) }
            do {
                try process.run()
            } catch {
                once.finish(nil)
                return
            }
            nonisolated(unsafe) let running = process
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard running.isRunning else { return }
                running.terminate()
                once.finish(nil)
            }
        }
    }
}

final class ArisHelperServiceObject: NSObject, ArisHelperService {
    private let runner: ArisProcessRunner
    private let brightness: ArisDisplayBrightness
    private let clock: ArisKickstartClock

    init(runner: @escaping ArisProcessRunner = ArisAgentRestart.liveRunner(timeout: ArisAgentRestart.timeout),
         brightness: ArisDisplayBrightness = ArisDisplayBrightness(backend: ArisSystemBrightness()), clock: ArisKickstartClock = .shared) {
        self.runner = runner
        self.brightness = brightness
        self.clock = clock
    }

    func restartAgent(reply: @escaping (Bool) -> Void) {
        nonisolated(unsafe) let reply = reply
        ArisAgentRestart.run(using: runner, mayKickstart: { [clock] in clock.take() }) { reply($0) }
    }

    func installAgent(reply: @escaping (String) -> Void) {
        nonisolated(unsafe) let reply = reply
        ArisAgentInstallLive.queue.async { reply(ArisAgentInstaller.run(ArisAgentInstallLive.world()).word) }
    }

    func setScreenBrightness(_ level: Float, reply: @escaping (Bool) -> Void) {
        reply(brightness.set(level))
    }

    func adjustScreenBrightness(by delta: Float, reply: @escaping (NSNumber?) -> Void) {
        reply(brightness.adjust(by: delta).map { NSNumber(value: $0) })
    }
}

/// Accepts connections from Aris itself only (ArisXPCTrust), one service object each.
final class ArisHelperListener: NSObject, NSXPCListenerDelegate {
    private let requirePeer: Bool
    private let makeService: () -> ArisHelperService

    init(requirePeer: Bool = true, makeService: @escaping () -> ArisHelperService = { ArisHelperServiceObject() }) {
        self.requirePeer = requirePeer
        self.makeService = makeService
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if requirePeer { connection.setCodeSigningRequirement(ArisXPCTrust.requirement(peer: ArisXPCTrust.appId)) }
        connection.exportedInterface = ArisHelperName.interface()
        connection.exportedObject = makeService()
        connection.resume()
        return true
    }
}
