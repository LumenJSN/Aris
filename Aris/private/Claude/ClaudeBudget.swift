//
//  ClaudeBudget.swift
//  Aris
//
//  The daily budget an API key's spend fills the ear ring against (설정 › 대화 › Claude Code): a free amount with a "$"
//  before it, decimals allowed, from $0.50 to $1,000. A good amount is saved as it is typed; a bad entry shows a short
//  hint and the last good amount is kept, and comes back when the field is left. The row's words are Korean like the
//  rest of the settings window. Foundation only (tested).
//

import Foundation

enum ClaudeBudget {
    static let range = 0.5...1000.0
    static let fallback = 5.0
    static let quick: [Double] = [3, 5, 10]
    static let amountKey = "claudeDailyBudget"
    static let onKey = "claudeDailyBudgetOn"
    /// What VoiceOver calls the field and its switch.
    static let fieldLabel = "하루 예산 (달러)"
    static let switchLabel = "하루 예산 쓰기"

    enum Problem: Error, Equatable, CaseIterable {
        case empty, notNumber, tooSmall, tooLarge
    }

    /// A typed amount: spaces, a leading "$" and a decimal comma are fine; up to two decimals.
    static func parse(_ text: String) -> Result<Double, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let bare = (trimmed.hasPrefix("$") ? String(trimmed.dropFirst()) : trimmed).replacingOccurrences(of: ",", with: ".")
        guard !bare.isEmpty else { return .failure(.empty) }
        guard bare.range(of: #"^[0-9]+(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil, let value = Double(bare) else {
            return .failure(.notNumber)
        }
        if value < range.lowerBound { return .failure(.tooSmall) }
        if value > range.upperBound { return .failure(.tooLarge) }
        return .success(value)
    }

    /// A saved amount, or $5 when it isn't one the field would take.
    static func stored(_ value: Double) -> Double { value.isFinite && range.contains(value) ? value : fallback }

    /// "$5", "$1.24", "$0.50" (whole dollars lose their ".00").
    static func money(_ value: Double) -> String {
        let text = String(format: "%.2f", (value * 100).rounded() / 100)
        return "$" + (text.hasSuffix(".00") ? String(text.dropLast(3)) : text)
    }

    /// The amount as the field shows it: 5 → "5", 4.5 → "4.5", 2.75 → "2.75".
    static func plain(_ value: Double) -> String {
        let text = String(format: "%.2f", (value * 100).rounded() / 100)
        guard text.contains(".") else { return text }
        let trimmed = text.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
        return trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
    }

    /// The line under the field: the allowed range, or what's wrong.
    static func hint(_ problem: Problem?) -> String {
        switch problem {
        case nil: "0.5에서 1000달러까지 · 소수점도 돼요"
        case .empty: "금액을 적어 주세요. 쓰지 않으려면 오른쪽 스위치를 꺼요"
        case .notNumber: "숫자만 적어 주세요 (예: 4.5)"
        case .tooSmall: "0.5달러보다 적게는 정할 수 없어요"
        case .tooLarge: "1000달러까지 정할 수 있어요"
        }
    }

    /// The row's own line: what the ring does with the amount (nil: the budget is off).
    static func line(_ budget: Double?) -> String {
        guard let budget else { return "꺼져 있으면 고리가 비어 있어요" }
        return "고리가 오늘 쓴 돈을 \(money(budget))에 대어 채워요"
    }
}

/// What's in the budget field while it is being typed in.
struct ClaudeBudgetEntry: Equatable {
    /// The text as typed (nil: the saved amount shows).
    var draft: String?
    var problem: ClaudeBudget.Problem?

    func text(saved: Double) -> String { draft ?? ClaudeBudget.plain(saved) }

    /// After a keystroke: the field's new state, and the amount to save when the text is a good one.
    func typing(_ text: String) -> (entry: ClaudeBudgetEntry, save: Double?) {
        switch ClaudeBudget.parse(text) {
        case .success(let dollars): (ClaudeBudgetEntry(draft: text, problem: nil), dollars)
        case .failure(let why): (ClaudeBudgetEntry(draft: text, problem: why), nil)
        }
    }

    /// Leaving the field, or Return: a bad entry goes and the last good amount shows again.
    func settled() -> ClaudeBudgetEntry { problem == nil ? self : ClaudeBudgetEntry() }
}

/// The Claude usage words in the notch, in Korean or English (ArisUIWords).
enum ClaudeUsageWords {
    static func todayLabel(english: Bool = ArisUIWords.english) -> String { english ? "Today" : "오늘" }
    static func sessionLabel(english: Bool = ArisUIWords.english) -> String { english ? "This session" : "이 세션" }
    static func apiKey(english: Bool = ArisUIWords.english) -> String { english ? "API key" : "API 키" }

    /// "오늘 $1.24 / $5 · 이 세션 $0.75" (no budget: no "/ $Y"; no session: no second part).
    static func today(spent: Double, budget: Double?, session: Double?, english: Bool = ArisUIWords.english) -> String {
        let parts = ["\(todayLabel(english: english)) \(ClaudeBudget.money(spent))" + (budget.map { " / \(ClaudeBudget.money($0))" } ?? ""),
                     session.map { "\(sessionLabel(english: english)) \(ClaudeBudget.money($0))" }]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// "귀: 5시간", "귀: 자동 · 주간": which window the ear's ring shows (the tab's meter).
    static func ringMark(mode: ClaudeRingMode, window: ClaudeLimitWindow, english: Bool = ArisUIWords.english) -> String {
        let name = window == .fiveHour ? (english ? "5-hour" : "5시간") : (english ? "weekly" : "주간")
        let lead = english ? "Ring: " : "귀: "
        return mode == .auto ? lead + (english ? "auto · " : "자동 · ") + name : lead + name
    }

    /// VoiceOver's name for a small usage ring: "Claude, weekly limit 21 percent used", "Claude, today $1.24 of $5
    /// budget" (it said "Claude usage N percent" for the budget's ring too).
    static func ringLabel(_ reading: ClaudeRingReading) -> String { "Claude" + spoken(reading) }

    /// VoiceOver's reading of the ring.
    static func spoken(_ reading: ClaudeRingReading) -> String {
        switch reading {
        case .limit(let window, let percent):
            guard let percent else { return "" }
            return ", \(window == .fiveHour ? "5-hour" : "weekly") limit \(Int(percent.rounded(.up))) percent used"
        case .budget(let spent, let budget):
            return ", today \(ClaudeBudget.money(spent))" + (budget.map { " of \(ClaudeBudget.money($0)) budget" } ?? "")
        }
    }
}
