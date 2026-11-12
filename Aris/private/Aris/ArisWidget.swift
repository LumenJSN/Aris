//
//  ArisWidget.swift
//  Aris
//
//  Answer widgets (the owner's pick B: the spoken line, then a card under it). An answer asks for a card with one fenced
//  block that only names it, ```aris-card {"type":"weather"} ```: aris-agent appends one when it saw the turn run
//  `aris-tools weather / timer / todo / music / stock / maps … --json` (ArisWidgetPick), and a brain may write one for
//  the calendar or what's playing, which it reads from the context. The block never carries a value: the app reads
//  every number and word on the card itself (Open-Meteo, Yahoo's chart and MapKit through aris-agent, EventKit,
//  Reminders, the timer, Now Playing), and the block is taken out of what is shown and said (ArisSpeakable). Only the
//  names to look up come through (a place, a symbol): shown, never acted on. One more card needs no value at all: a
//  permission of aris-agent's that is off (Full Disk Access for Messages, Mail and Notes; Screen Recording for the
//  screen), with a button that opens that list in System Settings. Pure, so the tests run it.
//

import Foundation

enum ArisWidgetKind: String, CaseIterable, Sendable {
    case weather, calendar, timer, music, todo, stock, map, permission, currency

    /// The card lists things an undo can take away again (a to-do added, an event made): after an undo its values
    /// are read once more, so it never goes on listing what was just undone. The others show something an undo doesn't
    /// touch, or follow their own model live (the timer, what's playing).
    var listsWhatUndoChanges: Bool { self == .todo || self == .calendar }
}

/// A permission of aris-agent's that a read needed and found off (QA after a macOS update: Notes, Mail and screen reads
/// failed with no word on why): which list in System Settings turns it back on, and the card's words. The list is one
/// of these two, never an address from an answer.
enum ArisPermissionPane: String, CaseIterable, Sendable {
    /// Full Disk Access: Messages, Mail and Notes.
    case disk
    /// Screen Recording: reading the screen.
    case screen

    /// The System Settings list the card's button opens.
    var settingsURL: String {
        "x-apple.systempreferences:com.apple.preference.security?" + (self == .disk ? "Privacy_AllFiles" : "Privacy_ScreenCapture")
    }

    func title(korean: Bool) -> String {
        switch self {
        case .disk: return korean ? "전체 디스크 접근 권한이 꺼져 있어요" : "Full Disk Access is off"
        case .screen: return korean ? "화면 기록 권한이 꺼져 있어요" : "Screen Recording is off"
        }
    }

    func detail(korean: Bool) -> String {
        switch self {
        case .disk:
            return korean ? "메시지·메일·메모를 읽으려면 Aris에 이 권한이 있어야 해요. macOS 업데이트 뒤에 꺼졌을 수 있어요. 목록에서 Aris를 켜 주세요."
                : "Reading Messages, Mail and Notes needs it for Aris. A macOS update may have turned it off: turn Aris on in the list."
        case .screen:
            return korean ? "화면을 읽으려면 Aris에 이 권한이 있어야 해요. macOS 업데이트 뒤에 꺼졌을 수 있어요. 목록에서 Aris를 켜 주세요."
                : "Reading the screen needs it for Aris. A macOS update may have turned it off: turn Aris on in the list."
        }
    }

    static func button(korean: Bool) -> String { korean ? "시스템 설정 열기" : "Open System Settings" }
}

/// The card an answer asked for: a kind from the closed list and, for the weather, a stock or a map, what to look up.
struct ArisWidgetRequest: Equatable, Sendable {
    let kind: ArisWidgetKind
    /// The weather somewhere other than home (nil is home); the map's place.
    var place: String?
    /// The stock's symbol or name, as the turn looked it up ("AAPL", "삼성전자").
    var symbol: String? = nil
    /// The map's start; nil is here.
    var from: String? = nil
    /// The permission card's list.
    var pane: ArisPermissionPane? = nil
    /// The calendar card's day, "yyyy-MM-dd" (ArisCalendarCardDay); nil is today.
    var day: String? = nil
}

enum ArisWidget {
    /// The fence's language tag (ArisWidgetPick writes the same one).
    static let tag = "aris-card"
    /// A block's body is a few dozen bytes; anything longer isn't one.
    static let longestBody = 512
    static let longestPlace = 60
    static let longestSymbol = 40
    static let longestMapPlace = 80

    /// The tag as a model may write it (QA BUG-51: "arис-card", with Cyrillic и and с): each letter or its Cyrillic, Greek
    /// or fullwidth lookalike, invisible format characters (zero widths) between them, any dash. Only for telling Aris's
    /// own tag; the block's JSON is read exactly as for the plain tag, so a lookalike unlocks nothing more.
    static let tagPattern: String = {
        let letters = ["[aаαａ]", "[rгｒ]", "[iіιиｉ]", "[sѕсｓ]", "[-‐‑‒–—−]", "[cсϲｃ]", "[aаαａ]", "[rгｒ]", "[dԁｄ]"]
        return letters.joined(separator: #"\p{Cf}*"#)
    }()

    private static let block = try! NSRegularExpression(pattern: #"(`{3,}|~{3,})[ \t]*"# + tagPattern + #"[ \t]*\n([\s\S]*?)\n?[ \t]*\1"#,
                                                         options: [.caseInsensitive])

    /// The marker a brain sometimes writes without its fence (seen live 2026-11-07): `aris-card` alone at the start of
    /// a line or after a space, then on the same line or the next only a one-line JSON object, or nothing. Never the word
    /// inside a sentence ("aris-card는…"), never inside a fence (a backtick comes before it there).
    private static let bare = try! NSRegularExpression(
        pattern: #"(?:^|(?<=[ \t]))"# + tagPattern + #"[ \t]*(?:\n[ \t]*)?(\{[^\n]{0,512}\})?[ \t]*$"#,
        options: [.caseInsensitive, .anchorsMatchLines])

    /// The card `answer` asks for: the last well-formed block wins (aris-agent's, appended after the brain's, so the
    /// place of the `aris-tools weather <place>` the turn ran comes before the one the brain wrote). An unfenced marker
    /// counts like a block. Nil when there is none, or none names a known kind.
    static func request(in answer: String) -> ArisWidgetRequest? {
        let range = NSRange(answer.startIndex..., in: answer)
        let bodies = (block.matches(in: answer, range: range).map { ($0.range.location, $0.range(at: 2)) }
            + bare.matches(in: answer, range: range).map { ($0.range.location, $0.range(at: 1)) })
            .sorted { $0.0 < $1.0 }
        let found = bodies.compactMap { _, bodyRange -> ArisWidgetRequest?? in
            guard bodyRange.location != NSNotFound, let body = Range(bodyRange, in: answer) else { return nil }
            let json = String(answer[body])
            if let request = request(json: json) { return .some(request) }
            // A known card whose place or symbol isn't one: no card at all, never an earlier block's city or stock.
            return isKnownKind(json) ? .some(nil) : nil
        }
        return found.last ?? nil
    }

    /// `text` with every unfenced marker (and the JSON after it) taken out, for what is shown and said. The fenced
    /// block is taken out where machine blocks are (ArisSpeakable).
    static func withoutBareCards(_ text: String) -> String {
        guard text.range(of: tagPattern, options: [.regularExpression, .caseInsensitive]) != nil || text.range(of: loneCardTag, options: .regularExpression) != nil else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = bare.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        // Any other fence tag or lone "…-card" token left on a line of its own is a tag, never words to show or say.
        return cleaned.replacingOccurrences(of: loneCardTag, with: "", options: .regularExpression)
    }

    /// A line holding only a "<word>-card" tag (an unknown or dangling one), a fence's opening included; never one a
    /// fence comes after (that is a block, taken out whole where machine blocks are).
    private static let loneCardTag = #"(?m)^[ \t]*(?:`{3,}|~{3,})?[ \t]*[\p{L}\p{Cf}]{1,12}[-‐‑‒–—−]\p{Cf}*[cсϲｃ]\p{Cf}*[aаαａ]\p{Cf}*[rгｒ]\p{Cf}*[dԁｄ][ \t]*$\n?(?![\s\S]*(?:`{3}|~{3}))"#

    private static func isKnownKind(_ json: String) -> Bool {
        guard json.utf8.count <= longestBody,
              let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let type = object["type"] as? String else { return false }
        return ArisWidgetKind(rawValue: type.lowercased()) != nil
    }

    /// What a turn's card is: the card and its place on any turn (the place is only looked up and shown, so a turn
    /// that saw the screen or outside text keeps it, the owner's ruling), its buttons only on a trusted one.
    static func presentation(in answer: String, untrusted: Bool) -> (request: ArisWidgetRequest, actions: Bool)? {
        request(in: answer).map { ($0, !untrusted) }
    }

    /// One block's body: a JSON object whose "type" is a known kind. Every other key is ignored. A weather block's
    /// "place" must read as a place name: one that doesn't makes no card (never the weather of somewhere else). A
    /// stock block needs its "symbol", a map block its "place" (and "from" reads as a place, or here).
    static func request(json: String) -> ArisWidgetRequest? {
        guard json.utf8.count <= longestBody,
              let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let type = object["type"] as? String, let kind = ArisWidgetKind(rawValue: type.lowercased()) else { return nil }
        switch kind {
        case .stock:
            return symbol(object["symbol"]).map { ArisWidgetRequest(kind: .stock, symbol: $0) }
        case .currency:
            // What was asked ("100 CNY CAD"), as the turn's `aris-tools currency` took it: aris-tools reads the rate again.
            return name(object["ask"], longest: longestPlace, extra: "").map { ArisWidgetRequest(kind: .currency, symbol: $0) }
        case .map:
            guard let place = mapPlace(object["place"]) else { return nil }
            if isHome(object["from"]) { return ArisWidgetRequest(kind: .map, place: place) }
            return mapPlace(object["from"]).map { ArisWidgetRequest(kind: .map, place: place, from: $0) }
        case .weather where !isHome(object["place"]):
            return place(object["place"]).map { ArisWidgetRequest(kind: kind, place: $0) }
        case .permission:
            return (object["pane"] as? String).flatMap(ArisPermissionPane.init(rawValue:)).map { ArisWidgetRequest(kind: .permission, pane: $0) }
        case .calendar:
            // The day the answer is about; one that isn't a date makes no card (never another day's).
            guard let raw = object["day"], !(raw is NSNull) else { return ArisWidgetRequest(kind: .calendar) }
            return ArisCalendarCardDay.valid(raw).map { ArisWidgetRequest(kind: .calendar, day: $0) }
        default:
            return ArisWidgetRequest(kind: kind)
        }
    }

    /// No place, an empty one, or "here" / "home" / "여기" / "집": the home weather.
    static func isHome(_ raw: Any?) -> Bool {
        guard let raw, !(raw is NSNull) else { return true }
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return text.isEmpty || ["here", "home", "여기", "집"].contains(text.lowercased())
    }

    /// A place name to look up: letters, digits, spaces and . , ' - · only, at most 60 characters, never starting with
    /// "-" (it goes to aris-tools as one argument). Nil for anything else, home words included (isHome).
    static func place(_ raw: Any?) -> String? { name(raw, longest: longestPlace, extra: "") }

    /// A map's place: as a weather place, up to 80 characters and with & too ("Central Library", "McDonald's").
    static func mapPlace(_ raw: Any?) -> String? { name(raw, longest: longestMapPlace, extra: "&") }

    /// A stock's symbol or name: as a place, up to 40 characters, with ^ = & too ("^GSPC", "KRW=X", "S&P500").
    static func symbol(_ raw: Any?) -> String? { name(raw, longest: longestSymbol, extra: "^=&") }

    private static func name(_ raw: Any?, longest: Int, extra: String) -> String? {
        guard !isHome(raw), let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.count <= longest, !text.hasPrefix("-") else { return nil }
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: " .,'-·" + extra))
        return text.unicodeScalars.allSatisfy(allowed.contains) ? text : nil
    }
}

// MARK: - Weather

/// The weather card's values, from aris-agent's POST /weather (aris-tools weather --json, Open-Meteo). Read as
/// outside data: a field out of range drops the card, an hour out of range drops that hour.
struct ArisWeatherCard: Equatable, Sendable, Codable {
    struct Hour: Equatable, Sendable, Codable {
        let label: String
        let code: Int
        let temp: Int
        let day: Bool
    }

    let place: String
    let temp: Int
    let code: Int
    let day: Bool
    let high: Int?
    let low: Int?
    /// 지금, then the next hours (six columns at most).
    let hours: [Hour]

    static let columns = 6

    static func parse(_ object: [String: Any], english: Bool = ArisUIWords.english, locale: Locale? = nil) -> ArisWeatherCard? {
        guard let place = (object["place"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty,
              let temp = degrees(object["temp"]), let code = weatherCode(object["code"]) else { return nil }
        let day = object["day"] as? Bool ?? true
        let later = (object["hours"] as? [[String: Any]] ?? []).compactMap { hour -> (Int, Int, Int, Bool)? in
            guard let at = hour["hour"] as? Int, (0...23).contains(at), let code = weatherCode(hour["code"]),
                  let temp = degrees(hour["temp"]) else { return nil }
            return (at, code, temp, hour["day"] as? Bool ?? true)
        }.prefix(columns - 1)
        let labels = hourLabels(later.map(\.0), english: english, locale: locale)
        let hours = [Hour(label: ArisUIWords.text("지금", "Now", english: english), code: code, temp: temp, day: day)]
            + zip(labels, later).map { Hour(label: $0, code: $1.1, temp: $1.2, day: $1.3) }
        return ArisWeatherCard(place: String(place.prefix(ArisWidget.longestPlace)), temp: temp, code: code, day: day,
                               high: degrees(object["high"]), low: degrees(object["low"]), hours: hours)
    }

    /// "오후 3시", "4시", "5시" …: the half of the day is said for the first hour and again when it changes.
    /// In English each hour is written whole, as the locale writes it: "3 PM", "4 PM", or "15", "16".
    static func hourLabels(_ hours: [Int], english: Bool = ArisUIWords.english, locale: Locale? = nil) -> [String] {
        if english {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            return hours.map { hour in
                let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour % 24)) ?? Date(timeIntervalSince1970: 0)
                return ArisUIDates.string(date, korean: "", template: "j", english: true, calendar: calendar, locale: locale)
            }
        }
        var previousHalf: Bool?
        return hours.map { hour in
            let afternoon = hour >= 12
            let clock = hour % 12 == 0 ? 12 : hour % 12
            defer { previousHalf = afternoon }
            return previousHalf == afternoon ? "\(clock)시" : "\(afternoon ? "오후" : "오전") \(clock)시"
        }
    }

    /// "최고 11° 최저 3°".
    var range: String? { range() }

    /// "최고 11° 최저 3°", "High 11° Low 3°".
    func range(english: Bool = ArisUIWords.english) -> String? {
        guard let high, let low else { return nil }
        return ArisUIWords.text("최고 \(high)° 최저 \(low)°", "High \(high)° Low \(low)°", english: english)
    }

    enum Sky: Equatable { case clear, partly, cloudy, fog, rain, snow, thunder }

    /// WMO weather codes, grouped for the card's gradients.
    static func sky(_ code: Int) -> Sky {
        switch code {
        case 0, 1: return .clear
        case 2: return .partly
        case 45, 48: return .fog
        case 51...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95...99: return .thunder
        default: return .cloudy
        }
    }

    /// The sky in a word (Open-Meteo's codes, as aris-tools names them).
    static func condition(_ code: Int, english: Bool = ArisUIWords.english) -> String {
        switch code {
        case 0: return ArisUIWords.text("맑음", "Clear", english: english)
        case 1: return ArisUIWords.text("대체로 맑음", "Mostly clear", english: english)
        case 2: return ArisUIWords.text("구름 조금", "Partly cloudy", english: english)
        case 3: return ArisUIWords.text("흐림", "Cloudy", english: english)
        case 45, 48: return ArisUIWords.text("안개", "Fog", english: english)
        case 51...57: return ArisUIWords.text("이슬비", "Drizzle", english: english)
        case 61, 63, 80...82: return ArisUIWords.text("비", "Rain", english: english)
        case 65: return ArisUIWords.text("강한 비", "Heavy rain", english: english)
        case 66, 67: return ArisUIWords.text("어는 비", "Freezing rain", english: english)
        case 71, 73, 77, 85, 86: return ArisUIWords.text("눈", "Snow", english: english)
        case 75: return ArisUIWords.text("많은 눈", "Heavy snow", english: english)
        case 95...99: return ArisUIWords.text("뇌우", "Thunderstorm", english: english)
        default: return ArisUIWords.text("흐림", "Cloudy", english: english)
        }
    }

    private static func degrees(_ raw: Any?) -> Int? {
        guard let value = (raw as? NSNumber)?.doubleValue, value.isFinite, (-90...60).contains(value) else { return nil }
        return Int(value.rounded())
    }

    private static func weatherCode(_ raw: Any?) -> Int? {
        guard let value = raw as? Int, (0...99).contains(value) else { return nil }
        return value
    }
}

// MARK: - Today's calendar

/// One event of today, as EventKit gave it.
struct ArisWidgetEvent: Equatable, Sendable, Codable {
    let start: Date
    let end: Date
    let title: String
    let location: String?
    let allDay: Bool
}

/// 오늘 일정: the day's events on a rail, the one on now or coming next marked (a still dot, never a pulse).
struct ArisCalendarCard: Equatable, Sendable {
    enum State: Equatable, Sendable { case past, next, later }

    struct Row: Equatable, Sendable {
        let time: String
        let title: String
        let sub: String?
        let state: State
        let chip: String?
    }

    let trailing: String
    let rows: [Row]
    /// Events past the rows shown.
    let more: Int
    /// The header ("오늘 일정", "내일 일정", "토요일 일정") and the line of a day with nothing on it.
    var title = ArisUIWords.text("오늘 일정", "Today")
    var empty = ArisUIWords.text("오늘은 일정이 없어요", "Nothing on the calendar today")

    static let mostRows = 5

    /// `day`: the day the answer is about (ArisCalendarCardDay); nil or today is today's card.
    static func make(_ events: [ArisWidgetEvent], now: Date, day: Date? = nil, calendar: Calendar = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> ArisCalendarCard {
        if let day, !calendar.isDate(day, inSameDayAs: now) {
            return make(events, of: calendar.startOfDay(for: day), now: now, calendar: calendar, english: english, locale: locale)
        }
        let today = events.filter { $0.allDay || calendar.isDate($0.start, inSameDayAs: now) || ($0.start < now && now < $0.end) }
            .sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
        let next = today.firstIndex { !$0.allDay && $0.end > now }
        // Past events give way first when the day is longer than the card.
        let start = max(0, min(next ?? today.count, today.count - mostRows))
        let shown = today.dropFirst(start).prefix(mostRows)
        let rows = shown.enumerated().map { offset, event -> Row in
            let index = start + offset
            let state: State = event.allDay ? .later : index == next ? .next : event.end <= now ? .past : .later
            return Row(time: event.allDay ? ArisUIWords.text("종일", "All day", english: english) : format(event.start, "HH:mm", calendar),
                       title: event.title.isEmpty ? ArisUIWords.text("제목 없음", "No title", english: english) : event.title,
                       sub: event.location.flatMap { $0.isEmpty ? nil : $0 },
                       state: state, chip: state == .next ? chip(event, now: now, english: english, locale: locale) : nil)
        }
        let date = ArisUIDates.string(now, korean: "M월 d일 EEEE", template: "MMMdEEEE", english: english, calendar: calendar, locale: locale)
        let counted = ArisUIWords.text("\(date) · \(today.count)개", "\(date) · \(today.count)", english: english)
        return ArisCalendarCard(trailing: today.isEmpty ? date : counted, rows: rows, more: today.count - rows.count - start,
                                title: ArisUIWords.text("오늘 일정", "Today", english: english),
                                empty: ArisUIWords.text("오늘은 일정이 없어요", "Nothing on the calendar today", english: english))
    }

    /// Another day's card: that day's events (all-day ones first), all ahead of now or all behind it, no chip.
    private static func make(_ events: [ArisWidgetEvent], of start: Date, now: Date, calendar: Calendar, english: Bool, locale: Locale?) -> ArisCalendarCard {
        let ahead = start > now
        let that = events.filter { calendar.isDate($0.start, inSameDayAs: start) || ($0.start < start && $0.end > start) }
            .sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
        let rows = that.prefix(mostRows).map { event in
            Row(time: event.allDay || event.start < start ? ArisUIWords.text("종일", "All day", english: english) : format(event.start, "HH:mm", calendar),
                title: event.title.isEmpty ? ArisUIWords.text("제목 없음", "No title", english: english) : event.title,
                sub: event.location.flatMap { $0.isEmpty ? nil : $0 }, state: ahead ? .later : .past, chip: nil)
        }
        let date = ArisUIDates.string(start, korean: "M월 d일 EEEE", template: "MMMdEEEE", english: english, calendar: calendar, locale: locale)
        let counted = ArisUIWords.text("\(date) · \(that.count)개", "\(date) · \(that.count)", english: english)
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: start).day ?? 0
        let weekday = ArisUIDates.string(start, korean: "EEEE", template: "EEEE", english: english, calendar: calendar, locale: locale)
        let title = offset == 1 ? ArisUIWords.text("내일 일정", "Tomorrow", english: english)
            : offset == -1 ? ArisUIWords.text("어제 일정", "Yesterday", english: english)
            : ArisUIWords.text("\(weekday) 일정", weekday, english: english)
        let empty = offset == 1 ? ArisUIWords.text("내일은 일정이 없어요", "Nothing on the calendar tomorrow", english: english)
            : ArisUIWords.text("이날은 일정이 없어요", "Nothing on the calendar that day", english: english)
        return ArisCalendarCard(trailing: that.isEmpty ? date : counted, rows: Array(rows), more: that.count - rows.count, title: title, empty: empty)
    }

    /// "진행 중", "25분 뒤", "2시간 뒤", "1시간 20분 뒤".
    static func chip(_ event: ArisWidgetEvent, now: Date, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        guard event.start > now else { return ArisUIWords.text("진행 중", "Now", english: english) }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if english { return "in " + ArisUIDates.length(minutes: minutes, locale: locale) }
        if minutes < 60 { return "\(minutes)분 뒤" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)시간 뒤" : "\(hours)시간 \(rest)분 뒤"
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

// MARK: - To-dos

/// 할 일: the open reminders, soonest first.
struct ArisTodoCard: Equatable, Sendable, Codable {
    struct Row: Equatable, Sendable, Codable {
        let title: String
        let sub: String
        let due: String?
        /// Due today or overdue: the due date is in the warm colour.
        let urgent: Bool
    }

    let rows: [Row]
    let total: Int

    static let mostRows = 5

    static func make(_ items: [ArisTodoItem], now: Date, calendar: Calendar = .current) -> ArisTodoCard {
        let ordered = items.sorted { ($0.due ?? .distantFuture, $0.title) < ($1.due ?? .distantFuture, $1.title) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let rows = ordered.prefix(mostRows).map { item in
            Row(title: item.title, sub: item.listName, due: item.due.map { dueText($0, hasTime: item.hasTime, now: now, calendar: calendar) },
                urgent: item.due.map { $0 < tomorrow } ?? false)
        }
        return ArisTodoCard(rows: rows, total: items.count)
    }

    /// "오늘 23:59", "내일", "목요일", "11월 20일".
    static func dueText(_ due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        if english {
            // "Today 23:59", "Tomorrow", "Thursday", "Nov 20": the locale writes the day and the date.
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
            let time = hasTime ? " " + ArisUIDates.string(due, korean: "", template: "Hmm", english: true, calendar: calendar, locale: locale) : ""
            switch days {
            case 0: return "Today" + time
            case 1: return "Tomorrow" + time
            case -1: return "Yesterday" + time
            case 2...6: return ArisUIDates.string(due, korean: "", template: "EEEE", english: true, calendar: calendar, locale: locale)
            default: return ArisUIDates.day(due, english: true, calendar: calendar, locale: locale)
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = calendar.timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        formatter.dateFormat = "HH:mm"
        let time = hasTime ? " " + formatter.string(from: due) : ""
        switch days {
        case 0: return "오늘" + time
        case 1: return "내일" + time
        case -1: return "어제" + time
        case 2...6:
            formatter.dateFormat = "EEEE"
            return formatter.string(from: due)
        default:
            formatter.dateFormat = "M월 d일"
            return formatter.string(from: due)
        }
    }
}

// MARK: - Timer and music

extension ArisTimerState {
    /// The card's small line: "집중 타이머 · 25분", "타이머 · 10분 · 멈춤".
    var cardLabel: String { cardLabel() }

    /// "Focus timer · 25 min", "Timer · 10 min · paused".
    func cardLabel(english: Bool = ArisUIWords.english) -> String {
        let minutes = max(1, (total + 59) / 60)
        let name: String
        switch phase {
        case .plain: name = ArisUIWords.text("타이머", "Timer", english: english)
        case .focus: name = cycle ? ArisUIWords.text("집중 \(round)/\(Self.rounds)", "Focus \(round)/\(Self.rounds)", english: english) : ArisUIWords.text("집중 타이머", "Focus timer", english: english)
        case .rest: name = ArisUIWords.text("휴식", "Break", english: english)
        }
        let paused = isPaused ? ArisUIWords.text(" · 멈춤", " · paused", english: english) : ""
        return ArisUIWords.text("\(name) · \(minutes)분", "\(name) · \(minutes) min", english: english) + paused
    }

    /// The share of time left, 0…1 (the ring and the bar).
    func remaining(at now: Date) -> Double { 1 - progress(at: now) }
}

/// What's playing, as Now Playing reports it: enough to place the progress at any moment without asking again.
struct ArisMusicCardState: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let playing: Bool
    let duration: TimeInterval
    /// The position at `at`, moving at `rate` while playing.
    let elapsed: TimeInterval
    let at: Date
    let rate: Double
    /// "Apple Music", "Spotify"; nil for anything else.
    let source: String?

    func position(at now: Date) -> TimeInterval {
        let moved = playing ? max(0, now.timeIntervalSince(at)) * rate : 0
        return duration > 0 ? min(duration, max(0, elapsed + moved)) : max(0, elapsed + moved)
    }

    /// "NewJeans · OMG".
    var byline: String { [artist, album].filter { !$0.isEmpty }.joined(separator: " · ") }

    static func source(bundle: String?) -> String? {
        switch bundle {
        case "com.apple.Music": return "Apple Music"
        case "com.spotify.client": return "Spotify"
        default: return nil
        }
    }

    /// "3:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
