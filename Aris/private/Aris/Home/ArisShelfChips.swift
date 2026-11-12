//
//  ArisShelfChips.swift
//  Aris
//
//  The shelf, folded into the open notch: what's on it as small chips you can drag back out, and "모두" for the
//  full shelf. And the drop target shown while you drag something over the notch: half for the shelf, half for Aris.
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct ArisShelfChips: View {
    @ObservedObject private var shelf = ShelfStateViewModel.shared
    let openShelf: () -> Void

    /// As many as fit with room for a name; five squeezed each to a few letters ("Lec…").
    private static let shown = ArisShelfTileLayout.chipsShown(rowWidth: ArisGlass.contentWidth)

    /// Items that still lead somewhere (a file whose link no longer opens has no name).
    static func visible(_ items: [ShelfItem]) -> [ShelfItem] { items.filter { !$0.displayName.isEmpty } }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill").font(.system(size: 10)).foregroundStyle(ArisGlass.secondaryText)
            ForEach(Self.visible(shelf.items).prefix(Self.shown)) { item in
                HStack(spacing: 5) {
                    Image(nsImage: item.icon).resizable().scaledToFit().frame(width: 14, height: 14)
                    Text(item.displayName).font(.system(size: 11.5)).foregroundStyle(ArisGlass.text)
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .frame(maxWidth: 120)
                .background(Capsule().fill(.white.opacity(0.08)))
                .onDrag { item.fileURL.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider(object: item.displayName as NSString) }
            }
            Spacer(minLength: 0)
            Button(action: openShelf) {
                Text(ArisShelfWords.label(count: shelf.items.count, shown: Self.shown))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(ArisGlass.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 26)
    }
}

/// Drop here: left keeps it on the shelf, right hands it to Aris for the next request. One drop target for both
/// halves (the side comes from where you let go), which also tells the notch a drag is still over it.
struct ArisDropZones: View {
    @EnvironmentObject private var vm: ArisNotchModel
    @State private var over: Side?

    enum Side { case shelf, aris }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                zone(.shelf, symbol: "tray.and.arrow.down.fill", title: ArisShelfWords.keep())
                zone(.aris, symbol: "sparkles", title: ArisShelfWords.give())
            }
            .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                    delegate: ArisDropDelegate(width: geometry.size.width, interaction: vm.dropInteraction, over: $over))
        }
        .frame(height: 84)
        .animation(.easeOut(duration: 0.15), value: lit)
    }

    /// The half under the drag, from whichever target is getting it.
    private var lit: Side? { over ?? vm.dropInteraction.homeDropSide }

    private func zone(_ side: Side, symbol: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
            Text(title).font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(lit == side ? Color.white : ArisGlass.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: ArisGlass.pillRadius, style: .continuous)
            .fill(.white.opacity(lit == side ? 0.14 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: ArisGlass.pillRadius, style: .continuous)
            .strokeBorder(.white.opacity(lit == side ? 0.32 : 0.06), lineWidth: 1))
        .scaleEffect(lit == side ? 1.02 : 1)
    }
}

private struct ArisDropDelegate: DropDelegate {
    let width: CGFloat
    let interaction: DropInteractionState
    @Binding var over: ArisDropZones.Side?

    private func side(_ info: DropInfo) -> ArisDropZones.Side { info.location.x < width / 2 ? .shelf : .aris }

    func dropEntered(info: DropInfo) {
        interaction.dropZoneTargeting = true
        over = side(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        interaction.dropZoneTargeting = true
        over = side(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        // The closed notch's drag detector is gone once the notch opened; its flag may never have been cleared.
        interaction.dropZoneTargeting = false
        interaction.dragDetectorTargeting = false
        over = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        over = nil
        ArisDropZones.deliver(info, to: side(info), interaction: interaction)
        return true
    }
}

extension ArisDropZones {
    /// The shelf keeps what's dropped on its half; files dropped on Aris's half ride along with the next request.
    static func deliver(_ info: DropInfo, to side: Side, interaction: DropInteractionState) {
        interaction.dropEvent = true
        interaction.dropZoneTargeting = false
        interaction.dragDetectorTargeting = false
        interaction.generalDropTargeting = false
        let providers = info.itemProviders(for: [.fileURL, .url, .utf8PlainText, .plainText, .data])
        switch side {
        case .shelf:
            ShelfStateViewModel.shared.load(providers)
        case .aris:
            // The notch stays open on the composer for what to do with them (BUG-24a).
            interaction.arisDropHold = true
            Task { @MainActor in
                let urls = await fileURLs(providers)
                Logger(subsystem: "com.lumenjsn.aris", category: "drop").notice("aris drop: \(providers.count, privacy: .public) providers, \(urls.count, privacy: .public) files")
                // They wait for the next request, with the chips for what Aris can do with them (ArisDropModel).
                ArisDropModel.shared.dropped(urls)
            }
        }
    }

    private static func fileURLs(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        // The shelf's own loader: loadObject(ofClass: URL.self) came back empty for Finder-style file drags.
        // SwiftUI hands the drag over as a generic item, so fall back to it like ShelfDropService does.
        for provider in providers {
            var url = await provider.extractFileURL()
            if url == nil { url = await provider.extractItem() }
            if let url, url.isFileURL { urls.append(url) }
        }
        return urls
    }
}
