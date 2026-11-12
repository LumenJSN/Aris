//
//  ArisActions.swift
//  aris-tools
//
//  The AppleScript behind aris-tools' Mac actions (music, volume, reminders, calendar
//  events, notes), built from checked arguments with every string escaped. These are
//  the only actions any of Aris's AIs can take on the Mac: none of them may run
//  osascript or open themselves, so a page that talks one into "running something"
//  has nothing to run.
//

import Foundation

enum ArisActions {
    /// Apps keys and text are never typed into: a terminal would run them, a vault would take them.
    static let untypableBundleIDs: Set<String> = [
        "com.apple.terminal", "com.googlecode.iterm2", "dev.warp.warp-stable", "dev.warp.warp", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
        "com.apple.keychainaccess", "com.apple.passwords", "com.1password.1password", "com.agilebits.onepassword7",
    ]

    /// Whether typing into the app with this bundle id is allowed (never for an unknown app).
    static func isTypingSafe(bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased(), !id.isEmpty else { return false }
        return !untypableBundleIDs.contains(id)
    }

    /// `--app` names exactly this app (its shown name or bundle file name, any case), not just part of it.
    static func namesMatch(_ name: String, localizedName: String?, fileName: String?) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return false }
        return [localizedName, fileName].contains { $0?.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    enum Music: String, CaseIterable {
        case play, pause, next, previous

        var verb: String {
            switch self {
            case .play: return "play"
            case .pause: return "pause"
            case .next: return "next track"
            case .previous: return "previous track"
            }
        }
    }

    /// An AppleScript string literal.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func musicScript(_ action: Music, app: String) -> String {
        "tell application \(quoted(app)) to \(action.verb)"
    }

    /// The app named ("spotify", "music"), else the one running, else Spotify when it is installed, else Apple Music
    /// (audit tools-7: on a Mac without Spotify the default was still Spotify, and asking a missing app hangs).
    static func musicApp(requested: String?, running bundleIDs: [String], spotifyInstalled: Bool = true) -> String {
        switch requested?.lowercased() {
        case "music", "apple music": return "Music"
        case "spotify": return "Spotify"
        default:
            if bundleIDs.contains("com.spotify.client") { return "Spotify" }
            return bundleIDs.contains("com.apple.Music") || !spotifyInstalled ? "Music" : "Spotify"
        }
    }

    /// Why the music app can't be asked at all: Spotify named on a Mac that doesn't have it. Nil when it can.
    static func musicProblem(app: String, spotifyInstalled: Bool) -> String? {
        app == "Spotify" && !spotifyInstalled ? "Spotify isn't installed on this Mac, so nothing was played or changed. Apple Music is: `music play music`." : nil
    }

    /// "40", "up", "down", "mute" or "unmute"; nil for anything else.
    static func volumeScript(_ argument: String) -> String? {
        let current = "(output volume of (get volume settings))"
        switch argument {
        case "up": return "set volume output volume (\(current) + 10)"
        case "down": return "set volume output volume (\(current) - 10)"
        case "mute": return "set volume with output muted"
        case "unmute": return "set volume without output muted"
        default:
            guard let level = Int(argument), (0...100).contains(level) else { return nil }
            return "set volume output volume \(level)"
        }
    }

    /// The output's level (0–100) and mute from AppleScript's `get volume settings` ("output volume:50, input volume:73,
    /// alert volume:100, output muted:false"). An HDMI or DisplayPort output has neither ("missing value").
    static func volumeSettings(_ printed: String) -> (level: Int?, muted: Bool?) {
        var fields: [String: String] = [:]
        for part in printed.split(separator: ",") {
            let pair = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if pair.count == 2 { fields[pair[0]] = pair[1] }
        }
        return (fields["output volume"].flatMap { Int($0) }, fields["output muted"].flatMap { Bool($0) })
    }

    /// Why this volume command can change nothing on the output in use, for the caller to say instead of "done"; nil
    /// when it can.
    static func volumeRefusal(_ argument: String, _ settings: (level: Int?, muted: Bool?)) -> String? {
        if ["mute", "unmute"].contains(argument) {
            return settings.muted == nil ? "this sound output has no mute the Mac can set, so nothing was changed" : nil
        }
        return settings.level == nil
            ? "the Mac can't set this sound output's volume (an HDMI or DisplayPort display sets its own), so nothing was changed" : nil
    }

    /// "2026-10-25 09:30", or a date alone (9 am). Nil for a day that isn't in the calendar (11월 31일, 2월 30일: audit
    /// tools-10, they rolled into the next month and the event was made there).
    static func moment(_ text: String) -> DateComponents? {
        let parts = text.split(separator: " ").map(String.init)
        let date = parts.first?.split(separator: "-").compactMap { Int($0) } ?? []
        let time = parts.count > 1 ? parts[1].split(separator: ":").compactMap { Int($0) } : [9, 0]
        guard parts.count <= 2, date.count == 3, time.count == 2, (1...12).contains(date[1]), (1...daysInMonth(date[1], year: date[0])).contains(date[2]),
              (0...23).contains(time[0]), (0...59).contains(time[1]) else { return nil }
        return DateComponents(year: date[0], month: date[1], day: date[2], hour: time[0], minute: time[1])
    }

    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    /// "2026-11-30 10:00": a moment as it was asked for.
    static func stamp(_ moment: DateComponents) -> String {
        String(format: "%04d-%02d-%02d %02d:%02d", moment.year ?? 0, moment.month ?? 0, moment.day ?? 0, moment.hour ?? 0, moment.minute ?? 0)
    }

    static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Why `text` isn't a moment when it is written as one but names a day its month doesn't have; nil for a real day
    /// and for text that isn't a date at all (the usage line answers that).
    static func noSuchDay(_ text: String) -> String? {
        let date = text.split(separator: " ").first?.split(separator: "-").compactMap { Int($0) } ?? []
        guard date.count == 3, (1...12).contains(date[1]), (1...31).contains(date[2]) else { return nil }
        let days = daysInMonth(date[1], year: date[0])
        guard date[2] > days else { return nil }
        let month = monthNames[date[1] - 1]
        return "There is no \(String(format: "%04d-%02d-%02d", date[0], date[1], date[2])): \(month) \(date[0]) has \(days) days. Nothing was added. Ask the user which day they mean."
    }

    // MARK: - An event's length

    /// The longest event `event` adds: 31 days.
    static let longestEvent = 31 * 24 * 60

    enum EventLength: Equatable {
        case minutes(Int)
        case invalid(String)
    }

    /// `--minutes`: an hour when not given; a whole number of minutes from 5 to 31 days. Anything else is refused with
    /// the reason, never changed (audit tools-4: 4320 was cut to 1440 and "90m" became 60, and the answer didn't say).
    static func eventLength(_ option: String?) -> EventLength {
        guard let option else { return .minutes(60) }
        guard let minutes = Int(option.trimmingCharacters(in: .whitespaces)), (5...longestEvent).contains(minutes) else {
            return .invalid("--minutes takes a whole number of minutes from 5 to \(longestEvent) (31 days), not \"\(option)\". Nothing was added.")
        }
        return .minutes(minutes)
    }

    /// "2026-11-20 15:00–16:30", the end with its day when that is another day: what an added event's line shows.
    static func span(start: DateComponents, minutes: Int, calendar: Calendar = .current) -> String {
        let stamp = { (date: Date, pattern: String) -> String in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = pattern
            return formatter.string(from: date)
        }
        guard let begin = calendar.date(from: start) else { return "" }
        let end = begin.addingTimeInterval(TimeInterval(minutes * 60))
        return stamp(begin, "yyyy-MM-dd HH:mm") + "–" + stamp(end, calendar.isDate(begin, inSameDayAs: end) ? "HH:mm" : "yyyy-MM-dd HH:mm")
    }

    /// Sets AppleScript variable `d` to `moment` (field by field, so the user's date format doesn't matter).
    private static func dateLines(_ moment: DateComponents) -> String {
        """
        set d to current date
        set day of d to 1
        set year of d to \(moment.year ?? 2000)
        set month of d to \(moment.month ?? 1)
        set day of d to \(moment.day ?? 1)
        set hours of d to \(moment.hour ?? 9)
        set minutes of d to \(moment.minute ?? 0)
        set seconds of d to 0
        """
    }

    static func reminderScript(text: String, due: DateComponents?) -> String {
        guard let due else {
            return "tell application \"Reminders\" to make new reminder with properties {name:\(quoted(text))}"
        }
        return dateLines(due) + "\ntell application \"Reminders\" to make new reminder with properties {name:\(quoted(text)), remind me date:d}"
    }

    static func eventScript(title: String, start: DateComponents, minutes: Int, calendar: String?) -> String {
        let target = calendar.map { "calendar \(quoted($0))" } ?? "(first calendar whose writable is true)"
        // Gives back the new event's id (Calendar's uid), which the activity log keeps to undo it, and the calendar it is
        // in (QA BUG-16: said "추가했어요" while nothing was where the user looked).
        return dateLines(start) + """

            set e to d + (\(minutes) * 60)
            tell application "Calendar" to tell \(target)
            set made to make new event with properties {summary:\(quoted(title)), start date:d, end date:e}
            return (uid of made) & tab & (name of it)
            end tell
            """
    }

    /// The made event's id and calendar from eventScript's answer; nil when it gave no usable id.
    static func eventMade(_ printed: String) -> (uid: String, calendar: String)? {
        let parts = printed.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        guard let uid = parts.first, isEventID(uid) else { return nil }
        return (uid, parts.dropFirst().joined(separator: "\t"))
    }

    /// How many events with this title start at this moment in the calendar (any writable one when none is named): a
    /// retry finds the one an earlier try already made, and adds no second (security review).
    static func existingEventScript(title: String, start: DateComponents, calendar: String?) -> String {
        let target = calendar.map { "calendar \(quoted($0))" } ?? "(first calendar whose writable is true)"
        return dateLines(start) + """

            tell application "Calendar" to tell \(target) to count (every event whose summary is \(quoted(title)) and start date is d)
            """
    }

    static func eventAlreadyLine(title: String) -> String {
        "event already there: “\(title)” at that time, so it wasn't added again. Tell the user it's already in the calendar."
    }

    /// Made, but not found by its id right after: maybe there. Never "not added", so a retry doesn't make it twice.
    static let eventMaybeLead = "MAY HAVE BEEN ADDED: don't add it again and don't say it was added."

    static func eventMaybeLine(title: String, uid: String?, calendar: String?) -> String {
        let id = uid.map { " (id \($0)\(calendar.map { ", calendar “\($0)”" } ?? ""))" } ?? ""
        return "\(eventMaybeLead) “\(title)”\(id) couldn't be confirmed after adding it. Tell the user it may have been added and to check the calendar."
    }

    /// What `aris-tools event` prints when the event is there: when it starts and ends, its id and its calendar, so the
    /// brain names where and when it went.
    static func eventAddedLine(title: String, uid: String, calendar: String, start: DateComponents? = nil, minutes: Int? = nil) -> String {
        let when = start.flatMap { start in minutes.map { " " + span(start: start, minutes: $0) } } ?? ""
        return "event added: “\(title)”\(when) in the calendar “\(calendar)” (Calendar saved it, id \(uid)). Tell the user which calendar it went into."
    }



    /// An event id Calendar gives (letters, digits and a few separators), nothing that could end a string literal.
    static func isEventID(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z0-9._:@\-]{1,200}$"#, options: .regularExpression) != nil
    }

    /// Deletes the event with that uid from whichever calendar holds it; nil when the id isn't a plain one.
    /// What `aris-tools calendar` opens: Apple's Calendar, whose calendars hold the Google accounts added in macOS (the user
    /// left Notion Calendar, 2026-11-02: QA BUG-16).
    static let calendarApp = "Calendar"

    static func deleteEventScript(uid: String) -> String? {
        guard isEventID(uid) else { return nil }
        return """
            tell application "Calendar"
            repeat with c in calendars
            set found to (every event of c whose uid is \(quoted(uid)))
            if (count of found) > 0 then
            delete item 1 of found
            return "deleted"
            end if
            end repeat
            error "no such event"
            end tell
            """
    }

    /// What `note` was asked for: a plain note's lines (only real line breaks split them), a titled checklist (one
    /// argument per item), the answer shape as markdown (ArisNoteMarkdown), or a usage error (nothing to write;
    /// --checklist with no title or no items).
    enum NoteRequest: Equatable {
        case plain(lines: [String])
        case checklist(title: String, items: [String])
        case markdown(String)
        case invalid
    }

    static func noteRequest(_ arguments: [String]) -> NoteRequest {
        if arguments.first == "--markdown" {
            let markdown = arguments.dropFirst().joined(separator: " ")
            return markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .invalid : .markdown(markdown)
        }
        if let flag = arguments.firstIndex(of: "--checklist") {
            let title = arguments[..<flag].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let items = arguments[(flag + 1)...].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return title.isEmpty || items.isEmpty ? .invalid : .checklist(title: title, items: items)
        }
        let lines = arguments.joined(separator: " ").components(separatedBy: .newlines)
        return lines.first.map { $0.trimmingCharacters(in: .whitespaces).isEmpty } ?? true ? .invalid : .plain(lines: lines)
    }

    /// The note's HTML: the title as its first line (Notes' title), then each line on its own.
    static func noteBody(title: String, lines: [String]) -> String {
        let escaped = { (text: String) in
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        return "<div><h1>\(escaped(title))</h1></div>" + lines.map { "<div>\(escaped($0))</div>" }.joined()
    }

    /// Makes the note and returns its id. Only `show` opens it in front (for the checklist keys): a plain note,
    /// from a turn or a scheduled job, never takes the screen or the keyboard.
    static func noteScript(body: String, show: Bool) -> String {
        """
        tell application "Notes"
        set made to make new note with properties {body:\(quoted(body))}
        \(show ? "show made\nactivate\n" : "")return id of made
        end tell
        """
    }

    /// The most items the checklist keys are pressed for (longer lists stay plain lines).
    static let checklistLimit = 30

    /// The keys that make the last `items` paragraphs a checklist: to the end of the note, select back to the start of
    /// the first item one paragraph at a time (⌥⇧↑), then Format › Checklist (⇧⌘L, the same in every language). Nil
    /// for no items or more than checklistLimit.
    static func checklistKeys(items: Int) -> [String]? {
        guard (1...checklistLimit).contains(items) else { return nil }
        return ["cmd+down"] + Array(repeating: "opt+shift+up", count: items) + ["cmd+shift+l"]
    }

    /// Whether a note's HTML body shows a checklist.
    static func isChecklist(_ body: String) -> Bool {
        body.range(of: "checklist", options: .caseInsensitive) != nil || body.range(of: "type=\"checkbox\"", options: .caseInsensitive) != nil
    }

    /// A phone number or email Messages can send to as it is; anything else is a name to look up.
    static func isHandle(_ text: String) -> Bool {
        text.contains("@") || text.range(of: #"^\+?[0-9][0-9 \-()]{6,}$"#, options: .regularExpression) != nil
    }

    /// Sends on the account of `service`: iMessage, or a text (SMS, RCS) for a number that isn't on iMessage.
    static func messageScript(to handle: String, text: String, service: ArisMessageSend.Service = .iMessage) -> String {
        """
        tell application "Messages"
        set target to participant \(quoted(handle)) of (1st account whose service type = \(service.rawValue))
        send \(quoted(text)) to target
        end tell
        """
    }

    /// Every number and address of the one contact whose name or nickname is exactly `name`, one "label<tab>value"
    /// line each (ArisMessageSend picks among them: the first number may be a home phone); nothing when no contact
    /// or more than one has it (then the message is refused and the user is asked who): "엄마" must never reach 시엄마 or
    /// 엄마친구.
    static func contactScript(_ name: String) -> String {
        """
        tell application "Contacts"
        set found to (every person whose name is \(quoted(name)) or nickname is \(quoted(name)))
        if (count of found) is not 1 then return ""
        set match to item 1 of found
        set listed to ""
        repeat with entry in phones of match
        set tag to ""
        try
        set tag to (label of entry) as text
        end try
        set listed to listed & tag & tab & (value of entry) & linefeed
        end repeat
        repeat with entry in emails of match
        set listed to listed & "email" & tab & (value of entry) & linefeed
        end repeat
        return listed
        end tell
        """
    }

    /// Chromium browsers name it "active tab … title"; Safari "current tab … name".
    private static let chromium: Set<String> = [
        "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
    ]

    /// The front tab's address and title in a browser; nil for an app that isn't one.
    static func tabScript(bundleID: String) -> String? {
        if bundleID == "com.apple.Safari" {
            return "tell application id \(quoted(bundleID)) to get {URL, name} of current tab of front window"
        }
        guard chromium.contains(bundleID) else { return nil }
        return "tell application id \(quoted(bundleID)) to get {URL, title} of active tab of front window"
    }

    static let finderSelectionScript = """
        tell application "Finder"
        set picked to selection as alias list
        set paths to ""
        repeat with item_ in picked
        set paths to paths & POSIX path of item_ & linefeed
        end repeat
        return paths
        end tell
        """

    /// Screen text without blank lines or runs of spaces, cut at `limit` characters.
    static func trimmedScreenText(_ text: String, limit: Int) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        return joined.count > limit ? String(joined.prefix(limit)) + "…" : joined
    }

    static func isWebLink(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "https" || scheme == "http") && url.host != nil
    }

    /// osascript's complaint, as a sentence the AI can pass on. `missing`: what "can't get that" (-1728, -1719) means
    /// for this script (no account signed in to Messages, an app that isn't installed); a browser's tab script, which
    /// names none, keeps "nothing open there".
    static func appleScriptProblem(_ complaint: String, app: String, missing: String? = nil) -> String {
        let text = complaint.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("-1743") || text.localizedCaseInsensitiveContains("not authorized") {
            return "Aris isn't allowed to control \(app): turn it on in System Settings > Privacy & Security > Automation"
        }
        if text.contains("-600") || text.localizedCaseInsensitiveContains("isn’t running") || text.localizedCaseInsensitiveContains("isn't running") {
            return "\(app) isn't running"
        }
        if text.contains("-1728") || text.contains("-1719") { return missing ?? "\(app) has nothing open there (no window or tab)" }
        let plain = text
            .replacingOccurrences(of: #"^\d+:\d+:\s*(execution error:\s*)?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(-?\d+\)\s*$"#, with: "", options: .regularExpression)
        return plain.isEmpty ? "\(app) didn't answer" : "\(app): \(plain)"
    }
}
