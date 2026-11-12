//
//  ArisShelfController.swift
//  Aris
//
//  What the shelf page does with its tiles: selection, open, Show in Finder, Quick Look, share, copy, remove, and
//  dragging items out (copy or move per the preference; removed afterwards when "auto-remove" is on).
//

import AppKit
import Defaults
import SwiftUI

@MainActor
final class ArisShelfController: ObservableObject {
    static let shared = ArisShelfController()

    @Published var selection = ArisShelfSelection()
    private var store: ShelfStateViewModel { ShelfStateViewModel.shared }

    var order: [UUID] { store.ordered(reversed: Defaults[.reverseShelfOrdering]).map(\.id) }

    func items(_ ids: Set<UUID>) -> [ShelfItem] { store.items.filter { ids.contains($0.id) } }

    /// The tile's items for an action: the selection when the tile is part of it, else just the tile.
    func targets(for id: UUID) -> [ShelfItem] {
        selection.contains(id) ? items(selection.selected) : items([id])
    }

    func click(_ id: UUID, shift: Bool, command: Bool) {
        selection.click(id, shift: shift, command: command, order: order)
    }

    func focus(_ id: UUID) { selection.focus(id) }

    /// Resolves a file item, storing refreshed bookmark bytes when the old ones were stale.
    func url(of item: ShelfItem) -> URL? {
        guard case .file(let data) = item.kind, let resolved = ArisBookmark(data: data).resolve() else { return nil }
        if let fresh = resolved.refreshed { store.updateBookmark(of: item.id, to: fresh) }
        return resolved.url
    }

    func open(_ items: [ShelfItem]) {
        for item in items {
            switch item.kind {
            case .file: if let url = url(of: item) { ArisBookmark.withAccess(to: url) { _ = NSWorkspace.shared.open($0) } }
            case .link(let link): NSWorkspace.shared.open(link)
            case .text(let text):
                if let file = ArisShelfTempFiles().text(text) {
                    ArisShelfTempFiles.markScratch(file)
                    NSWorkspace.shared.open(file)
                }
            }
        }
    }

    func reveal(_ items: [ShelfItem]) {
        let files = items.compactMap(url(of:))
        if !files.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(files) }
    }

    func quickLook(_ items: [ShelfItem]) {
        ArisShelfQuickLook.shared.show(items.compactMap(url(of:)))
    }

    /// Text alone shares its string; otherwise the files' and links' URLs. Files stay open until the share ends.
    func share(_ items: [ShelfItem], from view: NSView) {
        let objects: [Any]
        if items.count == 1, case .text(let text) = items[0].kind {
            objects = [text]
        } else {
            objects = items.compactMap { item -> Any? in
                if case .link(let link) = item.kind { return link }
                return url(of: item)
            }
        }
        let files = objects.compactMap { $0 as? URL }.filter(\.isFileURL)
        let opened = files.filter { $0.startAccessingSecurityScopedResource() }
        SharingStateManager.shared.showPicker(for: objects, relativeTo: view) {
            opened.forEach { $0.stopAccessingSecurityScopedResource() }
        }
    }

    func copy(_ items: [ShelfItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.compactMap(\.pasteboardWriter))
    }

    func remove(_ items: [ShelfItem]) {
        store.remove(Set(items.map(\.id)))
        selection.keep(Set(store.items.map(\.id)))
    }

    /// The drag's operations: copy only when "copy on drag" is on, else whatever the destination picks.
    var dragOperations: NSDragOperation { Defaults[.copyOnDrag] ? .copy : [.copy, .move, .generic] }

    func dragEnded(_ items: [ShelfItem], operation: NSDragOperation) {
        if Defaults[.autoRemoveShelfItems], !operation.isEmpty { remove(items) }
    }
}
