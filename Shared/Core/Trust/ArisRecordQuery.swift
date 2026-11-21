//
//  ArisRecordQuery.swift
//  Shared/Core (app, aris-agent, tests)
//
//  Reading the record back (ARCHITECTURE Part 3, F5): `record.query` by time, kind, app, task and capability, and the
//  day's digest the day-end recap is made from. A row is a call as the owner would name it (its capability, its verb,
//  where it went), never its body or its result text, and the capability marks what it returns as content Aris read
//  (ArisToolResult.Content "aris"/"record"): a recipient or a path in a line may have come from a page or a mail, so it
//  informs an answer and is never the reason for an outward or permanent call. The digest is counts only. Pure.
//

import Foundation

/// What kind of thing a call did, for the recap's "파일 넷, 일정 둘".
enum ArisRecordFamily: String, CaseIterable, Codable, Sendable {
    case files, calendar, todos, notes, sent, apps, controls, sessions, other

    /// By the capability's id and its effect; nil for what is not work done (an undo, a look).
    static func of(_ entry: ArisRecordEntry) -> ArisRecordFamily? {
        let id = (entry.capability ?? "").lowercased()
        let effect = entry.effect ?? .observe
        guard effect != .observe, effect != .never, !id.hasPrefix("record.") else { return nil }
        let has = { (words: [String]) in words.contains { id.contains($0) } }
        if id.hasPrefix("fleet.") || has(["session"]) { return .sessions }
        if effect == .outward { return .sent }
        if has(["event", "calendar"]) { return .calendar }
        if has(["todo", "remind"]) { return .todos }
        if has(["note", "remember", "memory"]) { return .notes }
        if id.hasPrefix("file.") || has(["file", "folder", "pdf", "convert", "merge", "compress", "move", "rename", "trash", "split"]) { return .files }
        if id.hasPrefix("app.") || id.hasPrefix("window.") || has(["desktop", "open_app", "keys", "type", "tile", "arrange"]) { return .apps }
        if has(["volume", "brightness", "music", "timer", "setting", "dark", "wifi"]) { return .controls }
        return .other
    }
}

/// The record's changes over a span, counted (what POST /dayend gives the app with `record`): no text at all.
struct ArisRecordDigest: Equatable, Sendable, Codable {
    /// Changes made and not undone since.
    var total = 0
    var families: [String: Int] = [:]
    /// Changes undone again (not counted above).
    var undone = 0
    /// Calls the policy or the owner turned down.
    var refused = 0
    /// Calls the owner was asked about (whatever he answered).
    var asked = 0

    func count(_ family: ArisRecordFamily) -> Int { families[family.rawValue] ?? 0 }

    /// `loggedUndone`: the activity log's undone entries (ids, lowercased), for calls whose run wrote them.
    static func make(_ state: ArisRecordState, from: Date, to: Date, loggedUndone: Set<String> = []) -> ArisRecordDigest {
        var digest = ArisRecordDigest()
        for entry in state.calls where entry.at >= ArisRecordEntry.whole(from) && entry.at <= to {
            if entry.answer != nil { digest.asked += 1 }
            if entry.decision == "refuse" || entry.answer == "no" { digest.refused += 1 }
            guard entry.ok == true, let family = ArisRecordFamily.of(entry) else { continue }
            if state.isUndone(entry, loggedUndone: loggedUndone) { digest.undone += 1; continue }
            digest.total += 1
            digest.families[family.rawValue, default: 0] += 1
        }
        return digest
    }

    var json: [String: Any] {
        ["total": total, "families": families, "undone": undone, "refused": refused, "asked": asked]
    }

    /// From POST /dayend's `record` object; nil when it isn't one.
    static func from(_ object: Any?) -> ArisRecordDigest? {
        guard let object = object as? [String: Any], let total = object["total"] as? Int else { return nil }
        let families = (object["families"] as? [String: Any] ?? [:]).compactMapValues { $0 as? Int }
            .filter { ArisRecordFamily(rawValue: $0.key) != nil && $0.value >= 0 }
        return ArisRecordDigest(total: max(0, total), families: families, undone: object["undone"] as? Int ?? 0,
                                refused: object["refused"] as? Int ?? 0, asked: object["asked"] as? Int ?? 0)
    }
}

struct ArisRecordQuery: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        /// Every call.
        case all
        /// What ran and changed something (not undone since).
        case changes
        /// What went out to other people.
        case sent
        /// What was turned down (by the policy or the owner).
        case refused
        /// What the owner was asked about.
        case asked
        /// What was taken back.
        case undone
    }

    static let defaultLimit = 50
    static let longestLimit = 200

    var from: Date
    var to: Date
    var kind: Kind = .all
    /// Words of the app a call acted in (its key argument), any case.
    var app: String? = nil
    /// A task's id; "conversation" for calls made outside a task.
    var task: String? = nil
    /// The capability's id or the start of it ("fleet.", "aris.file_move").
    var capability: String? = nil
    var limit = ArisRecordQuery.defaultLimit

    struct Row: Equatable, Sendable {
        let entry: ArisRecordEntry
        let undone: Bool
    }

    /// The calls that match, oldest first, the newest `limit` of them.
    func rows(_ state: ArisRecordState) -> [Row] {
        let start = ArisRecordEntry.whole(from)
        let picked = state.calls.filter { entry in
            guard entry.at >= start, entry.at <= to else { return false }
            if let capability, !(entry.capability ?? "").lowercased().hasPrefix(capability.lowercased()) { return false }
            if let task {
                if task == "conversation" ? entry.task != nil : entry.task != task { return false }
            }
            if let app {
                let words = app.lowercased()
                guard (entry.arguments ?? []).contains(where: { $0.kind == .app && $0.value.lowercased().contains(words) }) else { return false }
            }
            switch kind {
            case .all: return true
            case .changes: return entry.ok == true && (entry.effect ?? .observe) != .observe && !state.isUndone(entry.id)
            case .sent: return entry.effect == .outward && entry.ok == true
            case .refused: return entry.decision == "refuse" || entry.answer == "no"
            case .asked: return entry.answer != nil
            case .undone: return state.isUndone(entry.id)
            }
        }.sorted { $0.at < $1.at }
        return picked.suffix(max(1, min(limit, Self.longestLimit))).map { Row(entry: $0, undone: state.isUndone($0.id)) }
    }

    // MARK: - The capability's arguments

    /// From `record.query`'s arguments: `from` and `to` as "today", "yesterday", a day (2026-11-18) or an ISO 8601
    /// moment; `from` defaults to the start of today, `to` to now. Nil when a value can't be read (the call says so).
    static func parse(_ arguments: [String: Any], now: Date, calendar: Calendar = .current) -> ArisRecordQuery? {
        let today = calendar.startOfDay(for: now)
        func moment(_ value: Any?, end: Bool) -> Date?? {
            guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else { return .some(nil) }
            switch text {
            case "today": return end ? now : today
            case "yesterday": return end ? today : calendar.date(byAdding: .day, value: -1, to: today)
            case "now": return now
            default: break
            }
            if let day = dayFormatter(calendar).date(from: text) {
                return end ? calendar.date(byAdding: .day, value: 1, to: day) : day
            }
            let iso = ISO8601DateFormatter()
            if let date = iso.date(from: text.uppercased()) { return date }
            return nil
        }
        guard let from = moment(arguments["from"], end: false), let to = moment(arguments["to"], end: true) else { return nil }
        var query = ArisRecordQuery(from: from ?? today, to: to ?? now)
        if let raw = arguments["kind"] as? String {
            guard let kind = Kind(rawValue: raw.lowercased()) else { return nil }
            query.kind = kind
        }
        query.app = text(arguments["app"])
        query.task = text(arguments["task"])
        query.capability = text(arguments["capability"])
        if let limit = (arguments["limit"] as? NSNumber)?.intValue { query.limit = max(1, min(limit, longestLimit)) }
        return query.to >= query.from ? query : nil
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(120))
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    // MARK: - Words

    /// A call in a few words for a model (`record.query`) and the audit: its capability, its verb, where it went (no
    /// body, no result text).
    static func summary(_ entry: ArisRecordEntry) -> String {
        let verb = ArisAskPlan.verb(entry.effect ?? .observe, capability: entry.capability ?? "")
        return ArisRecordEntry.cut([entry.capability ?? "", verb, target(entry)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), 200)
    }

    /// A call as the owner reads it (the 한 일 list, the day-end card, an undo's line): its name and where it went,
    /// "앱에서 여러 단계: TextEdit", "이름 바꿈: a.txt", never a capability's id (ArisCapabilityNames).
    static func ownerSummary(_ entry: ArisRecordEntry) -> String {
        if let opened = opened(entry) { return ArisRecordEntry.cut(opened.name.korean + ": " + opened.target, 200) }
        let name = ArisJournalWords.replaced(entry.undo) ? ArisCapabilityNames.replacedText.korean
            : ArisCapabilityNames.shown(entry.capability ?? "", effect: entry.effect ?? .observe).korean
        return ArisRecordEntry.cut(target(entry).map { name + ": " + $0 } ?? name, 200)
    }

    /// What an app.open call opened when that was no app: a folder or a file (by its name), or a web page. From the
    /// call's own path or address, else from what its result says it opened ("opened /Users/…": a call that named the
    /// place in words carries no path). A path with no extension is taken as a folder. Nil: an app, or not known.
    private static func opened(_ entry: ArisRecordEntry) -> (name: ArisCapabilityNames.Name, target: String)? {
        guard entry.capability == "app.open" else { return nil }
        let arguments = entry.arguments ?? []
        if arguments.contains(where: { $0.kind == .app }) { return nil }
        if let url = arguments.first(where: { $0.kind == .url })?.value, url.lowercased().hasPrefix("http") { return (ArisCapabilityNames.openedPage, url) }
        var path = arguments.first { $0.kind == .path }?.value
        if path == nil, let data = entry.result?.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let did = object["did"] as? String, did.hasPrefix("opened /") {
            path = String(did.dropFirst("opened ".count))
        }
        guard let path, !path.isEmpty else { return nil }
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return ((name as NSString).pathExtension.isEmpty ? ArisCapabilityNames.openedFolder : ArisCapabilityNames.openedFile, name)
    }

    /// Where a call went: its recipient, file (by name), app, address or payee.
    private static func target(_ entry: ArisRecordEntry) -> String? {
        (entry.arguments ?? []).first { [.recipient, .path, .app, .url, .payee].contains($0.kind) }
            .map { $0.kind == .path ? ($0.value as NSString).lastPathComponent : $0.value }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The rows as `record.query` returns them: one line each, "HH:mm <summary> — <decision>", with the owner's answer,
    /// a failure and an undo marked.
    static func text(_ rows: [Row], query: ArisRecordQuery, calendar: Calendar = .current) -> String {
        guard !rows.isEmpty else { return "(nothing in the record for that)" }
        let clock = DateFormatter()
        clock.calendar = calendar
        clock.timeZone = calendar.timeZone
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = calendar.isDate(query.from, inSameDayAs: query.to) ? "HH:mm" : "MM-dd HH:mm"
        return rows.map { row in
            var marks = [row.entry.decision ?? ""]
            if let answer = row.entry.answer { marks.append("owner: " + answer) }
            if row.entry.ok == false { marks.append("not done") }
            if row.undone { marks.append("undone") }
            if let task = row.entry.task { marks.append("task " + task) }
            return clock.string(from: row.entry.at) + " " + summary(row.entry) + " — " + marks.filter { !$0.isEmpty }.joined(separator: ", ")
        }.joined(separator: "\n")
    }
}
