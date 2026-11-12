//
//  ArisHistory.swift
//  Aris
//
//  What the Aris tab lists: past turns and background tasks, newest first, kept across
//  launches. Tapping one picks the conversation up again (or opens the file a task saved).
//

import Foundation
import os

struct ArisHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let date: Date
    /// What you said (a task's title).
    let heard: String
    let reply: String
    /// The file a long task result was saved in.
    var file: String?
    var isTask = false
    /// The conversation had seen the screen (the agent said so): a resume tells the agent, so it stays sealed.
    var sawScreen: Bool? = nil
    /// The conversation had taken in outside text (the agent said so): a resume tells the agent, so it never dispatches.
    var sawOutside: Bool? = nil
    /// The background job this hand-out turn started ("해 놔"): its result updates this entry (ArisHistory.finishing).
    var job: UUID? = nil
    /// The card the answer showed, with the values it had, as ArisHistoryRestore writes and reads it (JSON of an
    /// ArisHistoryCard; kept as bytes so this file stands alone): saved once the values arrive, so the turn can be
    /// shown again as it was. Nil on rows from before this was kept, and on answers with no card.
    var card: Data? = nil
}

enum ArisHistory {
    static let most = 50

    /// A background job's (or the inbox's) result as a history entry: what was shown, no code or data block, and
    /// marked as outside text, so a resume of that conversation never dispatches (the job ran untrusted).
    static func jobEntry(title: String, shown: String, file: String?, date: Date = Date()) -> ArisHistoryEntry {
        ArisHistoryEntry(date: date, heard: title, reply: shown, file: file, isTask: true, sawOutside: true)
    }

    /// A job's result in the 기록 tab: the hand-out turn that started it (`job`) becomes its entry, in place, with
    /// The user's words kept, so the request is listed once; with no such entry (deleted, or none recorded), a new one.
    static func finishing(job: UUID, title: String, shown: String, file: String?, in list: [ArisHistoryEntry],
                          date: Date = Date()) -> [ArisHistoryEntry] {
        guard list.contains(where: { $0.job == job }) else { return adding(jobEntry(title: title, shown: shown, file: file, date: date), to: list) }
        return list.map { entry in
            guard entry.job == job else { return entry }
            let result = jobEntry(title: entry.heard, shown: shown, file: file, date: entry.date)
            return ArisHistoryEntry(id: entry.id, date: entry.date, heard: entry.heard, reply: result.reply, file: result.file, isTask: result.isTask,
                                    sawScreen: entry.sawScreen, sawOutside: result.sawOutside, job: job)
        }
    }

    static func adding(_ entry: ArisHistoryEntry, to list: [ArisHistoryEntry]) -> [ArisHistoryEntry] {
        guard !entry.heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return list }
        return Array(([entry] + list).prefix(most))
    }

    /// The list without the entries `remove` picks (one deleted from the 기록 tab).
    static func removing(_ list: [ArisHistoryEntry], where remove: (ArisHistoryEntry) -> Bool) -> [ArisHistoryEntry] {
        list.filter { !remove($0) }
    }

    /// "방금", "5분 전", "3시간 전", "어제", "10월 20일".
    static func when(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return ArisUIWords.text("방금", "Just now", english: english) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.isDate(date, inSameDayAs: now)
        if english, seconds < 3600 || today { return ArisUIDates.relative(seconds: -seconds, locale: locale) }
        if seconds < 3600 { return "\(Int(seconds / 60))분 전" }
        if today { return "\(Int(seconds / 3600))시간 전" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return ArisUIWords.text("어제", "Yesterday", english: english) }
        if english { return ArisUIDates.day(date, english: true, calendar: calendar, locale: locale) }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일"
    }

    /// A new group starts in the side notch's history after an hour with no turns.
    static let sessionGap: TimeInterval = 3_600

    /// Turns (newest first) in groups split wherever an hour or more passed; each group starts at its newest turn.
    static func sessions(_ entries: [ArisHistoryEntry]) -> [(start: Date, entries: [ArisHistoryEntry])] {
        var groups: [(start: Date, entries: [ArisHistoryEntry])] = []
        var previous: Date?
        for entry in entries {
            if let previous, previous.timeIntervalSince(entry.date) <= sessionGap, !groups.isEmpty {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append((entry.date, [entry]))
            }
            previous = entry.date
        }
        return groups
    }

    /// A group's heading: "오늘 오후 3:42", "어제 오후 3:42", "10월 20일 (화) 오후 3:42".
    static func sessionHeader(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if english {
            // "Today, 3:42 PM", "Yesterday, 3:42 PM", "Tue, Oct 20 at 3:42 PM": the locale orders the date and picks the clock.
            let time = ArisUIDates.time(date, english: true, calendar: calendar, locale: locale)
            if calendar.isDate(date, inSameDayAs: now) || date > now { return "Today, \(time)" }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday, \(time)" }
            return ArisUIDates.string(date, korean: "", template: "MMMdEjmm", english: true, calendar: calendar, locale: locale)
        }
        func format(_ pattern: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            return formatter.string(from: date)
        }
        let time = format("a h:mm")
        if calendar.isDate(date, inSameDayAs: now) || date > now { return "오늘 \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "어제 \(time)" }
        return "\(format("M월 d일 (E)")) \(time)"
    }

    /// The saved list, in the app's own Application Support.
    static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Aris/history.json")
    }

    /// A file that can't be read is kept aside, never overwritten by the next save (ArisJSONFile).
    static func load() -> [ArisHistoryEntry] {
        guard let file else { return [] }
        return ArisJSONFile.load([ArisHistoryEntry].self, from: file, what: "history")
    }

    static func save(_ list: [ArisHistoryEntry]) {
        guard let file else { return }
        do {
            let data = try JSONEncoder().encode(list)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            Logger(subsystem: "com.lumenjsn.aris", category: "files").error("history: couldn't save: \(error.localizedDescription, privacy: .public)")
        }
    }
}
