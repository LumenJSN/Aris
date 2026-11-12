//
//  ClaudeSounds.swift
//  Aris
//
//  Short system sounds for approval / done / error. Off with
//  `defaults write com.lumenjsn.aris claudeSounds -bool false`.
//

import AppKit

enum ClaudeSounds {
    enum Cue: String {
        case approval = "Ping"
        case done = "Glass"
        case error = "Basso"
    }

    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: "claudeSounds") as? Bool ?? true
    }

    /// `starter`: who began what the sound is about (ArisQuiet): Aris's own news unless a card says otherwise, so a
    /// muted Aris never chimes and its own news is silent in quiet time.
    static func play(_ cue: Cue, starter: ArisQuiet.Starter = .aris) {
        guard enabled, ArisQuietGate.maySound(starter) else { return }
        NSSound(named: NSSound.Name(cue.rawValue))?.play()
    }
}
