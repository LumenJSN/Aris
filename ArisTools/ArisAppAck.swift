//
//  ArisAppAck.swift
//  aris-tools
//
//  Whether the Aris app took a request aris-tools handed it through a file and a nudge (`timer`, `board`). The app is
//  sandboxed with ~/.config/aris read-only (Aris.entitlements), so it can read the file but never remove it: it answers
//  instead, a distributed notification `<nudge>.taken` whose object is the request's id (ArisAppTaken on its side; a
//  sandboxed app may post one with no userInfo). No answer within a moment means no app took it (it isn't running, or it
//  is stuck), and the command says that instead of "set" or "on the board". aris-tools removes the file itself after,
//  answered or not, so a request no app took never starts later (sixteenth VM run, M1: the timer ran, the file stayed,
//  and the reply said it couldn't be set).
//

import Foundation

enum ArisAppAck {
    /// How long the app has to take a request.
    static let wait: TimeInterval = 3

    /// The app's answer to a request nudged by `nudge`.
    static func takenName(_ nudge: String) -> String { nudge + ".taken" }

    /// How a request is nudged and its answer heard (a seam for the tests): the distributed notification centre.
    struct Channel {
        /// Listens for `name` with exactly `object`; the token to stop with.
        var listen: (_ name: String, _ object: String, _ heard: @escaping () -> Void) -> AnyObject
        var stop: (AnyObject) -> Void
        var post: (_ name: String) -> Void

        static var distributed: Channel {
            let center = DistributedNotificationCenter.default()
            return Channel(listen: { name, object, heard in
                center.addObserver(forName: .init(name), object: object, queue: nil) { _ in heard() } as AnyObject
            }, stop: { center.removeObserver($0) }, post: { name in
                center.postNotificationName(.init(name), object: nil, userInfo: nil, deliverImmediately: true)
            })
        }
    }

    /// Hands `entry` to the app: written to `file` (0600) with a new id, `nudge` posted, then up to `timeout` for the
    /// app's answer for that id (heard on this thread's run loop). The file is removed after, either way. True: taken.
    static func handOver(_ entry: [String: Any], to file: URL, nudge: String, timeout: TimeInterval = wait, channel: Channel = .distributed) throws -> Bool {
        let id = UUID().uuidString
        var entry = entry
        entry["id"] = id
        let heard = Heard()
        let token = channel.listen(takenName(nudge), id) { heard.set() }
        defer {
            channel.stop(token)
            remove(file)
        }
        try JSONSerialization.data(withJSONObject: entry).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        channel.post(nudge)
        let deadline = Date().addingTimeInterval(timeout)
        while !heard.value {
            guard Date() < deadline else { return false }
            // A run loop with no source returns at once: then a short sleep instead.
            if !RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(poll)) { Thread.sleep(forTimeInterval: poll) }
        }
        return true
    }

    private static let poll: TimeInterval = 0.05

    /// The request's file, gone once it was handed over; a remove that fails is said on stderr (never silently).
    private static func remove(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { try FileManager.default.removeItem(at: file) } catch {
            FileHandle.standardError.write(Data("aris-tools: couldn't remove \(file.lastPathComponent) after handing it to the app: \(error.localizedDescription)\n".utf8))
        }
    }

    private final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var heard = false
        var value: Bool { lock.withLock { heard } }
        func set() { lock.withLock { heard = true } }
    }

    /// Said when the app didn't take `what` ("the timer", "the board").
    static func notTakenLine(_ what: String) -> String {
        "The Aris app didn't take \(what) within \(Int(wait)) seconds (it may not be running), so it may not have happened. Tell the user; don't say it was done."
    }
}
