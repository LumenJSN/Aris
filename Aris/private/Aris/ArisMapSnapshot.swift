//
//  ArisMapSnapshot.swift
//  Aris
//
//  The map card's picture: one MKMapSnapshotter still (dark, no web tiles), framed by ArisMapCard.region so the place
//  and a nearby start sit above the glass label, with where the place, the start and the route fall on it. Made for
//  the card on screen only: never saved or passed on (MapKit's terms). Nil when MapKit can't make one in 12 seconds;
//  the card then shows without a map.
//

import AppKit
import MapKit

struct ArisMapTile: Equatable {
    let image: NSImage
    /// Where the place, the start and the route fall on the picture, 0…1 from the top left.
    let place: CGPoint
    let origin: CGPoint?
    let route: [CGPoint]

    static func == (lhs: ArisMapTile, rhs: ArisMapTile) -> Bool {
        lhs.image === rhs.image && lhs.place == rhs.place && lhs.origin == rhs.origin && lhs.route == rhs.route
    }
}

@MainActor
enum ArisMapSnapshot {
    /// The card's map, 416 × 216 in the open notch (mockup .mC .mimg).
    static let size = CGSize(width: 416, height: 216)
    /// The glass label's share of the bottom (10 under it, about 66 for its three lines) and room for the start's dot.
    static let covered: CGFloat = 90

    static func tile(for card: ArisMapCard, size: CGSize? = nil) async -> ArisMapTile? {
        let size = size ?? Self.size
        let region = card.region(width: size.width, height: size.height, covered: covered)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: region.center.latitude, longitude: region.center.longitude),
                                            span: MKCoordinateSpan(latitudeDelta: region.latitudeDelta, longitudeDelta: region.longitudeDelta))
        options.size = size
        options.appearance = NSAppearance(named: .darkAqua)
        let snapshotter = MKMapSnapshotter(options: options)
        let deadline = Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            snapshotter.cancel()
        }
        defer { deadline.cancel() }
        guard let snapshot = try? await snapshotter.start() else { return nil }
        let spot = { (coordinate: ArisMapCard.Coordinate) -> CGPoint in
            let point = snapshot.point(for: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
            // On the Mac the still's points count from the bottom left.
            return CGPoint(x: point.x / size.width, y: 1 - point.y / size.height)
        }
        return ArisMapTile(image: snapshot.image, place: spot(card.place), origin: card.origin.map(spot), route: card.route.map(spot))
    }
}
