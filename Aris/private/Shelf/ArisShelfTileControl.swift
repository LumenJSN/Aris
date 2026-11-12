//
//  ArisShelfTileControl.swift
//  Aris
//
//  The AppKit layer over each shelf tile: clicks (⇧ range, ⌘ toggle, ⌃ = right click, double-click opens), the
//  right-click menu, Space for Quick Look, and dragging the selection out as files, text and links.
//

import AppKit
import SwiftUI

struct ArisShelfTileControl: NSViewRepresentable {
    let item: ShelfItem
    let image: NSImage

    func makeNSView(context: Context) -> ArisShelfTileView {
        let view = ArisShelfTileView()
        view.item = item
        view.image = image
        return view
    }

    func updateNSView(_ view: ArisShelfTileView, context: Context) {
        view.item = item
        view.image = image
    }
}

@MainActor
final class ArisShelfTileView: NSView, NSDraggingSource {
    var item: ShelfItem?
    var image = NSImage()

    private enum Action: Int { case open = 1, reveal, quickLook, share, copy, remove }
    private static let dragStart: CGFloat = 3

    private var downPoint: NSPoint?
    private var downEvent: NSEvent?
    private var collapseOnUp = false
    private var dragged: [ShelfItem] = []
    private var dragAccess: [URL] = []
    private var controller: ArisShelfController { .shared }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let item else { return }
        if event.modifierFlags.contains(.control) { return rightMouseDown(with: event) }
        window?.makeFirstResponder(self)
        downPoint = event.locationInWindow
        downEvent = event
        let shift = event.modifierFlags.contains(.shift), command = event.modifierFlags.contains(.command)
        collapseOnUp = !shift && !command && controller.selection.contains(item.id)
        if !collapseOnUp { controller.click(item.id, shift: shift, command: command) }
        if event.clickCount == 2 { controller.open(controller.targets(for: item.id)) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let item, let start = downPoint, let down = downEvent else { return }
        let point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) > Self.dragStart else { return }
        downPoint = nil
        collapseOnUp = false
        beginDrag(controller.targets(for: item.id), event: down)
    }

    override func mouseUp(with event: NSEvent) {
        if collapseOnUp, let item { controller.click(item.id, shift: false, command: false) }
        collapseOnUp = false
        downPoint = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let item else { return }
        controller.focus(item.id)
        NSMenu.popUpContextMenu(menu(for: controller.targets(for: item.id)), with: event, for: self)
    }

    override func keyDown(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " ", let item else { return super.keyDown(with: event) }
        controller.quickLook(controller.targets(for: item.id))
    }

    // MARK: Menu

    private func menu(for items: [ShelfItem]) -> NSMenu {
        let menu = NSMenu()
        let hasFile = items.contains { if case .file = $0.kind { true } else { false } }
        func add(_ title: String, _ action: Action) {
            let entry = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            entry.tag = action.rawValue
            entry.target = self
            menu.addItem(entry)
        }
        add(String(localized: "Open"), .open)
        if hasFile {
            add(String(localized: "Show in Finder"), .reveal)
            add(String(localized: "Quick Look"), .quickLook)
        }
        menu.addItem(.separator())
        add(String(localized: "Share…"), .share)
        add(String(localized: "Copy"), .copy)
        menu.addItem(.separator())
        add(String(localized: "Remove"), .remove)
        return menu
    }

    /// Menu actions go by tag, never by the (translated) title.
    @objc private func choose(_ sender: NSMenuItem) {
        guard let item, let action = Action(rawValue: sender.tag) else { return }
        let items = controller.targets(for: item.id)
        switch action {
        case .open: controller.open(items)
        case .reveal: controller.reveal(items)
        case .quickLook: controller.quickLook(items)
        case .share: controller.share(items, from: self)
        case .copy: controller.copy(items)
        case .remove: controller.remove(items)
        }
    }

    // MARK: Drag out

    private func beginDrag(_ items: [ShelfItem], event: NSEvent) {
        dragged = items
        dragAccess = []
        let preview = ArisShelfDragPreview.image(for: items.first ?? item!, image: image, scale: window?.backingScaleFactor ?? 2)
        let draggingItems = items.compactMap { item -> NSDraggingItem? in
            var writer = item.pasteboardWriter
            if case .file = item.kind, let url = controller.url(of: item) {
                if url.startAccessingSecurityScopedResource() { dragAccess.append(url) }
                writer = url as NSURL
            }
            guard let writer else { return nil }
            let dragging = NSDraggingItem(pasteboardWriter: writer)
            let origin = convert(event.locationInWindow, from: nil)
            dragging.setDraggingFrame(NSRect(x: origin.x - preview.size.width / 2, y: origin.y - preview.size.height / 2,
                                             width: preview.size.width, height: preview.size.height), contents: preview)
            return dragging
        }
        guard !draggingItems.isEmpty else { return }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        MainActor.assumeIsolated { controller.dragOperations }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated {
            dragAccess.forEach { $0.stopAccessingSecurityScopedResource() }
            dragAccess = []
            controller.dragEnded(dragged, operation: operation)
            dragged = []
        }
    }
}

/// The image under the pointer while dragging a tile: the picture fitted into 56 pt (radius 12) over the name on an
/// accent chip, 105 pt wide, rendered at the screen's scale.
enum ArisShelfDragPreview {
    @MainActor
    static func image(for item: ShelfItem, image: NSImage, scale: CGFloat) -> NSImage {
        let view = VStack(spacing: 4) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(item.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
        }
        .frame(width: 105)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.nsImage ?? image
    }
}
