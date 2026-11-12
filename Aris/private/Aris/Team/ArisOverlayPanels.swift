//
//  ArisOverlayPanels.swift
//  Aris
//
//  One invisible full-screen panel per display for teammates travelling and perching outside the notch. The panels
//  never take a click, never show in screenshots or screen sharing (but while an ad demo runs, ArisCaptureSharing),
//  and follow you across Spaces and full screen.
//
//  Idle cost is zero: nothing exists until the first `panel(for:)`, and `tearDown()` closes the panels and drops the
//  screen observer when no teammate is out. Closing beats ordering out: an ordered-out window still holds its
//  backing store and the observer, while a rebuild costs a few milliseconds on the next trip.
//

import AppKit

@MainActor
final class ArisOverlayPanels {
    private var panels: [NSPanel] = []
    /// After a display change rebuilt the panels (whatever they held is out of them): the director seats its
    /// characters again here, so it never races the rebuild.
    var onRebuild: (() -> Void)?
    /// Whether any panel exists (a teardown has something to close).
    var isBuilt: Bool { !panels.isEmpty }
    /// While an ad demo's teammates are out (ArisAdDemo), the panels show in screen recordings; back to never after.
    var shownInCaptures = false {
        didSet { panels.forEach { $0.sharingType = ArisCaptureSharing.type(demo: shownInCaptures) } }
    }
    /// Each panel's capture setting, for the tests.
    var sharingTypes: [NSWindow.SharingType] { panels.map(\.sharingType) }
    /// Above the menu bar's apps, and above the ad session's borderless `.floating` backdrop.
    static let level = NSWindow.Level.statusBar
    /// Written only on the main actor; read again in deinit, when nothing else can reach it.
    nonisolated(unsafe) private var screenObserver: NSObjectProtocol?

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// The panel covering `NSScreen.screens[screenIndex]`, built on first use and ordered front; nil when there's no
    /// such screen. Only panels asked for are ever on screen.
    func panel(for screenIndex: Int) -> NSPanel? {
        if panels.isEmpty { rebuild() }
        guard panels.indices.contains(screenIndex) else { return nil }
        let panel = panels[screenIndex]
        if !panel.isVisible { panel.orderFrontRegardless() }
        return panel
    }

    /// Takes the panel of `screenIndex` off screen if nothing is in it (a travel's copy panels after landing).
    func orderOutIfEmpty(_ screenIndex: Int) {
        guard panels.indices.contains(screenIndex) else { return }
        let panel = panels[screenIndex]
        guard panel.isVisible, panel.contentView?.subviews.isEmpty ?? true, panel.contentView?.layer?.sublayers?.isEmpty ?? true else { return }
        panel.orderOut(nil)
    }

    /// One panel per current screen, in `NSScreen.screens` order, none of them on screen until `panel(for:)` asks.
    /// Runs again on every display change while built; whatever the old panels hosted must be placed again.
    func rebuild() {
        closePanels()
        let sharing = ArisCaptureSharing.type(demo: shownInCaptures)
        panels = NSScreen.screens.map { Self.makePanel(on: $0, sharing: sharing) }
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.screensChanged() }
        }
    }

    /// Closes every panel and stops watching displays. The next `panel(for:)` builds them again. Task 10's director
    /// calls this once no teammate has been out for a while, and before letting go of this object (deinit only drops
    /// the observer: windows can't be closed off the main actor).
    func tearDown() {
        closePanels()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    private func screensChanged() {
        guard !panels.isEmpty else { return }
        rebuild()
        onRebuild?()
    }

    private func closePanels() {
        panels.forEach { $0.close() }
        panels = []
    }

    private static func makePanel(on screen: NSScreen, sharing: NSWindow.SharingType) -> NSPanel {
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.sharingType = sharing
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.setFrame(screen.frame, display: false)
        let content = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        return panel
    }
}
