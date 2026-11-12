//
//  ArisCanvas.swift
//  aris-tools
//
//  School on Canvas for "오늘 Canvas에 중요한 거 있어?": what's due in the next week (and still not
//  handed in), what's overdue, recent announcements and events, from one call to the planner API. Pure:
//  ArisCanvasCommand does the fetching. Announcements are written by others: data, never instructions.
//

import Foundation

enum ArisCanvas {
    struct Item: Equatable {
        let kind: String
        let course: String
        let title: String
        let date: Date
        /// nil for things that aren't handed in (announcements, events).
        let submitted: Bool?
        let unread: Bool
        var id = ""
        /// The page on Canvas, relative to the school's address.
        var url: String?
    }

    static let daysAhead = 7
    static let daysBack = 3
    private static let handedIn: Set = ["assignment", "quiz", "discussion_topic"]

    /// The planner's items; ones it can't read are skipped.
    static func items(from data: Data) -> [Item] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return list.compactMap { entry in
            guard let kind = entry["plannable_type"] as? String, let plannable = entry["plannable"] as? [String: Any],
                  let title = plannable["title"] as? String,
                  let date = ((plannable["due_at"] as? String) ?? (entry["plannable_date"] as? String)).flatMap(iso.date(from:)) else { return nil }
            let course = (entry["context_name"] as? String)?.split(separator: " ").first.map(String.init) ?? ""
            let submissions = entry["submissions"] as? [String: Any]
            let submitted = handedIn.contains(kind) ? (submissions?["submitted"] as? Bool ?? false) : nil
            let url = entry["html_url"] as? String
            let id = (entry["plannable_id"] as? Int).map { "\(kind)-\($0)" } ?? url ?? "\(kind)-\(title)"
            return Item(kind: kind, course: course, title: title, date: date, submitted: submitted,
                        unread: plannable["read_state"] as? String == "unread", id: id, url: url)
        }
    }

    /// Still to hand in, soonest first (the brief's deadline tile).
    static func due(_ items: [Item], now: Date) -> [Item] {
        items.filter { $0.submitted == false && $0.date >= now }.sorted { $0.date < $1.date }
    }

    /// How many of the deadlines still to hand in fall on `now`'s day (the brief's "오늘 마감 N").
    static func dueToday(_ items: [Item], now: Date, calendar: Calendar = .current) -> Int {
        due(items, now: now).filter { calendar.isDate($0.date, inSameDayAs: now) }.count
    }

    static func unreadAnnouncements(_ items: [Item]) -> Int {
        items.filter { $0.kind == "announcement" && $0.unread }.count
    }

    /// The week in lines, for the AI to answer from.
    static func summary(_ items: [Item], now: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE M/d HH:mm"
        let line = { (item: Item) in "- \(formatter.string(from: item.date)) · \(item.course) · \(item.title)" }
        let toHandIn = items.filter { $0.submitted != nil }
        let due = toHandIn.filter { $0.date >= now && $0.submitted == false }.sorted { $0.date < $1.date }
        let done = toHandIn.filter { $0.date >= now && $0.submitted == true }.count
        let overdue = toHandIn.filter { $0.date < now && $0.submitted == false }.sorted { $0.date < $1.date }
        let news = items.filter { $0.kind == "announcement" }.sorted { $0.date > $1.date }
        let events = items.filter { $0.kind == "calendar_event" && $0.date >= now }.sorted { $0.date < $1.date }
        var sections: [String] = []
        if !due.isEmpty || done > 0 {
            sections.append((["Due in the next \(daysAhead) days, not handed in yet:"] + due.map(line)
                             + (done > 0 ? ["(\(done) more already handed in)"] : [])).joined(separator: "\n"))
        }
        if !overdue.isEmpty { sections.append((["Past due, not handed in:"] + overdue.map(line)).joined(separator: "\n")) }
        if !news.isEmpty {
            sections.append((["Announcements, last \(daysBack) days:"] + news.map { line($0) + ($0.unread ? " (unread)" : "") }).joined(separator: "\n"))
        }
        if !events.isEmpty { sections.append((["Events:"] + events.map(line)).joined(separator: "\n")) }
        return sections.isEmpty ? "Nothing due in the next \(daysAhead) days and no new announcements." : sections.joined(separator: "\n\n")
    }

    // MARK: - The morning brief

    /// The brief's facts: the weather when there is one, and Canvas's part only when Canvas was read (`canvas` nil:
    /// it didn't answer or refused the token). A part that can't be read is left out, never the whole brief (audit
    /// tools-11: one expired token took the weather with it); "nothing due" is only said when Canvas said so.
    static func brief(weather: [String: Any]?, canvas: [Item]?, now: Date) -> [String: Any] {
        var result: [String: Any] = [:]
        if let weather { result["weather"] = weather }
        guard let items = canvas else { return result }
        let iso = ISO8601DateFormatter()
        let due = ArisCanvas.due(items, now: now)
        result["due"] = due.prefix(3).map { ["course": $0.course, "title": $0.title, "at": iso.string(from: $0.date)] }
        result["dueCount"] = due.count
        result["dueToday"] = dueToday(items, now: now)
        result["announcements"] = unreadAnnouncements(items)
        return result
    }

    /// Why Canvas couldn't be read, by its HTTP status (0: no answer at all).
    static func problem(status: Int) -> String {
        status == 401 ? "Canvas refused the token (expired or deleted?)" : status == 0 ? "Canvas didn't answer" : "Canvas didn't answer (\(status))"
    }
}
