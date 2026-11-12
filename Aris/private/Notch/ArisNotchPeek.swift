//
//  ArisNotchPeek.swift
//  Aris
//
//  The music peek under (or, inline, inside) the closed notch, per display. Only music peeks are kept; anything else
//  is ignored. Each show gets a number, so a hide scheduled for an earlier show can't cut a later one short.
//

import SwiftUI

/// What a peek shows. Aris only peeks for music.
enum SneakContentType: Equatable {
    case music
}

struct SneakPeekState: Equatable {
    var show = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon = ""
    var accent: Color?
    var targetScreenUUID: String?
}

/// The inline peek: the closed notch widens to carry the title and artist.
struct ArisInlinePeek: Equatable {
    var show = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
}

struct ArisPeekBoard {
    private(set) var states: [String: SneakPeekState] = [:]
    private var shows: [String: Int] = [:]
    private var counter = 0

    /// The displays a peek goes to: the one asked for, else every connected one, else the main one.
    static func targets(_ target: String?, displays: [String], main: String?) -> [String] {
        if let target { return [target] }
        return displays.isEmpty ? [main].compactMap { $0 } : displays
    }

    /// Shows a peek on `targets`; returns each display with the number its auto-hide must carry.
    mutating func show(_ type: SneakContentType, value: CGFloat, icon: String, accent: Color?, on targets: [String]) -> [(display: String, show: Int)] {
        targets.map { display in
            counter += 1
            shows[display] = counter
            states[display] = SneakPeekState(show: true, type: type, value: value, icon: icon, accent: accent, targetScreenUUID: display)
            return (display, counter)
        }
    }

    /// Hides the peek on `display` — only if it is still show number `show`, when one is given.
    mutating func hide(_ display: String, show: Int? = nil) {
        if let show, shows[display] != show { return }
        shows[display] = nil
        guard states[display] != nil else { return }
        states[display] = SneakPeekState(targetScreenUUID: display)
    }

    func state(for display: String?) -> SneakPeekState {
        display.flatMap { states[$0] } ?? SneakPeekState()
    }

    var anyShowing: Bool { states.values.contains { $0.show } }
}
