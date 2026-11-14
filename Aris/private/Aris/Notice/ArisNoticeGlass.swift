//
//  ArisNoticeGlass.swift
//  Aris
//
//  AppKit's glass for one notification card (macOS 26): regular style, radius 22, the measured tint for the system's
//  appearance (dark sRGB(.055, .055, .065, .2), light white .06, switched live), and the notch's private variant and lensing (each made only where it still takes,
//  ArisGlassPrivate; one that stops taking turns the cards opaque, ArisNoticeCenter). Its window keeps it in the
//  active look (ArisNoticePanel). It only draws: clicks go to the card above it.
//

import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct ArisNoticeGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> ArisNoticeGlassView { ArisNoticeGlassView() }

    /// The system's appearance, as SwiftUI has it: called again whenever it changes.
    func updateNSView(_ view: ArisNoticeGlassView, context: Context) {
        view.follow(light: context.environment.colorScheme == .light)
    }
}

@available(macOS 26.0, *)
final class ArisNoticeGlassView: NSView {
    private let glass = NSGlassEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.style = .regular
        glass.cornerRadius = ArisNoticeLayout.cornerRadius
        follow(light: false)
        let took = ArisGlassPrivate.configure(glass)
        if !took.variant { ArisGlassHealth.shared.failed(\.variant) }
        if !took.lensing { ArisGlassHealth.shared.failed(\.lensing) }
        glass.autoresizingMask = [.width, .height]
        glass.frame = bounds
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The glass of the system's appearance: its tint and its own light or dark look.
    func follow(light: Bool) {
        let tint = (light ? ArisNoticePalette.light : ArisNoticePalette.dark).tint
        glass.tintColor = NSColor(srgbRed: tint.red, green: tint.green, blue: tint.blue, alpha: tint.alpha)
        glass.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    }

    /// A background: the card's taps and buttons are above it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
