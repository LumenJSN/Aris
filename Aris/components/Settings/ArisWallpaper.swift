//
//  ArisWallpaper.swift
//  Aris
//
//  A neutral wallpaper drawn in code: a soft dawn sky over two low hills. It stands behind the feature sheets' demo
//  scenes (a desktop for Aris's notch to act on) and behind the offscreen renders' stand-in for the window's material.
//  No image of anyone else's.
//

import SwiftUI

struct ArisWallpaper: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            // The sky: a cool blue at the top warming to a pale peach at the horizon.
            context.fill(Path(rect), with: .linearGradient(Gradient(stops: [
                .init(color: Color(arisHex: 0x9fb8dc), location: 0),
                .init(color: Color(arisHex: 0xc7d3e8), location: 0.45),
                .init(color: Color(arisHex: 0xf0d9c8), location: 0.78),
                .init(color: Color(arisHex: 0xe8c3b0), location: 1),
            ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            // A low sun's glow.
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.52, y: size.height * 0.38, width: size.width * 0.5, height: size.width * 0.5)),
                         with: .radialGradient(Gradient(colors: [Color(arisHex: 0xfff3e2, 0.85), Color(arisHex: 0xfff3e2, 0)]),
                                               center: CGPoint(x: size.width * 0.77, y: size.height * 0.38 + size.width * 0.25),
                                               startRadius: 0, endRadius: size.width * 0.25))
            // Two hills, the far one hazier.
            context.fill(hill(size, base: 0.74, peak: 0.6, at: 0.3), with: .color(Color(arisHex: 0x8f9fc0, 0.55)))
            context.fill(hill(size, base: 0.86, peak: 0.7, at: 0.72), with: .linearGradient(Gradient(colors: [Color(arisHex: 0x5d6f96), Color(arisHex: 0x46557a)]),
                                                                                     startPoint: CGPoint(x: 0, y: size.height * 0.7), endPoint: CGPoint(x: 0, y: size.height)))
        }
    }

    /// A hill across the whole width: `base` and `peak` are heights as shares of the height, the peak at `at` across.
    private func hill(_ size: CGSize, base: CGFloat, peak: CGFloat, at: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height * base))
        path.addCurve(to: CGPoint(x: size.width, y: size.height * (base + 0.04)),
                      control1: CGPoint(x: size.width * (at - 0.15), y: size.height * peak),
                      control2: CGPoint(x: size.width * (at + 0.2), y: size.height * peak))
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}
