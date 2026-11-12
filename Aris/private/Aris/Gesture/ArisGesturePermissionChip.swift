//
//  ArisGesturePermissionChip.swift
//  Aris
//
//  The Screen Recording line next to the pointer (plan D2; controller ruling 2026-11-03), when a turn or a circle
//  finds no grant: "화면을 보려면 화면 기록 권한이 필요해요 · 허용하기" (opens the guide), or, once the guide has been
//  opened this launch, "Aris를 다시 열면 화면을 볼 수 있어요 · 다시 열기" (relaunches). In the hint chip's look, at
//  status + 14, never in a capture; the only chip that takes a click. Each line shows once per launch
//  (`ArisScreenPermissionNotice`), stays 5 s and fades.
//

import AppKit
import QuartzCore

@MainActor
final class ArisGesturePermissionChip {
    static let shared = ArisGesturePermissionChip()

    /// How long the line stays before it fades.
    static let showFor: Duration = .seconds(5)

    private var panel: NSPanel?
    private var hide: Task<Void, Never>?

    /// Shows `line` by the pointer: 허용하기 opens the Screen Recording guide, 다시 열기 relaunches Aris.
    func showNearPointer(_ line: ArisScreenPermissionNotice.Line) {
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main else { return }
        show(line, near: cursor, screen: screen.frame) {
            switch line {
            case .permission: ArisPermissionGuide.shared.show(.screen)
            case .relaunch: ApplicationRelauncher.restart(at: Bundle.main.bundleURL)
            }
        }
    }

    /// Shows `line` by the cursor (Cocoa global point) on `screen` (Cocoa frame).
    func show(_ line: ArisScreenPermissionNotice.Line, near cursor: CGPoint, screen: CGRect, open: @escaping @MainActor () -> Void) {
        close()
        let size = ArisGestureChrome.permissionChipSize(text: line.text, action: line.action)
        let local = ArisGestureGeometry.panelLocal(cursor, screen: screen)
        let r = ArisGestureMotion.chipFrame(cursor: local, size: size, display: screen.size)
        let frame = CGRect(x: screen.minX + r.minX, y: screen.maxY - r.maxY, width: r.width, height: r.height)
        let image = ArisGestureChrome.permissionChipImage(text: line.text, action: line.action, scale: 2)
        let view = ArisPermissionChipView(frame: CGRect(origin: .zero, size: size), image: image,
                                          label: "\(line.text). \(line.action)") { [weak self] in
            self?.close()
            open()
        }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + ArisGestureConstants.Session.hintLevelOffset)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
        // emil-design-eng: enters like the hint chip (220 ms ease-out, 3 pt rise); it's rare, so it may animate.
        let curve = ArisInkView.timing(ArisGestureMotion.hintCurve)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = ArisGestureMotion.hintEntranceMs / 1000
        fade.timingFunction = curve
        view.layer?.add(fade, forKey: "in")
        hide = Task { @MainActor in
            try? await Task.sleep(for: Self.showFor)
            guard !Task.isCancelled else { return }
            // emil-design-eng: exits faster than it entered (150 ms).
            NSAnimationContext.runAnimationGroup { context in
                context.duration = ArisGestureMotion.hintFadeOutMs / 1000
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in ArisGesturePermissionChip.shared.close(ifShowing: panel) }
            }
        }
    }

    /// Closes the line if `panel` is still the one showing (a newer one stays).
    private func close(ifShowing panel: NSPanel) {
        guard self.panel === panel else { return }
        close()
    }

    func close() {
        hide?.cancel()
        hide = nil
        panel?.close()
        panel = nil
    }
}

/// The chip image; the whole chip is the 허용하기 button, with the pointing-hand cursor.
@MainActor
private final class ArisPermissionChipView: NSView {
    private let image: CGImage?
    private let action: () -> Void

    init(frame: CGRect, image: CGImage?, label: String, action: @escaping () -> Void) {
        self.image = image
        self.action = action
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action()
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
                                                        respectFlipped: true, hints: nil)
    }
}
