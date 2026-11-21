//
//  ArisPermissionsNote.swift
//  Aris
//
//  The note above 앱 › 권한's list says what 허용하기 does for the rows still missing: Microphone, Speech Recognition,
//  the folders, and Reminders and Calendar (never answered) raise macOS's own dialog, while Accessibility, Screen
//  Recording, Full Disk Access, Input Monitoring, System Audio and a permission refused before open System Settings.
//  The note used to say "System Settings opens: drag the Aris icon" for all of them, Reminders and Calendar too (VM
//  run 2026-11-19, A3). Foundation only (tested).
//

import Foundation

enum ArisPermissionsNote {
    static let dialogOnly = "허용하기를 누르면 macOS가 묻는 창이 떠요. 거기서 허용을 누르면 돼요."
    static let settingsOnly = "허용하기를 누르면 시스템 설정이 열리고, Aris 아이콘을 목록으로 끌어다 놓으면 돼요."
    static let both = "허용하기를 누르면 macOS가 묻는 창이 뜨거나 시스템 설정이 열려요. 창에서는 허용을 누르고, 시스템 설정에서는 Aris를 켜거나 목록으로 끌어다 놓으면 돼요."

    /// The rows whose 허용하기 opens System Settings (the rest raise macOS's dialog).
    static let settingsRows: Set<String> = ["ax", "screen", "fda", "input"]

    /// The note for what is still missing; nil when nothing is.
    static func note(_ s: ArisSettingsSnapshot) -> String? {
        let missing = s.permissions.filter { !$0.granted }.map(\.id)
        let settings = missing.contains { settingsRows.contains($0) } || s.systemAudioMissing
            || s.reminders == .blocked || s.calendarAccess == .blocked
        let dialog = missing.contains { !settingsRows.contains($0) } || s.reminders == .undecided || s.calendarAccess == .undecided
        switch (dialog, settings) {
        case (true, true): return both
        case (true, false): return dialogOnly
        case (false, true): return settingsOnly
        case (false, false): return nil
        }
    }

    static let english: [String: String] = [
        dialogOnly: "Press Allow and macOS asks in its own window: press Allow there.",
        settingsOnly: "Press Allow and System Settings opens: drag the Aris icon into the list there.",
        both: "Press Allow and macOS asks in its own window, or System Settings opens: press Allow in the window, or turn Aris on (or drag it into the list) in System Settings.",
    ]
}
