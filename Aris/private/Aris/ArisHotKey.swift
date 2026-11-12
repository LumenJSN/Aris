//
//  ArisHotKey.swift
//  Aris
//
//  ⌥Space talks to Aris: hold it while you talk, or tap it and pause when you're done.
//

import CoreGraphics
import Foundation
import KeyboardShortcuts
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "gesture")

extension KeyboardShortcuts.Name {
    static let talkToAris = Self("talkToAris", default: .init(.space, modifiers: [.option]))
}

enum ArisHotKey {
    @MainActor static func register() {
        KeyboardShortcuts.onKeyDown(for: .talkToAris) {
            log.notice("talk key down (voice only; ⌥⇧ draws)")
            Task { @MainActor in ArisController.shared.keyDown() }
        }
        KeyboardShortcuts.onKeyUp(for: .talkToAris) {
            Task { @MainActor in ArisController.shared.keyUp() }
        }
    }
}

/// Looks at the talk key itself, off the main thread, when the tap limit runs out: if it's already up, the press was
/// a tap however late the main thread hears about the release.
final class ArisTapProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var sawTap = false

    var wasTap: Bool { lock.withLock { sawTap } }

    @MainActor init() {
        let key = CGKeyCode(KeyboardShortcuts.getShortcut(for: .talkToAris)?.carbonKeyCode ?? 49)
        let limit = Double(ArisTalkKey.tapLimit.components.attoseconds) / 1e18 + Double(ArisTalkKey.tapLimit.components.seconds)
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + limit) { [self] in
            let up = !CGEventSource.keyState(.combinedSessionState, key: key)
            lock.withLock { sawTap = up }
        }
    }
}
