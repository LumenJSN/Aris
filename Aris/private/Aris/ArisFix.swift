//
//  ArisFix.swift
//  Aris (also built into aris-agent and aris-tools)
//
//  The one thing the user can do about a failure, said as a kind and never as a sentence: open one list of System Settings,
//  open Aris's own Settings on one row, run an AI's own login in Terminal, ask again, ask another AI this once, or copy
//  a command. The notch puts it under the failure as a button (ArisFixButtons). Whoever knows why something failed
//  says which it is: aris-agent on its /ask stream, as a `{"fix": …}` line just before the turn's last line
//  (ArisFixTurns); aris-tools by leaving a note for the agent when a call fails (ArisFixDrop); the app for its own
//  lines (ArisAppFix). Nobody works it out from the Korean or English words of a reply. Foundation only (tested).
//

import Foundation

struct ArisFix: Equatable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        /// A list of System Settings › Privacy & Security (`target`: an ArisFix.Pane).
        case pane
        /// A row of Aris's own Settings window (`target`: an ArisFix.Row).
        case settings
        /// The AI's own login, in Terminal (`target`: the brain).
        case login
        /// The same request once more (something passing: a slow answer, a process that stopped).
        case retry
        /// The same request, answered by another AI this once (`target`: the AI that takes it).
        case otherBrain
        /// A command for Terminal goes to the clipboard (`target`: the command), when nothing else can be done.
        case copy
        /// Aris.app itself is shown in Finder, to be moved to the Applications folder (no target: only ever the app
        /// that shows the button).
        case showApp
        /// An AI's own program changed (another signer, another place) and was not started: the owner accepts the new
        /// one (`target`: the brain). Only the Aris app's own press reaches the helper (security review 4, H1).
        case acceptProgram
    }

    /// The lists of System Settings › Privacy & Security a failure can point at.
    enum Pane: String, Sendable, CaseIterable {
        case disk, screen, accessibility, automation, contacts, calendars, reminders, microphone, speech, folders

        /// The list's name in the settings deep link.
        var anchor: String {
            switch self {
            case .disk: "Privacy_AllFiles"
            case .screen: "Privacy_ScreenCapture"
            case .accessibility: "Privacy_Accessibility"
            case .automation: "Privacy_Automation"
            case .contacts: "Privacy_Contacts"
            case .calendars: "Privacy_Calendars"
            case .reminders: "Privacy_Reminders"
            case .microphone: "Privacy_Microphone"
            case .speech: "Privacy_SpeechRecognition"
            case .folders: "Privacy_FilesAndFolders"
            }
        }

        var link: String { ArisFix.paneLink + anchor }

        /// This Mac's macOS. The tests set `osMajorForTests` so that what they pin does not change with the Mac they
        /// run on.
        static var osMajor: Int { osMajorForTests ?? ProcessInfo.processInfo.operatingSystemVersion.majorVersion }
        nonisolated(unsafe) static var osMajorForTests: Int?

        /// The list's name as System Settings › Privacy & Security shows it on that macOS, in English or Korean:
        /// the one place Aris takes a list's name from, so every card, button and sentence says what the user sees.
        ///  · macOS 27 renamed Accessibility: its list and its prompt read "Device Control and Data Access"
        ///    ("기기 제어 및 데이터 접근"). It is still the same permission and the same link.
        ///  · From macOS 15 the Screen Recording list is "Screen & System Audio Recording" ("화면 및 시스템 오디오 녹음").
        /// The names are macOS's own (read from its Privacy settings' strings on 27.2).
        func title(english: Bool, osMajor: Int = Pane.osMajor) -> String {
            switch self {
            case .accessibility:
                if osMajor >= 27 { return english ? "Device Control and Data Access" : "기기 제어 및 데이터 접근" }
                return english ? "Accessibility" : "손쉬운 사용"
            case .screen:
                if osMajor >= 15 { return english ? "Screen & System Audio Recording" : "화면 및 시스템 오디오 녹음" }
                return english ? "Screen Recording" : "화면 기록"
            case .disk: return english ? "Full Disk Access" : "전체 디스크 접근 권한"
            case .automation: return english ? "Automation" : "자동화"
            case .contacts: return english ? "Contacts" : "연락처"
            case .calendars: return english ? "Calendars" : "캘린더"
            case .reminders: return english ? "Reminders" : "미리 알림"
            case .microphone: return english ? "Microphone" : "마이크"
            case .speech: return english ? "Speech Recognition" : "음성 인식"
            case .folders: return english ? "Files & Folders" : "파일 및 폴더"
            }
        }

        /// What Aris calls the permission itself in a sentence ("Allow …", "… is on."): the list's name where macOS
        /// uses one name for both (Accessibility, on every macOS), and the short "Screen Recording" for the screen,
        /// which macOS's own prompt still calls recording the screen.
        func permission(english: Bool, osMajor: Int = Pane.osMajor) -> String {
            self == .screen ? (english ? "Screen Recording" : "화면 기록") : title(english: english, osMajor: osMajor)
        }

        /// A sentence written with the name from before macOS 27 ("Accessibility", "손쉬운 사용"), said with this
        /// macOS's name: for the setup's translated lines, which carry the name inside them.
        func renamed(in text: String, english: Bool, osMajor: Int = Pane.osMajor) -> String {
            let before = permission(english: english, osMajor: 26), now = permission(english: english, osMajor: osMajor)
            return before == now ? text : text.replacingOccurrences(of: before, with: now)
        }
    }

    /// The rows of Aris's Settings a failure can point at: the page and the row it lands on (ArisSettingsNav.go).
    enum Row: String, Sendable, CaseIterable {
        case brain, key, services, todoAccess, calendarAccess, skills, team, helper, control, memory

        var page: String {
            switch self {
            case .brain, .key, .services: "ai"
            case .todoAccess: "todo"
            case .calendarAccess: "todo"
            case .skills: "skills"
            case .team: "team"
            case .helper: "general"
            case .control: "control"
            case .memory: "memory"
            }
        }

        var anchor: String {
            switch self {
            case .brain: "ai.brain"
            case .key: "ai.brain"
            case .services: "ai.services"
            case .todoAccess: "todo.access"
            case .calendarAccess: "calendar.access"
            case .skills: "skills.feature"
            case .team: "team.detail"
            case .helper: "general.restart"
            case .control: "control.ax"
            case .memory: "memory.clear"
            }
        }
    }

    static let paneLink = "x-apple.systempreferences:com.apple.preference.security?"
    /// The AIs a login or a hand-over can name (ArisBrain's raw values; the tests hold them equal).
    static let brains: Set<String> = ["claude", "codex", "antigravity", "api"]
    /// The longest command a `copy` carries, and what it may be made of: a program's name and plain arguments.
    static let longestCommand = 80
    private static let commandCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._/-")

    let kind: Kind
    let target: String
    /// A second, quiet "try again" beside the button: only where asking again pairs with the fix (a limit that
    /// passes, a helper that is restarting).
    var again = false

    static func pane(_ pane: Pane) -> ArisFix { ArisFix(kind: .pane, target: pane.rawValue) }
    static func settings(_ row: Row, again: Bool = false) -> ArisFix { ArisFix(kind: .settings, target: row.rawValue, again: again) }
    static func login(_ brain: String) -> ArisFix { ArisFix(kind: .login, target: brain) }
    static let retry = ArisFix(kind: .retry, target: "")
    static func otherBrain(_ brain: String) -> ArisFix { ArisFix(kind: .otherBrain, target: brain, again: false) }
    static func copy(_ command: String) -> ArisFix { ArisFix(kind: .copy, target: command) }
    static let showApp = ArisFix(kind: .showApp, target: "")
    static func acceptProgram(_ brain: String) -> ArisFix { ArisFix(kind: .acceptProgram, target: brain, again: true) }

    var pane: Pane? { kind == .pane ? Pane(rawValue: target) : nil }
    var row: Row? { kind == .settings ? Row(rawValue: target) : nil }

    /// Whether the fix names something that exists: a known list, row or AI, a command of plain characters. Anything
    /// else is dropped where it is read, so a button never opens or copies what nobody meant.
    var isValid: Bool {
        switch kind {
        case .pane: return pane != nil
        case .settings: return row != nil
        case .login, .acceptProgram: return Self.brains.contains(target) && target != "api"
        case .otherBrain: return Self.brains.contains(target)
        case .retry, .showApp: return target.isEmpty
        case .copy:
            return !target.isEmpty && target.count <= Self.longestCommand && !target.hasPrefix("-")
                && target.unicodeScalars.allSatisfy(Self.commandCharacters.contains)
        }
    }

    /// osascript's complaint when macOS didn't let Aris control an app (error -1743): Automation's list. Read from the
    /// error's number or macOS's own "not authorized", the way ArisActions.appleScriptProblem tells it apart; nil for
    /// every other complaint (an app that isn't running, nothing open).
    static func appleScript(_ complaint: String) -> ArisFix? {
        complaint.contains("-1743") || complaint.localizedCaseInsensitiveContains("not authorized") ? .pane(.automation) : nil
    }

    // MARK: - On the wire

    var json: [String: Any] { again ? ["kind": kind.rawValue, "target": target, "again": true] : ["kind": kind.rawValue, "target": target] }

    static func parse(_ value: Any?) -> ArisFix? {
        guard let object = value as? [String: Any], let kind = (object["kind"] as? String).flatMap(Kind.init(rawValue:)),
              let target = object["target"] as? String else { return nil }
        let fix = ArisFix(kind: kind, target: target, again: object["again"] as? Bool == true)
        return fix.isValid ? fix : nil
    }

    /// The stream's line for it, newline included: sent just before the turn's last line.
    var line: Data {
        ((try? JSONSerialization.data(withJSONObject: ["fix": json], options: [.sortedKeys])) ?? Data()) + Data("\n".utf8)
    }

    /// The fix a stream line carries; nil for every other line.
    static func parse(line: String) -> ArisFix? {
        guard line.contains("\"fix\""), let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(object["fix"])
    }
}

/// How aris-tools tells aris-agent that a call failed for something the user can fix: one line in a small file both can
/// reach, written when the call fails (`fail(_:fix:)`). The brain reads the tool's sentence and says it its own way;
/// the agent reads this note when the turn ends, so the button is right even when the brain's wording is not. Only a
/// list of System Settings or a row of Aris's Settings travels this way (never a command or a login), and a background
/// job's notes are marked as such, so they never land under a conversation's answer.
enum ArisFixDrop {
    static let name = "fix-drop.jsonl"
    /// Notes older than this are dropped at the next write.
    static let kept: TimeInterval = 600

    struct Entry: Equatable {
        let at: Date
        let fix: ArisFix
        /// Written by a background job's process (ARIS_TASK).
        let task: Bool
    }

    static func file(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/aris/aris/" + name)
    }

    static func line(_ entry: Entry) -> String {
        var object: [String: Any] = ["at": entry.at.timeIntervalSince1970, "fix": entry.fix.json]
        if entry.task { object["task"] = true }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// One note; nil for a line that isn't one, or whose fix is not a list or a row.
    static func entry(_ line: String) -> Entry? {
        guard let data = line.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = (object["at"] as? NSNumber)?.doubleValue, let fix = ArisFix.parse(object["fix"]),
              fix.kind == .pane || fix.kind == .settings else { return nil }
        return Entry(at: Date(timeIntervalSince1970: at), fix: fix, task: object["task"] as? Bool == true)
    }

    static func read(_ file: URL) -> [Entry] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { entry(String($0)) }
    }

    /// Adds a note and drops the old ones. A file that can't be written loses the button, never the failure's words.
    static func append(_ fix: ArisFix, task: Bool, to file: URL, now: Date = Date()) {
        guard fix.isValid, fix.kind == .pane || fix.kind == .settings else { return }
        let recent = read(file).filter { now.timeIntervalSince($0.at) < kept && $0.at <= now }
        let text = (recent + [Entry(at: now, fix: fix, task: task)]).map(line).joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? Data(text.utf8).write(to: file, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// The fix a conversation turn earned: the latest note written while it ran, never a background job's.
    static func pick(_ entries: [Entry], since: Date, until: Date) -> ArisFix? {
        entries.filter { !$0.task && $0.at >= since && $0.at <= until }.max { $0.at < $1.at }?.fix
    }
}
