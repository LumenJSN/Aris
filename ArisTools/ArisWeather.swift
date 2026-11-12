//
//  ArisWeather.swift
//  aris-tools
//
//  The weather from Open-Meteo (free, no key), said the way Aris would say it:
//  right now, then today and the next days. `--json` gives the notch's weather card its values instead
//  (now, today's high and low, the next hours).
//

import Foundation

enum ArisWeather {
    struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let feelsLike: Double
            let code: Int
            let wind: Double
            /// "2026-11-04T14:45", the place's own time (asked only for the card).
            var time: String?
            var isDay: Int?

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m", feelsLike = "apparent_temperature"
                case code = "weather_code", wind = "wind_speed_10m", time, isDay = "is_day"
            }
        }

        /// Hour by hour (asked only for the card).
        struct Hourly: Decodable {
            let times: [String]
            let temperatures: [Double?]
            let codes: [Int?]
            let isDay: [Int?]

            enum CodingKeys: String, CodingKey {
                case times = "time", temperatures = "temperature_2m", codes = "weather_code", isDay = "is_day"
            }
        }

        struct Daily: Decodable {
            let dates: [String]
            let codes: [Int?]
            let highs: [Double?]
            let lows: [Double?]
            let rainChances: [Int?]

            enum CodingKeys: String, CodingKey {
                case dates = "time", codes = "weather_code", highs = "temperature_2m_max"
                case lows = "temperature_2m_min", rainChances = "precipitation_probability_max"
            }
        }

        let current: Current
        let daily: Daily
        var hourly: Hourly?
    }

    /// `hourly`: the card's request, with the hours and day or night too.
    static func forecastURL(latitude: Double, longitude: Double, timezone: String, days: Int, hourly: Bool = false) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m" + (hourly ? ",is_day" : "")),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: timezone),
            URLQueryItem(name: "forecast_days", value: String(days)),
        ]
        if hourly { components.queryItems?.append(URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day")) }
        return components.url!
    }

    /// One geocoding hit: where, and what kind of place (GeoNames' feature code, "PPLC" a capital, "MT" a mountain).
    struct GeoPlace: Decodable, Equatable {
        let name: String
        let latitude: Double
        let longitude: Double
        let timezone: String
        var featureCode: String?
        var population: Int?

        enum CodingKeys: String, CodingKey {
            case name, latitude, longitude, timezone, featureCode = "feature_code", population
        }
    }

    struct GeoReply: Decodable {
        let results: [GeoPlace]?
    }

    /// Big Korean cities by their English names: Open-Meteo finds no "서울" and takes "부산" for a mountain.
    static let koreanCities: [String: String] = [
        "서울": "Seoul", "부산": "Busan", "인천": "Incheon", "대구": "Daegu", "대전": "Daejeon", "광주": "Gwangju",
        "울산": "Ulsan", "세종": "Sejong", "수원": "Suwon", "성남": "Seongnam", "고양": "Goyang", "용인": "Yongin",
        "창원": "Changwon", "청주": "Cheongju", "전주": "Jeonju", "천안": "Cheonan", "포항": "Pohang", "김해": "Gimhae",
        "춘천": "Chuncheon", "강릉": "Gangneung", "여수": "Yeosu", "경주": "Gyeongju", "제주": "Jeju", "서귀포": "Seogwipo",
    ]

    /// The names to look `name` up by, in turn: a big Korean city's English name first ("서울시", "서울특별시" and
    /// "부산광역시" count), then the name as said.
    static func searchNames(_ name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var city = trimmed
        for suffix in ["특별자치시", "특별자치도", "특별시", "광역시", "시"] where city.hasSuffix(suffix) && city.count > suffix.count {
            city = String(city.dropLast(suffix.count))
            break
        }
        return [koreanCities[city], trimmed].compactMap { $0 }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// The hit to use: the most populous town or city (a PPL feature) when there is one, else the first.
    static func best(_ places: [GeoPlace]) -> GeoPlace? {
        let towns = places.filter { $0.featureCode?.hasPrefix("PPL") == true }
        return towns.max { ($0.population ?? 0) < ($1.population ?? 0) } ?? places.first
    }

    // MARK: - Home (aris/home.json)

    /// The place `weather` with no place is for, as aris/home.json keeps it.
    struct Home: Codable, Equatable {
        let name: String
        let latitude: Double
        let longitude: Double
        let timezone: String
    }

    /// The saved home place; nil when there is no file, or it isn't a place on Earth.
    static func readHome(_ file: URL) -> Home? {
        guard let data = try? Data(contentsOf: file), let home = try? JSONDecoder().decode(Home.self, from: data),
              !home.name.isEmpty, (-90...90).contains(home.latitude), (-180...180).contains(home.longitude) else { return nil }
        return home
    }

    /// Saves the home place: the folder 0700, the file 0600, written whole (nothing ever made this file, so a new Mac
    /// had no weather, no brief weather and no travel time from home: audit tools-6).
    static func writeHome(_ home: Home, to file: URL) throws {
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let temporary = folder.appendingPathComponent(".home-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: try encoder.encode(home), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, file.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func homeSetLine(_ home: Home) -> String {
        "home set to \(home.name) (\(String(format: "%.2f, %.2f", home.latitude, home.longitude)), \(home.timezone)): `weather` with no place, the morning brief " +
            "and travel times from home use it now. Tell the user which place was set."
    }

    /// The city a time zone is named for ("America/New_York" → "New York"); nil for one that names none (UTC, Etc/GMT+5).
    /// With no home set, the weather is for this city, and says so.
    static func zoneCity(_ identifier: String) -> String? {
        let parts = identifier.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] != "Etc", let last = parts.last, !last.isEmpty, !last.contains(where: \.isNumber) else { return nil }
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// The hit for a time zone's city: the best one in that very zone (London in America/New_York is the Ontario one);
    /// nil when no hit is there, so a namesake elsewhere is never taken for home.
    static func best(_ places: [GeoPlace], zone: String) -> GeoPlace? {
        best(places.filter { $0.timezone == zone })
    }

    /// What a forecast for a guessed place starts with: that it is a guess, and how to set the real home.
    static func guessedNote(place: String, korean: Bool) -> String {
        korean ? "(집 위치가 아직 정해지지 않아서, 이 Mac의 시간대로 짐작한 \(place) 기준이에요. 사는 곳을 알려 주면 `weather --set-home \"<도시>\"`로 정해져요.)"
            : "(No home place is set yet, so this is for \(place), guessed from this Mac's time zone. `weather --set-home \"<city>\"` sets the real one.)"
    }

    static let noHomeLine = "No home place is set, and this Mac's time zone names no city to guess from. Ask the user which city they live in, then run " +
        "`weather --set-home \"<city, in English>\"`; or ask for a place: `weather Seoul`."

    // MARK: - The command's words

    enum Request: Equatable {
        /// `place` empty: home. `language`: --ko or --en when given.
        case forecast(place: String, days: Int, json: Bool, language: String?)
        case setHome(String)
        case usage(String)
    }

    static let setHomeUsage = "usage: weather --set-home <city> (alone: no other words before it)"

    /// `weather [place] [--days N] [--ko|--en] [--json]`, or `weather --set-home <place>` (first, and alone with its place).
    static func request(_ args: [String]) -> Request {
        var words = args
        if words.first == "--set-home" {
            let place = words.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return place.isEmpty || place.hasPrefix("--") ? .usage(setHomeUsage) : .setHome(place)
        }
        guard !words.contains("--set-home") else { return .usage(setHomeUsage) }
        var days = 3
        if let flag = words.firstIndex(of: "--days"), flag + 1 < words.count, let value = Int(words[flag + 1]) {
            days = min(16, max(1, value))
            words.removeSubrange(flag...(flag + 1))
        }
        let json = words.contains("--json")
        words.removeAll { $0 == "--json" }
        let language = words.first { $0 == "--ko" || $0 == "--en" }
        words.removeAll { $0 == "--ko" || $0 == "--en" }
        return .forecast(place: words.joined(separator: " "), days: days, json: json, language: language)
    }

    static func geocodeURL(name: String, korean: Bool) -> URL {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: korean ? "ko" : "en"), URLQueryItem(name: "format", value: "json"),
        ]
        return components.url!
    }

    static func summary(_ forecast: Forecast, place: String, korean: Bool) -> String {
        let now = forecast.current
        let condition = describe(code: now.code, korean: korean)
        var sentences = [korean
            ? "\(place) 지금 \(degrees(now.temperature))°C (체감 \(degrees(now.feelsLike))°C), \(condition), 바람 \(degrees(now.wind))km/h."
            : "\(place) now \(degrees(now.temperature))°C (feels \(degrees(now.feelsLike))°C), \(condition), wind \(degrees(now.wind)) km/h."]
        let daily = forecast.daily
        for index in daily.dates.indices {
            guard let high = daily.highs[safe: index] ?? nil, let low = daily.lows[safe: index] ?? nil else { continue }
            let day = dayName(daily.dates[index], index: index, korean: korean)
            let sky = describe(code: (daily.codes[safe: index] ?? nil) ?? -1, korean: korean)
            let rain = (daily.rainChances[safe: index] ?? nil) ?? 0
            sentences.append(korean
                ? "\(day) \(degrees(low))~\(degrees(high))°C, \(sky), 비 올 확률 \(rain)%."
                : "\(day) \(degrees(low))–\(degrees(high))°C, \(sky), \(rain)% chance of rain.")
        }
        return sentences.joined(separator: " ")
    }

    /// The hours the card shows after 지금.
    static let cardHours = 5

    /// The weather card's values (ArisWeatherCard in the app): now, today's high and low, and the next hours, each
    /// hour as its hour of the day at the place.
    static func card(_ forecast: Forecast, place: String) -> [String: Any] {
        let now = forecast.current
        var card: [String: Any] = ["place": place, "temp": degrees(now.temperature), "code": now.code, "day": now.isDay != 0]
        if let high = forecast.daily.highs.first ?? nil, let low = forecast.daily.lows.first ?? nil {
            card["high"] = degrees(high)
            card["low"] = degrees(low)
        }
        if let hourly = forecast.hourly, let time = now.time, let at = hourly.times.firstIndex(where: { $0.prefix(13) == time.prefix(13) }) {
            card["hours"] = hourly.times.indices.dropFirst(at + 1).prefix(cardHours).compactMap { index -> [String: Any]? in
                guard let temperature = hourly.temperatures[safe: index] ?? nil, let code = hourly.codes[safe: index] ?? nil,
                      let hour = Int(hourly.times[index].dropFirst(11).prefix(2)) else { return nil }
                return ["hour": hour, "code": code, "temp": degrees(temperature), "day": ((hourly.isDay[safe: index] ?? nil) ?? 1) != 0]
            }
        }
        return card
    }

    /// WMO weather codes, as Open-Meteo reports them.
    static func describe(code: Int, korean: Bool) -> String {
        let names: (String, String)
        switch code {
        case 0: names = ("맑음", "clear")
        case 1: names = ("대체로 맑음", "mostly clear")
        case 2: names = ("구름 조금", "partly cloudy")
        case 3: names = ("흐림", "overcast")
        case 45, 48: names = ("안개", "fog")
        case 51, 53, 55: names = ("이슬비", "drizzle")
        case 56, 57: names = ("어는 이슬비", "freezing drizzle")
        case 61: names = ("약한 비", "light rain")
        case 63: names = ("비", "rain")
        case 65: names = ("강한 비", "heavy rain")
        case 66, 67: names = ("어는 비", "freezing rain")
        case 71: names = ("약한 눈", "light snow")
        case 73: names = ("눈", "snow")
        case 75: names = ("많은 눈", "heavy snow")
        case 77: names = ("싸락눈", "snow grains")
        case 80, 81, 82: names = ("소나기", "rain showers")
        case 85, 86: names = ("눈 소나기", "snow showers")
        case 95: names = ("뇌우", "thunderstorm")
        case 96, 99: names = ("우박을 동반한 뇌우", "thunderstorm with hail")
        default: names = ("알 수 없음", "unknown")
        }
        return korean ? names.0 : names.1
    }

    private static func degrees(_ value: Double) -> Int {
        Int(value.rounded())
    }

    private static func dayName(_ date: String, index: Int, korean: Bool) -> String {
        let named = korean ? ["오늘", "내일", "모레"] : ["Today", "Tomorrow"]
        if index < named.count { return named[index] }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: korean ? "ko_KR" : "en_US")
        formatter.dateFormat = korean ? "M월 d일(E)" : "EEEE"
        return formatter.string(from: day)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
