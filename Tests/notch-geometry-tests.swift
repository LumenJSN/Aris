// Acceptance tests for the clean-room notch sizing and shape (cleanroom-specs/04-sizing-and-shape.md).
import AppKit
import SwiftUI

func runNotchGeometryTests() {
    closedSizeTests()
    menuBarTests()
    syncTests()
    shapeTests()
}

/// A 1512 × 982 laptop with a notch (32 pt inset, 24 pt menu-bar strip) and auxiliary areas leaving a 196 pt notch.
private let laptop = ArisScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                       visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944), topInset: 38,
                                       auxiliaryTopLeft: CGRect(x: 0, y: 944, width: 660, height: 38),
                                       auxiliaryTopRight: CGRect(x: 852, y: 944, width: 660, height: 38))
/// An external display, menu bar 25 pt (24 measured).
private let external = ArisScreenMetrics(frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
                                         visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415), topInset: 0,
                                         auxiliaryTopLeft: nil, auxiliaryTopRight: nil)

private func closedSizeTests() {
    typealias G = ArisNotchGeometry
    check(G.closedSize(for: laptop, screens: [laptop, external], notchHeight: 38, nonNotchHeight: 24) == CGSize(width: 196, height: 38),
          "closed size: a notched display measures its notch (width − aux areas + 4) and uses the notch height")
    let scaled = G.closedSize(for: external, screens: [laptop, external], notchHeight: 38, nonNotchHeight: 24)
    check(scaled == CGSize(width: (196 * 25.0 / 38).rounded(), height: (38 * 25.0 / 38).rounded()),
          "closed size: next to a notch, a flat display borrows it, scaled by its menu bar / the inset (\(scaled))")
    check(G.closedSize(for: external, screens: [external], notchHeight: 38, nonNotchHeight: 24) == CGSize(width: 185, height: 24),
          "closed size: no notch anywhere -> 185 wide, the non-notch height, no scaling")
    check(G.closedSize(for: nil, screens: [], notchHeight: 38, nonNotchHeight: 32) == CGSize(width: 185, height: 32),
          "closed size: no displays at all -> the fallback")
    var tall = external
    tall.visibleFrame.size.height = 1440 - 80
    let capped = G.closedSize(for: tall, screens: [laptop, tall], notchHeight: 38, nonNotchHeight: 24)
    check(capped == CGSize(width: 196, height: 38), "closed size: never scaled up")
    var hidden = external
    hidden.visibleFrame.size.height = 1440
    check(G.closedSize(for: hidden, screens: [laptop, hidden], notchHeight: 38, nonNotchHeight: 24) == CGSize(width: 196, height: 38),
          "closed size: an auto-hidden menu bar skips the scaling")
    check(G.closedSize(for: laptop, screens: [laptop], notchHeight: 32.4, nonNotchHeight: 0).height == 32, "closed size: rounded to whole points")
    check(G.openSize == CGSize(width: 640, height: 190) && G.windowSize == CGSize(width: 640, height: 820) && G.openMaxHeight == 400
          && G.shadowPadding == 20 && G.openRadii == (31, 31), "sizes: open 640 × 190, window 640 × 820, max 400, padding 20, radii 31")
}

private func menuBarTests() {
    typealias G = ArisNotchGeometry
    check(G.defaultMenuBarHeight(hasNotch: true, osMajor: 26) == 38 && G.defaultMenuBarHeight(hasNotch: false, osMajor: 26) == 29
          && G.defaultMenuBarHeight(hasNotch: true, osMajor: 15) == 43 && G.defaultMenuBarHeight(hasNotch: false, osMajor: 14) == 23,
          "menu bar: defaults by OS and notch")
    check(G.menuBarHeight(of: external, osMajor: 26) == 24 && G.menuBarHeight(of: laptop, osMajor: 26) == 37, "menu bar: measured minus 1")
    var hidden = external
    hidden.visibleFrame.size.height = 1440
    check(G.menuBarHeight(of: hidden, osMajor: 26) == 29, "menu bar: auto-hidden -> the default")
    check(G.menuBarHeight(hasNotch: false, screens: [laptop, external], osMajor: 26) == 24
          && G.menuBarHeight(hasNotch: true, screens: [external], osMajor: 26) == 38, "menu bar: the first display of that kind, else the default")
    check(G.realNotchHeight([external, laptop]) == 38 && G.realNotchHeight([external]) == 38 && G.realNotchHeight([]) == 38,
          "real notch: the first notched display's inset, else 38")
    var short = laptop
    short.topInset = 32
    check(G.realNotchHeight([external, short]) == 32, "real notch: the inset itself")
    check([0, 7, 15, 26].map { G.migratedNonNotchHeight($0) } == [0, 15, 15, 26], "legacy height: 0 -> 0, 7 -> 15, 15 -> 15, 26 -> 26")
}

private func syncTests() {
    typealias G = ArisNotchGeometry
    var short = laptop
    short.topInset = 32
    let real = G.synced(notchRule: .matchRealNotch, nonNotchRule: .matchMenuBar, notchHeight: 10, nonNotchHeight: 10,
                        screens: [short, external], osMajor: 26)
    check(real.notchHeight == 32 && real.nonNotchHeight == 24 && real.nonNotchRule == .matchMenuBar, "sync: match real notch / match menu bar")
    let bar = G.synced(notchRule: .matchMenuBar, nonNotchRule: .custom, notchHeight: 10, nonNotchHeight: 20, screens: [short, external], osMajor: 26)
    check(bar.notchHeight == 37 && bar.nonNotchHeight == 20, "sync: notch follows the menu bar, custom stays")
    let custom = G.synced(notchRule: .custom, nonNotchRule: .custom, notchHeight: 33, nonNotchHeight: 0, screens: [short], osMajor: 26)
    check(custom.notchHeight == 33 && custom.nonNotchHeight == 0, "sync: custom heights are left alone")
    let wrong = G.synced(notchRule: .custom, nonNotchRule: .matchRealNotch, notchHeight: 33, nonNotchHeight: 5, screens: [external], osMajor: 26)
    check(wrong.nonNotchRule == .matchMenuBar && wrong.nonNotchHeight == 24, "sync: a flat display can't match a notch -> match the menu bar")
}

private func shapeTests() {
    let closed = NotchShape(topCornerRadius: 13, bottomCornerRadius: 13, circular: 1)
    check(NotchShape().topCornerRadius == 6 && NotchShape().bottomCornerRadius == 14 && NotchShape().circular == 0, "shape: defaults 6 / 14 / 0")
    check(abs(NotchShape(circular: 0).handle - 2.0 / 3) < 1e-9 && abs(closed.handle - 0.5522847498307936) < 1e-12
          && abs(NotchShape(circular: 0.5).handle - (2.0 / 3 + 0.5522847498307936) / 2) < 1e-9, "shape: the handle blends 2/3 -> the circle constant")
    var morph = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14, circular: 0)
    morph.animatableData = closed.animatableData
    check(morph == closed, "shape: animatable data round-trips")
    let rect = CGRect(x: 0, y: 0, width: 200, height: 32)
    let points = closed.outlinePoints(in: rect)
    check(points.first == CGPoint(x: 0, y: 0) && points.last == CGPoint(x: 200, y: 0), "shape: the outline runs shoulder tip to shoulder tip")
    check(points.allSatisfy { $0.y > 0 || $0.x == 0 || $0.x == 200 } && points.map(\.y).max() == 32, "shape: never along the top edge, down to the bottom")
    let bounds = closed.path(in: rect).boundingRect
    check(abs(bounds.width - 200) < 0.001 && abs(bounds.height - 32) < 0.001, "shape: the path fills its rect")
    let open = NotchShape(topCornerRadius: 31, bottomCornerRadius: 31).path(in: CGRect(x: 0, y: 0, width: 640, height: 190))
    check(open.contains(CGPoint(x: 320, y: 100)) && !open.contains(CGPoint(x: 33, y: 188)) && !open.contains(CGPoint(x: 5, y: 25)) && open.contains(CGPoint(x: 40, y: 2)),
          "shape: inside in the middle, outside past the bottom corner and in the shoulder's flare")
}
