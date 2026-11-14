//
//  ArisShelfTileLayout.swift
//  Aris
//
//  The arithmetic of the shelf's file tiles: how big a tile is in the 104-point strip of the open notch, how many
//  sit whole side by side, how many name chips the home page's shelf row has room for, and whether that row shows.
//  Sizes come from the viewport, not from boring.notch's fixed 105 × 108 tile, which stood taller than the strip and
//  was clipped.
//

import CoreGraphics

enum ArisShelfTileLayout {
    /// The open notch's shelf strip (ContentView's frame for the shelf page).
    static let stripHeight: CGFloat = 104
    /// From the panel's edge to the tiles, and between tiles: the most common gap.
    static let inset: CGFloat = 8
    static let spacing: CGFloat = 8
    /// Narrower than this and the name has no room; fewer, wider tiles instead.
    static let minTileWidth: CGFloat = 84
    /// Inside a tile: padding around the icon and name, and the 4-point step between them.
    static let padding: CGFloat = 8
    static let gap: CGFloat = 4
    /// One line of 11-point name, truncated in the middle so the extension stays ("Lecture…notes.pdf").
    static let nameSize: CGFloat = 11
    static let nameHeight: CGFloat = 14

    struct Tile: Equatable {
        let columns: Int
        let width: CGFloat
        let height: CGFloat
        let icon: CGFloat
        let cornerRadius: CGFloat
    }

    /// Tiles for a panel of `viewport` size: as many whole columns as fit at `minTileWidth`, sharing the width
    /// evenly; the strip's height less the inset; the corner concentric with the panel's (outer = inner + inset).
    static func tiles(in viewport: CGSize, panelRadius: CGFloat) -> Tile {
        let room = max(0, viewport.width - 2 * inset)
        let columns = max(1, Int(((room + spacing) / (minTileWidth + spacing)).rounded(.down)))
        let width = max(0, ((room - CGFloat(columns - 1) * spacing) / CGFloat(columns)).rounded(.down))
        let height = max(0, viewport.height - 2 * inset)
        let icon = max(0, min(height - 2 * padding - gap - nameHeight, width - 2 * padding))
        return Tile(columns: columns, width: width, height: height, icon: icon, cornerRadius: max(0, panelRadius - inset))
    }

    /// The home page's shelf row: name chips at least this wide, 6 apart, beside the tray glyph and "모두 N".
    static let minChipWidth: CGFloat = 100
    static let chipSpacing: CGFloat = 6
    static let chipRowReserved: CGFloat = 60

    /// How many chips fit a row `rowWidth` wide without squeezing a name to a couple of letters (at least one).
    static func chipsShown(rowWidth: CGFloat) -> Int {
        max(1, Int(((rowWidth - chipRowReserved - chipSpacing) / (minChipWidth + chipSpacing)).rounded(.down)))
    }

    /// Whether the home page has its shelf row: files that still lead somewhere, no turn on screen, and 첫 화면에도
    /// 보이기 on (off, the shelf's files show only in the Shelf tab; dragging over the notch still offers the shelf).
    static func homeRowShown(files: Int, turnShowing: Bool, onHome: Bool) -> Bool {
        onHome && !turnShowing && files > 0
    }
}
