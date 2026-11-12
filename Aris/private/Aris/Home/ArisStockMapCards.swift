//
//  ArisStockMapCards.swift
//  Aris
//
//  The stock and map answer cards, the owner's ③C (mockups/new-features.html §3, the day range as §3′ B). Stock: the name
//  and the quote's own time (never a delay badge), the price at 38 / 300 with its change in a pill, a 60-point
//  sparkline, then 고가 · 저가. Map: a 216-point MapKit still with the route and the pin, and a glass label with the
//  place, its address and the ETA. Values are drawn as Text(verbatim:); nothing moves or blinks. The map opens Maps
//  only on a click.
//

import AppKit
import SwiftUI

enum ArisStockMapStyle {
    static let up = Color(red: 84 / 255, green: 214 / 255, blue: 110 / 255)
    static let down = Color(red: 1, green: 109 / 255, blue: 109 / 255)
    static let pin = Color(red: 29 / 255, green: 114 / 255, blue: 232 / 255)
    static let start = Color(red: 50 / 255, green: 215 / 255, blue: 75 / 255)
    static let glass = Color(red: 18 / 255, green: 20 / 255, blue: 26 / 255).opacity(0.62)
    static let mapHeight: CGFloat = 216
}

// MARK: - Stock

/// `.stC`: padding 14 / 16 / 16, 10-point gaps, the generic card surface (radius 26, white 6%).
struct ArisStockCardView: View {
    let card: ArisStockCard
    /// A fixed moment, for the renders; nil is now.
    var now: Date?
    var calendar: Calendar = .current

    private var tone: Color { card.up ? ArisStockMapStyle.up : ArisStockMapStyle.down }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: card.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
                Text(verbatim: card.caption(now: now ?? Date(), calendar: calendar)).font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4)).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
            }
            HStack(alignment: .center, spacing: 10) {
                // line-height 1: a 38-point box.
                Text(verbatim: card.priceText).font(.system(size: 38, weight: .light).monospacedDigit()).tracking(-1.14)
                    .foregroundStyle(ArisWidgetStyle.ink92).lineLimit(1).minimumScaleFactor(0.6).frame(height: 38)
                Text(verbatim: card.changeText).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(tone.opacity(0.95))
                    .lineLimit(1).fixedSize()
                    .padding(.vertical, 3).padding(.horizontal, 9)
                    .background(Capsule().fill(tone.opacity(0.12)))
            }
            ArisSparkline(values: card.points, previous: card.previousClose, color: tone).frame(height: 60)
            HStack(spacing: 22) {
                stat(ArisUIWords.text("고가", "High"), card.highText)
                stat(ArisUIWords.text("저가", "Low"), card.lowText)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ArisWidgetStyle.radius, style: .continuous).fill(ArisWidgetStyle.fill))
        .accessibilityElement(children: .combine)
    }

    /// `.hl2`: the label 11 at .4, the value 13 / 600 six points after it.
    private func stat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            Text(verbatim: value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(ArisWidgetStyle.ink92)
        }
    }
}

/// The mockup's spark(): a 2.3-point line over an area fading from 22% to nothing; still.
struct ArisSparkline: View {
    let values: [Double]
    let previous: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let points = ArisStockCard.spark(values, previous: previous, size: geometry.size, inset: 8)
            if let first = points.first, let last = points.last {
                let line = Path { path in path.addLines(points) }
                Path { path in
                    path.addLines(points)
                    path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: first.x, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                line.stroke(color.opacity(0.95), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Map

/// `.mC`: the map 216 high in a radius-26 card, a glass label 10 in from the sides and the bottom (radius 18), the
/// map's attribution at the top right. A click opens the way there in Maps.
struct ArisMapCardView: View {
    let card: ArisMapCard
    let tile: ArisMapTile?
    /// Opens Maps; nil draws no click.
    var open: (() -> Void)?

    @State private var width: CGFloat = 416
    @State private var labelHeight: CGFloat = 60
    @State private var pointing = false

    var body: some View {
        picture
            .frame(maxWidth: .infinity)
            .frame(height: ArisStockMapStyle.mapHeight)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay(alignment: .bottom) { label.padding(10) }
            .overlay(alignment: .topTrailing) {
                if tile != nil { attribution.padding(.top, 8).padding(.trailing, 14) }
            }
            .clipShape(RoundedRectangle(cornerRadius: ArisWidgetStyle.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ArisWidgetStyle.radius, style: .continuous).inset(by: 0.25).stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: ArisWidgetStyle.radius, style: .continuous).inset(by: 0.5)
                    .stroke(LinearGradient(stops: [.init(color: .white.opacity(0.16), location: 0), .init(color: .clear, location: 0.04)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: ArisWidgetStyle.radius, style: .continuous))
            .onTapGesture { open?() }
            .onHover { inside in
                guard open != nil, inside != pointing else { return }
                pointing = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            // A card put away under the pointer gives the cursor back.
            .onDisappear { if pointing { NSCursor.pop(); pointing = false } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(open == nil ? [] : .isButton)
            .accessibilityHint(open == nil ? "" : ArisUIWords.text("지도 앱에서 열기", "Opens in Maps"))
    }

    /// The still with the route and the pins on it, or the mockup's dark gradient when there's none.
    private var picture: some View {
        ZStack {
            if let tile {
                Image(nsImage: tile.image).resizable().scaledToFill()
            } else {
                LinearGradient(stops: [.init(color: Color(red: 0x2b / 255, green: 0x3a / 255, blue: 0x4a / 255), location: 0),
                                       .init(color: Color(red: 0x24 / 255, green: 0x30 / 255, blue: 0x3d / 255), location: 0.55),
                                       .init(color: Color(red: 0x1f / 255, green: 0x29 / 255, blue: 0x35 / 255), location: 1)],
                               startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
            }
            if let tile {
                GeometryReader { geometry in
                    let at = { (point: CGPoint) in CGPoint(x: point.x * geometry.size.width, y: point.y * geometry.size.height) }
                    if tile.route.count >= 2 {
                        let route = Path { $0.addLines(tile.route.map(at)) }
                        route.stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        route.stroke(ArisStockMapStyle.pin, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    if let origin = tile.origin {
                        Circle().fill(ArisStockMapStyle.start).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .frame(width: 14, height: 14).position(at(origin))
                    }
                    ArisMapPin().frame(width: 28, height: 38).position(x: at(tile.place).x, y: at(tile.place).y - 19)
                }
            }
        }
    }

    /// `.glass`: the place and its address on the left, the ETA on the right, over a blurred copy of the map.
    private var label: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: card.name).font(.system(size: 14.5, weight: .semibold)).tracking(-0.435).foregroundStyle(ArisWidgetStyle.ink95).lineLimit(1)
                if let address = card.address {
                    Text(verbatim: address).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                }
                if let others = card.othersLine {
                    Text(verbatim: others).font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let line = card.primaryLine {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: line.eta).font(.system(size: 20, weight: .heavy).monospacedDigit()).tracking(-0.8).foregroundStyle(ArisWidgetStyle.ink95)
                    Text(verbatim: line.how).font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.62))
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { labelHeight = $0 }
        .background {
            ArisStockMapStyle.glass
                .background(alignment: .topLeading) {
                    picture.frame(width: width, height: ArisStockMapStyle.mapHeight)
                        .blur(radius: 18).saturation(1.4)
                        .offset(x: -10, y: -(ArisStockMapStyle.mapHeight - 10 - labelHeight))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 9, y: 6)
    }

    private static let legal = URL(string: "https://www.apple.com/legal/internet-services/maps/")!

    /// Apple's map attribution, kept in sight on the still.
    private var attribution: some View {
        HStack(spacing: 5) {
            Text(verbatim: ArisUIWords.text("\u{F8FF} 지도", "\u{F8FF} Maps"))
            // Apple's map terms, on a click (a fixed page; nothing from the turn goes into it).
            Text(verbatim: ArisUIWords.text("법적 고지", "Legal")).onTapGesture { NSWorkspace.shared.open(Self.legal) }
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
        .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
    }
}

/// The mockup's pin: a 28-point drop in the pin blue with a white rim and a white centre; its tip is the place.
private struct ArisMapPin: View {
    var body: some View {
        ZStack {
            ArisMapPinShape().fill(ArisStockMapStyle.pin)
            ArisMapPinShape().stroke(.white, lineWidth: 1.5)
            Circle().fill(.white).frame(width: 10, height: 10).position(x: 14, y: 14)
        }
        .frame(width: 28, height: 38)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

/// M0 0 c-9-11 -14-17 -14-24 a14 14 0 0 1 28 0 c0 7 -5 13 -14 24z, with the tip at the bottom centre of 28 × 38.
private struct ArisMapPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip = CGPoint(x: rect.midX, y: rect.maxY), centre = CGPoint(x: rect.midX, y: rect.minY + 14)
        path.move(to: tip)
        path.addCurve(to: CGPoint(x: rect.minX, y: centre.y), control1: CGPoint(x: tip.x - 9, y: tip.y - 11), control2: CGPoint(x: rect.minX, y: tip.y - 17))
        path.addArc(center: centre, radius: 14, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addCurve(to: tip, control1: CGPoint(x: rect.maxX, y: centre.y + 7), control2: CGPoint(x: tip.x + 9, y: tip.y - 11))
        path.closeSubpath()
        return path
    }
}
