//
//  NotchButtonStyle.swift
//  Aris
//
//  One look for every Claude card button: white capsule (primary), dim capsule
//  (secondary) or plain grey text (quiet). Pure SwiftUI, so no system accent
//  blue and no AppKit button quirks in the non-activating notch panel.
//

import SwiftUI

struct NotchButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        NotchButtonBody(kind: kind, label: configuration.label, pressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NotchButtonStyle {
    static func notch(_ kind: NotchButtonStyle.Kind) -> NotchButtonStyle { NotchButtonStyle(kind: kind) }
}

private struct NotchButtonBody<Label: View>: View {
    let kind: NotchButtonStyle.Kind
    let label: Label
    let pressed: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        label
            .font(.system(size: kind == .quiet ? 11 : 12, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .quiet ? 4 : 12)
            .padding(.vertical, kind == .quiet ? 2 : 6)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .opacity(isEnabled ? (pressed ? 0.7 : 1) : 0.35)
            .onHover { hovering = $0 && isEnabled }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .black
        case .secondary: return .white
        case .quiet: return hovering ? .white : .gray
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: return hovering ? Color(white: 0.85) : .white
        case .secondary: return Color.white.opacity(hovering ? 0.24 : 0.14)
        case .quiet: return .clear
        }
    }
}

/// Button title with its keyboard hint ("Allow  Y").
struct KeyHintLabel: View {
    let title: String
    let key: String

    init(_ title: String, key: String) {
        self.title = title
        self.key = key
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Text(key)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .padding(.horizontal, 3)
                .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(lineWidth: 0.7))
                .opacity(0.5)
        }
    }
}
