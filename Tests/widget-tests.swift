// Tests for the answer widgets (the owner's pick B): the aris-card block, the agent's pick from the commands it saw, the
// stripping from what is shown and said, and the cards' values. Called from main.swift; uses its check().
import Foundation

func runWidgetTests() {
    widgetBlockTests()
    widgetStrippingTests()
    widgetPickTests()
    weatherCardTests()
    calendarCardTests()
    todoCardTests()
    timerAndMusicCardTests()
    widgetPromptTests()
    placeLookupTests()
}

// MARK: - Place names (aris-tools weather 서울)

private func placeLookupTests() {
    check(ArisWeather.searchNames("서울") == ["Seoul", "서울"] && ArisWeather.searchNames("서울특별시") == ["Seoul", "서울특별시"]
          && ArisWeather.searchNames("서울시") == ["Seoul", "서울시"], "place: 서울 is looked up as Seoul (Open-Meteo has no 서울)")
    check(ArisWeather.searchNames("부산") == ["Busan", "부산"] && ArisWeather.searchNames("부산광역시") == ["Busan", "부산광역시"],
          "place: 부산 is looked up as Busan (Open-Meteo's 부산 is a mountain)")
    check(ArisWeather.searchNames("올랜도") == ["올랜도"] && ArisWeather.searchNames("도쿄") == ["도쿄"] && ArisWeather.searchNames("Seoul") == ["Seoul"],
          "place: other names go as said (Open-Meteo finds 올랜도 and 도쿄 with language=ko)")
    check(ArisWeather.searchNames("시") == ["시"], "place: a bare suffix isn't cut to nothing")
    check(ArisWeather.geocodeURL(name: "도쿄", korean: true).absoluteString.contains("language=ko")
          && ArisWeather.geocodeURL(name: "Tokyo", korean: false).absoluteString.contains("language=en"), "place: Korean names search in Korean")
    // Open-Meteo's replies for 부산 (a mountain first), 올랜도 and 도쿄, trimmed.
    let decode = { (json: String) in (try? JSONDecoder().decode(ArisWeather.GeoReply.self, from: Data(json.utf8)))?.results ?? [] }
    let busan = decode(#"{"results":[{"name":"부산","latitude":37.04,"longitude":128.07,"feature_code":"MT","timezone":"Asia/Seoul"},{"name":"부산","latitude":35.1,"longitude":129.04,"feature_code":"PPLA","population":3678555,"timezone":"Asia/Seoul"},{"name":"부산리","latitude":36,"longitude":127,"feature_code":"PPL","population":200,"timezone":"Asia/Seoul"}]}"#)
    check(ArisWeather.best(busan)?.latitude == 35.1, "place: the city, never a mountain of the same name")
    let orlando = decode(#"{"results":[{"name":"올랜도","latitude":43.70643,"longitude":-79.39864,"feature_code":"PPLA","population":2794356,"timezone":"America/New_York"}]}"#)
    check(ArisWeather.best(orlando)?.timezone == "America/New_York", "place: 올랜도")
    let tokyo = decode(#"{"results":[{"name":"도쿄","latitude":35.6895,"longitude":139.69171,"feature_code":"PPLC","population":9733276,"timezone":"Asia/Tokyo"}]}"#)
    check(ArisWeather.best(tokyo)?.name == "도쿄" && ArisWeather.best(tokyo)?.timezone == "Asia/Tokyo", "place: 도쿄")
    let seoul = decode(#"{"results":[{"name":"서울특별시","latitude":37.566,"longitude":126.9784,"feature_code":"PPLC","population":10349312,"timezone":"Asia/Seoul"}]}"#)
    check(ArisWeather.best(seoul)?.name == "서울특별시" && decode(#"{"generationtime_ms":0.15}"#).isEmpty, "place: 서울 as Seoul; no hit is no place")
    let lone = decode(#"{"results":[{"name":"Mont Blanc","latitude":45.8,"longitude":6.9,"feature_code":"MT","timezone":"Europe/Paris"}]}"#)
    check(ArisWeather.best(lone)?.name == "Mont Blanc" && ArisWeather.best([]) == nil, "place: with no town, the first hit")
}

private func block(_ json: String, fence: String = "```") -> String { "\(fence)aris-card\n\(json)\n\(fence)" }

// MARK: - The block

private func widgetBlockTests() {
    check(ArisWidget.request(in: "올랜도는 맑아요.\n\n" + block(#"{"type":"weather","place":"Orlando"}"#)) == ArisWidgetRequest(kind: .weather, place: "Orlando"),
          "widget: a weather block names the kind and the place")
    // Stock and map blocks need what to look up (stock-map-tests.swift), a permission block its list (qa-final4-tests.swift),
    // a currency block what was asked (fx-tests.swift).
    for kind in ArisWidgetKind.allCases where kind != .stock && kind != .map && kind != .permission && kind != .currency {
        check(ArisWidget.request(in: "한 줄.\n" + block(#"{"type":"\#(kind.rawValue)"}"#))?.kind == kind, "widget: \(kind.rawValue) is a kind")
    }
    check(ArisWidget.request(in: block(#"{"type":"Weather"}"#))?.kind == .weather, "widget: the type's case doesn't matter")
    check(ArisWidget.request(in: block(#"{"type":"crypto"}"#)) == nil, "widget: an unknown type is no card")
    check(ArisWidget.request(in: block(#"{"kind":"weather"}"#)) == nil, "widget: a block without a type is no card")
    check(ArisWidget.request(in: block(#"{"type":"weather""#)) == nil, "widget: broken JSON is no card")
    check(ArisWidget.request(in: block(#"["weather"]"#)) == nil, "widget: an array is no card")
    check(ArisWidget.request(in: "```json\n{\"type\":\"weather\"}\n```") == nil, "widget: only an aris-card fence asks for a card")
    check(ArisWidget.request(in: "날씨 {\"type\":\"weather\"}") == nil, "widget: bare JSON in the prose asks for nothing")
    check(ArisWidget.request(in: "날씨예요.") == nil, "widget: plain prose has no card")
    check(ArisWidget.request(in: block(#"{"type":"timer"}"#, fence: "~~~"))?.kind == .timer, "widget: a ~~~ fence works too")
    let both = "한 줄.\n" + block(#"{"type":"music"}"#) + "\n\n" + block(#"{"type":"weather"}"#)
    check(ArisWidget.request(in: both)?.kind == .weather, "widget: the last block wins (the agent's, appended after the brain's)")
    check(ArisWidget.request(in: "한 줄.\n" + block(#"{"type":"todo"}"#) + "\n" + block(#"{"type":"nope"}"#))?.kind == .todo,
          "widget: a broken later block doesn't hide a good one")
    let long = #"{"type":"weather","note":""# + String(repeating: "x", count: 600) + #""}"#
    check(ArisWidget.request(in: block(long)) == nil, "widget: a long body isn't a card block")
    // Values the model writes are never read: only the kind (and a place name) come through.
    let stuffed = ArisWidget.request(in: block(#"{"type":"weather","temp":99,"place":"Seoul","hours":[1,2]}"#))
    check(stuffed == ArisWidgetRequest(kind: .weather, place: "Seoul"), "widget: numbers in the block are ignored")
    check(ArisWidget.request(in: block(#"{"type":"calendar","place":"Seoul"}"#))?.place == nil, "widget: a place only for the weather")
    // The owner's ruling (2026-11-04: a Seoul answer showed Orlando): the place is only looked up and shown, so a screen turn
    // keeps it; only the buttons go.
    let seoulOnScreen = ArisWidget.presentation(in: ArisWidgetPick.attach(to: "서울은 지금 10도쯤이에요.", commands: ["/t weather Seoul --ko"], tools: "/t"),
                                                untrusted: true)
    check(seoulOnScreen?.request == ArisWidgetRequest(kind: .weather, place: "Seoul") && seoulOnScreen?.actions == false,
          "widget: a screen turn about Seoul gets Seoul's card, without buttons")
    let brainSeoul = ArisWidget.presentation(in: "서울은 10도예요.\n" + block(#"{"type":"weather","place":"서울"}"#), untrusted: true)
    check(brainSeoul?.request.place == "서울", "widget: with no weather command seen, the brain's place is kept on a screen turn too")
    check(ArisWidget.presentation(in: block(#"{"type":"timer"}"#), untrusted: false)?.actions == true, "widget: a trusted turn's card has its buttons")
    let brainBusan = "서울은 10도예요.\n" + block(#"{"type":"weather","place":"Busan"}"#)
    check(ArisWidget.request(in: ArisWidgetPick.attach(to: brainBusan, commands: ["/t weather Seoul"], tools: "/t"))?.place == "Seoul",
          "widget: the place the turn's command looked up comes before the brain's")
    // A place that can't be resolved: no card, never another city (home or an earlier block's).
    check(ArisWidget.request(in: block(#"{"type":"weather","place":"<script>"}"#)) == nil
          && ArisWidget.request(in: block(#"{"type":"weather","place":"--days"}"#)) == nil
          && ArisWidget.request(in: block(#"{"type":"weather","place":42}"#)) == nil, "widget: an unresolvable place makes no card, not home's")
    check(ArisWidget.request(in: block(#"{"type":"weather","place":"Busan"}"#) + "\n" + block(#"{"type":"weather","place":"$(x)"}"#)) == nil,
          "widget: a last block with a bad place isn't covered by an earlier city")
    check(ArisWidget.request(in: block(#"{"type":"weather","place":"여기"}"#)) == ArisWidgetRequest(kind: .weather)
          && ArisWidget.request(in: block(#"{"type":"weather","place":null}"#)) == ArisWidgetRequest(kind: .weather), "widget: here or no place is home")
    check(ArisWidgetPick.weatherArguments(request: ["place": "Seoul"]) == ["weather", "Seoul", "--json"]
          && ArisWidgetPick.weatherArguments(request: [:]) == ["weather", "--json"]
          && ArisWidgetPick.weatherArguments(request: ["place": NSNull()]) == ["weather", "--json"]
          && ArisWidgetPick.weatherArguments(request: ["place": "a;b"]) == nil && ArisWidgetPick.weatherArguments(request: ["place": 7]) == nil,
          "widget: POST /weather refuses a place that isn't one instead of giving home's weather")
    check(ArisWeatherCard.parse([:]) == nil, "widget: a refused or failed lookup ({}) shows no card")
    for bad in ["--days", "-x", "a;rm -rf", "$(say hi)", "<b>", String(repeating: "가", count: 61), "here", "여기", "", "   "] {
        check(ArisWidget.place(bad) == nil, "widget: \"\(bad.prefix(12))\" is no place")
    }
    for good in ["Seoul", "올랜도", "New York", "St. John's", "Saint-Étienne", "서울 강남구"] {
        check(ArisWidget.place(good) == good, "widget: \"\(good)\" is a place")
        check(ArisWidgetPick.place(good) == good, "widget: the agent reads \"\(good)\" as the app does")
    }
    for bad in ["--days", "a;b", "$(x)", String(repeating: "a", count: 61)] {
        check(ArisWidgetPick.place(bad) == nil, "widget: the agent refuses \"\(bad.prefix(12))\" as the app does")
    }
    check(ArisWidget.place(42) == nil && ArisWidgetPick.place(nil) == nil, "widget: a place is a string")
    check(ArisWidgetPick.weatherArguments(place: nil) == ["weather", "--json"]
          && ArisWidgetPick.weatherArguments(place: "New York") == ["weather", "New York", "--json"],
          "widget: POST /weather runs aris-tools weather [place] --json, the place one argument")
}

// MARK: - Stripping

private func widgetStrippingTests() {
    let answer = "올랜도는 지금 8도이고 맑아요.\n\n" + block(#"{"type":"weather","place":"Orlando"}"#)
    check(ArisSpeakable.shown(answer, korean: true) == "올랜도는 지금 8도이고 맑아요.", "widget: the block never shows")
    check(ArisSpeakable.shown(answer, korean: true, say: .keep) == "올랜도는 지금 8도이고 맑아요.", "widget: not even on an untrusted turn")
    check(ArisSpeakable.speakable(answer) == "올랜도는 지금 8도이고 맑아요.", "widget: the block is never said")
    check(ArisSpeakable.fullReading(answer, korean: true) == ["올랜도는 지금 8도이고 맑아요."], "widget: 읽어줘 doesn't read it either")
    let tagged = "<say>일정이 세 개예요.</say>\n9시 수업, 1시 튜토리얼, 4시 회의가 있어요.\n" + block(#"{"type":"calendar"}"#)
    check(ArisSpeakable.shown(tagged, korean: true) == "9시 수업, 1시 튜토리얼, 4시 회의가 있어요.", "widget: a say-line answer shows without the block")
    check(ArisAgentStream.spoken(answer).hasSuffix(block(#"{"type":"weather","place":"Orlando"}"#)),
          "widget: the agent passes the block through unchanged, so the app can read it")
    check(ArisDispatch.parse(answer, teammateIds: []) == nil, "widget: a card block is never a jobs block")
    let attached = ArisWidgetPick.attach(to: "타이머 25분 맞췄어요.", commands: ["/t timer 25"], tools: "/t")
    check(ArisSpeakable.shown(attached, korean: true) == "타이머 25분 맞췄어요." && ArisSpeakable.speakable(attached) == "타이머 25분 맞췄어요.",
          "widget: the agent's block is taken out of what is shown and said")
    check(ArisSpeakable.holdPoint(in: attached).map { attached[..<$0].trimmingCharacters(in: .whitespacesAndNewlines) } == "타이머 25분 맞췄어요.",
          "widget: the voice holds at the block while it streams")
}

// MARK: - The agent's pick

private func widgetPickTests() {
    let pick = { (commands: [String]) in ArisWidgetPick.card(commands: commands, tools: "/t") }
    check(pick(["/t weather"]) == ["type": "weather"], "pick: weather at home")
    check(pick(["/t weather Orlando --ko"]) == ["type": "weather", "place": "Orlando"], "pick: the place it looked up, flags left out")
    check(pick(["/t weather --days 3 \"New York\" --en"]) == ["type": "weather", "place": "New York"], "pick: --days takes its number with it")
    check(pick(["/bin/zsh -lc '/t timer 25 --focus'"]) == ["type": "timer"], "pick: Codex's wrapped command")
    check(pick(["/t timer stop"]) == nil, "pick: a stopped timer has no card")
    check(pick(["/t todo"]) == ["type": "todo"] && pick(["/t todo add \"우유 사기\""]) == ["type": "todo"], "pick: to-dos, listed or changed")
    check(pick(["/t music next"]) == ["type": "music"], "pick: music")
    check(pick(["/Users/p/.config/aris/aris-tools todo"]) == ["type": "todo"], "pick: aris-tools by its full path")
    check(pick(["cd /tmp && /t weather Seoul"]) == ["type": "weather", "place": "Seoul"], "pick: a chained command")
    check(pick(["/t calendar", "/t event x --start \"2026-11-05 10:00\"", "ls", "/t remember x"]) == nil, "pick: other commands earn no card")
    check(pick(["/t weather", "/t timer 5"]) == ["type": "timer"], "pick: the last command wins")
    check(pick(["/t weather $(cat ~/x)"]) == nil, "pick: shell syntax is never read")
    check(ArisWidgetPick.attach(to: "네.", commands: ["ls"], tools: "/t") == "네.", "pick: no card leaves the answer alone")
    let attached = ArisWidgetPick.attach(to: "올랜도는 맑아요.", commands: ["/t weather Orlando"], tools: "/t")
    check(ArisWidget.request(in: attached) == ArisWidgetRequest(kind: .weather, place: "Orlando"), "pick: the app reads the agent's block")
    check(ArisWidgetPick.tag == ArisWidget.tag, "pick: the agent and the app use the same fence tag")
    let theirs = "한 줄.\n" + block(#"{"type":"music"}"#)
    check(ArisWidget.request(in: ArisWidgetPick.attach(to: theirs, commands: ["/t todo"], tools: "/t"))?.kind == .todo,
          "pick: what the turn ran wins over what the brain wrote")
}

// MARK: - Weather

private func weatherCardTests() {
    let json: [String: Any] = ["place": "올랜도", "temp": 8.4, "code": 0, "day": true, "high": 11, "low": 3,
                               "hours": [["hour": 15, "code": 0, "temp": 10, "day": true], ["hour": 16, "code": 2, "temp": 11, "day": true],
                                         ["hour": 17, "code": 2, "temp": 10, "day": true], ["hour": 18, "code": 3, "temp": 8, "day": false],
                                         ["hour": 19, "code": 0, "temp": 6, "day": false], ["hour": 20, "code": 0, "temp": 5, "day": false]]]
    let card = ArisWeatherCard.parse(json)
    check(card?.place == "올랜도" && card?.temp == 8 && card?.range == "최고 11° 최저 3°", "weather card: now, high and low")
    check(card?.hours.map(\.label) == ["지금", "오후 3시", "4시", "5시", "6시", "7시"], "weather card: 지금 then the next five hours: \(card?.hours.map(\.label) ?? [])")
    check(card?.hours.first?.temp == 8 && card?.hours[4].day == false && card?.hours[3].day == true, "weather card: 지금 is now; night hours are marked")
    check(ArisWeatherCard.hourLabels([10, 11, 12, 13]) == ["오전 10시", "11시", "오후 12시", "1시"]
          && ArisWeatherCard.hourLabels([22, 23, 0, 1]) == ["오후 10시", "11시", "오전 12시", "1시"], "weather card: the half of the day is said again when it turns")
    var bad = json
    bad["temp"] = 400
    check(ArisWeatherCard.parse(bad) == nil, "weather card: an impossible temperature drops the card")
    bad = json
    bad["code"] = "sunny"
    check(ArisWeatherCard.parse(bad) == nil, "weather card: a code that isn't a number drops the card")
    check(ArisWeatherCard.parse(["temp": 3, "code": 0]) == nil && ArisWeatherCard.parse(["place": " ", "temp": 3, "code": 0]) == nil,
          "weather card: no place, no card")
    var odd = json
    odd["hours"] = [["hour": 25, "code": 0, "temp": 1], ["hour": 9, "code": 0, "temp": "x"], ["hour": 9, "code": 1, "temp": 4]]
    check(ArisWeatherCard.parse(odd)?.hours.map(\.label) == ["지금", "오전 9시"], "weather card: a bad hour is left out")
    check(ArisWeatherCard.parse(["place": "Seoul", "temp": 3, "code": 0])?.range == nil, "weather card: high and low are optional")
    check(ArisWeatherCard.sky(0) == .clear && ArisWeatherCard.sky(2) == .partly && ArisWeatherCard.sky(3) == .cloudy && ArisWeatherCard.sky(45) == .fog
          && ArisWeatherCard.sky(61) == .rain && ArisWeatherCard.sky(81) == .rain && ArisWeatherCard.sky(73) == .snow && ArisWeatherCard.sky(95) == .thunder,
          "weather card: codes group into the sky's gradients")
    check(ArisWeatherCard.condition(0) == ArisWeather.describe(code: 0, korean: true) && ArisWeatherCard.condition(3) == ArisWeather.describe(code: 3, korean: true),
          "weather card: the sky reads as aris-tools says it")

    // aris-tools weather --json, from Open-Meteo's reply.
    let reply = """
    {"current":{"time":"2026-11-04T14:45","temperature_2m":8.2,"apparent_temperature":5.1,"weather_code":0,"wind_speed_10m":9,"is_day":1},
     "daily":{"time":["2026-11-04","2026-11-05"],"weather_code":[0,3],"temperature_2m_max":[11.4,9],"temperature_2m_min":[2.6,1],"precipitation_probability_max":[0,40]},
     "hourly":{"time":["2026-11-04T13:00","2026-11-04T14:00","2026-11-04T15:00","2026-11-04T16:00","2026-11-04T17:00","2026-11-04T18:00","2026-11-04T19:00","2026-11-04T20:00"],
               "temperature_2m":[7,8,10,10.6,9.5,8,6,5],"weather_code":[0,0,0,2,2,3,0,null],"is_day":[1,1,1,1,1,0,0,0]}}
    """
    guard let forecast = try? JSONDecoder().decode(ArisWeather.Forecast.self, from: Data(reply.utf8)) else {
        return check(false, "weather --json: Open-Meteo's reply decodes")
    }
    let made = ArisWeather.card(forecast, place: "Orlando")
    let hours = made["hours"] as? [[String: Any]] ?? []
    check(made["temp"] as? Int == 8 && made["high"] as? Int == 11 && made["low"] as? Int == 3 && made["day"] as? Bool == true,
          "weather --json: now and today's high and low")
    check(hours.map { $0["hour"] as? Int ?? -1 } == [15, 16, 17, 18, 19] && hours[3]["day"] as? Bool == false && hours[1]["temp"] as? Int == 11,
          "weather --json: the five hours after this one: \(hours)")
    check(ArisWeatherCard.parse(made)?.hours.count == 6, "weather --json: the app reads what aris-tools writes")
    let plain = try? JSONDecoder().decode(ArisWeather.Forecast.self, from: Data(#"{"current":{"temperature_2m":1,"apparent_temperature":1,"weather_code":3,"wind_speed_10m":2},"daily":{"time":[],"weather_code":[],"temperature_2m_max":[],"temperature_2m_min":[],"precipitation_probability_max":[]}}"#.utf8))
    check(plain.map { ArisWeather.card($0, place: "x")["hours"] == nil } == true, "weather --json: a reply without hours still makes a card")
    let url = ArisWeather.forecastURL(latitude: 1, longitude: 2, timezone: "UTC", days: 2, hourly: true).absoluteString
    check(url.contains("hourly=temperature_2m,weather_code,is_day") && url.contains("is_day")
          && !ArisWeather.forecastURL(latitude: 1, longitude: 2, timezone: "UTC", days: 3).absoluteString.contains("hourly"),
          "weather --json: hours are asked only for the card")
}

// MARK: - Calendar

private func calendarCardTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let at = { (hour: Int, minute: Int) in calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour, minute: minute))! }
    let now = at(12, 35)
    let events = [ArisWidgetEvent(start: at(13, 0), end: at(14, 0), title: "CSC263 튜토리얼", location: "Bahen 1170", allDay: false),
                  ArisWidgetEvent(start: at(10, 0), end: at(11, 0), title: "MAT237 강의", location: "Sidney Smith 2118", allDay: false),
                  ArisWidgetEvent(start: at(16, 30), end: at(17, 30), title: "팀 프로젝트 회의", location: "", allDay: false)]
    let card = ArisCalendarCard.make(events, now: now, calendar: calendar)
    check(card.rows.map(\.time) == ["10:00", "13:00", "16:30"] && card.rows.map(\.state) == [.past, .next, .later],
          "calendar card: the day in order, past, next, later")
    check(card.rows[1].chip == "25분 뒤" && card.rows[0].chip == nil && card.rows[2].sub == nil, "calendar card: the next one says when; an empty place is left out")
    check(card.trailing == "11월 4일 수요일 · 3개", "calendar card: the date and the count: \(card.trailing)")
    let during = ArisCalendarCard.make(events, now: at(13, 20), calendar: calendar)
    check(during.rows[1].state == .next && during.rows[1].chip == "진행 중", "calendar card: the one on now is the marked one")
    let done = ArisCalendarCard.make(events, now: at(20, 0), calendar: calendar)
    check(done.rows.allSatisfy { $0.state == .past } && done.rows.allSatisfy { $0.chip == nil }, "calendar card: after the last one, nothing is marked")
    check(ArisCalendarCard.make([], now: now, calendar: calendar).rows.isEmpty && ArisCalendarCard.make([], now: now, calendar: calendar).trailing == "11월 4일 수요일",
          "calendar card: an empty day")
    let busy = (8...17).map { ArisWidgetEvent(start: at($0, 0), end: at($0, 30), title: "일 \($0)", location: nil, allDay: false) }
    let crowded = ArisCalendarCard.make(busy, now: now, calendar: calendar)
    check(crowded.rows.count == 5 && crowded.rows.first?.time == "13:00" && crowded.rows.first?.state == .next && crowded.more == 0,
          "calendar card: a long day drops what's past first: \(crowded.rows.map(\.time))")
    let morning = ArisCalendarCard.make(busy, now: at(7, 0), calendar: calendar)
    check(morning.rows.first?.time == "08:00" && morning.more == 5 && morning.trailing.hasSuffix("10개"), "calendar card: the rest is counted")
    let allDay = ArisCalendarCard.make([ArisWidgetEvent(start: at(0, 0), end: at(23, 59), title: "", location: nil, allDay: true)] + events, now: now, calendar: calendar)
    check(allDay.rows.first?.time == "종일" && allDay.rows.first?.title == "제목 없음" && allDay.rows[2].state == .next,
          "calendar card: an all-day event comes first and is never the marked one")
    check(ArisCalendarCard.chip(events[0], now: at(11, 0)) == "2시간 뒤" && ArisCalendarCard.chip(events[0], now: at(11, 40)) == "1시간 20분 뒤",
          "calendar card: hours and minutes")
}

// MARK: - To-dos

private func todoCardTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let day = { (d: Int, hour: Int) in calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour, minute: 59))! }
    let now = day(4, 12)
    let item = { (title: String, due: Date?, time: Bool, list: String) in
        ArisTodoItem(id: title, title: title, notes: nil, due: due, hasTime: time, listID: list, listName: list, colorHex: "#ffffff")
    }
    let items = [item("엄마한테 전화하기", nil, false, "개인"), item("우유 · 계란 사기", day(5, 23), false, "장보기"),
                 item("CSC263 과제 2 내기", day(4, 23), true, "학교"), item("MAT237 문제 풀이", day(6, 23), false, "학교")]
    let card = ArisTodoCard.make(items, now: now, calendar: calendar)
    check(card.rows.map(\.title) == ["CSC263 과제 2 내기", "우유 · 계란 사기", "MAT237 문제 풀이", "엄마한테 전화하기"], "todo card: soonest first, undated last")
    check(card.rows.map(\.due) == ["오늘 23:59", "내일", "금요일", nil], "todo card: due dates said shortly: \(card.rows.map(\.due))")
    check(card.rows.map(\.urgent) == [true, false, false, false] && card.rows[0].sub == "학교" && card.total == 4, "todo card: today's is the warm one")
    check(ArisTodoCard.make([item("늦음", day(2, 9), false, "x")], now: now, calendar: calendar).rows.first?.urgent == true, "todo card: overdue is urgent too")
    check(ArisTodoCard.dueText(day(20, 9), hasTime: false, now: now, calendar: calendar) == "11월 20일"
          && ArisTodoCard.dueText(day(3, 9), hasTime: false, now: now, calendar: calendar) == "어제", "todo card: far and past dates")
    let many = (1...9).map { item("할 일 \($0)", nil, false, "x") }
    check(ArisTodoCard.make(many, now: now, calendar: calendar).rows.count == 5 && ArisTodoCard.make(many, now: now, calendar: calendar).total == 9,
          "todo card: five rows, all counted")
}

// MARK: - Timer and music

private func timerAndMusicCardTests() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let focus = ArisTimerState.start(seconds: 1_500, phase: .focus, at: start)
    check(focus.cardLabel == "집중 타이머 · 25분", "timer card: the label")
    check(abs(focus.remaining(at: start.addingTimeInterval(378)) - 0.748) < 0.001, "timer card: the share left")
    check(focus.paused(at: start.addingTimeInterval(60)).cardLabel == "집중 타이머 · 25분 · 멈춤", "timer card: paused says so")
    check(ArisTimerState.start(seconds: 300, phase: .rest, at: start, cycle: true).cardLabel == "휴식 · 5분"
          && ArisTimerState.start(seconds: 1_500, phase: .focus, at: start, round: 2, cycle: true).cardLabel == "집중 2/4 · 25분"
          && ArisTimerState.start(seconds: 90, phase: .plain, at: start).cardLabel == "타이머 · 2분", "timer card: pomodoro, rest and plain labels")
    let song = ArisMusicCardState(title: "Ditto", artist: "NewJeans", album: "OMG", playing: true, duration: 185, elapsed: 72, at: start, rate: 1,
                                  source: ArisMusicCardState.source(bundle: "com.apple.Music"))
    check(song.position(at: start.addingTimeInterval(10)) == 82 && song.position(at: start.addingTimeInterval(500)) == 185,
          "music card: playing moves, never past the end")
    let paused = ArisMusicCardState(title: "Ditto", artist: "NewJeans", album: "", playing: false, duration: 185, elapsed: 72, at: start, rate: 1, source: nil)
    check(paused.position(at: start.addingTimeInterval(10)) == 72, "music card: paused stays put")
    check(song.byline == "NewJeans · OMG" && paused.byline == "NewJeans" && ArisMusicCardState.clock(185) == "3:05" && ArisMusicCardState.clock(72.9) == "1:12",
          "music card: byline and clock")
    check(song.source == "Apple Music" && ArisMusicCardState.source(bundle: "com.spotify.client") == "Spotify" && ArisMusicCardState.source(bundle: "x") == nil,
          "music card: the source app")
}

// MARK: - Prompts

private func widgetPromptTests() {
    let conversation = ArisAgentPrompt.system(tools: "/t"), task = ArisAgentPrompt.system(tools: "/t", task: true)
    let codex = ArisAgentPrompt.system(tools: "/t", notion: true, gated: true)
    check(conversation.contains(ArisAgentPrompt.cardRule(calendar: true)) && ArisAgentPrompt.sealed(tools: "/t").contains(ArisAgentPrompt.cardRule(calendar: true)),
          "prompts: a conversation brain (and the sealed one) is told how to ask for a card")
    check(!task.contains("aris-card"), "prompts: a background task never asks for a card")
    // The user left Notion Calendar (QA BUG-16): Codex's schedule is the Mac calendar too, so it asks for the calendar card.
    check(codex.contains(ArisAgentPrompt.cardRule(calendar: true)) && !ArisAgentPrompt.cardRule(calendar: false).contains("calendar"),
          "prompts: every brain's schedule is the Mac calendar, so Codex asks for the calendar card too")
    // A brain that writes the card marker without its fence (seen live 2026-11-07): never shown or said, still a card.
    let bare = "올랜도는 지금 칠 도로 흐리고, 오늘은 이슬비가 올 수 있어요.\naris-card\n{\"type\":\"weather\"}"
    let bareAndFenced = bare + "\n```aris-card\n{\"type\":\"weather\"}\n```"
    for answer in [bare, bareAndFenced, "칠 도예요. aris-card {\"type\":\"weather\"}", "칠 도예요.\naris-card"] {
        let shown = ArisSpeakable.shown(answer, korean: true)
        check(!shown.lowercased().contains("aris-card") && !shown.contains("{"), "card: an unfenced marker isn't shown: \(answer.debugDescription)")
        check(!ArisSpeakable.speakable(shown).lowercased().contains("aris") && !ArisSpeakable.fullReading(answer, korean: true).joined().lowercased().contains("card"),
              "card: an unfenced marker isn't said: \(answer.debugDescription)")
    }
    check(ArisSpeakable.shown(bare, korean: true) == "올랜도는 지금 칠 도로 흐리고, 오늘은 이슬비가 올 수 있어요.", "card: the line before an unfenced marker stays as it was")
    check(ArisWidget.request(in: bare)?.kind == .weather && ArisWidget.request(in: "칠 도예요. aris-card {\"type\":\"weather\"}")?.kind == .weather,
          "card: an unfenced marker still asks for its card")
    check(ArisWidget.request(in: "aris-card\n{\"type\":\"rocket\"}") == nil && ArisSpeakable.shown("aris-card는 이름이에요", korean: true).contains("aris-card는"),
          "card: an unknown kind is no card, and the word inside a sentence is left alone")
    check(ArisSpeakable.holdPoint(in: "칠 도예요.\naris-card") != nil, "card: speaking waits at an unfenced marker")
    check(ArisWidget.request(in: "한 줄.\n```aris-card\n{\"type\":\"weather\"}\n```") != nil && ArisAgentPrompt.cardRule(calendar: true).contains("```aris-card\n{\"type\":\"weather\"}\n```"),
          "prompts: the block the prompt shows is one the app reads")
}
