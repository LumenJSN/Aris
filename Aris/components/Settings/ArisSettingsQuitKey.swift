//
//  ArisSettingsQuitKey.swift
//  Aris
//
//  Which key press is ⌘Q for the settings window (ArisSettingsNSWindow quits Aris on it, like the menu's Quit).
//

import AppKit

/// ⌘Q: Command alone (no Option, Control or Shift) with Q, by its letter or, under an input source that gives another
/// letter (두벌식's ㅂ), by the Q key's place. Pure.
enum ArisSettingsQuitKey {
    static let qKeyCode: UInt16 = 12

    static func quits(characters: String?, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.intersection([.command, .option, .control, .shift]) == [.command] else { return false }
        let letter = characters?.lowercased() ?? ""
        if letter == "q" { return true }
        return keyCode == qKeyCode && !(letter.count == 1 && letter.unicodeScalars.allSatisfy { $0.isASCII })
    }
}
