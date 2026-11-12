//
//  ClaudeAccent+Color.swift
//  Aris
//
//  ClaudeAccent's colours as SwiftUI colours, and what each tone paints.
//

import SwiftUI

extension Color {
    init(_ c: ClaudeRGBA) {
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}

extension ClaudeTone {
    /// The tone's colour; `rest` differs by place (a dim white dot in the ear, grey in a chip).
    func color(accent: Color, rest: Color) -> Color {
        switch self {
        case .accent: accent
        case .approval: Color(ClaudeAccent.approval)
        case .done: Color(ClaudeAccent.done)
        case .error: Color(ClaudeAccent.error)
        case .rest: rest
        }
    }
}
