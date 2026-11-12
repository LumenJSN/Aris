//
//  ArisProviderColors.swift
//  Aris
//
//  Each AI service's own colour in the 사용량 tab, the way CodexBar does it (github.com/steipete/CodexBar, MIT): one
//  fixed colour a provider, all in one table, so a provider added later brings its colour with it in one line. The
//  values are CodexBar's shipped accents (Antigravity keeps its blue); for a provider it doesn't have, take the colour from the company's own logo
//  or site. A colour too dim for the side notch's glass is lifted toward white until it reads (as the Claude card's
//  accent is). A provider the table doesn't know has none: the views draw it in the glass's white. Foundation only
//  (tested).
//

import Foundation

enum ArisProviderColors {
    /// "#RRGGBB" by provider id.
    static let hex: [String: String] = [
        "claude": "#CC7C5E",
        "codex": "#49A3B0",
        // The owner's pick: the blue it had, not CodexBar's green (#60BA7E), which sits too near the pace tick's green.
        "antigravity": "#8AB4F8",
        "gemini": "#AB87EA",
        "openrouter": "#6467F2",
    ]

    static func color(_ id: String) -> ClaudeRGBA? {
        hex[id].flatMap(ClaudeAccent.parse).map(ClaudeAccent.readable)
    }
}
