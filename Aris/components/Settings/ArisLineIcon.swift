//
//  ArisLineIcon.swift
//  Aris
//
//  The Settings window's icons, drawn the measured way: a 24 grid, a 2-unit stroke with round caps and joins, outline
//  (ArisLineIconData's glyphs through ArisLineIconPath), in the colour of the text around it. Sizes by place are
//  ArisIconSizes. A name with no glyph falls back to the SF Symbol of that name, so nothing goes missing.
//

import SwiftUI

struct ArisLineIcon: View {
    let name: String
    /// The box the 24 grid is scaled into.
    var size: CGFloat = 20
    /// The stroke in grid units (2 everywhere unless a place says otherwise: 1.75 card headers, 1.6 info values, 2.25 chevrons).
    var stroke: CGFloat = 2

    init(_ name: String, size: CGFloat = 20, stroke: CGFloat = 2) {
        self.name = name
        self.size = size
        self.stroke = stroke
    }

    var body: some View {
        if let glyph = ArisLineIconPath.glyph(name) {
            ZStack {
                ArisGlyphShape(path: Path(glyph.stroke))
                    .stroke(style: StrokeStyle(lineWidth: stroke * size / ArisLineIconPath.grid, lineCap: .round, lineJoin: .round))
                ArisGlyphShape(path: Path(glyph.fill)).fill()
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            Image(systemName: name).font(.system(size: size * 0.8)).frame(width: size, height: size)
        }
    }
}

/// A glyph's path scaled from its 24 grid to the rect it is given.
struct ArisGlyphShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        let scale = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / ArisLineIconPath.grid, y: rect.height / ArisLineIconPath.grid)
        return path.applying(scale)
    }
}

/// The measured icon sizes by place (stroke 2 unless noted).
enum ArisIconSizes {
    /// The sidebar's pages, a settings row's icon, a card header (stroke 1.75).
    static let nav: CGFloat = 20
    static let row: CGFloat = 20
    static let cardHeaderStroke: CGFloat = 1.75
    /// Buttons, the select's chevrons.
    static let button: CGFloat = 14
    static let pill: CGFloat = 12
    /// A detail sheet's info strip value (stroke 1.6), its close button, a list chevron (stroke 2.25).
    static let info: CGFloat = 24
    static let infoStroke: CGFloat = 1.6
    static let close: CGFloat = 20
    static let chevron: CGFloat = 15
    static let chevronStroke: CGFloat = 2.25
}
