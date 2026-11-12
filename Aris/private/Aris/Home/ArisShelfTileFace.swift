//
//  ArisShelfTileFace.swift
//  Aris
//
//  What a shelf tile shows: the file's icon or Quick Look thumbnail, whole, over one line of name truncated in the
//  middle. Sized by ArisShelfTileLayout so the tile fits the shelf strip.
//

import AppKit
import SwiftUI

struct ArisShelfTileFace: View {
    let image: NSImage
    let name: String
    let tile: ArisShelfTileLayout.Tile

    var body: some View {
        VStack(spacing: ArisShelfTileLayout.gap) {
            // No corner mask: Quick Look's icon-mode thumbnails and Finder icons draw their own edges, and a
            // rounded clip on the square frame shaved their corners.
            Image(nsImage: image)
                .resizable().scaledToFit()
                .frame(width: tile.icon, height: tile.icon)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
            Text(name)
                .font(.system(size: ArisShelfTileLayout.nameSize, weight: .medium))
                .foregroundStyle(ArisGlass.text)
                .lineLimit(1)
                .truncationMode(.middle)
                // 15 points tall, a point over the layout's line, so a Korean name's fallback glyphs aren't clipped.
                .frame(maxWidth: .infinity, minHeight: 15, maxHeight: 15)
        }
        // The name gets the tile's width less a 4-point edge; the icon keeps the full padding.
        .padding(.vertical, ArisShelfTileLayout.padding)
        .padding(.horizontal, ArisShelfTileLayout.gap)
        .frame(width: tile.width, height: tile.height)
    }
}
