//
//  ClaudeRingMode.swift
//  Aris
//
//  What the closed notch's ear ring fills with (mockup claude-usage.html, A): on a plan, the 5-hour or the weekly
//  limit, or 자동 (whichever is used more); on an API key, today's spend against the daily budget. The tints follow
//  ClaudeUsage.warnAt either way. Foundation only (tested).
//

import Foundation

/// A plan's two limit windows.
enum ClaudeLimitWindow: Equatable {
    case fiveHour, sevenDay
}

/// The owner's pick in 설정 › 대화 › Claude Code › 귀에 보일 사용량.
enum ClaudeRingMode: String, CaseIterable {
    case fiveHour, sevenDay, auto

    static let defaultsKey = "claudeRingMode"

    /// The saved pick; nothing or anything unknown is 5시간, the ring as it always was.
    init(stored: String?) {
        self = stored.flatMap(ClaudeRingMode.init(rawValue:)) ?? .fiveHour
    }

    /// The window the ring shows. 자동 takes the higher percent (5시간 on a tie) and, with one window reported, that one.
    func window(fiveHour: Double?, sevenDay: Double?) -> ClaudeLimitWindow {
        switch self {
        case .fiveHour: return .fiveHour
        case .sevenDay: return .sevenDay
        case .auto:
            guard let week = sevenDay else { return .fiveHour }
            guard let five = fiveHour else { return .sevenDay }
            return week > five ? .sevenDay : .fiveHour
        }
    }
}

/// What the ring shows right now.
enum ClaudeRingReading: Equatable {
    /// A plan's window and its percent (nil until reported).
    case limit(ClaudeLimitWindow, Double?)
    /// An API key: today's spend, against the budget (nil: the budget is off and the ring stays empty).
    case budget(spent: Double, budget: Double?)

    static func make(plan: ClaudePlan, mode: ClaudeRingMode, usage: ClaudeUsage?, spent: Double, budget: Double?, now: Date) -> ClaudeRingReading {
        if plan == .apiKey { return .budget(spent: spent, budget: budget) }
        let five = usage?.fiveHour?.percent(at: now), week = usage?.sevenDay?.percent(at: now)
        let window = mode.window(fiveHour: five, sevenDay: week)
        return .limit(window, window == .fiveHour ? five : week)
    }

    /// How full the ring is, 0…100; nil leaves it empty.
    var percent: Double? {
        switch self {
        case .limit(_, let percent): return percent
        case .budget(let spent, let budget):
            guard let budget, budget > 0 else { return nil }
            return min(max(spent / budget * 100, 0), 100)
        }
    }

    /// 0 the accent, 1 the approval yellow (from 80 %), 2 the error red (from 95 %): ClaudeUsage.warnAt.
    var tintLevel: Int {
        guard let percent else { return 0 }
        return ClaudeUsage.warnAt.filter { percent >= $0 }.count
    }

    /// The limit window the ring is showing, if it shows one (the tab lights its label).
    var window: ClaudeLimitWindow? {
        if case .limit(let window, _) = self { return window }
        return nil
    }
}
