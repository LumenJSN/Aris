//
//  ArisBrief.swift
//  Aris
//
//  The morning brief (design B, the owner's pick): three tiles in the open notch: the weather, the next thing on the
//  calendar today, and the soonest Canvas deadline still to hand in. It shows at the day's first unlock, or on
//  "브리핑 해줘". The facts come from aris-agent (/brief) and the calendar; this turns them into words.
//

import Foundation

struct ArisBrief: Equatable {
    struct Tile: Equatable {
        let label: String
        let big: String
        let detail: String
        /// The deadline is today: the tile stands out.
        var urgent = false
    }

    struct Event: Equatable {
        let start: Date
        let title: String
    }

    /// What a brief leaves in the history (which the AI reads later): not the Canvas titles, which others wrote.
    static let remembered = remembered(english: false)
    static func remembered(english: Bool) -> String { english ? "Showed the brief." : "브리핑을 보여줬어요." }

    /// The brief's name over its tiles and in the 기록 tab, in the language its tiles are in.
    static func name(english: Bool) -> String { english ? "Brief" : "브리핑" }

    let greeting: String
    let tiles: [Tile]
    /// One line for the history and for how long the notch stays open (the spoken line).
    let summary: String

    /// The same brief as one line to be spoken: commas and full stops, never the tiles' "·" (QA BUG-19).
    let spoken: String

    /// From aris-agent's /brief JSON (weather, due, dueCount, dueToday, announcements) and today's timed events.
    /// `english`: the tiles' words in English.
    static func make(facts: [String: Any], events: [Event], now: Date, calendar: Calendar = .current, english: Bool = false) -> ArisBrief {
        let locale = english ? "en_US" : "ko_KR"
        let time = formatter("H:mm", calendar, locale), day = formatter(english ? "EEEE, MMMM d" : "M월 d일 EEEE", calendar, locale)
        let hour = calendar.component(.hour, from: now)
        let hello = english ? (hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening")
            : (hour < 12 ? "좋은 아침이에요" : hour < 18 ? "좋은 오후예요" : "좋은 저녁이에요")
        let unread = facts["announcements"] as? Int ?? 0
        let news = unread > 0 ? (english ? "\(unread) new announcement\(unread == 1 ? "" : "s")" : "새 공지 \(unread)개") : nil
        let greeting = ([hello, day.string(from: now)] + [news].compactMap { $0 }).joined(separator: " · ")
        var said = [([hello, day.string(from: now)] + [news].compactMap { $0 }).joined(separator: ", ")]

        var tiles: [Tile] = []
        if let weather = facts["weather"] as? [String: Any], let temp = weather["temp"] as? Int {
            let rain = weather["rain"] as? Int ?? 0
            // aris-tools names the sky in Korean; with its code the English tiles say it in English (they read "맑음").
            let named = weather["sky"] as? String ?? ""
            let sky = english ? (weather["code"] as? Int).map { ArisWeatherCard.condition($0, english: true) } ?? named : named
            let place = weather["place"] as? String ?? (english ? "Weather" : "날씨")
            let umbrella = english ? "umbrella" : "우산"
            tiles.append(Tile(label: place, big: "\(temp)°", detail: rain >= 50 ? "\(sky) · \(english ? "rain" : "비") \(rain)% · \(umbrella)" : sky))
            said.append(english ? "\(place), \(temp) degrees, \(sky)" + (rain >= 50 ? ", \(rain)% chance of rain, take an umbrella" : "")
                        : "\(place) \(temp)도, \(sky)" + (rain >= 50 ? ", 비 올 확률 \(rain)%라 우산 챙기세요" : ""))
        }
        let later = events.filter { $0.start >= now && calendar.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
        if let next = later.first {
            let more = later.count > 1 ? (english ? " · \(later.count - 1) more" : " · 외 \(later.count - 1)개") : ""
            tiles.append(Tile(label: english ? "Next" : "다음 일정", big: time.string(from: next.start), detail: next.title + more))
            said.append(english ? "next, \(next.title) at \(time.string(from: next.start))" + (later.count > 1 ? ", and \(later.count - 1) more" : "")
                        : "다음 일정은 \(time.string(from: next.start)) \(next.title)" + (later.count > 1 ? ", 그 뒤로 \(later.count - 1)개 더" : ""))
        } else {
            tiles.append(Tile(label: english ? "Calendar" : "일정", big: english ? "None" : "없음", detail: english ? "Nothing more today" : "오늘 남은 일정 없어요"))
            said.append(english ? "nothing more on the calendar today" : "오늘 남은 일정은 없어요")
        }
        let iso = ISO8601DateFormatter()
        if let first = (facts["due"] as? [[String: Any]])?.first, let at = (first["at"] as? String).flatMap(iso.date(from:)) {
            let count = facts["dueCount"] as? Int ?? 1
            let isToday = calendar.isDate(at, inSameDayAs: now)
            // An older agent sends no dueToday: the soonest alone tells whether there is one today.
            let todayCount = facts["dueToday"] as? Int ?? (isToday ? 1 : 0)
            let tomorrow = calendar.isDate(at, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
            let when = isToday ? (english ? "today" : "오늘") : tomorrow ? (english ? "tomorrow" : "내일") : formatter("EEEE", calendar, locale).string(from: at)
            let course = first["course"] as? String ?? "", title = first["title"] as? String ?? ""
            let what = "\(course) \(title)".trimmingCharacters(in: .whitespaces)
            // "오늘 마감 N · 이번 주 M" (QA BUG-19): the soonest's day goes in the detail when it isn't today.
            tiles.append(Tile(label: english ? "\(todayCount) due today · \(count) this week" : "오늘 마감 \(todayCount) · 이번 주 \(count)",
                              big: time.string(from: at), detail: isToday ? what : "\(when) \(what)", urgent: isToday))
            said.append(english ? "\(todayCount) due today and \(count) this week, the first \(when) at \(time.string(from: at)), \(what)"
                        : "오늘 마감 \(todayCount)개, 이번 주 \(count)개, 가장 먼저 \(when) \(time.string(from: at)) \(what)")
        } else if facts["dueCount"] != nil {
            tiles.append(Tile(label: english ? "Due" : "마감", big: english ? "None" : "없음", detail: english ? "Nothing due this week" : "이번 주 남은 마감 없어요"))
            said.append(english ? "nothing due this week" : "이번 주 남은 마감은 없어요")
        }
        let spoken = said.joined(separator: ". ") + "."
        return ArisBrief(greeting: greeting, tiles: tiles, summary: spoken, spoken: spoken)
    }

    /// Once a day, from 5 in the morning: `last` is the day it last showed.
    static func isDue(last: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard calendar.component(.hour, from: now) >= 5 else { return false }
        return last.map { !calendar.isDate($0, inSameDayAs: now) } ?? true
    }

    private static func formatter(_ pattern: String, _ calendar: Calendar, _ locale: String = "ko_KR") -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter
    }
}
