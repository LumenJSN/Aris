//
//  ArisNativeGlass.swift
//  Aris
//
//  AppKit's own Liquid Glass view behind the notch with public API only, for the comparison look
//  ArisGlassLook.regularGlass: `NSGlassEffectView` in its regular style with the notch's tint. (The shipped look,
//  private-glass, is ArisNotchGlass.)
//
//  The glass's shape. Public API offers one corner radius for all four corners, so the glass is the notch's body
//  (the outline without its two flared shoulders) with the bottom corners' radius; the shoulders and the top corners
//  lie under the full black, where no glass shows. The view around it clips it to the outline (ArisGlassSurface).
//

import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct ArisNativeGlass: NSViewRepresentable {
    /// The tint, sRGB(0, 0, .02) at .18.
    var tint: NSColor
    /// The body inside the outline: how far in from each side it starts (a shoulder's width) and its bottom corners.
    var inset: CGFloat
    var corner: CGFloat

    func makeNSView(context: Context) -> ArisNativeGlassView { ArisNativeGlassView() }

    func updateNSView(_ view: ArisNativeGlassView, context: Context) {
        view.apply(tint: tint, inset: inset, corner: corner)
    }
}

@available(macOS 26.0, *)
final class ArisNativeGlassView: NSView {
    private let glass = NSGlassEffectView()
    private var inset: CGFloat = 0
    private var corner: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.style = .regular
        // The notch is dark whatever the Mac's appearance (its panel is too): the regular glass must not turn light.
        glass.appearance = NSAppearance(named: .darkAqua)
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A background: clicks belong to the notch's content above it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(tint: NSColor, inset: CGFloat, corner: CGFloat) {
        glass.tintColor = tint
        self.inset = inset
        self.corner = corner
        place()
    }

    override func layout() {
        super.layout()
        place()
    }

    /// The glass over the notch's body with one radius.
    private func place() {
        glass.frame = bounds.insetBy(dx: min(inset, bounds.width / 2), dy: 0)
        glass.cornerRadius = min(corner, glass.frame.width / 2, glass.frame.height / 2)
    }
}
