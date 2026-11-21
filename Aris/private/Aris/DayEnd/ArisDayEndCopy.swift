//
//  ArisDayEndCopy.swift
//  Aris
//
//  Every word of the day-end summary (ArisDayEnd), Korean and English: the one sentence that is said and shown, the 목록
//  row and its tiles, and the chip that offers it in the evening (the setting's row is ArisDayEndSetting's). Kept here
//  and not in Localizable.xcstrings, so the summary can be written in the language the user asked in. Numbers in the sentence are
//  words, as they are said ("다섯 가지", "five"); the rows hold no sentences at all. Foundation only.
//

import Foundation

enum ArisDayEndCopy {
    /// What a summary leaves in the history the AI reads later: never the titles (events, deadlines and job results
    /// carry other people's words).
    static func remembered(english: Bool) -> String { english ? "Showed today's wrap-up." : "오늘 정리를 보여줬어요." }

    /// The notch's title while the summary came by itself (the evening chip).
    static func title(english: Bool) -> String { english ? "Today's wrap-up" : "오늘 정리" }

    // MARK: - The list

    static func list(english: Bool) -> String { english ? "List" : "목록" }
    /// Whether the row is open, for whoever can't see its chevron (VoiceOver).
    static func listState(open: Bool, english: Bool) -> String {
        open ? (english ? "Open" : "펼쳐짐") : (english ? "Folded" : "접힘")
    }
    static func listHelp(open: Bool, english: Bool) -> String {
        open ? (english ? "Fold the list" : "목록 접기") : (english ? "Open the list" : "목록 펼치기")
    }

    static func plannedTitle(_ count: Int, english: Bool) -> String { english ? "Planned for today · \(count)" : "오늘 하려던 일 · \(count)" }
    static func waitingTitle(_ count: Int, english: Bool) -> String { english ? "Needs your OK · \(count)" : "내 확인 · \(count)" }
    static func tomorrowTitle(_ count: Int, english: Bool) -> String { english ? "Tomorrow · \(count)" : "내일 · \(count)" }
    static func extrasTitle(_ count: Int, english: Bool) -> String { english ? "Also done · \(count)" : "그 밖 · \(count)" }
    /// In the 그 밖 row's place when the activity record couldn't be read: never told as nothing done.
    static func extrasUnread(english: Bool) -> String { english ? "Also done · couldn't read the record" : "그 밖 · 기록을 읽지 못했어요" }

    static func kind(_ kind: ArisDayEnd.Kind, english: Bool) -> String {
        switch kind {
        case .todo: return english ? "To-do" : "할 일"
        case .event: return english ? "Event" : "일정"
        case .deadline: return english ? "Deadline" : "마감"
        case .job: return english ? "Job" : "시킨 일"
        case .routine: return english ? "Routine" : "루틴"
        }
    }

    /// What a mark means, for whoever can't see it (VoiceOver).
    static func mark(_ mark: ArisDayEnd.Mark, english: Bool) -> String {
        switch mark {
        case .done: return english ? "Done" : "끝냄"
        case .part: return english ? "Under way" : "하는 중"
        case .none: return english ? "Not done" : "남음"
        case .wait: return english ? "Waiting for you" : "확인 대기"
        }
    }

    static func push(english: Bool) -> String { english ? "Move to tomorrow" : "내일로 넘기기" }
    static func pushed(english: Bool) -> String { english ? "Moved" : "넘겼어요" }
    static func notPushed(english: Bool) -> String { english ? "Couldn't move" : "못 넘겼어요" }
    static func show(english: Bool) -> String { english ? "Show" : "보기" }
    static func allDay(english: Bool) -> String { english ? "All day" : "종일" }
    static func andMore(_ count: Int, english: Bool) -> String { english ? "\(count) more" : "외 \(count)개" }

    /// A schedule that repeats through the day: "30분마다", "every 2 h".
    static func every(seconds: Int, english: Bool) -> String {
        let minutes = max(1, seconds / 60)
        if minutes % 60 == 0 { return english ? "every \(minutes / 60) h" : "\(minutes / 60)시간마다" }
        return english ? "every \(minutes) min" : "\(minutes)분마다"
    }

    // MARK: - The sentence

    /// The day in one sentence of spoken length: how much of what was planned got done, then what is left, what was
    /// put off and what waits for his answer, each only when there is some. With nothing planned it says what was done
    /// instead, or that there was nothing.
    static func sentence(_ counts: ArisDayEnd.Counts, unread: Bool, english: Bool) -> String {
        guard counts.planned > 0 else { return unplanned(counts, unread: unread, english: english) }
        return english ? englishSentence(counts) : koreanSentence(counts)
    }

    /// The answer to a request: the card's sentence, and when the user asked what they did ("오늘 뭐 했어"), what was done
    /// besides the plan too, in the day in review's words (ArisRecapSentences.didToday). Third VM run, D5: "오늘 뭐
    /// 했어" with nine open plans and four things done (to-dos added, a timer) answered with the open plans only.
    /// `phrase`: the request, lowercased with its end marks off (ArisIntent.phrase).
    static func answer(_ counts: ArisDayEnd.Counts, unread: Bool, english: Bool, phrase: String) -> String {
        let said = sentence(counts, unread: unread, english: english)
        guard counts.planned > 0, asksWhatWasDone(phrase), let done = alsoDone(counts, english: english) else { return said }
        return said + " " + done
    }

    /// The request asks what was done: "오늘 뭐 했어", "내가 한 일", "what did I do today", "what have I done".
    static func asksWhatWasDone(_ phrase: String) -> Bool {
        let cores = [#"뭐\s*(했|한\s*거|한\s*게)"#, #"무엇을\s*했"#, #"한\s*일"#, #"했던\s*(일|거|것)"#, #"\bwhat\s+(did|have)\s+(i|we|you)\s+(do|done|get done)\b"#,
                     #"\bwhat\s+got\s+done\b"#, #"\bwhat\s+i\s+did\b"#]
        return cores.contains { phrase.range(of: $0, options: .regularExpression) != nil }
    }

    /// The things done that weren't planned, in the recap's words; nil when there were none.
    static func alsoDone(_ counts: ArisDayEnd.Counts, english: Bool) -> String? {
        guard counts.extra > 0 else { return nil }
        var facts = ArisRecapFacts()
        facts.plan.planned = counts.planned
        facts.extra = counts.extra
        return ArisRecapSentences(facts: facts, fleet: ArisRecapFleet([], since: .distantPast), today: Date(), english: english, calendar: .current).didToday()
    }

    private static func unplanned(_ counts: ArisDayEnd.Counts, unread: Bool, english: Bool) -> String {
        var said: [String]
        if counts.extra > 0 {
            said = [english ? "Nothing was planned for today, and \(number(counts.extra)) \(counts.extra == 1 ? "thing" : "things") got done."
                        : "오늘 따로 정한 일은 없었고, \(things(counts.extra))를 했어요."]
        } else if unread {
            said = [english ? "Nothing was planned for today." : "오늘 따로 정한 일은 없었어요."]
        } else {
            said = [english ? "Nothing was planned or done today." : "오늘은 정한 일도 한 일도 없었어요."]
        }
        if unread { said.append(english ? "I couldn't read today's activity record just now." : "오늘 한 일 기록은 지금 읽지 못했어요.") }
        if counts.waiting > 0 { said.append(waitingAlone(counts.waiting, english: english)) }
        return said.joined(separator: " ")
    }

    private static func koreanSentence(_ counts: ArisDayEnd.Counts) -> String {
        let lead = "오늘 하려던 \(things(counts.planned))"
        let all = counts.planned > 1 ? "모두 " : ""
        var whole: String?
        if counts.done == counts.planned { whole = "\(lead)를 \(all)끝냈어요." }
        if counts.left == counts.planned { whole = "\(lead)가 아직 남았어요." }
        if counts.moved == counts.planned { whole = "\(lead)를 \(all)내일로 넘겼어요." }
        if let whole { return counts.waiting > 0 ? whole + " " + waitingAlone(counts.waiting, english: false) : whole }
        let first = counts.done > 0 ? "\(lead) 중 \(things(counts.done))를 끝냈어요." : "\(lead) 중 끝낸 건 아직 없어요."
        // Each clause as it joins the next ("남았고") and as it ends the sentence ("남았어요").
        var clauses: [(joins: String, ends: String)] = []
        if counts.left > 0 { clauses.append(("\(things(counts.left))가 남았고", "\(things(counts.left))가 남았어요")) }
        if counts.moved > 0 { clauses.append(("\(things(counts.moved))는 내일로 넘겼고", "\(things(counts.moved))는 내일로 넘겼어요")) }
        if counts.waiting > 0 {
            let who = ArisJosa.attach(alone(counts.waiting), "은", "는")
            clauses.append(("\(who) 확인을 기다리고", "\(who) 확인을 기다려요"))
        }
        let rest = clauses.dropLast().map(\.joins) + [clauses.last?.ends].compactMap { $0 }
        return first + " " + rest.joined(separator: ", ") + "."
    }

    private static func englishSentence(_ counts: ArisDayEnd.Counts) -> String {
        let planned = counts.planned
        let whole = planned == 1 ? "the one thing" : planned == 2 ? "both things" : "all \(number(planned)) things"
        var one: String?
        if counts.done == planned { one = "You finished \(whole) you planned for today." }
        if counts.left == planned { one = "\(whole.prefix(1).uppercased() + whole.dropFirst()) you planned for today \(planned == 1 ? "is" : "are") still open." }
        if counts.moved == planned { one = "You moved \(whole) you planned for today to tomorrow." }
        if let one { return counts.waiting > 0 ? one + " " + waitingAlone(counts.waiting, english: true) : one }
        let first = counts.done > 0 ? "You finished \(number(counts.done)) of the \(number(planned)) things you planned for today."
            : "You haven't finished any of the \(number(planned)) things you planned for today yet."
        var clauses: [String] = []
        if counts.left > 0 { clauses.append("\(number(counts.left)) \(counts.left == 1 ? "is" : "are") left") }
        if counts.moved > 0 { clauses.append("\(number(counts.moved)) moved to tomorrow") }
        if counts.waiting > 0 { clauses.append("\(number(counts.waiting)) \(counts.waiting == 1 ? "is" : "are") waiting for your OK") }
        let joined = clauses.count > 1 ? clauses.dropLast().joined(separator: ", ") + ", and " + (clauses.last ?? "") : clauses.joined()
        return first + " " + joined.prefix(1).uppercased() + joined.dropFirst() + "."
    }

    /// What waits, said on its own (after a sentence that has no "left" to hang it on).
    private static func waitingAlone(_ count: Int, english: Bool) -> String {
        guard english else { return "확인을 기다리는 일이 \(alone(count)) 있어요." }
        let word = number(count)
        return "\(word.prefix(1).uppercased() + word.dropFirst()) \(count == 1 ? "thing is" : "things are") waiting for your OK."
    }

    // MARK: - Numbers as they are said

    /// "다섯 가지", "스무 가지", "스물한 가지" (the recap counts with the same words: ArisRecapWords).
    static func things(_ count: Int) -> String { ArisRecapWords.things(count) }

    /// A count standing by itself: "하나", "둘", "열둘".
    static func alone(_ count: Int) -> String { ArisRecapWords.alone(count) }

    /// "three"; past twenty in figures.
    static func number(_ count: Int) -> String { ArisRecapWords.number(count) }

    // MARK: - The evening chip

    /// The chip's counts ("끝냄 3", "남음 2", "확인 1", "내일 4"): only the parts with something in them. With nothing
    /// planned, what was done anyway is counted in its place.
    static func chipCounts(_ counts: ArisDayEnd.Counts, english: Bool) -> [String] {
        let done = counts.planned > 0 ? counts.done : counts.extra
        let parts: [(Int, String)] = [(done, english ? "done" : "끝냄"), (counts.left, english ? "left" : "남음"),
                                      (counts.waiting, english ? "waiting" : "확인"), (counts.tomorrow, english ? "tomorrow" : "내일")]
        return parts.filter { $0.0 > 0 }.map { english ? "\($0.0) \($0.1)" : "\($0.1) \($0.0)" }
    }

    static func chipHelp(english: Bool) -> String { english ? "Show today's wrap-up" : "오늘 정리 보기" }
}
