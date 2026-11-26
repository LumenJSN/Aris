//
//  ArisAppTaken.swift
//  Aris
//
//  The app's answer to a request aris-tools handed it through ~/.config/aris (timer.json, board.json, nudged by
//  com.lumenjsn.aris.timer / .board). The sandbox lets the app read there but never write or remove (Aris.entitlements:
//  read-only), so removing the file can't be its answer (sixteenth VM run, M1: the remove failed silently and the timer
//  that ran was told as not set). It answers `<nudge>.taken` with the request's id instead (ArisAppAck on the other
//  side, which removes the file), once per id: the same request nudged again is not done twice. Foundation only (tested).
//

import Foundation

struct ArisAppTaken {
    let nudge: String
    /// The id answered last.
    private(set) var last: String?

    init(nudge: String) { self.nudge = nudge }

    /// The answer's name: what aris-tools listens for (ArisAppAck.takenName).
    static func answerName(_ nudge: String) -> String { nudge + ".taken" }

    /// Whether `entry` is to be done: not the request answered last. Its id is answered first; an entry with no id (or
    /// one that isn't a UUID) is done with no answer.
    mutating func take(_ entry: [String: Any], post: (String, String) -> Void = ArisAppTaken.post) -> Bool {
        guard let id = entry["id"] as? String, UUID(uuidString: id) != nil else { return true }
        guard id != last else { return false }
        last = id
        post(Self.answerName(nudge), id)
        return true
    }

    /// A sandboxed app's distributed notification carries no userInfo: the id is its object.
    static func post(_ name: String, _ id: String) {
        DistributedNotificationCenter.default().postNotificationName(.init(name), object: id, userInfo: nil, deliverImmediately: true)
    }
}
