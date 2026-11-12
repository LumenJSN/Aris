//
//  ClaudeSpend.swift
//  Aris
//
//  Today's Claude Code spend on an API key, and whether Claude Code runs on a plan or on a key. The status line's
//  `cost.total_cost_usd` is per session and cumulative, so each report adds only its session's growth since the
//  last one to the local day's total (a session first heard adds its total so far; one whose total went down started
//  over and counts from zero). The day starts over at local midnight, and the ledger is saved so a restart keeps it
//  (ClaudeStore). Foundation only (tested).
//

import Foundation

/// How Claude Code is paid for, as its status line shows it.
enum ClaudePlan: String, Codable, Equatable {
    /// Nothing decisive yet: shown as a plan, as before.
    case unknown
    /// Pro / Max: `rate_limits` came with a report.
    case subscription
    /// A session spent money and never reported `rate_limits`.
    case apiKey
}

struct ClaudeSpendLedger: Codable, Equatable {
    /// One session as last heard.
    struct Seen: Codable, Equatable {
        /// Its total when first heard (a fresh session's is 0; a resumed one's may not be).
        var first: Double
        /// Its total in the latest report.
        var last: Double
        /// It has reported `rate_limits`: a plan's session, whatever it reports later.
        var limited: Bool
        var at: Date
    }

    static let defaultsKey = "claudeSpendLedger"
    /// Sessions not heard from for this long are dropped. Until then one that speaks again adds only its growth, so a
    /// terminal left open over a weekend never adds its whole total a second time.
    static let forgetAfter: TimeInterval = 30 * 24 * 60 * 60
    /// While a plan session reported its limits this recently, a key session's spend doesn't take the ring: with both
    /// kinds open the ring stays on the plan instead of flipping with every report.
    static let planHold: TimeInterval = 10 * 60

    /// The local day `today` belongs to, "yyyy-MM-dd".
    var day = ""
    var today = 0.0
    var seen: [String: Seen] = [:]
    var plan = ClaudePlan.unknown

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Today's total; $0 once local midnight has passed, before any new report.
    func spent(at now: Date, calendar: Calendar = .current) -> Double {
        day == Self.dayKey(now, calendar: calendar) ? today : 0
    }

    /// A session's own total so far (이 세션).
    func session(_ id: String) -> Double? { seen[id]?.last }

    /// The ledger after `report`: its session's growth added to today, and the plan decided if the report decides it.
    func recording(_ report: ClaudeStatusReport, now: Date, calendar: Calendar = .current) -> ClaudeSpendLedger {
        var next = self
        let key = Self.dayKey(now, calendar: calendar)
        if next.day != key {
            next.day = key
            next.today = 0
        }
        next.seen = next.seen.filter { now.timeIntervalSince($0.value.at) < Self.forgetAfter }
        guard let id = report.sessionId else {
            if report.hasLimits { next.plan = .subscription }
            return next
        }
        let previous = next.seen[id]
        if let cost = report.cost {
            // A total lower than the last one started over (a new process for the same session): count it from zero.
            let base = previous.map { cost >= $0.last ? $0.last : 0 } ?? 0
            next.today += cost - base
        }
        let limited = report.hasLimits || previous?.limited == true
        let seen = Seen(first: previous?.first ?? report.cost ?? 0, last: report.cost ?? previous?.last ?? 0, limited: limited, at: now)
        let planHeard = next.seen.contains { $0.key != id && $0.value.limited && now.timeIntervalSince($0.value.at) < Self.planHold }
        next.seen[id] = seen
        next.plan = Self.plan(after: report, seen: seen, heardBefore: previous != nil, planHeard: planHeard, was: plan)
        return next
    }

    /// `rate_limits` is a plan. A report without them is an API key only once the session has been seen to spend
    /// (its total grew since first heard) and never reported limits: a fresh plan session reports none until its
    /// first response, and a resumed one may carry a cost before it, so neither flips anything. Nor does a key
    /// session while another session reported a plan's limits in the last ten minutes (`planHeard`).
    private static func plan(after report: ClaudeStatusReport, seen: Seen, heardBefore: Bool, planHeard: Bool, was: ClaudePlan) -> ClaudePlan {
        if report.hasLimits { return .subscription }
        if heardBefore, !seen.limited, seen.last > seen.first, !planHeard { return .apiKey }
        return was
    }

    /// Whether anything but the times the sessions were last heard changed: a new amount, day, session or plan is
    /// worth saving again, the time of a repeated report is not.
    func changedMoney(from old: ClaudeSpendLedger) -> Bool { timeless != old.timeless }

    private var timeless: ClaudeSpendLedger {
        var copy = self
        copy.seen = seen.mapValues { Seen(first: $0.first, last: $0.last, limited: $0.limited, at: .distantPast) }
        return copy
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// A saved ledger; nothing or junk is a fresh one.
    static func decoded(_ data: Data?) -> ClaudeSpendLedger {
        guard let data, let ledger = try? JSONDecoder().decode(ClaudeSpendLedger.self, from: data) else { return ClaudeSpendLedger() }
        return ledger
    }
}
