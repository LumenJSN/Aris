//
//  ArisMicRestart.swift
//  Aris
//
//  What to do when the audio engine's configuration changes mid-turn (which stops it). On the device the turn opened,
//  a format, sample-rate or output change means the tap is reinstalled for the new format and the engine started
//  again, at most twice a turn; a different or vanished input device, or a third change, ends the turn cleanly with
//  what was heard. Pure, so the policy is tested without audio hardware.
//

import Foundation

enum ArisMicRestart {
    /// Engine restarts allowed in one turn.
    static let mostRestarts = 2

    enum Decision: Equatable {
        /// Reinstall the tap for the new format and start the engine again.
        case reinstall
        /// Stop listening and keep the partial text.
        case endTurn
    }

    /// `opened`: the device the turn opened (nil when it couldn't be read: then only the count limits restarts);
    /// `current`: the device the engine uses now; `present`: the input devices present now.
    static func decide(restarts: Int, opened: UInt32?, current: UInt32?, present: Set<UInt32>) -> Decision {
        if let opened, current != opened || !present.contains(opened) { return .endTurn }
        return restarts < mostRestarts ? .reinstall : .endTurn
    }
}
