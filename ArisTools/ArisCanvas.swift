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

    // MARK: - The fetch (ArisCanvasCommand)

    /// One request's limit. It used to be 10 s, and every way a request can end without an HTTP answer was said as
    /// the same "Canvas didn't answer" with the reason dropped (the owner's agent.log, 2026-11-19, while the host
    /// answered): a busy school's planner can take longer, and a Mac just awake has no network for a moment. The
    /// callers give `aris-tools canvas` 20 s in all.
    static let requestTimeout: TimeInterval = 15
    /// Every page within this (under the callers' 20 s for the whole command); a page past it is left unread.
    static let allPagesWithin: TimeInterval = 18
    /// The most of the planner's pages read (100 items each; a full term's announcements can pass 100).
    static let maxPages = 5
    /// A failure this quick that may pass (the network coming back after sleep) is tried once more, a second later.
    static let retryWithin: TimeInterval = 4

    /// Why no HTTP answer came, from URLSession's error: said, never dropped.
    static func problem(noAnswer code: URLError.Code?, host: String) -> String {
        switch code {
        case .timedOut?: return "Canvas didn't answer within \(Int(requestTimeout)) seconds (\(host) may be slow right now)"
        case .notConnectedToInternet?, .networkConnectionLost?, .dataNotAllowed?: return "Canvas couldn't be reached: no network connection"
        case .cannotFindHost?, .dnsLookupFailed?: return "Canvas couldn't be reached: \(host) wasn't found (check the school's address)"
        case .cannotConnectToHost?: return "Canvas couldn't be reached: \(host) refused the connection"
        case .secureConnectionFailed?, .serverCertificateUntrusted?, .serverCertificateHasBadDate?, .serverCertificateNotYetValid?,
             .serverCertificateHasUnknownRoot?, .clientCertificateRejected?, .clientCertificateRequired?:
            return "Canvas couldn't be reached: the secure connection to \(host) failed (a proxy or a network filter?)"
        case let other?: return "Canvas didn't answer (\(other.rawValue))"
        case nil: return "Canvas didn't answer"
        }
    }

    /// Whether a request that got no answer is tried once more: a quick failure of the network that may pass.
    static func retries(_ code: URLError.Code?, elapsed: TimeInterval) -> Bool {
        guard elapsed < retryWithin, let code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed, .cannotFindHost, .cannotConnectToHost].contains(code)
    }

    /// The planner's next page from its `Link` header, only on the school's own host over https (the token goes with
    /// it, so never anywhere else).
    static func nextPage(link: String?, host: String) -> URL? {
        guard let link else { return nil }
        for part in link.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 2, pieces.dropFirst().contains(where: { $0.replacingOccurrences(of: " ", with: "") == "rel=\"next\"" }),
                  pieces[0].hasPrefix("<"), pieces[0].hasSuffix(">") else { continue }
            guard let url = URL(string: String(pieces[0].dropFirst().dropLast())), url.scheme == "https",
                  url.host?.lowercased() == host.lowercased(), url.port == nil || url.port == 443, url.user == nil else { return nil }
            return url
        }
        return nil
    }
}
