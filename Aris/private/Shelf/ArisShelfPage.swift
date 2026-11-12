//
//  ArisShelfPage.swift
//  Aris
//
//  The open notch's shelf page (spec 07, "Shelf page look"): the share tile on the left and the strip of item tiles
//  on the right, both on the user's ArisShelfSurface, 12 pt apart.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    let dropInteraction: DropInteractionState
    let animation: Animation?

    init(dropInteraction: DropInteractionState, animation: Animation?) {
        self.dropInteraction = dropInteraction
        self.animation = animation
    }

    var body: some View {
        HStack(spacing: 12) {
            ArisShareTile(dropInteraction: dropInteraction)
                .aspectRatio(1, contentMode: .fit)
            ArisShelfStrip(dropInteraction: dropInteraction, animation: animation)
        }
        .frame(height: ArisShelfTileLayout.stripHeight)
    }
}

/// The scrolling strip of tiles, or the empty hint.
struct ArisShelfStrip: View {
    let dropInteraction: DropInteractionState
    let animation: Animation?
    @ObservedObject private var store = ShelfStateViewModel.shared
    @Default(.reverseShelfOrdering) private var reversed

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: ArisGlass.pillRadius, style: .continuous) }

    var body: some View {
        let items = store.ordered(reversed: reversed)
        ZStack {
            ArisShelfSurface(lit: dropInteraction.dragDetectorTargeting)
            if items.isEmpty {
                ArisShelfEmpty()
            } else {
                GeometryReader { geometry in
                    let tile = ArisShelfTileLayout.tiles(in: geometry.size, panelRadius: ArisGlass.pillRadius)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: ArisShelfTileLayout.spacing) {
                            ForEach(items) { item in
                                ArisShelfTile(item: item, tile: tile, dropInteraction: dropInteraction)
                            }
                        }
                        .padding(ArisShelfTileLayout.inset)
                    }
                    .clipShape(shape)
                }
            }
        }
        .animation(animation, value: items)
        .contentShape(shape)
        .onDrop(of: [.item], isTargeted: Binding(get: { dropInteraction.dragDetectorTargeting },
                                                  set: { dropInteraction.dragDetectorTargeting = $0 })) { providers in
            store.load(providers)
            dropInteraction.dragDetectorTargeting = false
            return true
        }
    }
}

struct ArisShelfEmpty: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .symbolVariant(.fill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .imageScale(.large)
            Text("Drop files here")
                .foregroundStyle(.gray)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.medium)
        }
        .padding()
    }
}

/// One item: the user's tile face, a selection / drop highlight behind it, and the AppKit control on top.
struct ArisShelfTile: View {
    let item: ShelfItem
    let tile: ArisShelfTileLayout.Tile
    let dropInteraction: DropInteractionState
    @ObservedObject private var controller = ArisShelfController.shared
    @Environment(\.displayScale) private var scale
    @State private var thumbnail: NSImage?
    @State private var targeted = false
    @State private var hovered = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: tile.cornerRadius, style: .continuous) }

    var body: some View {
        let image = thumbnail ?? item.icon
        let selected = controller.selection.contains(item.id)
        ArisShelfTileFace(image: image, name: item.displayName, tile: tile)
            .background {
                if hovered {
                    shape.fill(Color.accentColor.opacity(0.25)).overlay(shape.strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 3))
                } else if selected {
                    shape.fill(Color.accentColor.opacity(0.15)).overlay(shape.strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2))
                }
            }
            .animation(.easeInOut(duration: 0.1), value: selected)
            .animation(.easeInOut(duration: 0.1), value: hovered)
            .overlay(ArisShelfTileControl(item: item, image: image))
            .onDrop(of: [.item], isTargeted: $targeted) { providers in
                ShelfStateViewModel.shared.load(providers)
                return true
            }
            .onChange(of: targeted) { _, now in
                dropInteraction.dragDetectorTargeting = now
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    if targeted == now { hovered = now }
                }
            }
            .task(id: item.id) {
                guard let url = item.fileURL else { return }
                thumbnail = await ArisShelfThumbnails.shared.thumbnail(url, side: tile.icon, scale: scale)
            }
    }
}
