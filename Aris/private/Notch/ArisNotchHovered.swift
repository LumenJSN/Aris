//
//  ArisNotchHovered.swift
//  Aris
//
//  Whether the pointer is on this notch, for the controls it shows on hover (the mute switch beside the mark, a
//  running tag's stop mark, the stop button's "esc", a receipt's lift). Each keeps its own hover, and a hover is
//  never told it ended when the pointer leaves in one jump or the view under it changes; so each also listens to the
//  notch, which checks where the pointer really is (ArisNotchPointer), and lets go when the pointer has left the notch.
//

import SwiftUI

private struct ArisNotchHoveredKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// The pointer is on the notch this view is in (true outside a notch: nothing there overrides a view's own hover).
    var arisNotchHovered: Bool {
        get { self[ArisNotchHoveredKey.self] }
        set { self[ArisNotchHoveredKey.self] = newValue }
    }
}

/// A view's hover that ends with the notch's: `hovering` follows the pointer on the view, and goes false when the
/// pointer has left the notch altogether.
private struct ArisNotchHover: ViewModifier {
    @Binding var hovering: Bool
    @Environment(\.arisNotchHovered) private var onNotch

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .onChange(of: onNotch) { _, on in if !on, hovering { hovering = false } }
    }
}

extension View {
    /// `.onHover { hovering = $0 }`, for a control inside the notch: it also ends when the pointer leaves the notch.
    func arisNotchHover(_ hovering: Binding<Bool>) -> some View { modifier(ArisNotchHover(hovering: hovering)) }
}
