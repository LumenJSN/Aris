//
//  ArisPermissionGuide.swift
//  Aris
//
//  Giving Aris a permission: System Settings opens on the right list, and a small panel floats beside it with
//  Aris's icon to drag into that list ("Drag Aris into the Accessibility list, then turn its switch on."). It
//  watches the permission and closes itself with a check once it's on. Aris never also asks macOS
//  for Screen Recording itself: that request put up macOS's own window behind the guide, where it stayed unanswered
//  and showed again after the permission was on (fresh install F8). Dragging Aris into the list (or its + button) is
//  what adds it, as for Accessibility. The panel steps aside for macOS's own sheets (ArisPermissionPanelRules).
//

import AppKit
import SwiftUI

@MainActor
final class ArisPermissionGuide {
    static let shared = ArisPermissionGuide()

    enum Kind: String {
        case accessibility, screen

        var pane: String { self == .accessibility ? "Privacy_Accessibility" : "Privacy_ScreenCapture" }
        var granted: Bool { self == .accessibility ? AXIsProcessTrusted() : CGPreflightScreenCaptureAccess() }
    }

    private var panel: NSPanel?
    private var watch: Timer?
    private let model = Model()

    final class Model: ObservableObject {
        @Published var kind: Kind = .accessibility
        @Published var done = false
    }

    /// Opens System Settings on the list for `kind` and shows the drag panel beside it.
    func show(_ kind: Kind) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.pane)") {
            NSWorkspace.shared.open(url)
        }
        // Already on: the list is open to look at, and nothing more is asked or shown.
        guard ArisPermissionPanelRules.showsPanel(granted: kind.granted) else { return close() }
        // The user pressed 허용하기: the notch's next line is "Aris를 다시 열면…", not the ask again. macOS itself is not
        // asked (no request window of its own is left behind); the panel's row is dragged into the list.
        if kind == .screen { ArisScreenPermissionNotice.guideOpened() }
        model.kind = kind
        model.done = false
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
        // System Settings takes a moment to open its window; place the panel once it's there.
        place(panel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.place(panel) }
        watch?.invalidate()
        watch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in ArisPermissionGuide.shared.check() }
        }
    }

    func close() {
        watch?.invalidate()
        watch = nil
        panel?.orderOut(nil)
    }

    private func check() {
        keepClear()
        guard !model.done else { return }
        guard model.kind.granted else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0)) { model.done = true }
        watch?.invalidate()
        watch = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.close() }
    }

    /// The panel steps aside while a sheet of System Settings or macOS's own password window is where it sits (fresh
    /// install F9: it floated over the password sheet's Cancel), and comes back when that is gone.
    private func keepClear() {
        guard let panel, watch != nil, let first = NSScreen.screens.first else { return }
        // The window list's frames start at the top left of the first screen; AppKit's at its bottom left.
        let frame = CGRect(x: panel.frame.minX, y: first.frame.maxY - panel.frame.maxY, width: panel.frame.width, height: panel.frame.height)
        let aside = ArisPermissionPanelRules.yields(panel: frame, windows: Self.windowsOnScreen())
        if aside, panel.isVisible {
            panel.orderOut(nil)
        } else if !aside, !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    /// Every other app's window on screen, as the rules need it (who owns it, its layer and frame; never its title or content).
    private static func windowsOnScreen() -> [ArisPermissionPanelRules.Window] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let own = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != own,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return ArisPermissionPanelRules.Window(owner: window[kCGWindowOwnerName as String] as? String ?? "", settings: settingsPIDs.contains(pid),
                                                   layer: window[kCGWindowLayer as String] as? Int ?? 0,
                                                   frame: CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0))
        }
    }

    private static var settingsPIDs: Set<Int32> {
        let ids: Set = ["com.apple.systempreferences", "com.apple.SystemSettings"]
        return Set(NSWorkspace.shared.runningApplications.filter { ids.contains($0.bundleIdentifier ?? "") }.map(\.processIdentifier))
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: Self.size.width, height: Self.size.height),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // No window shadow: on a clear, rounded panel macOS drew it as a grey box outline around the card (third VM run).
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: ArisPermissionGuideView(model: model, onClose: { [weak self] in self?.close() }))
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = host
        return panel
    }

    /// The panel: 560 × 132, 56 taller for the line about aris-agent's row under the row to drag;
    /// the card sits 12 in from its edges, so the window around it is clear.
    static let size = CGSize(width: 560, height: 132)

    /// Docked under the System Settings window (centred on it, overlapping its bottom by 24, 12 in from the
    /// display's edges); at the bottom of the main screen when it can't be found.
    private func place(_ panel: NSPanel) {
        // A display handoff can leave the list empty for a moment: then nothing to place against.
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let first = NSScreen.screens.first else { return }
        var origin = CGPoint(x: screen.visibleFrame.midX - Self.size.width / 2, y: screen.visibleFrame.minY + 40)
        if let settings = Self.settingsWindowFrame() {
            // CG frames start at the top left of the first screen; AppKit's at the bottom left.
            let bottom = first.frame.maxY - settings.maxY
            let x = min(max(screen.visibleFrame.minX + Self.edge, settings.midX - Self.size.width / 2), screen.visibleFrame.maxX - Self.size.width - Self.edge)
            origin = CGPoint(x: x, y: max(screen.visibleFrame.minY + Self.edge, bottom + Self.overlap - Self.size.height))
        }
        panel.setFrameOrigin(origin)
    }

    private static let overlap: CGFloat = 24
    private static let edge: CGFloat = 12

    private static func settingsWindowFrame() -> CGRect? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let pids = settingsPIDs
        guard let window = windows.first(where: { pids.contains($0[kCGWindowOwnerPID as String] as? Int32 ?? -1)
                                                  && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        return CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
    }
}

/// The panel (mockups/onboarding2 .dragpanel): a 560×132
/// window, the card pinned to its bottom 12 in (radius 16, padding 12, rows 10 apart, white .95 / #2a2a2c .95, shadow
/// 0 12 40 .28). On top a 28 blue badge with the instruction at 13 and a 24 close; under it the row to drag (radius 12,
/// padding 6 10 6 6, gap 10): Aris's own app icon at 32, the one the row in System Settings' list will show (VM run
/// 2026-11-11: the panel drew the star, the list the dark "A"), "Aris" at 14 medium and the hint at 11.
/// Dragging it drags the app itself (its bundle URL), which System Settings adds to the list. Once the switch is on the
/// badge turns into a green check. There is one row to drag and nothing about a second one: the helper lives inside the
/// app, so "Aris" is the only row macOS makes (one row per permission). Its words follow the onboarding's language
/// (ArisOnboardingCopy, ArisSetupWords).
struct ArisPermissionGuideView: View {
    @ObservedObject var model: ArisPermissionGuide.Model
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var screen: Bool { model.kind == .screen }
    // Tailwind gray-800/100, gray-900/50, gray-400/500 and the card's white / #2a2a2c.
    private var ink: Color { dark ? ArisOBColor.hex(0xf3f4f6) : ArisOBColor.hex(0x1e2939) }
    private var name: Color { dark ? ArisOBColor.hex(0xf9fafb) : ArisOBColor.hex(0x101828) }
    private var hint: Color { dark ? ArisOBColor.hex(0x6a7282) : ArisOBColor.hex(0x99a1af) }
    /// A sentence to read, not a label: gray-500 / gray-400, as the setup's secondary text.
    private var note: Color { dark ? ArisOBColor.hex(0x99a1af) : ArisOBColor.hex(0x6a7282) }
    private var card: Color { dark ? ArisOBColor.hex(0x2a2a2c, 0.95) : .white.opacity(0.95) }
    private var chipFill: Color { dark ? .white.opacity(0.06) : .black.opacity(0.04) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            chip
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(card))
                .shadow(color: .black.opacity(0.28), radius: 20, y: 12)
        }
        .padding(12)
        .frame(width: ArisPermissionGuide.size.width, height: ArisPermissionGuide.size.height, alignment: .bottom)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(model.done ? Color.green : ArisOBColor.blue)
                Image(systemName: model.done ? "checkmark" : "arrow.down.to.line")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 28, height: 28)
            Text(model.done ? ArisOnboardingCopy.dragDone(screen: screen) : ArisOnboardingCopy.dragInstruction(screen: screen))
                .font(.system(size: 13)).lineSpacing(13 * 0.375 - 3).foregroundStyle(ink)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(hint)
                    .frame(width: 24, height: 24).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(ArisOnboardingCopy.dragClose)
            .accessibilityLabel(ArisOnboardingCopy.dragClose)
        }
        .padding(.horizontal, 4)
    }

    private var chip: some View {
        HStack(spacing: 10) {
            ArisOwnAppIcon(size: 32)
            Text("Aris").font(.system(size: 14, weight: .medium)).foregroundStyle(name)
            Spacer(minLength: 0)
            Text(model.done ? ArisOnboardingCopy.dragAllowed : ArisOnboardingCopy.dragHint).font(.system(size: 11)).foregroundStyle(hint)
        }
        .padding(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 10))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(chipFill))
        .opacity(model.done ? 0.6 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // The app bundle itself: System Settings adds a dropped .app to the list.
        .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
        .help(ArisOnboardingCopy.dragHelp)
        .accessibilityElement(children: .combine)
        .accessibilityHint(ArisOnboardingCopy.dragHelp)
    }
}

/// Aris's icon as macOS shows it in the Dock and in System Settings' lists (the running app's own icon), wherever a
/// picture says "look for this in the list".
struct ArisOwnAppIcon: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
