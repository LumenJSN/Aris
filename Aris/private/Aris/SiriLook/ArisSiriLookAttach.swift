//
//  ArisSiriLookAttach.swift
//  Aris
//
//  What the siri look's round + does: it opens the system's file chooser, and what is chosen is given to Aris exactly
//  as files dropped on the notch are.
//

import AppKit

/// The field's +: choose files to give Aris, the same as dropping them on the notch.
@MainActor
enum ArisSiriLookAttach {
    static func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = ArisUIWords.text("Aris한테 주기", "Give to Aris")
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { answer in
            guard answer == .OK, !panel.urls.isEmpty else { return }
            ArisAttachments.shared.add(panel.urls)
        }
    }
}
