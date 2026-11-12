//
//  ArisShelfSupport.swift
//  Aris
//
//  The shelf's smaller parts: which tiles are selected, tile images (icons and Quick Look thumbnails), the Quick
//  Look panel, and what an item puts on a pasteboard.
//

import AppKit
import QuickLookThumbnailing
import Quartz
import SwiftUI

/// Tile selection: click selects one, ⇧-click extends from the anchor, ⌘-click toggles.
struct ArisShelfSelection: Equatable {
    private(set) var selected: Set<UUID> = []
    private(set) var anchor: UUID?

    mutating func click(_ id: UUID, shift: Bool, command: Bool, order: [UUID]) {
        if command {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            anchor = id
        } else if shift, let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) {
            selected = Set(order[min(from, to)...max(from, to)])
        } else {
            selected = [id]
            anchor = id
        }
    }

    /// Before a right-click or a drag: keep a selection that includes the tile, else select just it.
    mutating func focus(_ id: UUID) {
        if !selected.contains(id) { selected = [id]; anchor = id }
    }

    mutating func keep(_ ids: Set<UUID>) {
        selected.formIntersection(ids)
        if let anchor, !ids.contains(anchor) { self.anchor = nil }
    }

    func contains(_ id: UUID) -> Bool { selected.contains(id) }
}

enum ArisShelfIcons {
    static let glyphBox = CGSize(width: 51, height: 54)

    static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }

    /// Text and link items: their symbol, black, on a white card (the look of a document icon).
    static func card(_ name: String) -> NSImage {
        let canvas = NSSize(width: 108, height: 108)
        let card = NSRect(x: 13.5, y: 2.5, width: 81, height: 103)
        return NSImage(size: canvas, flipped: false) { _ in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: card, xRadius: 4.5, yRadius: 4.5).fill()
            // The symbol drawn into a square in the card's middle (filling it, so a wide symbol stands taller).
            let configuration = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
                .applying(.init(paletteColors: [.black]))
            if let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                let box = ArisShelfIcons.glyphBox
                glyph.draw(in: NSRect(x: card.midX - box.width / 2, y: card.midY - box.height / 2, width: box.width, height: box.height))
            }
            return true
        }
    }
}

/// Quick Look thumbnails at tile size, made once per file and size.
@MainActor
final class ArisShelfThumbnails {
    static let shared = ArisShelfThumbnails()
    private var cache: [String: NSImage] = [:]

    func cached(_ url: URL, side: CGFloat) -> NSImage? { cache[key(url, side)] }

    func thumbnail(_ url: URL, side: CGFloat, scale: CGFloat) async -> NSImage? {
        if let hit = cached(url, side: side) { return hit }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale,
                                                   representationTypes: [.icon, .thumbnail])
        // Icon mode: Quick Look draws the thumbnail with its own edges, like a Finder icon (the tile adds no mask).
        request.iconMode = true
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage else { return nil }
        cache[key(url, side)] = image
        return image
    }

    private func key(_ url: URL, _ side: CGFloat) -> String { "\(url.path)#\(Int(side))" }
}

/// The system Quick Look panel for the selected files.
@MainActor
final class ArisShelfQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = ArisShelfQuickLook()
    private var urls: [URL] = []
    private var opened: [URL] = []
    private var closing: NSObjectProtocol?

    /// Shows the panel; the files' scoped access stays open until the panel closes.
    func show(_ files: [URL]) {
        guard !files.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        close()
        urls = files
        opened = files.filter { $0.startAccessingSecurityScopedResource() }
        panel.dataSource = self
        panel.delegate = self
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        opened.forEach { $0.stopAccessingSecurityScopedResource() }
        opened = []
        if let closing { NotificationCenter.default.removeObserver(closing) }
        closing = nil
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}

extension ShelfItem {
    /// What the item puts on a pasteboard or hands to a share service.
    var shareObject: Any? {
        switch kind {
        case .file: fileURL
        case .text(let text): text
        case .link(let url): url
        }
    }

    var pasteboardWriter: NSPasteboardWriting? {
        switch kind {
        case .file: fileURL as NSURL?
        case .text(let text): text as NSString
        case .link(let url): url as NSURL
        }
    }
}
