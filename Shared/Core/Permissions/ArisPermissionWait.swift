//
//  ArisPermissionWait.swift
//  Aris (ArisCore)
//
//  A calendar or to-do request from a turn the user is in front of may raise macOS's own Calendars or Reminders
//  dialog the first time (ArisPermissionRoute). A person can take a minute to read it (VM run 2026-11-19, A2: the
//  answer came about 25 s later, past the route's old 15 s cut and aris-tools' 20 s wait; the brain then said "Aris
//  isn't running", the repeat showed a second card, and the event was added only on a third try). So every caller on
//  the way waits for that answer, the innermost shortest:
//   · the app's route waits `dialog` for the answer, then does the request under the grant it already had;
//   · the hook server keeps such a request open, and aris-tools waits for its answer, `request`;
//   · the helper lets that aris-tools run go on for `run`.
//  All of them stay inside a chat turn's silence limit (ArisTurnLimits.chat, 120 s) and Claude Code's two-minute Bash
//  limit. A request that can't raise the dialog keeps the old 20 s. Also here: what aris-tools makes of the app's
//  answer (a late one is never "Aris isn't running"), and the race the route runs against the dialog. Pure.
//

import Foundation

enum ArisPermissionWait {
    /// How long the app's route waits for the answer to macOS's dialog.
    static let dialog: TimeInterval = 90
    /// How long the hook server keeps an asking request open, and aris-tools waits for it.
    static let request: TimeInterval = dialog + 10
    /// The helper's limit on an aris-tools run that may wait on the dialog.
    static let run: TimeInterval = request + 5
    /// A request that never asks: as before.
    static let plain: TimeInterval = 20

    /// The routes that may raise the dialog (ArisEventRoute, the to-do route).
    static let askingPaths: Set<String> = ["/aris/events", "/aris/todos"]

    /// aris-tools' wait for one request: longer only when it lets the app ask (`ask` in its body).
    static func requestLimit(asks: Bool) -> TimeInterval { asks ? request : plain }

    /// Whether this request to the hook server lets the app ask: one of `askingPaths` with `"ask": true`.
    static func asks(path: String, body: Data) -> Bool {
        guard askingPaths.contains(path), let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return false }
        return object["ask"] as? Bool == true
    }

    /// The aris-tools commands whose run may wait on the dialog: the calendar's and the to-do list's (they ask the app).
    static let askingCommands: Set<String> = ["event", "remind", "todo", "calendars", "use-calendar"]

    /// The helper's limit for this aris-tools run when it may wait on the dialog; nil for every other command.
    static func runLimit(argv: [String]) -> TimeInterval? {
        guard let first = argv.first, askingCommands.contains(first) else { return nil }
        return run
    }

    // MARK: - Lines

    /// The route's answer when macOS's dialog was still up after `dialog`: nothing was done, and the app is running.
    static let stillAskingLine = "macOS is still asking for access in its own dialog, so nothing was done yet. " +
        "Tell the user to answer that dialog and then ask again. Never say Aris isn't running."

    /// aris-tools' line when the app answered too late (or the server gave up on the request): the app is running.
    static let lateLine = "The Aris app was still working on this when aris-tools stopped waiting, so it may or may not have happened. " +
        "Don't say it was done, and never say Aris isn't running."

    // MARK: - aris-tools' reading of the app's answer

    /// What aris-tools makes of the app's answer: the JSON of a 200; the late line (under `lineKey`, the route's key for
    /// its words) when the server gave up (504) or the wait ran out; nil when no app answered at all (it isn't running).
    static func reply(status: Int?, data: Data?, timedOut: Bool, lineKey: String) -> [String: Any]? {
        if status == 200, let data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { return object }
        if status == 504 || (status == nil && timedOut) { return ["ok": false, lineKey: lateLine] }
        return nil
    }

    // MARK: - The route's race against the dialog

    /// `work`'s value, or nil when `seconds` pass first. `work` is not stopped: a dialog answered later still counts
    /// in the permission layer, it is only too late for this request.
    static func first<T: Sendable>(within seconds: TimeInterval, _ work: @escaping @Sendable () async -> T) async -> T? {
        let once = Once<T?>()
        return await withCheckedContinuation { continuation in
            once.wait(continuation)
            Task { once.resume(await work()) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                once.resume(nil)
            }
        }
    }

    /// One continuation, resumed by whichever comes first.
    private final class Once<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?

        func wait(_ continuation: CheckedContinuation<T, Never>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func resume(_ value: T) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: value)
        }
    }
}

// MARK: - macOS's Automation dialog ("Aris wants to control Notes")

/// Tenth VM run, item 6: the first note raised macOS's Automation dialog; aris-tools stopped its script at 30 s and said
/// Notes hadn't answered, and the note was made when he pressed Allow a little later. A script whose app macOS is still
/// asking about is not stuck: it waits for him, inside the same one cap as the Calendars and Reminders dialogs
/// (`dialog`), and is then told as what it is. Nothing here sends anything twice: the one script goes on or is stopped.
extension ArisPermissionWait {
    /// The apps Aris's own scripts drive, by the name a script calls them (lowercased), with their bundle ids.
    static let scriptedApps: [String: String] = [
        "notes": "com.apple.Notes", "finder": "com.apple.finder", "system events": "com.apple.systemevents",
        "safari": "com.apple.Safari", "mail": "com.apple.mail", "music": "com.apple.Music", "spotify": "com.spotify.client",
        "calendar": "com.apple.iCal", "reminders": "com.apple.reminders", "contacts": "com.apple.AddressBook",
        "messages": "com.apple.MobileSMS", "terminal": "com.apple.Terminal", "iterm": "com.googlecode.iterm2",
        "iterm2": "com.googlecode.iterm2", "google chrome": "com.google.Chrome", "arc": "company.thebrowser.Browser",
        "brave browser": "com.brave.Browser", "microsoft edge": "com.microsoft.edgemac", "textedit": "com.apple.TextEdit",
        "preview": "com.apple.Preview", "system settings": "com.apple.systempreferences", "shortcuts": "com.apple.shortcuts",
    ]

    /// The aris-tools commands that drive an app by Apple Events, so their run may wait on macOS's Automation dialog.
    static let scriptingCommands: Set<String> = ["note", "music", "power"]

    /// The helper's limit for an aris-tools run that may wait on the Automation dialog; nil for every other command.
    static func scriptRunLimit(argv: [String]) -> TimeInterval? {
        guard let first = argv.first, scriptingCommands.contains(first) else { return nil }
        return run
    }

    /// Marks a target a script names that isn't on the list: the live side looks its bundle id up among the running apps.
    static let namePrefix = "name:"

    /// The apps a script sends events to, once each in the order they come: `application "Notes"` as its bundle id (or
    /// `name:` and the name when it isn't on the list), `application id "…"` as written. Only outside the script's own
    /// quoted text: an app named inside a note's body is not driven.
    static func scriptTargets(_ script: String) -> [String] {
        var found: [String] = []
        let characters = Array(script)
        var index = 0
        var outside = ""
        // The script's code with every string literal's contents taken out, each literal kept by its number.
        var literals: [String] = []
        while index < characters.count {
            if characters[index] == "\"" {
                var text = ""
                index += 1
                while index < characters.count, characters[index] != "\"" {
                    if characters[index] == "\\", index + 1 < characters.count { index += 1 }
                    text.append(characters[index])
                    index += 1
                }
                index += 1
                outside += "\"\(literals.count)\""
                literals.append(text)
            } else {
                outside.append(characters[index])
                index += 1
            }
        }
        guard let regex = try? NSRegularExpression(pattern: #"\bapplication\s+(id\s+)?"(\d+)""#, options: [.caseInsensitive]) else { return [] }
        for match in regex.matches(in: outside, range: NSRange(outside.startIndex..., in: outside)) {
            guard let number = Range(match.range(at: 2), in: outside).flatMap({ Int(outside[$0]) }), number < literals.count else { continue }
            let named = literals[number].trimmingCharacters(in: .whitespaces)
            guard !named.isEmpty else { continue }
            let target = match.range(at: 1).location != NSNotFound ? named : scriptedApps[named.lowercased()] ?? namePrefix + named
            if !found.contains(target) { found.append(target) }
        }
        return found
    }

    /// At a script's limit, with macOS's answer for each app it drives: how much longer it may wait, when macOS is
    /// still asking about one of them (never answered: its dialog is up); nil when nothing is asked (the app is slow
    /// or stuck, or the answer isn't known) or his time (`dialog`, counted from the script's start) is used up.
    static func automationExtension(states: [ArisPermissionState], waited: TimeInterval) -> TimeInterval? {
        guard states.contains(.notAsked), waited < dialog else { return nil }
        return dialog - waited
    }

    /// What is said of a script stopped at the end of its wait, by macOS's answer then; nil when macOS isn't the
    /// reason (the caller's own "didn't answer" line stands). Still asking: it isn't done, it may still happen if he
    /// allows it now, and it is never repeated. Refused meanwhile: said as refused. Read by the AI.
    static func automationTimeoutLine(app: String, states: [ArisPermissionState], waited: TimeInterval) -> String? {
        if states.contains(.notAsked) {
            return "macOS is still asking, in its own dialog, whether Aris may control \(app) (no answer in \(Int(waited)) seconds), so this isn't done yet. "
                + "If the user allows it now it may still go through: don't repeat it. Tell the user to answer that dialog, then to check \(app) or ask again."
        }
        if states.contains(.denied) {
            return "Aris isn't allowed to control \(app) (macOS's dialog was answered no), so nothing was done: "
                + "it can be turned on in System Settings > Privacy & Security > Automation"
        }
        return nil
    }
}
