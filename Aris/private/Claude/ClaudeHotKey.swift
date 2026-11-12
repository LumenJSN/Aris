//
//  ClaudeHotKey.swift
//  Aris
//
//  ⌃⌥Space opens the Claude tab; with a card pending it also arms the keyboard,
//  so a question or approval can be answered without touching the mouse.
//

import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let answerClaude = Self("answerClaude", default: .init(.space, modifiers: [.control, .option]))
}

extension Notification.Name {
    static let claudeAnswerHotKey = Notification.Name("com.lumenjsn.aris.claudeAnswerHotKey")
}

enum ClaudeHotKey {
    @MainActor static func register() {
        KeyboardShortcuts.onKeyDown(for: .answerClaude) {
            NotificationCenter.default.post(name: .claudeAnswerHotKey, object: nil)
        }
    }
}
