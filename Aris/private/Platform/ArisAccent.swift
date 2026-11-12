//
//  ArisAccent.swift
//  Aris
//
//  The accent colour: the system's, or a colour the owner picked (stored as a keyed archive of an NSColor).
//  The preference reading lives in ArisAccent+Preferences.swift; this file is the plain part.
//

import AppKit

enum ArisAccent {
    /// The background tint is the accent at this opacity.
    static let backgroundAlpha: CGFloat = 0.25

    /// Apple's accent palette, sRGB 0…1.
    enum Preset: String, CaseIterable, Identifiable {
        case blue, purple, pink, red, orange, yellow, green, graphite

        var id: String { rawValue }

        var rgb: (Double, Double, Double) {
            switch self {
            case .blue: (0, 0.478, 1)
            case .purple: (0.686, 0.322, 0.871)
            case .pink: (1, 0.176, 0.333)
            case .red: (1, 0.271, 0.227)
            case .orange: (1, 0.584, 0)
            case .yellow: (1, 0.8, 0)
            case .green: (0.4, 0.824, 0.176)
            case .graphite: (0.557, 0.557, 0.576)
            }
        }

        var color: NSColor {
            let (r, g, b) = rgb
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
    }

    static func archive(_ color: NSColor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
    }

    static func unarchive(_ data: Data) -> NSColor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    /// The stored colour when custom is on and the data decodes; the system accent otherwise.
    static func effective(custom: Bool, data: Data?) -> NSColor {
        guard custom, let data, let color = unarchive(data) else { return .controlAccentColor }
        return color
    }
}
