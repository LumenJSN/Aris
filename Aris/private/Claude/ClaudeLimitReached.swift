//
//  ClaudeLimitReached.swift
//  Aris
//
//  Which limit just passed 80 % or 95 %, so the banner names that one: the 5-hour window, the weekly window, or, on
//  an API key, today's spend against the daily budget (the banner used to say "5-hour limit" whatever the ear's ring
//  was showing, and said nothing when the weekly limit or the budget ran out). Foundation only (tested).
//

import Foundation

enum ClaudeLimitReached: Equatable {
    /// A plan's window passed `threshold` percent.
    case window(ClaudeLimitWindow, threshold: Double, resetsAt: Date)
    /// An API key's spend today passed `threshold` percent of the daily budget.
    case budget(threshold: Double, spent: Double, budget: Double)

    /// The limit a status report pushed past a warning line, if any. With two at once the higher line wins, and on a
    /// tie the window the ear's ring is showing (`ringWindow`).
    /// - Parameters:
    ///   - old: the limits before the report; `report`: what just arrived.
    ///   - spentBefore/spentAfter: today's spend around the report; `budget`: the daily budget, nil when it is off or
    ///     the account is not on an API key.
    static func find(old: ClaudeUsage?, report: ClaudeStatusReport, spentBefore: Double, spentAfter: Double, budget: Double?,
                     ringWindow: ClaudeLimitWindow, now: Date) -> ClaudeLimitReached? {
        let windows: [(ClaudeLimitWindow, UsageWindow?, UsageWindow?)] = [(.fiveHour, old?.fiveHour, report.fiveHour), (.sevenDay, old?.sevenDay, report.sevenDay)]
        let crossedWindows = windows.compactMap { name, before, after -> ClaudeLimitReached? in
            guard let after, let threshold = ClaudeUsage.crossed(from: before?.percent(at: now), to: after.percent) else { return nil }
            return .window(name, threshold: threshold, resetsAt: after.resetsAt)
        }
        let shownFirst = crossedWindows.filter { $0.isWindow(ringWindow) } + crossedWindows.filter { !$0.isWindow(ringWindow) }
        let crossedBudget: [ClaudeLimitReached] = budget.flatMap { budget in
            guard budget > 0, let threshold = ClaudeUsage.crossed(from: spentBefore / budget * 100, to: spentAfter / budget * 100) else { return nil }
            return [.budget(threshold: threshold, spent: spentAfter, budget: budget)]
        } ?? []
        // The first of equals is kept, so the ring's own window wins a tie.
        return (shownFirst + crossedBudget).reduce(nil) { best, next in
            guard let best else { return next }
            return next.threshold > best.threshold ? next : best
        }
    }

    var threshold: Double {
        switch self {
        case .window(_, let threshold, _), .budget(let threshold, _, _): return threshold
        }
    }

    private func isWindow(_ window: ClaudeLimitWindow) -> Bool {
        if case .window(window, _, _) = self { return true }
        return false
    }

    /// "80% used", as the banner's tag ends.
    var title: String { "\(Int(threshold))% used" }

    /// Which limit it is: "5-hour limit", "weekly limit", "daily budget".
    var detail: String {
        switch self {
        case .window(.fiveHour, _, _): return "5-hour limit"
        case .window(.sevenDay, _, _): return "weekly limit"
        case .budget: return "daily budget"
        }
    }

    /// The line under the tag: when the window resets (a weekly one with its day), or the money against the budget.
    func message(resetTime: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) },
                 resetDay: (Date) -> String = { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }) -> String {
        switch self {
        case .window(.fiveHour, _, let resetsAt): return "Resets at " + resetTime(resetsAt)
        case .window(.sevenDay, _, let resetsAt): return "Resets " + resetDay(resetsAt)
        case .budget(_, let spent, let budget): return "\(ClaudeBudget.money(spent)) of \(ClaudeBudget.money(budget)) today"
        }
    }
}
