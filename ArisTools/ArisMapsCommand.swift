//
//  ArisMapsCommand.swift
//  aris-tools
//
//  `maps search "<place>" --json` and `maps directions "<from, or here>" "<to>" --json`: MapKit's local search and
//  ETAs (car, transit, on foot), and the leading way's route, with nothing opened (ArisMapsCard is the pure half).
//  The start is the current location only when Location Services already allow it (never asked), else home.
//

import CoreLocation
import Foundation
import MapKit

/// Spins the main run loop (MapKit answers on it) until `start` calls back or `seconds` pass.
private func mapsWait<T>(_ seconds: TimeInterval, _ start: (@escaping (T?) -> Void) -> Void) -> T? {
    var value: T?, finished = false
    start { value = $0; finished = true }
    let deadline = Date().addingTimeInterval(seconds)
    while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    return value
}

/// One fix from Location Services, when they already allow it.
private final class MapsFix: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var done: ((CLLocation?) -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { done?(locations.last); done = nil }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { done?(nil); done = nil }
}

private func mapsOrigin() -> (point: ArisMapsCard.Point, kind: ArisMapsCard.OriginKind)? {
    let fix = MapsFix()
    let authorized = fix.manager.authorizationStatus == .authorizedAlways
    var current: ArisMapsCard.Point?
    if authorized {
        // Never requestAuthorization: without a yes already given, home is the start.
        let recent = fix.manager.location.flatMap { -$0.timestamp.timeIntervalSinceNow < 1_800 ? $0 : nil }
        let location = recent ?? mapsWait(4) { (finish: @escaping (CLLocation?) -> Void) in
            fix.manager.delegate = fix
            fix.done = finish
            fix.manager.requestLocation()
        }
        current = location.map { ArisMapsCard.Point(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
    }
    let home = (try? Data(contentsOf: homeFile)).flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
        .map { ArisMapsCard.Point(latitude: $0.latitude, longitude: $0.longitude) }
    return ArisMapsCard.origin(authorized: authorized, current: current, home: home)
}

private func mapsFind(_ query: String, near: ArisMapsCard.Point?) -> MKMapItem? {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    if let near {
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude),
                                            latitudinalMeters: 50_000, longitudinalMeters: 50_000)
    }
    return mapsWait(10) { finish in MKLocalSearch(request: request).start { reply, _ in finish(reply?.mapItems.first) } }
}

private func mapsItem(_ point: ArisMapsCard.Point) -> MKMapItem {
    // MapKit's location/address API is macOS 26; aris-tools runs from macOS 14, where the placemark gives the same.
    let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    if #available(macOS 26.0, *) { return MKMapItem(location: CLLocation(latitude: point.latitude, longitude: point.longitude), address: nil) }
    return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
}

/// Where a found place is, on any macOS (the placemark before 26).
private func mapsCoordinate(_ item: MKMapItem) -> CLLocationCoordinate2D {
    if #available(macOS 26.0, *) { return item.location.coordinate }
    return item.placemark.coordinate
}

/// Its address in one short line, on any macOS (the placemark's title before 26).
private func mapsAddress(_ item: MKMapItem) -> String? {
    if #available(macOS 26.0, *) {
        return item.address?.shortAddress ?? item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
    }
    return item.placemark.title
}

private let mapsWays: [(String, MKDirectionsTransportType)] = [("car", .automobile), ("transit", .transit), ("walk", .walking)]

func mapsLookup(_ args: [String]) {
    guard let request = ArisMapsCard.request(args) else {
        fail("usage: maps search \"<place>\" --json | maps directions \"<from, or here>\" \"<to>\" --json")
    }
    var origin = mapsOrigin()
    let target: String
    switch request {
    case .search(let words): target = words
    case .directions(let from, let to):
        target = to
        if let from {
            guard let start = mapsFind(from, near: origin?.point) else { fail("couldn't find \(from) in Maps") }
            let at = mapsCoordinate(start)
            origin = (ArisMapsCard.Point(latitude: at.latitude, longitude: at.longitude), .place)
        }
    }
    guard let found = mapsFind(target, near: origin?.point) else { fail("couldn't find \(target) in Maps") }
    let at = mapsCoordinate(found)
    let place = ArisMapsCard.Point(latitude: at.latitude, longitude: at.longitude)
    var eta: [String: TimeInterval] = [:], distance: [String: Double] = [:], route: [ArisMapsCard.Point] = []
    if let origin {
        for (key, type) in mapsWays {
            let ask = MKDirections.Request()
            ask.source = mapsItem(origin.point)
            ask.destination = found
            ask.transportType = type
            guard let answer = mapsWait(8, { finish in MKDirections(request: ask).calculateETA { reply, _ in finish(reply) } }) else { continue }
            eta[key] = answer.expectedTravelTime
            distance[key] = answer.distance
        }
        // The leading way's line on the map (MapKit draws no transit route).
        if let mode = ArisMapsCard.primary(eta), let type = mapsWays.first(where: { $0.0 == mode && mode != "transit" })?.1 {
            let ask = MKDirections.Request()
            ask.source = mapsItem(origin.point)
            ask.destination = found
            ask.transportType = type
            if let line = mapsWait(8, { finish in MKDirections(request: ask).calculate { reply, _ in finish(reply?.routes.first?.polyline) } }) {
                let points = UnsafeBufferPointer(start: line.points(), count: line.pointCount)
                route = points.map { ArisMapsCard.Point(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
            }
        }
    }
    let address = mapsAddress(found)
    let card = ArisMapsCard.card(name: found.name ?? target, address: address, place: place, origin: origin, eta: eta, distance: distance, route: route)
    guard args.contains("--json") else { return print(ArisMapsCard.summary(card)) }
    let data = (try? JSONSerialization.data(withJSONObject: card, options: [.sortedKeys])) ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
}
