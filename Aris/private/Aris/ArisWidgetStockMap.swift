//
//  ArisWidgetStockMap.swift
//  Aris
//
//  The stock and map cards' values (the owner's ③C; the day range as B, "고가 · 저가" only). Both come from aris-agent's
//  app-only routes (POST /stock: aris-tools stock --json, Yahoo's chart; POST /maps: aris-tools maps … --json,
//  MapKit) and are read here as outside data: a value that isn't one drops the card or that one value, names and
//  addresses lose control characters, and nothing the brain wrote reaches them. No delay badge: the card says the
//  quote's own time ("오후 2:26 기준"). Pure, so the tests run it.
//

import CoreGraphics
import Foundation

/// A JSON number that is one (never a true/false, never infinite).
private func arisNumber(_ raw: Any?) -> Double? {
    guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let value = number.doubleValue
    return value.isFinite ? value : nil
}

/// Plain text on one line: control characters as spaces, runs of spaces as one, at most `longest` characters.
private func arisPlainText(_ raw: Any?, longest: Int) -> String? {
    guard let raw = raw as? String else { return nil }
    let spaced = raw.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
    let text = spaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return text.isEmpty ? nil : String(text.prefix(longest))
}

// MARK: - Stock

struct ArisStockCard: Equatable, Sendable, Codable {
    let symbol: String
    let name: String
    let currency: String?
    let price: Double
    let previousClose: Double
    let high: Double
    let low: Double
    /// The quote's own time (Yahoo's regularMarketTime).
    let time: Date
    /// Today's prices, for the sparkline.
    let points: [Double]
    let decimals: Int

    static let mostPoints = 300

    static func parse(_ object: [String: Any], now: Date = Date()) -> ArisStockCard? {
        guard let symbol = object["symbol"] as? String, symbol.range(of: #"^[A-Za-z0-9^][A-Za-z0-9.\-=^]{0,19}$"#, options: .regularExpression) != nil,
              let name = arisPlainText(object["name"], longest: 40),
              let price = positive(object["price"]), let previous = positive(object["previousClose"]),
              let high = positive(object["high"]), let low = positive(object["low"]),
              low <= price, price <= high,
              let seconds = arisNumber(object["time"]), seconds > 946_684_800, seconds <= now.timeIntervalSince1970 + 86_400 else { return nil }
        let currency = (object["currency"] as? String).flatMap { $0.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil ? $0 : nil }
        let points = ((object["points"] as? [Any]) ?? []).prefix(mostPoints).compactMap(positive)
        let decimals = arisNumber(object["decimals"]).map(Int.init).flatMap { (0...4).contains($0) ? $0 : nil } ?? 2
        return ArisStockCard(symbol: symbol, name: name, currency: currency, price: price, previousClose: previous, high: high, low: low,
                             time: Date(timeIntervalSince1970: seconds), points: points, decimals: decimals)
    }

    private static func positive(_ raw: Any?) -> Double? {
        arisNumber(raw).flatMap { $0 > 0 && $0 < 1e12 ? $0 : nil }
    }

    var change: Double { price - previousClose }
    var percent: Double { change / previousClose * 100 }
    var up: Bool { change >= 0 }

    /// "Apple · AAPL"; the symbol alone when it is the name.
    var title: String { name == symbol ? symbol : "\(name) · \(symbol)" }
    var priceText: String { format(price) }
    var highText: String { format(high) }
    var lowText: String { format(low) }

    /// "+3.18 (+1.19%)", "−7,700 (−3.82%)".
    var changeText: String {
        let sign = up ? "+" : "−"
        return "\(sign)\(format(abs(change))) (\(sign)\(String(format: "%.2f", abs(percent)))%)"
    }

    /// "오후 2:26 기준" today, "11월 4일 오후 4:00 기준" on another day.
    func asOf(now: Date, calendar: Calendar = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        if english {
            // "As of 2:26 PM", "As of Nov 4 at 4:00 PM".
            return "As of " + ArisUIDates.string(time, korean: "", template: calendar.isDate(time, inSameDayAs: now) ? "jmm" : "MMMdjmm", english: true, calendar: calendar, locale: locale)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.isDate(time, inSameDayAs: now) ? "a h:mm" : "M월 d일 a h:mm"
        return formatter.string(from: time) + " 기준"
    }

    /// The small grey words after the title: "USD · 오후 2:26 기준".
    func caption(now: Date, calendar: Calendar = .current) -> String {
        (currency.map { "\($0) · " } ?? "") + asOf(now: now, calendar: calendar)
    }

    private func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// The sparkline's points in `size` (the mockup's spark()): 2 in from each side, `inset` from the top and the
    /// bottom; the chart's floor is the lower of the day's low and the previous close. Fewer than two points: none.
    static func spark(_ values: [Double], previous: Double, size: CGSize, inset: CGFloat) -> [CGPoint] {
        guard values.count >= 2, let top = values.max(), let least = values.min() else { return [] }
        let floor = min(least, previous)
        let width = size.width - 4, height = size.height - 2 * inset
        return values.enumerated().map { index, value in
            let x = 2 + width * CGFloat(index) / CGFloat(values.count - 1)
            let share = top > floor ? CGFloat((value - floor) / (top - floor)) : 0.5
            return CGPoint(x: x, y: inset + height * (1 - share))
        }
    }
}

// MARK: - Map

struct ArisMapCard: Equatable, Sendable, Codable {
    struct Coordinate: Equatable, Sendable, Codable {
        let latitude: Double
        let longitude: Double
    }

    enum Mode: String, CaseIterable, Sendable, Codable {
        case walk, transit, car

        var words: String { words() }

        func words(english: Bool = ArisUIWords.english) -> String {
            switch self {
            case .walk: return ArisUIWords.text("걸어서", "Walking", english: english)
            case .transit: return ArisUIWords.text("대중교통", "Transit", english: english)
            case .car: return ArisUIWords.text("차로", "Driving", english: english)
            }
        }

        /// Maps' dirflg.
        var flag: String {
            switch self {
            case .walk: return "w"
            case .transit: return "r"
            case .car: return "d"
            }
        }
    }

    enum OriginKind: String, Sendable, Codable { case current, home, place }

    let name: String
    let address: String?
    let place: Coordinate
    let origin: Coordinate?
    let originKind: OriginKind?
    let eta: [Mode: TimeInterval]
    let distance: [Mode: Double]
    let route: [Coordinate]

    static let mostRoutePoints = 200
    static let walkingLimit: TimeInterval = 20 * 60

    static func parse(_ object: [String: Any]) -> ArisMapCard? {
        guard let name = arisPlainText(object["name"], longest: 80), let place = coordinate(object["latitude"], object["longitude"]) else { return nil }
        let start = object["origin"] as? [String: Any]
        let kind = (start?["kind"] as? String).flatMap(OriginKind.init(rawValue:))
        let origin = kind == nil ? nil : coordinate(start?["latitude"], start?["longitude"])
        let route = ((object["route"] as? [Any]) ?? []).prefix(mostRoutePoints).compactMap { raw -> Coordinate? in
            guard let pair = raw as? [Any], pair.count == 2 else { return nil }
            return coordinate(pair[0], pair[1])
        }
        return ArisMapCard(name: name, address: arisPlainText(object["address"], longest: 120), place: place, origin: origin,
                           originKind: origin == nil ? nil : kind, eta: modes(object["eta"], within: 0...172_800),
                           distance: modes(object["distance"], within: 0...50_000_000), route: route)
    }

    private static func coordinate(_ latitude: Any?, _ longitude: Any?) -> Coordinate? {
        guard let latitude = arisNumber(latitude), let longitude = arisNumber(longitude),
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    private static func modes(_ raw: Any?, within range: ClosedRange<Double>) -> [Mode: Double] {
        var out: [Mode: Double] = [:]
        for (key, value) in (raw as? [String: Any]) ?? [:] {
            if let mode = Mode(rawValue: key), let number = arisNumber(value), range.contains(number) { out[mode] = number }
        }
        return out
    }

    /// The way the card leads with: on foot up to 20 minutes, else by car, else transit, else on foot.
    static func primary(_ eta: [Mode: TimeInterval]) -> Mode? {
        if let walk = eta[.walk], walk <= walkingLimit { return .walk }
        return [Mode.car, .transit, .walk].first { eta[$0] != nil }
    }

    var primary: Mode? { Self.primary(eta) }

    /// ("8분", "걸어서 · 650m").
    var primaryLine: (eta: String, how: String)? {
        guard let primary, let seconds = eta[primary] else { return nil }
        return (Self.duration(seconds), primary.words + (distance[primary].map { " · " + Self.distance($0) } ?? ""))
    }

    /// "차로 4분 · 대중교통 9분": the other ways there.
    var othersLine: String? {
        let others = [Mode.car, .transit, .walk].filter { $0 != primary }.compactMap { mode in eta[mode].map { "\(mode.words) \(Self.duration($0))" } }
        return others.isEmpty ? nil : others.joined(separator: " · ")
    }

    /// "8분", "1시간 5분", "2시간".
    static func duration(_ seconds: TimeInterval, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        if english { return ArisUIDates.length(minutes: minutes, locale: locale) }
        guard minutes >= 60 else { return "\(minutes)분" }
        return minutes % 60 == 0 ? "\(minutes / 60)시간" : "\(minutes / 60)시간 \(minutes % 60)분"
    }

    /// "650m", "4.2km", "12km".
    static func distance(_ meters: Double) -> String {
        if meters < 1_000 { return "\(Int(meters.rounded()))m" }
        return meters < 10_000 ? String(format: "%.1fkm", meters / 1_000) : "\(Int((meters / 1_000).rounded()))km"
    }

    /// The way there in Maps, by coordinates only (a name never goes into the link); the start only when it isn't
    /// where the Mac is.
    var mapsURL: URL? {
        let start = originKind != .current ? origin.map { "saddr=\($0.latitude),\($0.longitude)&" } ?? "" : ""
        let flag = primary.map { "&dirflg=\($0.flag)" } ?? ""
        return URL(string: "maps://?\(start)daddr=\(place.latitude),\(place.longitude)\(flag)")
    }

    /// The snapshot's region for a `width` × `height` map whose bottom `covered` points are under the label: the
    /// place, and the start and the route when the start is near, framed between `top` (room for the pin, which
    /// stands 38 points over the place) and the label.
    func region(width: CGFloat, height: CGFloat, covered: CGFloat,
                top inset: CGFloat = 46) -> (center: Coordinate, latitudeDelta: Double, longitudeDelta: Double) {
        let near = origin.map { abs($0.latitude - place.latitude) < 0.08 && abs($0.longitude - place.longitude) < 0.1 } ?? false
        let shown = [place] + (near ? (origin.map { [$0] } ?? []) + route : [])
        let lats = shown.map(\.latitude), lons = shown.map(\.longitude)
        let minLat = lats.min() ?? place.latitude, maxLat = lats.max() ?? place.latitude
        let minLon = lons.min() ?? place.longitude, maxLon = lons.max() ?? place.longitude
        let middle = (minLat + maxLat) / 2, cosine = max(0.2, cos(middle * .pi / 180))
        let visible = max(maxLat - minLat, 0.003) * 1.2, across = max(maxLon - minLon, 0.004) * 1.3
        let open = Double(max(0.2, (height - covered - inset) / height)), aspect = Double(width / height)
        let total = max(visible / open, across * cosine / aspect)
        // The open band's middle, as a share of the height from the top, sits on the framed points' middle.
        let band = Double((inset + height - covered) / 2 / height)
        return (Coordinate(latitude: middle + (band - 0.5) * total, longitude: (minLon + maxLon) / 2), total, total * aspect / cosine)
    }
}
