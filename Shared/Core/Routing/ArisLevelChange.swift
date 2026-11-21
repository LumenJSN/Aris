//
//  ArisLevelChange.swift
//  Aris (Shared/Core)
//
//  How a spoken volume or brightness request moves the level. An absolute number sets it ("볼륨 30", "30으로 맞춰",
//  "set the volume to 30", "최대로"); a relative one moves it from where it is: by points ("10 올려", "down by 20"), by a
//  share ("반으로 줄여", "half"), or by the usual step made smaller or larger ("조금 줄여", "a bit", "많이 올려", "a lot").
//  The matcher used to read the first number in the sentence as the level, so "볼륨 10 줄여" set it to 10.
//  Foundation only (swift test).
//

import Foundation

enum ArisLevelChange: Equatable, Sendable {
    /// Set to this level (0–100).
    case to(Int)
    /// Move by this many points (signed).
    case by(Int)
    /// Move by this many of the device's own steps (signed: 0.5 for "a bit", 2 for "a lot").
    case steps(Double)
    /// Multiply the level ("반으로" is 0.5, "두 배로" 2).
    case scaled(Double)

    /// The level after the change, from `current` (0–100), with `step` points per step; always 0–100.
    func target(from current: Int, step: Int) -> Int {
        let next: Double
        switch self {
        case .to(let level): next = Double(level)
        case .by(let points): next = Double(current + points)
        case .steps(let count): next = Double(current) + count * Double(step)
        case .scaled(let factor): next = Double(current) * factor
        }
        return min(100, max(0, Int(next.rounded())))
    }

    private static let little = #"조금|살짝|약간|쪼금|좀만|조금만|살짝만|a\s+bit|a\s+little|a\s+touch|slightly|a\s+tad"#
    private static let lot = #"많이|훨씬|확|팍|a\s+lot|way|much|a\s+great\s+deal"#
    private static let halves = #"반으로|절반으로|절반|(?<![가-힣])반(?![가-힣])|\bhalf\b|\bby\s+half\b|\bin\s+half\b"#
    private static let doubles = #"두\s*배|2\s*배|\bdouble\b|\btwice\b"#
    /// A number that is the level itself: "30으로", "30에", "30까지", "30%로", "to 30", "at 30".
    private static let absolute = #"([0-9]{1,3})\s*(?:%|퍼센트|프로)?\s*(?:으로|로|에|까지)(?![가-힣])|\b(?:to|at)\s+([0-9]{1,3})\b"#
    /// A number that moves it: "10 올려", "10% 줄여", "by 10", "10 points".
    private static let relative = #"\bby\s+([0-9]{1,3})\b|([0-9]{1,3})\s*(?:%|퍼센트|프로|칸|단계|points?|notches|notch|steps?)?"#
    private static let stepUnit = #"([0-9]{1,3})\s*(?:칸|단계|notches|notch|steps?)"#

    /// The change `phrase` asks for, its direction from the verb (+1 up, -1 down, nil: none said); nil when it says no
    /// amount at all (then the usual step in that direction).
    static func read(_ phrase: String, direction: Int?) -> ArisLevelChange? {
        let text = phrase.lowercased()
        if let number = first(absolute, in: text) { return .to(min(100, number)) }
        if text.range(of: #"최대|\bmax(?:imum)?\b|\bfull\b|끝까지"#, options: .regularExpression) != nil, direction != -1 { return .to(100) }
        if text.range(of: #"최소|\bmin(?:imum)?\b"#, options: .regularExpression) != nil { return .to(0) }
        guard let direction else {
            // No verb: a bare number is the level ("볼륨 50", "volume 30").
            return first(#"([0-9]{1,3})"#, in: text).map { .to(min(100, $0)) }
        }
        let sign = Double(direction)
        if let count = first(stepUnit, in: text) { return .steps(sign * Double(count)) }
        if let points = first(relative, in: text) { return .by(direction * points) }
        if text.range(of: halves, options: .regularExpression) != nil { return .scaled(direction < 0 ? 0.5 : 1.5) }
        if text.range(of: doubles, options: .regularExpression) != nil, direction > 0 { return .scaled(2) }
        if text.range(of: little, options: .regularExpression) != nil { return .steps(sign * 0.5) }
        if text.range(of: lot, options: .regularExpression) != nil { return .steps(sign * 2) }
        return nil
    }

    /// The first number one of the pattern's groups caught.
    private static func first(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for index in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: index), in: text), let value = Int(text[range]) { return value }
        }
        return nil
    }
}
