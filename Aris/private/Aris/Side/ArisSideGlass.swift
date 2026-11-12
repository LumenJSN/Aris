//
//  ArisSideGlass.swift
//  Aris
//
//  The side notch's glass: the very glass view of the top notch (AppKit's `NSGlassEffectView`, regular style, glass
//  variant 11, content lensing 3) with its tint overridden to sRGB(0, 0, .015, .9), the side notch's outline as its
//  own path and the window's active appearance forced. Every private part goes through the top notch's own gate
//  (ArisGlassPrivate, each call made only when the system still has it) and its own record (ArisGlassHealth): a part
//  that stops taking turns the top notch to its public look and this body to its public blur (ArisSideLook.material).
//
//  It fills the side window's whole content and never moves: only its path does, set from the outline on screen on
//  every frame of a morph (ArisSideLayers).
//

import AppKit

/// A plain layer-backed view that only draws: clicks go to what is under it.
final class ArisSidePassiveView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@available(macOS 26.0, *)
final class ArisSideGlassView: NSView {
    private let glass = NSGlassEffectView()
    /// The window whose active appearance this view forced, to give it back.
    private weak var forcedWindow: NSWindow?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        autoresizingMask = [.width, .height]
        // Style 0 (regular), with the side notch's tint.
        glass.style = .regular
        glass.tintColor = NSColor(srgbRed: 0, green: 0, blue: ArisSideLook.glassTintBlue, alpha: ArisSideLook.glassTintAlpha)
        // Dark whatever the Mac's appearance: the side notch is always the dark glass.
        glass.appearance = NSAppearance(named: .darkAqua)
        let took = ArisGlassPrivate.configure(glass)
        if !took.variant { ArisGlassHealth.shared.failed(\.variant) }
        if !took.lensing { ArisGlassHealth.shared.failed(\.lensing) }
        glass.autoresizingMask = [.width, .height]
        glass.frame = bounds
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A background: clicks belong to the panel's content above it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The outline for this frame, in this view's own coordinates; nil or no width draws no glass.
    func setOutline(_ path: CGPath?, visible: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !ArisGlassPrivate.setPath(glass, path) { ArisGlassHealth.shared.failed(\.path) }
        glass.isHidden = !visible || path == nil
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncWindow()
    }

    /// The view is going away (another material): the window's active appearance is AppKit's again.
    func release() {
        if let forcedWindow { ArisGlassPrivate.forceActiveAppearance(forcedWindow, on: false) }
        forcedWindow = nil
    }

    /// The side window keeps its glass in the active look while this view is in it (as the top notch's window
    /// does), and gets its own back when it leaves.
    private func syncWindow() {
        if let forcedWindow, forcedWindow !== window { release() }
        guard let window, forcedWindow == nil else { return }
        if ArisGlassPrivate.forceActiveAppearance(window, on: true) {
            forcedWindow = window
        } else {
            ArisGlassPrivate.forceActiveAppearance(window, on: false)
            ArisGlassHealth.shared.failed(\.activeAppearance)
        }
    }
}
