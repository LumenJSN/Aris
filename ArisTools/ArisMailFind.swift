//
//  ArisMailFind.swift
//  aris-tools (also built into aris-agent)
//
//  Finding the right mail without its number: `mail recent` and `mail search "<words>"` narrowed by who sent it
//  (`--from`, a name or an address), words of its subject (`--subject`), the days it came (`--since`, `--before`) and
//  unread only (`--unread`), so "교수님 메일" or "the invoice from last week" is found from what the user said. The newest
//  come first (ArisMailRead.read runs the search). Pure, so the tests run it.
//

import Foundation

enum ArisMailFind {
    /// SQL conditions for a filter, their values added to `bind` (each ?N is its place there).
    static func conditions(_ filter: ArisMailFilter, columns: Set<String>, bind: inout [Any]) -> [String] {
        var found: [String] = []
        func like(_ words: String?, fields: [String]) {
            for word in (words ?? "").split(separator: " ").prefix(6) {
                bind.append(ArisLocalStore.likePattern(String(word.prefix(60))))
                found.append("(" + fields.map { "\($0) LIKE ?\(bind.count) ESCAPE '\\'" }.joined(separator: " OR ") + ")")
            }
        }
        like(filter.from, fields: ["a.address", "a.comment"])
        like(filter.subject, fields: ["s.subject"])
        if let since = filter.since { bind.append(Int(since.timeIntervalSince1970)); found.append("m.date_received >= ?\(bind.count)") }
        if let before = filter.before { bind.append(Int(before.timeIntervalSince1970)); found.append("m.date_received < ?\(bind.count)") }
        if filter.unread, columns.contains("read") { found.append("IFNULL(m.read, 0) = 0") }
        return found
    }

    /// The flags of `mail recent` and `mail search` that take a value.
    static let listFlags: Set<String> = ["--limit", "--from", "--subject", "--since", "--before"]
    static let listUsage = "usage: mail recent | mail search \"<words>\"   (both take: [--from \"<name or address>\"] [--subject \"<words>\"] [--since YYYY-MM-DD] [--before YYYY-MM-DD] [--unread] [--limit N]; a search may have only those)"
    /// Said under a list: what the numbers are for.
    static let listHint = "(메일 전체는 mail read <#번호>, 주고받은 대화 전체는 mail thread <#번호>)"

    /// The filter in a list command's words; nil when a day isn't one ("2026-11-03").
    static func filter(_ args: [String], zone: TimeZone = .current) -> ArisMailFilter? {
        var filter = ArisMailFilter(from: ArisLocalStore.value("--from", in: args), subject: ArisLocalStore.value("--subject", in: args), unread: args.contains("--unread"))
        for (flag, place) in [("--since", \ArisMailFilter.since), ("--before", \ArisMailFilter.before)] {
            guard let text = ArisLocalStore.value(flag, in: args) else { continue }
            guard let date = day(text, zone: zone) else { return nil }
            filter[keyPath: place] = date
        }
        return filter
    }

    /// A day as the search takes it ("2026-11-03", the Mac's own time zone): its first moment.
    static func day(_ text: String, zone: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: text).flatMap { formatter.string(from: $0) == text ? $0 : nil }
    }
}
