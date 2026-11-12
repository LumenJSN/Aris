//
//  ArisScreenRead.swift
//  aris-agent
//
//  What a look at the screen came to ("이거", "what's on my screen"), and what the AI is told about it. Two rules from
//  the VM run of 10–11 Nov 2026:
//  - Whether the screen could be read is what the capture gave back this turn, never an answer the agent kept from
//    when it started: macOS answers a running process the same way for as long as it runs, so after the user switched
//    aris-agent on, every reply still said Screen Recording wasn't allowed (bug 1).
//  - A look asks macOS for nothing. Without Accessibility it reads no other app's elements, and without Screen
//    Recording it tries no capture: each try made macOS put up its own window in the middle of the question, behind
//    the open notch (bug 2). What it had to do without is reported (`needs`), and said only when it mattered.
//  The row to switch on is "Aris": the helper sits inside the app, so macOS counts its captures as the app's (one row).
//  Pure, so the tests run its table.
//

import Foundation

enum ArisScreenRead {
    /// One run of `aris-tools screen`: how it ended, what it printed, what it complained of.
    struct Captured: Equatable {
        let status: Int32
        let output: String
        let errors: String
    }

    /// What reading the front window's text came to.
    enum Outcome: Equatable {
        /// The capture came back with the window's words.
        case text(String)
        /// Nothing came back, and macOS says aris-agent may not record the screen.
        case permissionOff
        /// Nothing came back for another reason (no window, macOS handed nothing over): the tool's own words, if any.
        case nothing(String?)
    }

    /// The row as System Settings shows it: the helper is inside the app, so there is one row, the app's.
    static let row = "Aris"
    /// The most of a tool's complaint that goes to the AI.
    static let reasonLimit = 200

    /// The Screen Recording list's name in System Settings › Privacy & Security on this macOS.
    static func listName(macOSMajor: Int) -> String {
        ArisFix.Pane.screen.title(english: true, osMajor: macOSMajor)
    }

    /// Whether aris-agent may record the screen now: true, false, or nil when macOS couldn't be asked.
    /// `known`: this process has already seen it on. Only "on" is ever taken from the process itself; anything else is
    /// asked anew of a new process (`fresh`), so a grant given while the agent runs counts at once.
    static func allowed(known: Bool, fresh: () -> Bool?) -> Bool? {
        known ? true : fresh()
    }

    /// `captured`: the run, or nil when none was tried or it couldn't run. `allowed`: what macOS says now (nil: unknown).
    /// Words that came back are the read, whatever `allowed` says.
    static func outcome(captured: Captured?, allowed: Bool?) -> Outcome {
        if let captured, captured.status == 0 {
            let text = captured.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return .text(text) }
        }
        if allowed == false { return .permissionOff }
        return .nothing(captured.flatMap { reason($0.errors) })
    }

    /// The last thing the tool complained of (its own line comes after screencapture's), cut to `reasonLimit`.
    private static func reason(_ errors: String) -> String? {
        let lines = errors.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.last.map { String($0.prefix(reasonLimit)) }
    }

    /// What the AI is told when the front window's words didn't come; nil when they did. For a turn that carries no
    /// picture of the screen only (ArisLookContext in the app leaves it out when its own screenshot goes along).
    static func unreadLine(_ outcome: Outcome, list: String) -> String? {
        switch outcome {
        case .text:
            return nil
        case .permissionOff:
            return permissionOffLead + " for \"\(row)\". "
                + "Don't guess what is on the screen. Tell the user what to do, in a sentence or two: open System Settings › Privacy & Security › \(list), "
                + "switch on the row named \"\(row)\" (if it isn't in the list, press + and choose Aris in Applications), "
                + "then ask again.)"
        case .nothing(let why):
            return "(The front window's words could not be read this time\(why.map { " (\($0))" } ?? ""). "
                + "Don't guess what is on the screen; if the request needs it, say in a few words that the window couldn't be read.)"
        }
    }

    /// What the AI is told when the request is to change what is selected and aris-agent has no Accessibility, so the
    /// selection was neither read nor can be replaced.
    static var unselectedLine: String {
        let list = ArisFix.Pane.accessibility.title(english: true)
        return "(The selected text could not be read or replaced: macOS has \(list) switched off for \"\(row)\". "
        + "Do what was asked from what you can see and give the new text in your answer, then tell the user in one sentence: "
        + "to have Aris change text in place, switch on \"\(row)\" in System Settings › Privacy & Security › \(list) "
        + "(if it isn't in the list, press + and choose Aris in Applications).)"
    }

    /// Which of aris-agent's own permissions a look had to do without ("accessibility", "screen"), for the app.
    /// How the line for a switched-off Screen Recording begins.
    static let permissionOffLead = "(The screen could not be read: macOS has Screen Recording switched off"

    /// Whether a question's screen context (what the app sends with it) carries that line: the AI is being told the
    /// screen couldn't be read for the permission.
    static func saysPermissionOff(_ screen: String?) -> Bool {
        screen?.components(separatedBy: "\n").contains { $0.hasPrefix(permissionOffLead) } == true
    }

    static func needs(accessibility: Bool, screen: Bool?) -> [String] {
        (accessibility ? [] : ["accessibility"]) + (screen == false ? ["screen"] : [])
    }
}
