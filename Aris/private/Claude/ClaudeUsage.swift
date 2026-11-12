//
//  ClaudeUsage.swift
//  Aris
//
//  Plan limits and context use, from the JSON Claude Code feeds its status line
//  (forwarded to /status by ~/.config/aris/statusline.sh). `rate_limits`
//  only exists for Pro/Max plans and only after the first response of a session;
//  `cost.total_cost_usd` is the session's spend so far (ClaudeSpend).
//

import Foundation

struct UsageWindow: Equatable {
    let percent: Double
    let resetsAt: Date

    /// A window that has already reset reads 0% until a fresh report arrives.
    func percent(at now: Date) -> Double { now >= resetsAt ? 0 : percent }

    init(percent: Double, resetsAt: Date) {
        self.percent = percent
        self.resetsAt = resetsAt
    }

    fileprivate init?(json: Any?) {
        guard let window = json as? [String: Any],
              let percent = ClaudeStatusReport.percent(window["used_percentage"]),
              let resets = window["resets_at"] as? NSNumber else { return nil }
        self.init(percent: percent, resetsAt: Date(timeIntervalSince1970: resets.doubleValue))
    }
}

/// One status line update.
struct ClaudeStatusReport: Equatable {
    let sessionId: String?
    let contextPercent: Double?
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    /// The session's spend so far (`cost.total_cost_usd`, cumulative per session); nil when absent or not a number ≥ 0.
    let cost: Double?
    /// The plan's limits came with it (Pro/Max, after the session's first response); an API key never has them.
    let hasLimits: Bool

    /// nil when the payload carries nothing the notch shows.
    init?(json: [String: Any]) {
        let limits = json["rate_limits"] as? [String: Any]
        sessionId = (json["session_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        contextPercent = Self.percent((json["context_window"] as? [String: Any])?["used_percentage"])
        fiveHour = UsageWindow(json: limits?["five_hour"])
        sevenDay = UsageWindow(json: limits?["seven_day"])
        cost = Self.dollars((json["cost"] as? [String: Any])?["total_cost_usd"])
        hasLimits = fiveHour != nil || sevenDay != nil
        if contextPercent == nil && fiveHour == nil && sevenDay == nil && cost == nil { return nil }
    }

    /// A finite, non-negative number.
    static func dollars(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let dollars = number.doubleValue
        return dollars.isFinite && dollars >= 0 ? dollars : nil
    }

    /// A finite number, clamped to 0…100.
    static func percent(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let percent = number.doubleValue
        return percent.isFinite ? min(max(percent, 0), 100) : nil
    }
}

/// The plan's limits as last reported by any session (they are account-wide).
struct ClaudeUsage: Equatable {
    static let warnAt: [Double] = [80, 95]

    var fiveHour: UsageWindow? = nil
    var sevenDay: UsageWindow? = nil
    let updatedAt: Date

    /// Fields the report lacks keep their last known value.
    func merging(_ report: ClaudeStatusReport, now: Date) -> ClaudeUsage {
        ClaudeUsage(fiveHour: report.fiveHour ?? fiveHour, sevenDay: report.sevenDay ?? sevenDay, updatedAt: now)
    }

    /// The highest warning threshold passed on the way from `old` up to `new`, if any.
    static func crossed(from old: Double?, to new: Double) -> Double? {
        guard let old else { return nil }
        return warnAt.last { old < $0 && new >= $0 }
    }
}
