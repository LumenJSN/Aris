//
//  ArisDictationPillPanel.swift
//  Aris
//
//  The dictation pill's own window: a borderless, non-activating, transparent panel at the bottom centre of the
//  screen being typed on, above ordinary windows and the Dock, on every space and over full-screen apps. It never
//  becomes key or main, so the app being dictated into keeps the keyboard and its focus; a click on the pill reaches it
//  (first mouse) without activating Aris. It lets every click through (ignoresMouseEvents) except while the pointer is
//  on the pill itself (ArisDictationPillCenter watches the pointer).
//

import AppKit
import Defaults
import SwiftUI

final class ArisDictationPillPanel: NSPanel {
    /// Under the notch's panel (mainMenu + 3) and the cards' (+ 2), over the Dock and ordinary windows.
    static let level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    static let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let behaviour: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: ArisDictationPillRules.windowSize), styleMask: Self.style,
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = Self.level
        isOpaque = false
        backgroundColor = .clear
        // The measured window draws its shadows itself (none on the pill).
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        // The ambient layer is dark-only.
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = Self.behaviour
        ignoresMouseEvents = true
        sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The panel's content: the pill takes the first click although the panel is never key.
final class ArisDictationPillHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
