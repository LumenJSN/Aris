//
//  ArisSidePanels.swift
//  Aris
//
//  The two side notches that hang off the screen's left and right edges. Left: sessions and history, the
//  clipboard, plan limits. Right: to-dos and the calendar. They follow the display the pointer is on; an open panel
//  stays on the display it opened on. At an edge two displays share, a pointer that is only crossing brings nothing
//  out (ArisSideEdgeRules).
//
//  The pointer reaching the edge brings out the sliver (with a haptic tap) and it goes back in as soon
//  as the pointer leaves; resting on it shows what the dots are, with
//  a way to hide it for a while; dragging it moves it up or down (remembered); clicking it opens the 232 × 580 panel,
//  and a click anywhere else closes it (unless it's locked open).
//
//  Each window is the screen's full height and the panel's width, so the outline (ArisSideLayers) can grow and
//  shrink and the sliver can sit anywhere inside it without resizing anything. Closed, the window lets every click
//  through except on the sliver and its popover.
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class ArisSidePanels: ObservableObject {
    static let shared = ArisSidePanels()

    typealias Edge = ArisSideEdge
    typealias Tab = ArisSideTab

    @Published private(set) var open: Set<Edge> = []
    /// The sliver is out because the pointer is at the edge, on it, or on its popover.
    @Published private(set) var revealed: Set<Edge> = []
    /// Resting on the sliver shows what its dots are (the sliver's popover).
    @Published private(set) var popover: Set<Edge> = []
    @Published private(set) var pinned: Set<Edge> = []
    @Published var leftTab: Tab = .history
    @Published var rightTab: Tab = .todo
    /// The tabs turned off in settings (ArisSideTab raw values); a side with none left never comes out.
    @Published private(set) var hiddenTabs = ArisSideTabChoice.hidden(Defaults[.arisSideHiddenTabs])
    /// A text field in the panel has the keyboard (the to-do composer): clicks in its popovers and menus don't close it.
    var holdOpen = false
    /// The provider open in the usage tab's detail, nil for its list.
    @Published var usageDetail: String?
    /// Each side's sliver dots, recomputed only when the stores behind them change.
    @Published private(set) var dots: [Edge: [ArisSideSliver.Dot]] = [:]
    /// The sliver's centre, down from the window's centre (the window is the screen's height).
    @Published private(set) var sliverOffset: [Edge: CGFloat] = [:]

    /// The sliver's widest footprint, for hit testing.
    static let sliverWidth: CGFloat = 18
    /// Room around the panel for its shadow and glow.
    static let gutter: CGFloat = 30
    static let popoverSize = CGSize(width: 220, height: 132)
    static let popoverLeft: CGFloat = 26
    /// Where the pointer is, checked this often (hover events miss a window that changed under a still pointer).
    private static let checkEvery: TimeInterval = 0.08
    private static let restBeforePopover: TimeInterval = 0.8
    private static let popoverLinger: TimeInterval = 0.18
    private static let dragThreshold: CGFloat = 4

    private var windows: [Edge: ArisSideWindow] = [:]
    private var pointerWatch: Timer?
    private var clickWatch: [Any] = []
    private var layers: [Edge: ArisSideLayers] = [:]
    private var watching: [AnyCancellable] = []
    private var screenID: CGDirectDisplayID?
    /// The frame of the display the windows are on: every rect here is measured from it, wherever the pointer is.
    private var placedFrame: CGRect?
    /// Since when the pointer has been at each side's edge or on its sliver's place (a shared edge asks for a rest).
    private var nearSince: [Edge: Date] = [:]
    private var restingSince: [Edge: Date] = [:]
    private var awayFromPopoverSince: [Edge: Date] = [:]
    /// The sliver's state stays put while the panel closes into it, so nothing cuts the closing short.
    private var settlingUntil: [Edge: Date] = [:]
    private var hiddenUntil: [Edge: Date] = [:]
    private var press: (edge: Edge, startY: CGFloat, startPosition: CGFloat, dragging: Bool)?

    func start() {
        for edge in Edge.allCases where windows[edge] == nil {
            let window = ArisSideWindow(edge: edge)
            // place() alone sizes these windows; inside a plain container the hosting view can only follow it (as the
            // content view it resized the window mid-animation until AppKit aborted the layout loop).
            let host = NSHostingView(rootView: ArisSidePanelView(edge: edge))
            // The popover sits over the outline, outside its mask (the dots are layers inside the outline's clip).
            let overlay = ArisPassthroughHostingView(rootView: ArisSideOverlayView(edge: edge))
            let container = NSView(frame: CGRect(x: 0, y: 0, width: ArisGlass.sideSize.width + Self.gutter, height: 800))
            for view in [host, overlay] as [NSView] {
                (view as? NSHostingView<ArisSidePanelView>)?.sizingOptions = []
                (view as? ArisPassthroughHostingView<ArisSideOverlayView>)?.sizingOptions = []
                view.autoresizingMask = [.width, .height]
                view.frame = container.bounds
                container.addSubview(view)
            }
            window.contentView = container
            windows[edge] = window
            layers[edge] = ArisSideLayers(edge: edge, container: container, content: host)
            window.orderFrontRegardless()
        }
        place()
        tabsChanged()
        // Claude's store changes many times a second while it works; only a change in the dots reaches the outline.
        let changes = [ClaudeStore.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                       ArisTodoModel.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                       ArisUsageModel.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                       ArisController.shared.$pastTurns.map { _ in () }.eraseToAnyPublisher()]
        watching = changes.map { publisher in
            publisher.throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true).sink { _ in
                MainActor.assumeIsolated { ArisSidePanels.shared.dotsMayHaveChanged() }
            }
        }
        // Hops onto the main actor instead of assuming it: assumeIsolated in this timer crashed twice at launch
        // (SIGSEGV in the executor check, macOS 26.0, 2026-11-01).
        startPointerWatch()
        // Pointer moves are acted on at once; the timer carries the rest and linger clocks while anything is showing,
        // and stops when nothing is (idle CPU), to be started again by the next move.
        clickWatch += [
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
                MainActor.assumeIsolated { ArisSidePanels.shared.pointerMoved() }
            } as Any,
            NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
                MainActor.assumeIsolated { ArisSidePanels.shared.pointerMoved() }
                return event
            } as Any,
        ]
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ArisSidePanels.shared.place() }
        }
        // A click anywhere outside an open panel closes it: in other apps (global) and in Aris's other windows (local).
        // Added to the pointer monitors above, which `=` used to drop.
        clickWatch += [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                MainActor.assumeIsolated { ArisSidePanels.shared.clickedOutside() }
            } as Any,
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                MainActor.assumeIsolated {
                    // Answering the notch's card (the 한 일 tab's undo asks there) is part of what the panel started.
                    let answering = event.window is ArisNotchPanel && ArisController.shared.session.question != nil
                    if !(event.window is ArisSideWindow) && !answering { ArisSidePanels.shared.clickedOutside() }
                }
                return event
            } as Any,
        ]
    }

    // MARK: - Opening and closing

    /// `keyboard`: take the keyboard too (a hotkey asked); a click on the sliver never takes it from the app you're
    /// typing in.
    func show(_ edge: Edge, tab: Tab? = nil, keyboard: Bool = false) {
        // A tab that's turned off opens its side's first one instead; a side with every tab off doesn't open.
        guard let shown = ArisSideTabChoice.resolve(tab ?? current(edge), hidden: hiddenTabs) else { return }
        followPointer()
        startPointerWatch()
        if shown != current(edge) {
            // Not a press on the tab (a shortcut, a chip that leads here): the tab is shown at once (side 3).
            ArisTabPress.changedWithoutPress()
            edge == .left ? (leftTab = shown) : (rightTab = shown)
        }
        if !open.contains(edge) {
            hiddenUntil[edge] = nil
            popover.remove(edge)
            revealed.remove(edge)
            restingSince[edge] = nil
            windows[edge]?.ignoresMouseEvents = false
            withAnimation(ArisGlass.sideOpening) { _ = open.insert(edge) }
            render(edge, .opening)
        }
        // A hotkey opened it: it takes the keyboard (and stays until it loses it or a click lands elsewhere).
        if keyboard { focus(edge) }
    }

    func collapse(_ edge: Edge) {
        guard open.contains(edge) else { return }

        // Straight into the sliver if the pointer is at the edge, otherwise straight to nothing.
        let pointer = where_(edge)
        if pointer.atEdge || pointer.onSliver { revealed.insert(edge) } else { revealed.remove(edge) }
        settlingUntil[edge] = Date().addingTimeInterval(ArisSideLayers.Motion.closing.duration + 0.05)
        withAnimation(ArisGlass.sideClosing) { _ = open.remove(edge) }
        render(edge, .closing)
        pinned.remove(edge)
        windows[edge]?.ignoresMouseEvents = true
        // A field typed in goes, and the user's app gets the keyboard back.
        ArisPanelKeys.closed(windows[edge])
        windows[edge]?.resignKey()
    }

    /// A press in a panel opened the Settings window (ArisStepAside): the panel folds out of its way. One locked open
    /// stays: the user asked for it to.
    func stepAside() {
        for edge in Edge.allCases where ArisSideEdgeRules.stepsAside(open: open.contains(edge), pinned: pinned.contains(edge)) { collapse(edge) }
    }

    // MARK: - Tabs turned off

    func shownTabs(_ edge: Edge) -> [Tab] { ArisSideTabChoice.shown(edge, hidden: hiddenTabs) }

    func shows(_ tab: Tab) -> Bool { !hiddenTabs.contains(tab.rawValue) }

    /// Every tab of this side is off: no sliver, no panel.
    func isOff(_ edge: Edge) -> Bool { shownTabs(edge).isEmpty }

    func setShown(_ tab: Tab, _ on: Bool) {
        let hidden = ArisSideTabChoice.toggled(hiddenTabs, tab, shown: on)
        guard hidden != hiddenTabs else { return }
        Defaults[.arisSideHiddenTabs] = ArisSideTabChoice.stored(hidden)
        hiddenTabs = hidden
        tabsChanged()
    }

    private func current(_ edge: Edge) -> Tab { edge == .left ? leftTab : rightTab }

    /// Each side moves off a tab that no longer shows, a side left with none goes away, and the dots follow. What
    /// runs behind a tab stops with it: the 사용량 tab's reads, and the hold on the 클립보드 and right side's shortcuts.
    private func tabsChanged() {
        for edge in Edge.allCases {
            if let tab = ArisSideTabChoice.resolve(current(edge), hidden: hiddenTabs) {
                if tab != current(edge) {
                    ArisTabPress.changedWithoutPress()
                    edge == .left ? (leftTab = tab) : (rightTab = tab)
                }
            } else {
                collapse(edge)
                popover.remove(edge)
                setRevealed(edge, false)
            }
        }
        ArisUsageModel.shared.tabsChanged(hidden: hiddenTabs)
        ArisClipboardHotKey.setEnabled(ArisSideTabWork.takesClipboardKey(hidden: hiddenTabs))
        ArisRightPanelHotKey.setEnabled(ArisSideTabWork.takesRightKey(hidden: hiddenTabs))
        dotsMayHaveChanged()
    }

    func lostFocus(_ edge: Edge) {
        guard open.contains(edge), !pinned.contains(edge), !holdOpen, !panelRect(edge).contains(NSEvent.mouseLocation) else { return }
        collapse(edge)
    }

    func togglePin(_ edge: Edge) {
        if pinned.contains(edge) { pinned.remove(edge) } else { pinned.insert(edge) }
    }

    /// Opened by the keyboard to type in (the clipboard's search): Aris takes the keyboard, so nothing typed reaches
    /// the app in front (QA BUG-22), and gives it back when the panel goes.
    func focus(_ edge: Edge) {
        guard let window = windows[edge] else { return }
        window.orderFront(nil)
        ArisPanelKeys.take(window)
    }

    /// Brings back a side whose sliver was hidden for a while, without opening it.
    func unhide(_ edge: Edge) {
        guard isHidden(edge) else { return }
        hiddenUntil[edge] = nil
        startPointerWatch()
        checkPointer()
    }

    /// The sliver comes out by itself for `seconds`, the pointer nowhere near, then goes back in as it always does
    /// (the first-run setup's finish shows the left side notch once: ArisFirstTries). False when this side has no
    /// sliver to show (every tab off, hidden for a while, or its panel open).
    @discardableResult
    func showOnce(_ edge: Edge, for seconds: TimeInterval) -> Bool {
        guard !isOff(edge), !isHidden(edge), !open.contains(edge) else { return false }
        followPointer()
        settlingUntil[edge] = Date().addingTimeInterval(seconds)
        setRevealed(edge, true)
        startPointerWatch()
        return true
    }

    var isHiddenAny: Bool { Edge.allCases.contains { isHidden($0) } }

    func isHidden(_ edge: Edge) -> Bool { (hiddenUntil[edge] ?? .distantPast) > Date() }

    /// The sliver goes away for a while, or until the panel is opened again (nil);
    /// a hotkey or the menu still opens the panel.
    func hide(_ edge: Edge, for interval: TimeInterval?) {
        hiddenUntil[edge] = interval.map { Date().addingTimeInterval($0) } ?? .distantFuture
        popover.remove(edge)
        setRevealed(edge, false)
        startPointerWatch()
    }

    private func clickedOutside() {
        let mouse = NSEvent.mouseLocation
        for edge in open where !pinned.contains(edge) && !holdOpen {
            guard !panelRect(edge).contains(mouse) else { continue }
            collapse(edge)
        }
        // A click elsewhere also puts an open popover away.
        for edge in popover where !popoverRect(edge).contains(mouse) && !sliverRect(edge).contains(mouse) {
            popover.remove(edge)
        }
    }

    // MARK: - The pointer

    /// The timer stops after this long with nothing showing, no press and no clock running.
    private static let idleAfter: TimeInterval = 2
    private var lastActivity = Date()

    private func pointerMoved() {
        startPointerWatch()
        checkPointer()
    }

    private func startPointerWatch() {
        lastActivity = Date()
        guard pointerWatch == nil else { return }
        pointerWatch = Timer.scheduledTimer(withTimeInterval: Self.checkEvery, repeats: true) { _ in
            Task { @MainActor in ArisSidePanels.shared.checkPointer() }
        }
    }

    /// Something the timer must carry: a side showing, pressed, settling, resting toward its popover or lingering.
    private var hasClocksRunning: Bool {
        !open.isEmpty || !revealed.isEmpty || !popover.isEmpty || press != nil || !restingSince.isEmpty
            || !awayFromPopoverSince.isEmpty || settlingUntil.values.contains { $0 > Date() }
    }

    /// Brings the sliver out at the edge and puts it back, shows its popover after a rest, and lets clicks through
    /// everywhere but the sliver and the popover.
    private func checkPointer() {
        followPointer()
        let now = Date()
        defer {
            if hasClocksRunning { lastActivity = now } else if now.timeIntervalSince(lastActivity) > Self.idleAfter {
                pointerWatch?.invalidate()
                pointerWatch = nil
            }
        }
        // Open, the screen-tall window takes clicks only on the panel; around it they reach the app below (and the
        // click monitor closes the panel).
        for edge in open { setIgnoresMouse(edge, !panelRect(edge).contains(NSEvent.mouseLocation)) }
        for edge in Edge.allCases where !open.contains(edge) && press?.edge != edge {
            if isOff(edge) || (hiddenUntil[edge] ?? .distantPast) > now {
                nearSince[edge] = nil
                setRevealed(edge, false)
                setIgnoresMouse(edge, true)
                continue
            }
            let pointer = where_(edge)
            let inPopover = popover.contains(edge) && pointer.inPopover
            let near = pointer.atEdge || pointer.onSliver
            nearSince[edge] = near ? (nearSince[edge] ?? now) : nil
            // Take the pointer at the edge too: the trackpad's haptic only plays for the
            // window under the pointer, so with clicks passing through, the tap below went to another app and was lost.
            setIgnoresMouse(edge, !(near || inPopover))
            if (settlingUntil[edge] ?? .distantPast) <= now {
                // Where another display continues past this edge the pointer may only be crossing: the sliver (and
                // its tap) waits until it has rested here.
                let comesOut = ArisSideEdgeRules.comesOut(near: near, shared: isShared(edge),
                                                          restedFor: now.timeIntervalSince(nearSince[edge] ?? now))
                setRevealed(edge, comesOut || inPopover)
            }
            // The popover: after a rest on the sliver; gone a moment after the pointer leaves both.
            if pointer.onSliver {
                awayFromPopoverSince[edge] = nil
                let resting = restingSince[edge] ?? now
                restingSince[edge] = resting
                if !popover.contains(edge), now.timeIntervalSince(resting) >= Self.restBeforePopover {
                    popover.insert(edge)
                }
            } else {
                restingSince[edge] = nil
                if popover.contains(edge) && !inPopover {
                    let away = awayFromPopoverSince[edge] ?? now
                    awayFromPopoverSince[edge] = away
                    if now.timeIntervalSince(away) >= Self.popoverLinger {
                        popover.remove(edge)
                        awayFromPopoverSince[edge] = nil
                    }
                } else {
                    awayFromPopoverSince[edge] = nil
                }
            }
        }
    }

    /// Another display continues past this side, at the pointer's height.
    private func isShared(_ edge: Edge) -> Bool {
        guard let frame else { return false }
        return ArisSideEdgeRules.isShared(edge, of: frame, at: NSEvent.mouseLocation.y, displays: NSScreen.screens.map(\.frame))
    }

    private func where_(_ edge: Edge) -> (atEdge: Bool, onSliver: Bool, inPopover: Bool) {
        guard let frame else { return (false, false, false) }
        let mouse = NSEvent.mouseLocation
        let fromEdge = edge == .left ? mouse.x - frame.minX : frame.maxX - mouse.x
        let center = sliverCenterY(edge)
        // The very edge brings it out, along the panel's height around the sliver.
        let atEdge = fromEdge >= -1 && fromEdge <= 1 && abs(mouse.y - center) <= ArisGlass.sideSize.height / 2
        return (atEdge, sliverRect(edge).insetBy(dx: 0, dy: -6).contains(mouse), popoverRect(edge).contains(mouse))
    }

    private func setRevealed(_ edge: Edge, _ on: Bool) {
        guard revealed.contains(edge) != on else { return }
        if on {
            // Tap the trackpad as the sliver comes out; a beat later, once the window has the pointer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        withAnimation(ArisGlass.sliverVisibility) { if on { revealed.insert(edge) } else { revealed.remove(edge) } }
        render(edge, .sliver)
    }

    private func setIgnoresMouse(_ edge: Edge, _ ignore: Bool) {
        guard let window = windows[edge], window.ignoresMouseEvents != ignore else { return }
        window.ignoresMouseEvents = ignore
    }

    // MARK: - Pressing and dragging the sliver (ArisSideWindow sends these)

    /// True when the press is the sliver's (anything else, such as the popover's buttons, goes to the view).
    func pressBegan(_ edge: Edge) -> Bool {
        guard !open.contains(edge), sliverRect(edge).insetBy(dx: -2, dy: -6).contains(NSEvent.mouseLocation) else { return false }
        press = (edge, NSEvent.mouseLocation.y, position(edge), false)
        return true
    }

    func pressMoved() {
        guard var current = press, let frame else { return }
        let dy = NSEvent.mouseLocation.y - current.startY
        if !current.dragging && abs(dy) >= Self.dragThreshold {
            current.dragging = true
            popover.remove(current.edge)
        }
        press = current
        guard current.dragging else { return }
        // Position is measured down from the top, so moving up (dy > 0) lowers it.
        setPosition(current.edge, current.startPosition - dy / frame.height, animated: false)
    }

    func pressEnded() {
        guard let current = press else { return }
        press = nil
        if current.dragging {
            UserDefaults.standard.set(Double(position(current.edge)), forKey: Self.positionKey(current.edge))
        } else {
            show(current.edge)
        }
    }

    // MARK: - Dots

    private func dotsMayHaveChanged() {
        for edge in Edge.allCases {
            let dots = Array(ArisSideSliver.dots(edge).prefix(ArisSideSliver.maxDots))
            guard dots != self.dots[edge] else { continue }
            self.dots[edge] = dots
            updateSliverOffset(edge)
            render(edge, .sliver)
        }
    }

    // MARK: - Geometry

    private static func positionKey(_ edge: Edge) -> String { "arisSliverPosition." + edge.rawValue }

    /// The sliver's centre as a fraction of the screen's height, from the top.
    private func position(_ edge: Edge) -> CGFloat {
        let saved = UserDefaults.standard.object(forKey: Self.positionKey(edge)) as? Double
        return CGFloat(saved ?? 0.5)
    }

    private func setPosition(_ edge: Edge, _ value: CGFloat, animated: Bool) {
        UserDefaults.standard.set(Double(min(1, max(0, value))), forKey: Self.positionKey(edge))
        updateSliverOffset(edge)
        render(edge, animated ? .sliver : .none)
    }

    private var sliverHeight: [Edge: CGFloat] {
        Dictionary(uniqueKeysWithValues: Edge.allCases.map { ($0, ArisSideSliver.height(dots: (dots[$0] ?? []).count)) })
    }

    /// The sliver's centre in screen coordinates (y up), kept clear of the screen's corners.
    private func sliverCenterY(_ edge: Edge) -> CGFloat {
        guard let frame else { return 0 }
        let half = (sliverHeight[edge] ?? 48) / 2
        let margin = ArisGlass.sideShoulder + half
        let y = frame.maxY - position(edge) * frame.height
        return min(frame.maxY - margin, max(frame.minY + margin, y))
    }

    private func updateSliverOffset(_ edge: Edge) {
        guard let frame else { return }
        sliverOffset[edge] = frame.midY - sliverCenterY(edge)
    }

    private func sliverRect(_ edge: Edge) -> CGRect {
        guard let frame else { return .zero }
        let height = sliverHeight[edge] ?? 48
        let x = edge == .left ? frame.minX : frame.maxX - Self.sliverWidth
        return CGRect(x: x, y: sliverCenterY(edge) - height / 2, width: Self.sliverWidth, height: height)
    }

    private func popoverRect(_ edge: Edge) -> CGRect {
        guard let frame else { return .zero }
        let size = Self.popoverSize
        let x = edge == .left ? frame.minX + Self.popoverLeft : frame.maxX - Self.popoverLeft - size.width
        let y = min(frame.maxY - size.height, max(frame.minY, sliverCenterY(edge) - size.height / 2))
        // A little slack around it, so crossing the gap from the sliver keeps it.
        return CGRect(x: x, y: y, width: size.width, height: size.height).insetBy(dx: -8, dy: -8)
            .union(CGRect(x: edge == .left ? frame.minX : x + size.width, y: y, width: Self.popoverLeft, height: size.height))
    }

    private func panelRect(_ edge: Edge) -> CGRect {
        guard let frame else { return .zero }
        return ArisSideEdgeRules.panelRect(edge, in: frame, size: ArisGlass.sideSize)
    }

    /// The outline for this side's state: the panel when open; otherwise the sliver (18 wide under the pointer) as
    /// tall as its dots need, or nothing when it's put away.
    private func render(_ edge: Edge, _ motion: ArisSideLayers.Motion, force: Bool = false) {
        guard let frame else { return }
        let size = ArisGlass.sideSize
        let isOpen = open.contains(edge)
        let dots = self.dots[edge] ?? []
        let hidden = isOff(edge) || (hiddenUntil[edge] ?? .distantPast) > Date()
        let shown = !hidden && revealed.contains(edge)
        let spec: ArisSideOutline.Spec
        if isOpen {
            spec = .init(width: size.width, height: size.height, shoulder: ArisGlass.sideShoulder, corner: ArisGlass.sideShoulder, top: 0)
        } else {
            let height = ArisSideSliver.height(dots: dots.count)
            // From the panel's top (the panel is centred in the screen-tall window).
            let top = (frame.maxY - sliverCenterY(edge) - height / 2) - (frame.height - size.height) / 2
            if shown {
                let width = revealed.contains(edge) ? ArisSideOutline.sliverHoverWidth : ArisSideOutline.sliverWidth
                spec = .init(width: width, height: height, shoulder: ArisSideOutline.sliverShoulder,
                             corner: width - ArisSideOutline.sliverShoulder, top: top)
            } else {
                spec = .hidden(height: height, top: top)
            }
        }
        layers[edge]?.apply(spec, open: isOpen, dots: dots, motion: motion, force: force)
    }

    // MARK: - Placement

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    /// The display the windows are on (the pointer's, until they are first placed).
    private var frame: CGRect? { placedFrame ?? screen?.frame }

    /// Moves the slivers to the display the pointer is on now. Not while a panel is open or the sliver is being
    /// dragged: those stay where they are. Nothing is carried across: a sliver that was out on the display the
    /// pointer left doesn't flash on the new one.
    private func followPointer() {
        guard open.isEmpty, press == nil, let screen, screen.arisDisplayID != screenID else { return }
        revealed.removeAll()
        popover.removeAll()
        nearSince.removeAll()
        restingSince.removeAll()
        awayFromPopoverSince.removeAll()
        place()
    }

    func place() {
        // An open panel keeps its display while that display is still connected; otherwise the pointer's display.
        let target = (open.isEmpty ? nil : NSScreen.screens.first { $0.arisDisplayID == screenID }) ?? screen
        screenID = target?.arisDisplayID
        placedFrame = target?.frame
        guard let frame else { return }
        for edge in Edge.allCases {
            guard let window = windows[edge] else { continue }
            let width = ArisGlass.sideSize.width + Self.gutter
            let x = edge == .left ? frame.minX : frame.maxX - width
            window.setFrame(CGRect(x: x, y: frame.minY, width: width, height: frame.height), display: true)
            window.ignoresMouseEvents = !open.contains(edge)
            layers[edge]?.layout()
            updateSliverOffset(edge)
            render(edge, .none, force: true)
        }
    }
}

/// A hosting view that takes clicks only where its SwiftUI content does (the popover), so the panel under it works.
final class ArisPassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// A borderless, non-activating panel above other windows on every Space. Its fields (the clipboard's search, the
/// to-do field) take the keyboard through ArisPanelKeys: Aris comes forward while they're typed in (QA BUG-22).
final class ArisSideWindow: NSPanel, ArisKeyPanel {
    let edge: ArisSidePanels.Edge
    private var pressing = false

    init(edge: ArisSidePanels.Edge) {
        self.edge = edge
        super.init(contentRect: CGRect(x: 0, y: 0, width: 262, height: 800),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// Always (its buttons take the first click); a field typed in also brings Aris forward (ArisPanelKeys).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let made = super.makeFirstResponder(responder)
        MainActor.assumeIsolated { ArisPanelKeys.responderChanged(firstResponder, in: self) }
        return made
    }

    /// A press on the closed sliver is handled here (a SwiftUI gesture in an inactive non-activating panel can miss
    /// the first click): a click opens the panel, a drag moves the sliver. Everything else goes to the view.
    override func sendEvent(_ event: NSEvent) {
        let edge = edge
        switch event.type {
        case .leftMouseDown:
            if MainActor.assumeIsolated({ ArisSidePanels.shared.pressBegan(edge) }) { pressing = true; return }
        case .leftMouseDragged where pressing:
            MainActor.assumeIsolated { ArisSidePanels.shared.pressMoved() }
            return
        case .leftMouseUp where pressing:
            pressing = false
            MainActor.assumeIsolated { ArisSidePanels.shared.pressEnded() }
            return
        default:
            break
        }
        // A press on a field was seen first by ArisPanelKeys' monitor (QA BUG-22).
        super.sendEvent(event)
    }

    /// Opened by a hotkey and then you click elsewhere: put it away (unless the pointer is on it or it's pinned).
    override func resignKey() {
        super.resignKey()
        MainActor.assumeIsolated { ArisPanelKeys.lostKey(self) }
        let edge = edge
        Task { @MainActor in ArisSidePanels.shared.lostFocus(edge) }
    }
}

private extension NSScreen {
    var arisDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
