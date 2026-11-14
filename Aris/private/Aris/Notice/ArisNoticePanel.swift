//
//  ArisNoticePanel.swift
//  Aris
//
//  The notification cards' own window, not the notch's: a borderless, non-activating, transparent panel one level
//  under the notch's (mainMenu + 2; the notch is + 3), on every space and over full-screen apps, centred on the notch's
//  display with the cards' top 50 under the work area. It never becomes key or main, so it never takes the keyboard or
//  focus from the frontmost app; its buttons take the first click. It lets every click through (ignoresMouseEvents)
//  except while the pointer is on a card, its close circle, a peeking layer or the "+N" row (ArisNoticeLayout.hitRects).
//

import AppKit
import Defaults
import SwiftUI

final class ArisNoticePanel: NSPanel {
    init() {
        super.init(contentRect: CGRect(origin: .zero, size: ArisNoticeLayout.windowSize), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        // One level under the notch's panel (ArisNotchPanel: mainMenu + 3): the open notch is always drawn over the cards.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        // The system's appearance, followed live: the glass card is light or dark with it (ArisNoticePalette).
        appearance = nil
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Placed on `screen`: centred, the cards' top 50 under its work area's top.
    func place(on screen: NSScreen) {
        let frame = ArisNoticeLayout.windowFrame(workArea: screen.visibleFrame)
        if self.frame != frame { setFrame(frame, display: false) }
    }

    /// The pointer `point` (screen coordinates) in the cards' space (x from the cards' left, y down from their top).
    func cardsPoint(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x - frame.minX - ArisNoticeLayout.cardsOrigin.x, y: frame.maxY - point.y - ArisNoticeLayout.cardsOrigin.y)
    }
}

/// The panel's content: its buttons take the first click although the panel is never key.
final class ArisNoticeHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
