//
//  ArisMusicSource.swift
//  Aris
//
//  A place now-playing information comes from (the system's Now Playing through the adapter, Music, Spotify): it
//  reports playback as it changes and takes transport commands.
//

import AppKit
import Foundation

enum ArisMusicCommand {
    case play, pause, toggle, next, previous
}

@MainActor
protocol ArisMusicSource: AnyObject {
    /// Called on the main actor with each new playback.
    var onUpdate: ((ArisPlayback) -> Void)? { get set }
    /// Called once if the source stops working on its own (the adapter's stream dying).
    var onFailure: (() -> Void)? { get set }
    func start()
    func stop()
    /// Asks for the current state now.
    func refresh()
    func send(_ command: ArisMusicCommand)
    /// Does the command and says whether it was done (what Aris says comes from this: QA BUG-37's follow-up).
    func perform(_ command: ArisMusicCommand) async -> Bool
    /// The state read now (or a moment ago), for "지금 무슨 노래야?"; nil when it can't be read.
    func current() async -> ArisPlayback?
}

extension ArisMusicSource {
    /// A source whose commands report nothing back (the system's Now Playing): sent, and taken as done.
    func perform(_ command: ArisMusicCommand) async -> Bool {
        send(command)
        return true
    }

    func current() async -> ArisPlayback? { nil }
}

/// Runs a short-lived helper process and waits for its exit status (nil if it could not start or ran past the
/// timeout, in which case it is killed).
enum ArisProcessRun {
    static func status(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async -> Int32? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            let once = ArisOnce()
            process.terminationHandler = { finished in
                if once.claim() { continuation.resume(returning: finished.terminationStatus) }
            }
            do { try process.run() } catch {
                if once.claim() { continuation.resume(returning: nil) }
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                guard once.claim() else { return }
                kill(process.processIdentifier, SIGKILL)
                continuation.resume(returning: nil)
            }
        }
    }

    /// Starts a helper without waiting for it.
    static func launch(_ executable: URL, _ arguments: [String]) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            Log.music.error("could not start \(executable.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// A flag that only the first caller gets.
final class ArisOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}
