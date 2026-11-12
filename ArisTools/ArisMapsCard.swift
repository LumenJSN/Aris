//
//  ArisMapsCard.swift
//  aris-tools
//
//  The pure half of `maps search "<place>" --json` and `maps directions "<from, or here>" "<to>" --json`: a lookup
//  that opens nothing. The place (MapKit's local search near the start), its address, and how long it takes by car,
//  transit and on foot (MapKit's ETA), from the current location only when Location Services already allow it (never
//  asked for), otherwise from home (aris/home.json). --json is the notch card's values; ArisMapCard in the app reads
//  them again as data and draws the map with MKMapSnapshotter.
//

import Foundation

enum ArisMapsCard {
    struct Point: Equatable {
        let latitude: Double
        let longitude: Double

        var isValid: Bool {
            latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
        }
    }

    enum OriginKind: String { case current, home, place }

    enum Request: Equatable {
        case search(String)
        /// nil `from`: from here.
        case directions(from: String?, to: String)
    }

    /// Route points on the card at most.
    static let mostRoutePoints = 100
    /// On foot when it takes this long or less.
    static let walkingLimit: TimeInterval = 20 * 60

    /// `maps` arguments with --json: `search <words…>` or `directions <from> <to>`; nil for anything else.
    static func request(_ arguments: [String]) -> Request? {
        let words = arguments.filter { $0 != "--json" }
        switch words.first {
        case "search" where words.count >= 2:
            let query = words.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return query.isEmpty ? nil : .search(query)
        case "directions" where words.count == 3:
            let from = words[1].trimmingCharacters(in: .whitespaces), to = words[2].trimmingCharacters(in: .whitespaces)
            guard !to.isEmpty, !from.isEmpty else { return nil }
            return .directions(from: ArisMapsLink.here.contains(from.lowercased()) ? nil : from, to: to)
        default:
            return nil
        }
    }

    /// Where the times are measured from: the current location when it's allowed and known, else home.
    static func origin(authorized: Bool, current: Point?, home: Point?) -> (point: Point, kind: OriginKind)? {
        if authorized, let current, current.isValid { return (current, .current) }
        if let home, home.isValid { return (home, .home) }
        return nil
    }

    /// The way the card leads with: on foot up to 20 minutes, else by car, else transit, else on foot (ArisMapCard.primary).
    static func primary(_ eta: [String: TimeInterval]) -> String? {
        if let walk = eta["walk"], walk <= walkingLimit { return "walk" }
        return ["car", "transit", "walk"].first { eta[$0] != nil }
    }

    static func thin(_ route: [Point], to count: Int) -> [Point] {
        guard route.count > count, count >= 2 else { return route }
        return (0..<count).map { route[Int((Double($0) * Double(route.count - 1) / Double(count - 1)).rounded())] }
    }

    static func card(name: String, address: String?, place: Point, origin: (point: Point, kind: OriginKind)?,
                     eta: [String: TimeInterval], distance: [String: Double], route: [Point]) -> [String: Any] {
        // Six decimals are a tenth of a metre (and keep the reply small).
        let round = { (value: Double) in (value * 1_000_000).rounded() / 1_000_000 }
        var card: [String: Any] = ["name": name, "latitude": round(place.latitude), "longitude": round(place.longitude), "eta": eta,
                                   "distance": distance,
                                   "route": thin(route.filter(\.isValid), to: mostRoutePoints).map { [round($0.latitude), round($0.longitude)] }]
        if let address, !address.isEmpty { card["address"] = address }
        if let origin { card["origin"] = ["latitude": round(origin.point.latitude), "longitude": round(origin.point.longitude), "kind": origin.kind.rawValue] }
        if let mode = primary(eta) { card["mode"] = mode }
        return card
    }

    /// The brain's line: "Central Library (100 Main St, Orlando): on foot 8 min (650 m), by car 4 min, … from home."
    static func summary(_ card: [String: Any]) -> String {
        let name = card["name"] as? String ?? ""
        let head = (card["address"] as? String).map { "\(name) (\($0))" } ?? name
        let eta = card["eta"] as? [String: TimeInterval] ?? [:], distance = card["distance"] as? [String: Double] ?? [:]
        let mode = card["mode"] as? String
        let ways = [("walk", "on foot"), ("car", "by car"), ("transit", "by transit")].compactMap { key, words -> String? in
            guard let seconds = eta[key] else { return nil }
            let far = key == mode ? distance[key].map { " (\(meters($0)))" } ?? "" : ""
            return "\(words) \(max(1, Int((seconds / 60).rounded(.up)))) min\(far)"
        }
        let from: String
        switch (card["origin"] as? [String: Any])?["kind"] as? String {
        case "current": from = "from the current location"
        case "home": from = "from home"
        case "place": from = "from the start given"
        default: from = ""
        }
        let rest = (ways + (from.isEmpty || ways.isEmpty ? [] : [from])).joined(separator: ", ")
        return rest.isEmpty ? head + "." : "\(head): \(rest)."
    }

    private static func meters(_ value: Double) -> String {
        value < 1_000 ? "\(Int(value.rounded())) m" : String(format: "%.1f km", value / 1_000)
    }
}
