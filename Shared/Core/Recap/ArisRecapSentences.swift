//
//  ArisRecapSentences.swift
//  Shared/Core (app, tests)
//
//  Each sentence of the day's recap (ArisRecap), Korean first and the same in English; nil when it would have nothing
//  in it. Numbers are words, as they are said ("다섯 가지", "five"); a title is said at most once, cut short.
//  Foundation only.
//

import Foundation

struct ArisRecapSentences {
    let facts: ArisRecapFacts
    let fleet: ArisRecapFleet
    let today: Date
    let english: Bool
    let calendar: Calendar

    private typealias W = ArisRecapWords

    /// Korean clauses joined as one sentence: each one's joining form ("남았고") but the last's ending ("남았어요").
    private static func joined(_ clauses: [(joins: String, ends: String)]) -> String? {
        guard let last = clauses.last else { return nil }
        return (clauses.dropLast().map(\.joins) + [last.ends]).joined(separator: ", ") + "."
    }

    private static func sentence(_ parts: [String]) -> String? {
        parts.isEmpty ? nil : W.capitalized(W.and(parts)) + "."
    }

    // MARK: - The plan

    /// How much of what was planned got done, what is left and what was put off; nil with nothing planned.
    func plan() -> String? {
        let p = facts.plan
        guard p.planned > 0 else { return nil }
        if english {
            let whole = p.planned == 1 ? "the one thing" : p.planned == 2 ? "both things" : "all \(W.number(p.planned)) things"
            if p.done == p.planned { return "You finished \(whole) you planned for today." }
            if p.moved == p.planned { return "You moved \(whole) you planned for today to tomorrow." }
            let first = p.done > 0 ? "You finished \(W.number(p.done)) of the \(W.number(p.planned)) things you planned for today"
                : "You haven't finished any of the \(W.number(p.planned)) things you planned for today yet"
            var rest: [String] = []
            if p.left > 0 { rest.append("\(W.number(p.left)) \(p.left == 1 ? "is" : "are") left") }
            if p.moved > 0 { rest.append("\(W.number(p.moved)) moved to tomorrow") }
            return first + (rest.isEmpty ? "." : "; " + W.and(rest) + ".")
        }
        let lead = "오늘 하려던 \(W.things(p.planned))"
        let all = p.planned > 1 ? "모두 " : ""
        if p.done == p.planned { return "\(lead)를 \(all)끝냈어요." }
        if p.moved == p.planned { return "\(lead)를 \(all)내일로 넘겼어요." }
        var clauses = [p.done > 0 ? ("\(lead) 중 \(W.things(p.done))를 끝냈고", "\(lead) 중 \(W.things(p.done))를 끝냈어요")
                                  : ("\(lead) 중 끝낸 건 아직 없고", "\(lead) 중 끝낸 건 아직 없어요")]
        if p.left > 0 { clauses.append(("\(W.things(p.left))가 남았고", "\(W.things(p.left))가 남았어요")) }
        if p.moved > 0 { clauses.append(("\(W.things(p.moved))는 내일로 넘겼고", "\(W.things(p.moved))는 내일로 넘겼어요")) }
        return Self.joined(clauses)
    }

    /// What is left of the plan, by name when it is one or two things. Always says something.
    func left() -> String {
        let p = facts.plan
        let titles = p.leftTitles.prefix(2).map { W.title($0) }.filter { !$0.isEmpty }
        if english {
            guard p.planned > 0 else { return "Nothing was planned for today, so nothing is left." }
            guard p.left > 0 else { return p.moved > 0 ? "Everything you planned for today is done or moved to tomorrow." : "Everything you planned for today is done." }
            let lead = W.capitalized(W.counted(p.left, "thing is", "things are")) + " left today"
            if titles.isEmpty { return lead + "." }
            return lead + (titles.count == p.left ? ": " : ", including ") + W.and(titles) + "."
        }
        guard p.planned > 0 else { return "오늘 따로 남은 일은 없어요." }
        guard p.left > 0 else { return p.moved > 0 ? "오늘 하려던 일은 다 끝냈거나 내일로 넘겼어요." : "오늘 하려던 일은 다 끝냈어요." }
        if titles.isEmpty { return "오늘 남은 일은 \(W.ieyo(W.things(p.left)))." }
        let named = titles.joined(separator: ", ")
        return titles.count == p.left ? "오늘 남은 일은 \(named), 이렇게 \(W.ieyo(W.things(p.left)))." : "오늘 남은 일은 \(named) 등 \(W.ieyo(W.things(p.left)))."
    }

    // MARK: - What Aris did

    private static func noun(_ family: ArisRecordFamily, english: Bool) -> (ko: String, one: String, many: String) {
        switch family {
        case .files: return ("파일 작업", "file change", "file changes")
        case .calendar: return ("일정", "calendar item", "calendar items")
        case .todos: return ("할 일", "to-do", "to-dos")
        case .notes: return ("메모", "note", "notes")
        case .sent: return ("메시지 전송", "message sent", "messages sent")
        case .apps: return ("앱 작업", "app action", "app actions")
        case .controls: return ("설정 변경", "setting changed", "settings changed")
        case .sessions: return ("코딩 세션 지시", "instruction to a coding session", "instructions to coding sessions")
        case .other: return ("그 밖의 일", "other thing", "other things")
        }
    }

    /// The record's changes by kind (the two commonest named), or else what the activity log says was done unplanned.
    func didToday() -> String? {
        if let record = facts.record, record.total > 0 {
            // The number said is the number of rows the card lists under 그 밖 (`extra`): what is shown is what is said
            // (VM run 2026-11-19, D5: "다섯 가지" beside a list of six). The record only names the kinds, while they fit.
            let total = facts.extra
            guard total > 0 else { return nil }
            let order = ArisRecordFamily.allCases
            var named: [ArisRecordFamily] = [], covered = 0
            for family in order.filter({ $0 != .other && record.count($0) > 0 })
                .sorted(by: { (record.count($1), order.firstIndex(of: $0) ?? 0) < (record.count($0), order.firstIndex(of: $1) ?? 0) })
            where named.count < 2 && covered + record.count(family) <= total {
                named.append(family)
                covered += record.count(family)
            }
            if english {
                let list = named.map { family -> String in
                    let words = Self.noun(family, english: true)
                    return W.counted(record.count(family), words.one, words.many)
                }
                if list.isEmpty || covered < total {
                    let said = "Today I took care of " + W.counted(total, "thing", "things")
                    return said + (list.isEmpty ? "." : ", including " + W.and(list) + ".")
                }
                return "Today I took care of " + W.and(list) + "."
            }
            let list = named.map { Self.noun($0, english: false).ko + " " + W.alone(record.count($0)) }.joined(separator: ", ")
            if list.isEmpty { return "제가 오늘 \(W.things(total))를 처리했어요." }
            if covered < total { return "제가 오늘 \(list) 등 \(W.things(total))를 처리했어요." }
            return "제가 오늘 \(W.josa(list, "을", "를")) 처리했어요."
        }
        guard facts.extra > 0 else { return nil }
        if english {
            return facts.plan.planned > 0 ? W.capitalized(W.counted(facts.extra, "other thing", "other things")) + " got done too."
                : W.capitalized(W.counted(facts.extra, "thing", "things")) + " got done today."
        }
        return facts.plan.planned > 0 ? "그 밖에 \(W.things(facts.extra))를 더 했어요." : "오늘 한 일은 \(W.ieyo(W.things(facts.extra)))."
    }

    // MARK: - What finished, what is under way

    /// The jobs handed over that finished or didn't, and the coding sessions that wrapped up.
    func finished() -> String? {
        let t = facts.tasks
        if english {
            var parts: [String] = []
            if t.done > 0 { parts.append(W.counted(t.done, "job", "jobs") + " you handed over finished") }
            if t.failed > 0 { parts.append(W.counted(t.failed, "job", "jobs") + " didn't finish") }
            if fleet.finished > 0 {
                parts.append(W.counted(fleet.finished, "coding session", "coding sessions") + " wrapped up \(fleet.finished == 1 ? "its" : "their") work")
            }
            return Self.sentence(parts)
        }
        var clauses: [(joins: String, ends: String)] = []
        if t.done > 0 { clauses.append(("맡기신 일 \(W.josa(W.alone(t.done), "이", "가")) 끝났고", "맡기신 일 \(W.josa(W.alone(t.done), "이", "가")) 끝났어요")) }
        if t.failed > 0 {
            let lead = t.done > 0 ? "" : "맡기신 일 "
            clauses.append(("\(lead)\(W.josa(W.alone(t.failed), "은", "는")) 끝내지 못했고", "\(lead)\(W.josa(W.alone(t.failed), "은", "는")) 끝내지 못했어요"))
        }
        if fleet.finished > 0 {
            let who = "코딩 세션 " + W.josa(W.alone(fleet.finished), "이", "가")
            clauses.append(("\(who) 일을 마쳤고", "\(who) 일을 마쳤어요"))
        }
        return Self.joined(clauses)
    }

    /// The jobs still running and the coding sessions at work.
    func underWay() -> String? {
        let running = facts.tasks.running
        if english {
            var parts: [String] = []
            if running > 0 { parts.append(W.counted(running, "job", "jobs") + " you handed over \(running == 1 ? "is" : "are") still running") }
            if fleet.working > 0 { parts.append(W.counted(fleet.working, "coding session", "coding sessions") + " \(fleet.working == 1 ? "is" : "are") working") }
            return Self.sentence(parts)
        }
        var clauses: [(joins: String, ends: String)] = []
        if running > 0 {
            let who = "맡기신 일 " + W.josa(W.alone(running), "이", "가")
            clauses.append(("\(who) 아직 하는 중이고", "\(who) 아직 하는 중이에요"))
        }
        if fleet.working > 0 {
            let who = "코딩 세션 " + W.josa(W.alone(fleet.working), "이", "가")
            clauses.append(("\(who) 일하는 중이고", "\(who) 일하는 중이에요"))
        }
        return Self.joined(clauses)
    }

    // MARK: - What waits for the owner

    func waiting() -> String? {
        if english {
            var parts: [String] = []
            if facts.waiting > 0 { parts.append(W.counted(facts.waiting, "thing to OK", "things to OK")) }
            if fleet.asking > 0 { parts.append(W.counted(fleet.asking, "coding session with a question", "coding sessions with a question")) }
            if fleet.failed > 0 { parts.append(W.counted(fleet.failed, "coding session that stopped on an error", "coding sessions that stopped on an error")) }
            return parts.isEmpty ? nil : "Waiting on you: " + W.and(parts) + "."
        }
        var parts: [String] = []
        if facts.waiting > 0 { parts.append("확인하실 것 " + W.alone(facts.waiting)) }
        if fleet.asking > 0 { parts.append("답을 기다리는 코딩 세션 " + W.alone(fleet.asking)) }
        if fleet.failed > 0 { parts.append("오류로 멈춘 코딩 세션 " + W.alone(fleet.failed)) }
        return parts.isEmpty ? nil : "지금 기다리는 건 " + W.ieyo(parts.joined(separator: ", ")) + "."
    }

    func nothingWaits() -> String {
        english ? "Nothing is waiting for your OK." : "확인을 기다리는 건 없어요."
    }

    func nothingPlanned() -> String {
        english ? "Nothing was planned for today." : "오늘 따로 정해 둔 일은 없었어요."
    }

    func nothingAtAll() -> String {
        english ? "Nothing was planned or done today." : "오늘은 정한 일도 한 일도 없었어요."
    }

    func nothingNext() -> String {
        english ? "Nothing is set for tomorrow yet." : "내일은 아직 잡힌 일이 없어요."
    }

    // MARK: - What is next

    /// Tomorrow's first thing with a time (or how much tomorrow holds) and the nearest open deadline.
    func next() -> String? {
        if english {
            var parts: [String] = []
            if let thing = facts.tomorrowFirst {
                parts.append("tomorrow starts with \(W.title(thing.title)) at \(W.time(thing.at, english: true, calendar: calendar))")
            } else if facts.tomorrowCount > 0 {
                parts.append("tomorrow holds " + W.counted(facts.tomorrowCount, "thing", "things"))
            }
            if let thing = facts.deadline { parts.append("the nearest deadline is \(W.title(thing.title)) \(when(thing, english: true))") }
            return parts.isEmpty ? nil : W.capitalized(parts.joined(separator: ", and ")) + "."
        }
        var clauses: [(joins: String, ends: String)] = []
        if let thing = facts.tomorrowFirst {
            let start = "내일은 \(W.time(thing.at, english: false, calendar: calendar)) \(W.ro(W.title(thing.title)))"
            clauses.append(("\(start) 시작하고", "\(start) 시작해요"))
        } else if facts.tomorrowCount > 0 {
            clauses.append(("내일은 \(W.things(facts.tomorrowCount))가 있고", "내일은 \(W.things(facts.tomorrowCount))가 있어요"))
        }
        if let thing = facts.deadline {
            let title = W.title(thing.title)
            let line = "가장 가까운 마감은 \(when(thing, english: false)) \(W.ieyo(title))"
            clauses.append((line, line))
        }
        return Self.joined(clauses)
    }

    /// A deadline's day, with its time when it is today or tomorrow: "금요일", "내일 오후 11시 59분"; "on Friday",
    /// "tomorrow at 11:59 PM".
    private func when(_ thing: ArisRecapFacts.Thing, english: Bool) -> String {
        let day = W.day(thing.at, today: today, english: english, calendar: calendar)
        let soon = (calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: thing.at)).day ?? 9) <= 1
        let time = soon && thing.timed ? W.time(thing.at, english: english, calendar: calendar) : nil
        if english {
            let named = ["today", "tomorrow"].contains(day) ? day : "on " + day
            return named + (time.map { " at " + $0 } ?? "")
        }
        return day + (time.map { " " + $0 } ?? "")
    }
}
