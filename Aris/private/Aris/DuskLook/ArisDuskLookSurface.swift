//
//  ArisDuskLookSurface.swift
//  Aris
//
//  The notch's surface in the dusk look: black at the top (the camera housing's band is full black, as always),
//  thinning evenly to clear glass at the bottom with the system assistant's measured fill, rim and shadow (ArisDuskLook.Surface).
//  Aris's own drawing over a plain glass base: the glass files are another branch's, so this look brings its own
//  layer and hands it the recipe as data; when the glass layer takes a recipe, this view is that call. Closed, and
//  with macOS's Reduce Transparency, it is solid black, as today.
//

import SwiftUI

struct ArisDuskLookSurface<S: Shape>: View {
    let shape: S
    let open: Bool
    /// The top band that sits beside the camera housing: full black.
    let band: CGFloat
    /// `dusk-frost`: the system's frosted glass under the fill instead of the clear one.
    var frosted = false
    /// What stands in for the glass where none can be drawn (the off-screen renders).
    var base: AnyView?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private typealias Spec = ArisDuskLook.Surface

    var body: some View {
        let glass = open && !reduceTransparency
        ZStack {
            shadow
            if !reduceTransparency { glassBase.opacity(glass ? 1 : 0) }
            GeometryReader { proxy in
                LinearGradient(stops: Spec.stops(height: proxy.size.height, band: band, open: open, glass: !reduceTransparency, base: baseShare).map {
                    .init(color: Color(.sRGB, white: $0.grey, opacity: $0.coverage), location: $0.location)
                }, startPoint: .top, endPoint: .bottom)
            }
            .clipShape(shape)
            if glass { rim }
        }
        .animation(ArisDuskLookMotion.surface(open: open), value: open)
    }

    /// The shadow alone, cut out under the surface so it never shows through the clear part.
    private var shadow: some View {
        shape.fill(.black)
            .shadow(color: .black.opacity(open ? Spec.shadowAlpha : 0.25), radius: open ? Spec.shadowSigma : 6, y: open ? Spec.shadowY : 2)
            .overlay(shape.fill(.black).blendMode(.destinationOut))
            .compositingGroup()
            .allowsHitTesting(false)
    }

    /// Half a point of light inside the edge: almost none at the top and sides, strongest along the bottom.
    private var rim: some View {
        shape.stroke(LinearGradient(stops: [
            .init(color: .white.opacity(Spec.rimTop), location: 0),
            .init(color: .white.opacity(Spec.rimSide), location: 0.3),
            .init(color: .white.opacity(Spec.rimSide), location: 0.8),
            .init(color: .white.opacity(Spec.rimBottom), location: 1),
        ], startPoint: .top, endPoint: .bottom), lineWidth: 2 * Spec.rimWidth)
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    /// What the glass under the fill already takes (ArisDuskLook.Surface.clearBase); a stand-in takes nothing.
    private var baseShare: Double { base != nil ? 0 : Self.baseShare(frosted: frosted) }

    static func baseShare(frosted: Bool) -> Double { frosted ? ArisDuskLook.Surface.frostBase : ArisDuskLook.Surface.clearBase }

    @ViewBuilder
    private var glassBase: some View {
        if let base {
            base.clipShape(shape)
        } else if #available(macOS 26.0, *) {
            // Public glass only. Aris's clear glass with its tint (untinted, the system dims it far more: 167 of
            // 255 over white in the VM) under the system assistant's fill reads as the system assistant's over white and over black; regular is
            // frosted as the system assistant's is but reads darker over a white window.
            Color.clear.glassEffect(frosted ? .regular : .clear.tint(ArisDuskLookBase.tint), in: shape)
        } else {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).clipShape(shape)
        }
    }
}

/// The dusk look's clocks: the system assistant's measured springs (ArisDuskLook.Motion), or Aris's own curves with Reduce Motion
/// (a spring's overshoot is motion nobody asked for).
enum ArisDuskLookMotion {
    static var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func spring(_ spring: ArisDuskLook.Spring) -> Animation {
        .spring(response: spring.response, dampingFraction: spring.damping)
    }

    /// The surface opening (growing) or closing (shrinking).
    static func surface(open: Bool) -> Animation {
        if reduceMotion() { return .easeOut(duration: open ? 0.28 : 0.2) }
        return spring(open ? ArisDuskLook.Motion.grow : ArisDuskLook.Motion.shrink)
    }

    /// The open surface following its content's height.
    static func resize(taller: Bool) -> Animation {
        if reduceMotion() { return .easeInOut(duration: 0.34) }
        return spring(taller ? ArisDuskLook.Motion.grow : ArisDuskLook.Motion.shrink)
    }
}

/// The clear glass's tint, the one Aris's own glass uses (sRGB 0, 0, .02 at .18).
enum ArisDuskLookBase {
    static let tint = Color(.sRGB, red: 0, green: 0, blue: 0.02, opacity: 0.18)
}

/// What the content needs to know of the surface it stands on, for the scrim.
struct ArisDuskLookSurfaceInfo: Equatable {
    var height: CGFloat = 0
    var band: CGFloat = 0
    var base: Double = 0
}

private struct ArisDuskLookSurfaceKey: EnvironmentKey {
    static let defaultValue = ArisDuskLookSurfaceInfo()
}

extension EnvironmentValues {
    var arisDuskLookSurface: ArisDuskLookSurfaceInfo {
        get { self[ArisDuskLookSurfaceKey.self] }
        set { self[ArisDuskLookSurfaceKey.self] = newValue }
    }
}

/// The black behind the content column in the dusk look (ArisDuskLook.Scrim): as much as it takes for Aris's white
/// text to stay readable over a white window where the system assistant's fill has thinned, and nothing where the surface is dark
/// enough already. A soft-edged plate the column's own size, so the margins and the bottom inset stay the system assistant's glass.
struct ArisDuskLookScrim: View {
    /// The surface's coordinate space: the column's place in it decides how much black it needs.
    static let space = "ArisDuskLookSurface"

    @Environment(\.arisDuskLookSurface) private var surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject private var duskLook = ArisDuskLookGate.shared

    private typealias Spec = ArisDuskLook.Scrim

    var body: some View {
        if ArisDuskLookNow.surfaceOn, !reduceTransparency, surface.height > 0 {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(Self.space))
                LinearGradient(stops: Spec.stops(top: frame.minY, bottom: frame.maxY, height: surface.height, band: surface.band, base: surface.base).map {
                    .init(color: .black.opacity($0.alpha), location: $0.location)
                }, startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: Spec.radius, style: .continuous))
                .padding(.horizontal, -Spec.outset)
                .blur(radius: Spec.soften)
            }
            .allowsHitTesting(false)
        }
    }
}
