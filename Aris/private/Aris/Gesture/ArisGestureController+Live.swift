//
//  ArisGestureController+Live.swift
//  Aris
//
//  The real world for the gesture controller: the system pointer and button, the displays, a monotonic clock, and
//  Aris's own fabric star in the hint chip. Kept apart so the offscreen renders build the controller without
//  SwiftUI or BotAvatarsKit.
//

import AppKit
import QuartzCore
import SwiftUI

extension ArisGestureController.Environment {
    static var live: Self {
        Self(
            now: { CACurrentMediaTime() * 1000 },
            pointer: { NSEvent.mouseLocation },
            buttonDown: { NSEvent.pressedMouseButtons & 1 != 0 },
            screens: { NSScreen.screens.compactMap { screen in
                displayID(of: screen).map { ArisGestureScreen(id: $0, frame: screen.frame) }
            } },
            nsScreen: { id in NSScreen.screens.first { displayID(of: $0) == id } },
            // The owner's pick B: Aris's star, not an arrow, in the 13 pt icon slot.
            hintIcon: { .view { NSHostingView(rootView: ArisCharacterView(size: 13, isAris: true)) } },
            headless: false,
            samples: { ArisPointerSampler.shared.drain() },
            sampling: { ArisPointerSampler.shared.session(running: $0) }
        )
    }

    private static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
