//
//  ArisQuietHoursWords.swift
//  Aris
//
//  Quiet hours by voice and in Settings: what the user says to set them ("방해 금지 시간을 밤 11시부터 아침 8시로 바꿔
//  줘", "set quiet hours from 10 pm to 7 am", "방해 금지 시간 꺼 줘"), read on the Mac with no AI, what Aris answers
//  (the new hours, said back), and the Settings rows: the old choice with "직접 고르기", which shows a 시작 and a 끝
//  menu of every half hour. Only a sentence that names quiet hours and gives two times (or turns them off) counts:
//  "방해 금지 모드 켜 줘" is still macOS's Focus, the AI's to answer. Foundation only, so it is tested.
//

import Foundation

enum ArisQuietHoursAsk {
    /// What the sentence must name. "방해 금지" alone is macOS's Focus, so the times decide (see `parse`).
    private static let subjects = ["방해 금지 시간", "방해금지 시간", "방해 금지", "방해금지", "조용한 시간", "조용히 할 시간", "조용히 하는 시간",
                                   "밤에는 조용히", "quiet hours", "quiet time", "do not disturb hours", "do not disturb time", "night quiet"]
    /// Subjects that are quiet hours by themselves (they name the hours), so "… 꺼 줘" can turn them off.
    private static let hourSubjects = ["방해 금지 시간", "방해금지 시간", "조용한 시간", "조용히 할 시간", "조용히 하는 시간", "밤에는 조용히",
                                       "quiet hours", "quiet time", "do not disturb hours", "do not disturb time", "night quiet"]
    private static let offWords = ["꺼", "끄", "없애", "해제", "off", "disable", "remove", "no more"]
    private static let offSmall = ["아리스", "이제", "좀", "줘", "주세요", "줄래", "해", "을", "를", "은", "는", "기능", "aris", "please", "turn", "switch", "the", "my"]

    /// The value to store ("23-8", "22:30-6:00" or "off") when the words set quiet hours; nil when they ask anything
    /// else. `phrase`: as ArisIntent reads it (lowercased, end marks off, numbers as digits).
    static func parse(_ phrase: String) -> String? {
        guard subjects.contains(where: phrase.contains) else { return nil }
        let times = times(in: phrase)
        if times.count == 2, joinsTwoTimes(phrase) {
            let start = settled(times[0], isStart: true, other: times[1]), end = settled(times[1], isStart: false, other: times[0])
            return ArisQuietSpan.stored(start: start, end: end)
        }
        // "방해 금지 시간 꺼 줘", "turn off quiet hours": nothing else in the sentence.
        guard times.isEmpty, ArisIntentScope.isOnly(phrase, about: hourSubjects, with: offWords + offSmall),
              offWords.contains(where: phrase.contains) else { return nil }
        return ArisQuietHours.off
    }

    // MARK: - Times in a sentence

    /// A time as it was said: the hour as said (1...12, or 0...23), its minutes, and what was said about the part of
    /// the day.
    struct Said: Equatable {
        enum Part: Equatable { case morning, afternoon, evening, night, dawn, none }
        var hour: Int
        var minute: Int
        var part: Part
    }

    private static let koreanParts: [(String, Said.Part)] = [("오전", .morning), ("아침", .morning), ("오후", .afternoon), ("낮", .afternoon),
                                                              ("저녁", .evening), ("밤", .night), ("새벽", .dawn)]
    private static let koreanTime = #"(오전|아침|오후|낮|저녁|밤|새벽)?\s*(\d{1,2})\s*시\s*(반|(\d{1,2})\s*분)?|(자정|정오)"#
    private static let englishTime = #"\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?(?=\s|$|,)|\b(midnight|noon)\b"#

    /// Every time the phrase names, in order. Korean when it has any "N시", else English.
    static func times(in phrase: String) -> [Said] {
        let korean = matches(koreanTime, in: phrase).compactMap { groups -> Said? in
            if let word = groups[5] { return Said(hour: word == "자정" ? 0 : 12, minute: 0, part: word == "자정" ? .night : .afternoon) }
            guard let hour = groups[2].flatMap({ Int($0) }), (0...24).contains(hour) else { return nil }
            let minute = groups[3] == "반" ? 30 : groups[4].flatMap { Int($0) } ?? 0
            guard (0...59).contains(minute) else { return nil }
            return Said(hour: hour % 24, minute: minute, part: koreanParts.first { $0.0 == groups[1] }?.1 ?? .none)
        }
        if !korean.isEmpty { return korean }
        // "ten pm": an hour said as a word reads as its number.
        let hours = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
        let numbered = hours.enumerated().reduce(phrase) { text, hour in
            text.replacingOccurrences(of: "\\b" + hour.element + "\\b", with: "\(hour.offset + 1)", options: .regularExpression)
        }
        return matches(englishTime, in: numbered).compactMap { groups -> Said? in
            if let word = groups[4] { return Said(hour: word == "midnight" ? 0 : 12, minute: 0, part: word == "midnight" ? .night : .afternoon) }
            guard let hour = groups[1].flatMap({ Int($0) }), (0...24).contains(hour) else { return nil }
            let minute = groups[2].flatMap { Int($0) } ?? 0
            guard (0...59).contains(minute) else { return nil }
            let mark = groups[3]?.replacingOccurrences(of: ".", with: "")
            return Said(hour: hour % 24, minute: minute, part: mark == "am" ? .morning : mark == "pm" ? .afternoon : .none)
        }
    }

    /// The two times are a range: "…부터 …", "… ~ …", "from … to …", "between … and …".
    private static func joinsTwoTimes(_ phrase: String) -> Bool {
        ["부터", "에서", "~", "-", "–", " to ", " until ", " till ", " through ", " and "].contains(where: phrase.contains)
    }

    /// A said time as minutes from midnight. Quiet hours are a night: with nothing said about the part of the day, a
    /// start from 6 to 11 is the evening ("11시부터" is 23:00) and an end is the morning ("7시까지" is 07:00); 13 and up
    /// is the 24-hour clock as said.
    static func settled(_ said: Said, isStart: Bool, other: Said) -> Int {
        var hour = said.hour
        switch said.part {
        case .morning, .dawn: if hour == 12 { hour = 0 }
        case .afternoon, .evening: if hour < 12 { hour += 12 }
        case .night:
            // 밤 9시 is 21:00, 밤 12시 is midnight, 밤 1시 is 01:00.
            if (6...11).contains(hour) { hour += 12 } else if hour == 12 { hour = 0 }
        case .none:
            if isStart, (6...11).contains(hour) { hour += 12 } else if isStart, hour == 12 { hour = 0 }
        }
        return hour * 60 + said.minute
    }

    private static func matches(_ pattern: String, in text: String) -> [[String?]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } }
        }
    }
}

/// The lines about quiet hours: Aris's reply to a spoken change, and the Settings rows' words.
enum ArisQuietHoursCopy {
    private static func text(_ korean: String, _ english: String, _ inEnglish: Bool) -> String { inEnglish ? english : korean }

    /// A time as it is said back: "밤 11시", "아침 7시 30분"; "11 PM", "7:30 AM".
    static func said(_ minute: Int, english: Bool) -> String {
        let hour = minute / 60, minutes = minute % 60
        guard english else { return ArisKoreanClock.phrase(hour: hour, minute: minutes) }
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve)" + (minutes == 0 ? "" : ":" + (minutes < 10 ? "0" : "") + "\(minutes)") + (hour < 12 ? " AM" : " PM")
    }

    /// What Aris answers once the hours are stored: the hours as they now are, never just "바꿨어요".
    static func reply(stored: String, was: String, english: Bool) -> String {
        guard let edges = ArisQuietSpan.edges(stored) else {
            return ArisQuietSpan(stored: was) == nil
                ? text("방해 금지 시간은 이미 꺼져 있어요.", "Quiet hours are already off.", english)
                : text("방해 금지 시간을 껐어요. 이제 밤에도 소리 내서 알려요.", "Quiet hours are off. Aris will speak up at night too.", english)
        }
        let start = said(edges.start, english: english), end = said(edges.end, english: english)
        if edges.start == edges.end {
            return text("시작과 끝이 둘 다 \(start)라서 방해 금지 시간이 없어요. 꺼 둔 것과 같아요.",
                        "The start and the end are both \(start), so there are no quiet hours: it is the same as off.", english)
        }
        if ArisQuietSpan(stored: was) == ArisQuietSpan(stored: stored) {
            return text("방해 금지 시간은 이미 \(start)부터 \(end)까지예요.", "Quiet hours are already \(start) to \(end).", english)
        }
        return text("방해 금지 시간을 \(start)부터 \(end)까지로 바꿨어요.", "Quiet hours are now \(start) to \(end).", english)
    }

    // MARK: Settings rows (the pages are written in Korean; their English is looked up: ArisSettingsCopyMore)

    static let customLabel = "직접 고르기"
    static let startTitle = "시작"
    static let endTitle = "끝"
    static let sameTimes = "시작과 끝이 같아서 지금은 꺼져 있어요."

    /// A menu's time: "23:00" (the catalog says it as "11:00 PM" in English).
    static func menuLabel(_ minute: Int) -> String {
        (minute / 60 < 10 ? "0" : "") + ArisQuietSpan.clock(minute)
    }

    static func menuLabelEnglish(_ minute: Int) -> String {
        let hour = minute / 60, twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve):" + (minute % 60 < 10 ? "0" : "") + "\(minute % 60)" + (hour < 12 ? " AM" : " PM")
    }

    /// The rows' English, by their Korean (the settings pages look every string up).
    static var english: [String: String] {
        var pairs = [customLabel: "Custom", startTitle: "Start", endTitle: "End",
                     sameTimes: "The start and the end are the same, so quiet hours are off for now."]
        for minute in stride(from: 0, to: ArisQuietSpan.day, by: ArisQuietSpan.step) { pairs[menuLabel(minute)] = menuLabelEnglish(minute) }
        return pairs
    }
}

extension ArisQuietSettingsRows {
    /// The night hours' rows: the choice (끄기, the three nights, 직접 고르기) and, while 직접 고르기 is picked, the 시작
    /// and 끝 menus under it. `stored`: the hours as the preference holds them.
    static func hourRows(_ stored: String) -> [ArisSettingItem] {
        let picked = ArisQuietSpan.choice(for: stored)
        let options = ArisQuietHours.choices.map { ArisSettingOption(id: $0, title: ArisQuietCopy.hoursLabel($0, english: false)) }
            + [ArisSettingOption(id: ArisQuietSpan.custom, title: ArisQuietHoursCopy.customLabel)]
        let choice = ArisSettingItem(id: "aris.quietHours", icon: .symbol("moon"), title: ArisQuietCopy.hoursTitle(english: false),
                                     desc: ArisQuietCopy.hoursDesc(english: false), control: .choice(.quietHours, options, selected: picked))
        guard picked == ArisQuietSpan.custom, let edges = ArisQuietSpan.edges(stored) else { return [choice] }
        let menu = { (chosen: Int) in
            ArisQuietSpan.menuTimes(including: chosen).map { ArisSettingOption(id: ArisQuietSpan.clock($0), title: ArisQuietHoursCopy.menuLabel($0)) }
        }
        return [
            choice,
            ArisSettingItem(id: "aris.quietStart", icon: .symbol("sunset"), title: ArisQuietHoursCopy.startTitle,
                            control: .menu(.quietStart, menu(edges.start), selected: ArisQuietSpan.clock(edges.start)), indexed: false),
            ArisSettingItem(id: "aris.quietEnd", icon: .symbol("sunrise"), title: ArisQuietHoursCopy.endTitle,
                            desc: edges.start == edges.end ? ArisQuietHoursCopy.sameTimes : nil,
                            control: .menu(.quietEnd, menu(edges.end), selected: ArisQuietSpan.clock(edges.end)), indexed: false),
        ]
    }
}
