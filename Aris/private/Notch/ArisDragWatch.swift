//
//  ArisDragWatch.swift
//  Aris
//
//  Spots a content drag (files, links or text) heading for the notch while another app is in front, so the notch can
//  open before the pointer arrives. A drag counts as content when the drag pasteboard changed since the mouse went
//  down and every item on it offers a file URL, a URL or plain text — dragging a window by its title bar doesn't.
//

import AppKit

/// The decisions, fed one mouse event at a time (tests drive it directly).
struct ArisDragWatch {
    enum Event: Equatable { case entered, exited, moved(CGPoint) }

    let region: CGRect
    private var tracking = false
    private var startCount = 0
    private var isContent = false
    private var inside = false

    init(region: CGRect) { self.region = region }

    mutating func mouseDown(changeCount: Int) {
        tracking = true
        startCount = changeCount
        isContent = false
        inside = false
    }

    /// `qualifies` says whether every pasteboard item offers one of the content types.
    mutating func dragged(to point: CGPoint, changeCount: Int, qualifies: () -> Bool) -> [Event] {
        guard tracking else { return [] }
        if !isContent, changeCount != startCount, qualifies() { isContent = true }
        guard isContent else { return [] }
        var events: [Event] = [.moved(point)]
        let now = region.contains(point)
        if now != inside {
            inside = now
            events.append(now ? .entered : .exited)
        }
        return events
    }

    mutating func mouseUp() {
        tracking = false
        isContent = false
        inside = false
    }
}

/// Global mouse monitors around one notch's region (screen coordinates).
final class DragDetector {
    var onDragEntersNotchRegion: (() -> Void)?
    var onDragExitsNotchRegion: (() -> Void)?
    var onDragMove: ((CGPoint) -> Void)?
    /// The mouse came up: any drag is over.
    var onDragEnds: (() -> Void)?

    private var watch: ArisDragWatch
    private var monitors: [Any] = []
    private static let contentTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string]

    init(notchRegion: CGRect) {
        watch = ArisDragWatch(region: notchRegion)
    }

    deinit { stopMonitoring() }

    func startMonitoring() {
        guard monitors.isEmpty else { return }
        let pasteboard = NSPasteboard(name: .drag)
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.watch.mouseDown(changeCount: pasteboard.changeCount)
        }
        let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard let self else { return }
            let events = watch.dragged(to: NSEvent.mouseLocation, changeCount: pasteboard.changeCount) {
                guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return false }
                return items.allSatisfy { item in item.types.contains { Self.contentTypes.contains($0) } }
            }
            for event in events {
                switch event {
                case .entered: onDragEntersNotchRegion?()
                case .exited: onDragExitsNotchRegion?()
                case .moved(let point): onDragMove?(point)
                }
            }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.watch.mouseUp()
            self?.onDragEnds?()
        }
        monitors = [down, drag, up].compactMap { $0 }
    }

    func stopMonitoring() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        watch.mouseUp()
    }
}
