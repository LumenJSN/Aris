//
//  ArisShelfLook.swift
//  Aris
//
//  The shelf page's Aris look: the composer's surface behind the share tile and the tile strip (it brightens
//  while a file is over it), and AirDrop's mark drawn in one colour.
//

import SwiftUI

/// The composer's surface for the shelf page; `lit` while a file is over it.
struct ArisShelfSurface: View {
    let lit: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: ArisGlass.pillRadius, style: .continuous)
            .fill(Color.white.opacity(lit ? 0.12 : 0.06))
            .overlay {
                RoundedRectangle(cornerRadius: ArisGlass.pillRadius, style: .continuous)
                    .strokeBorder(lit ? Color.white.opacity(0.35) : Color.white.opacity(0.05), lineWidth: 1)
            }
    }
}

/// AirDrop's mark, drawn in one colour: three arcs opening downward around a point (the dot is added by the caller).
struct ArisAirDropGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.245)
        // From lower left, over the top, to lower right (y grows downward, so 270° is straight up).
        for radius in [0.2, 0.36, 0.52] {
            let r = rect.width * radius
            let points = stride(from: 140.0, through: 400.0, by: 5).map { degrees in
                CGPoint(x: center.x + r * cos(degrees * .pi / 180), y: center.y + r * sin(degrees * .pi / 180))
            }
            path.move(to: points[0])
            path.addLines(points)
        }
        return path
    }
}
