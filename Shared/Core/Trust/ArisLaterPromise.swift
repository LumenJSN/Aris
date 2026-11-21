//
//  ArisLaterPromise.swift
//  Shared/Core (aris-agent, tests)
//
//  A reply never promises work at a later time that nothing was set up to do (twelfth VM run, B6: "내일 9시에 쿠팡에서
//  휴지 주문해 줘" set one reminder, due 11-22 09:00, and the job's reply went on "9시에 장바구니까지 준비해 두고 결제
//  직전에서 멈출게요", which no schedule would do). A sentence that says Aris will do something at a time to come is
//  taken out when no schedule was added while the reply was made; what was really done (the reminder, "걸어 뒀어요") stays,
//  and one line says nothing was scheduled to run then. Code blocks stay as written. Pure.
//

import Foundation

enum ArisLaterPromise {
    /// A time to come.
    private static let later = #"\d{1,2}\s?시|\d{1,2}:\d{2}|내일|모레|글피|오전|오후|아침|저녁|밤에|새벽|나중에|그때|이따|매일|매주|매달|\d+\s?(?:분|시간|일)\s?(?:뒤|후)|"#
        + #"\b(?:tomorrow|tonight|later|then|every\s+(?:day|week|morning|evening)|in the (?:morning|evening|afternoon)|at\s+\d{1,2}(?::\d{2})?|\d{1,2}(?::\d{2})?\s?(?:am|pm)|in\s+\d+\s+(?:minutes?|hours?|days?))\b"#
    /// Aris saying it will do something (its own future, first person).
    private static let promise = #"(?:게요|겠습니다|겠어요|드릴게|둘게|놓을게)[.!]?\s*$|\b(?:i'll|i will|i'm going to|i am going to|aris will)\b"#

    static func line(korean: Bool) -> String {
        korean ? "그때 따로 해 두도록 예약된 일은 없어요." : "Nothing was scheduled to run then."
    }

    /// Whether a sentence promises work at a later time.
    static func promises(_ sentence: String) -> Bool {
        let text = sentence.lowercased()
        return text.range(of: later, options: .regularExpression) != nil && text.range(of: promise, options: .regularExpression) != nil
    }

    /// The reply as it may be passed on. `scheduled`: a schedule (or a job that runs later) was added while it was made.
    static func checked(_ reply: String, scheduled: Bool, korean: Bool) -> String {
        guard !scheduled else { return reply }
        var inCode = false, dropped = false
        var kept: [String] = []
        for row in reply.components(separatedBy: "\n") {
            if row.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inCode.toggle() }
            guard !inCode else { kept.append(row); continue }
            let sentences = row.replacingOccurrences(of: #"([.!?。])\s+"#, with: "$1\u{1F}", options: .regularExpression).components(separatedBy: "\u{1F}")
            let left = sentences.filter { !promises($0) }
            if left.count != sentences.count { dropped = true }
            let joined = left.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            if !joined.isEmpty || left.count == sentences.count { kept.append(joined.isEmpty ? row : joined) }
        }
        guard dropped else { return reply }
        let rest = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? line(korean: korean) : rest + " " + line(korean: korean)
    }
}
