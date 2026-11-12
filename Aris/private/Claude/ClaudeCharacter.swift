//
//  ClaudeCharacter.swift
//  Aris
//
//  What the Claude Code teammate's character does for each Claude state, pure (mockups/clawd-replace.html, pick C).
//  The nine states fold into Bot Avatars' own: idle; working for thinking, typing, building and juggling (the right
//  ear's tool glyph already tells them apart); a poke on the way into done, then idle; an error the rest pose, muted;
//  waiting for the user the idle loop facing the pointer; asleep with no sessions. ClaudeCharacterView draws it.
//

import Foundation

/// What a state's colour means (ClaudeAccent holds the colours).
enum ClaudeTone: Equatable {
    case accent, approval, done, error, rest
}

extension ClaudeState {
    var tone: ClaudeTone {
        switch self {
        case .notification: return .approval
        case .error: return .error
        case .happy: return .done
        case .thinking, .typing, .building, .juggling: return .accent
        case .idle, .sleeping: return .rest
        }
    }
}

/// How ArisCharacterView is asked to play a state.
struct ClaudeCharacterPose: Equatable {
    /// ArisCharacterMood's raw states: "default", "working" or "sleeping".
    let mood: String
    /// Faces the pointer while it comes near.
    let follows: Bool
    /// Holds the rest pose.
    let still: Bool
    /// Greyed and tilted.
    let muted: Bool
}

enum ClaudeCharacter {
    /// It sleeps when Claude has no sessions.
    static let canSleep = true

    static func pose(_ state: ClaudeState) -> ClaudeCharacterPose {
        switch state {
        case .thinking, .typing, .building, .juggling:
            return ClaudeCharacterPose(mood: "working", follows: false, still: false, muted: false)
        case .notification:
            return ClaudeCharacterPose(mood: "default", follows: true, still: false, muted: false)
        case .error:
            return ClaudeCharacterPose(mood: "default", follows: false, still: true, muted: true)
        case .sleeping:
            return ClaudeCharacterPose(mood: "sleeping", follows: false, still: false, muted: false)
        case .idle, .happy:
            return ClaudeCharacterPose(mood: "default", follows: false, still: false, muted: false)
        }
    }

    /// A poke plays once as Claude finishes.
    static func pokes(from old: ClaudeState, to new: ClaudeState) -> Bool {
        new == .happy && old != .happy
    }
}
