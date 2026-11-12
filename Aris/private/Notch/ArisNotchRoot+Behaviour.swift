//
//  ArisNotchRoot+Behaviour.swift
//  Aris
//
//  How one display's notch reacts: hover (open after the minimum hover time, close 350 ms after the pointer
//  leaves — never while an Aris turn holds the notch, BUGS-notch N1), taps, the right-click menu, swipes, drops, and
//  The user's Aris and Claude rules (approvals, notices, hot keys, a turn opening and putting back the notch).
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

extension ArisNotchRoot {
    static let closeDelay: Duration = .milliseconds(350)
    static let dropTypes: [UTType] = [.fileURL, .url, .utf8PlainText, .plainText, .data]

    var turnHolds: Bool { aris.holdsNotch }
    /// The display the current (or last) turn happened on: where the pointer was when it started.
    @MainActor static var turnDisplay: String?
    var approvalsPending: Bool { !claude.approvals.isEmpty }

    var mayCloseAutomatically: Bool {
        ArisNotchDecisions.automaticCloseAllowed(open: isOpen, hovering: hovering, popover: vm.isPopoverActive,
                                                 sharing: sharing.preventNotchClose, approvalsPending: approvalsPending, turnHolds: turnHolds,
                                                 dropHold: vm.dropInteraction.arisDropHold)
    }

    /// The pointer is on this notch's display.
    var pointerIsHere: Bool {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        return screen?.displayUUID == displayUUID
    }

    @discardableResult
    func open() -> Bool {
        var opened = false
        withAnimation(StandardAnimations.interactive) { opened = vm.open() }
        return opened
    }

    // MARK: - Hover

    /// This display's notch window, on the screen.
    private var windowFrame: CGRect? {
        let panels = NSApp.windows.filter { $0 is ArisNotchPanel }
        return (panels.count == 1 ? panels.first : panels.first { $0.screen?.displayUUID == displayUUID })?.frame
    }

    /// Where the pointer really is, whatever the hover events said (ArisNotchPointer). `slack`: how far off the
    /// surface still counts.
    func pointerOnNotch(slack: CGFloat) -> Bool {
        ArisNotchPointer.isOn(pointer: NSEvent.mouseLocation, surface: surfaceFrame, window: windowFrame, insets: hoverInsets, slack: slack)
    }

    /// While the notch believes the pointer is on it, its real place is read a few times a second: a pointer that left
    /// without a hover event (the view under it had just changed, or it left in one jump) is treated as having left.
    private func watchHover() {
        guard hoverWatch == nil else { return }
        hoverWatch = Task { @MainActor in
            var misses = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ArisNotchPointer.checkEvery))
                guard !Task.isCancelled, hovering, pointerTrusted else { break }
                misses = ArisNotchPointer.misses(misses, onNotch: pointerOnNotch(slack: ArisNotchPointer.slack),
                                                 buttonDown: NSEvent.pressedMouseButtons != 0)
                guard ArisNotchPointer.hasLeft(misses: misses) else { continue }
                hoverTask?.cancel()
                vm.dropInteraction.arisDropHold = ArisNotchDecisions.dropHold(vm.dropInteraction.arisDropHold, hoverInside: false, wasHovering: true)
                withAnimation(StandardAnimations.interactive) { hovering = false }
                if mayCloseAutomatically { vm.close() }
                break
            }
            hoverWatch = nil
        }
    }

    /// While the notch is open: a hover that began untrusted earns its trust once events and measurement agree, and
    /// with no hover known at all the pointer's place is read as the hover watch reads it (ArisNotchPointer.openStep).
    func watchOpen() {
        guard openWatch == nil else { return }
        openWatch = Task { @MainActor in
            var watch = ArisNotchPointer.OpenWatch()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ArisNotchPointer.checkEvery))
                guard !Task.isCancelled, isOpen else { break }
                let measured = surfaceFrame.width > 0 && windowFrame != nil
                guard measured, Date() >= openingUntil else { continue }
                let onNotch = pointerOnNotch(slack: ArisNotchPointer.slack)
                if hovering {
                    // The hover watch's own business; it only gains the trust it may have missed at the enter.
                    let trusted = ArisNotchPointer.trustGained(trusted: pointerTrusted, hovering: true, measured: measured, onNotch: onNotch)
                    if trusted != pointerTrusted {
                        pointerTrusted = trusted
                        watchHover()
                    }
                    watch = ArisNotchPointer.OpenWatch(seenOn: true, misses: 0)
                    continue
                }
                let step = ArisNotchPointer.openStep(watch, onNotch: onNotch, buttonDown: NSEvent.pressedMouseButtons != 0)
                watch = step.next
                guard step.left else { continue }
                if mayCloseAutomatically { vm.close() }
                watch = ArisNotchPointer.OpenWatch()
            }
            openWatch = nil
        }
    }

    func hoverChanged(_ inside: Bool) {
        guard !navigation.firstLaunch else { return }
        // Told the pointer left while it is still on the notch (what is under it changed): it has not left. The watch
        // notices when it really does.
        // A closed notch at ArisVNotch's sizes lets go 8 points out (its hover exit padding), so the growth does not
        // flutter.
        let exitSlack = closed && closedIsVNotch ? ArisVNotch.hoverExitPadding : 0
        if ArisNotchPointer.ignoresExit(inside: inside, hovering: hovering, trusted: pointerTrusted, onNotch: pointerOnNotch(slack: exitSlack)) {
            return watchHover()
        }
        hoverTask?.cancel()
        let held = vm.dropInteraction.arisDropHold
        vm.dropInteraction.arisDropHold = ArisNotchDecisions.dropHold(held, hoverInside: inside, wasHovering: hovering)
        if inside {
            withAnimation(StandardAnimations.interactive) { hovering = true }
            // The pointer has just come onto the notch: the measured place must say so too, or it is not used at all.
            pointerTrusted = ArisNotchPointer.trusted(measured: surfaceFrame.width > 0 && windowFrame != nil,
                                                      onNotchAtEnter: pointerOnNotch(slack: ArisNotchPointer.slack))
            watchHover()
            if closed && hapticsOn { hoverHaptic() }
            guard ArisNotchDecisions.hoverOpens(closed: closed, notice: noticeActive, peek: musicPeekHere, openOnHover: openOnHover) else { return }
            let delay = hoverDelay
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, closed, hovering, !noticeActive, !musicPeekHere else { return }
                open()
            }
        } else {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: Self.closeDelay)
                guard !Task.isCancelled else { return }
                withAnimation(StandardAnimations.interactive) { hovering = false }
                if mayCloseAutomatically { vm.close() }
            }
        }
    }

    /// After a share finishes or the popover flag changes: close if the pointer has left.
    func closeUnlessHovering() {
        guard isOpen, !hovering, !vm.isPopoverActive else { return }
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: Self.closeDelay)
            guard !Task.isCancelled, mayCloseAutomatically else { return }
            vm.close()
        }
    }

    // MARK: - Gestures

    var gestureSensitivity: CGFloat { sensitivity }

    func swipeDown(_ translation: CGFloat, _ phase: NSEvent.Phase) {
        guard phase != .ended else { return resetProgress() }
        withAnimation(StandardAnimations.interactive) { gestureProgress = ArisNotchDecisions.progress(translation: translation, sensitivity: gestureSensitivity) }
        guard translation > gestureSensitivity else { return }
        if hapticsOn { haptic.toggle() }
        resetProgress()
        open()
    }

    func swipeUp(_ translation: CGFloat, _ phase: NSEvent.Phase) {
        guard phase != .ended else { return resetProgress() }
        withAnimation(StandardAnimations.interactive) { gestureProgress = -ArisNotchDecisions.progress(translation: translation, sensitivity: gestureSensitivity) }
        guard translation > gestureSensitivity else { return }
        hovering = false
        if !sharing.preventNotchClose { vm.close() }
        if hapticsOn { haptic.toggle() }
        resetProgress()
    }

    func swipeMedia(_ translation: CGFloat, _ phase: NSEvent.Phase, next: Bool) {
        if phase == .ended { mediaFired = false; return }
        guard !mediaFired, translation > gestureSensitivity else { return }
        mediaFired = true
        next ? music.nextTrack() : music.previousTrack()
        if hapticsOn { haptic.toggle() }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.62)) { mediaNudge = next ? -1 : 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.18, dampingFraction: 0.62)) { mediaNudge = 0 }
        }
    }

    private func resetProgress() {
        withAnimation(StandardAnimations.interactive) { gestureProgress = 0 }
    }

    var swipeDownEnabled: Bool { gesturesOn && closed && !noticeActive }
    var swipeUpEnabled: Bool {
        gesturesOn && closeGestureOn && isOpen && navigation.currentView == .shelf && !vm.isHoveringCalendar
    }
    var mediaSwipeEnabled: Bool {
        gesturesOn && mediaGesturesOn && !noticeActive && closed && !hidden && (musicShowing || musicPeekHere)
    }

    // MARK: - Drops

    func dropTargetingChanged(_ active: Bool) {
        dropLeaveTask?.cancel()
        if active {
            vm.dropInteraction.dragNear = false
            // Open on a page without drop zones (Claude's): home's show them (BUG-24b).
            if isOpen, let page = ArisNotchDecisions.dropPage(navigation.currentView) { navigation.currentView = page }
            guard shelfOn, closed else { return }
            if open() { navigation.currentView = .home }
            return
        }
        dropLeaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if vm.dropInteraction.dropEvent {
                vm.dropInteraction.dropEvent = false
                return
            }
            guard isOpen, !sharing.preventNotchClose, !turnHolds, !vm.dropInteraction.arisDropHold else { return }
            vm.close()
        }
    }

    // MARK: - the user's Aris and Claude rules

    func approvalsChanged(_ first: String?) {
        guard first != lastApproval else { return }
        lastApproval = first
        guard first != nil else {
            KeyboardFocus.arm(false)
            if aris.isActive && arisOpenedNotch != nil {
                navigation.currentView = .aris
            } else if ApprovalAutoClose.shouldClose(isOpen: isOpen, hovering: hovering, openedForApproval: openedForApproval,
                                                    showingClaude: navigation.currentView == .claude) {
                vm.close()
            }
            return
        }
        openedForApproval = true
        navigation.currentView = .claude
        if closed { open() }
    }

    func noticeChanged(_ id: String?) {
        guard id != nil else {
            guard openedForNotice else { return }
            openedForNotice = false
            if !approvalsPending && ApprovalAutoClose.shouldClose(isOpen: isOpen, hovering: hovering, openedForApproval: false,
                                                                  showingClaude: navigation.currentView == .claude) {
                vm.close()
            }
            return
        }
        guard pointerIsHere, !approvalsPending, !aris.isActive, closed, !hidden else { return }
        openedForNotice = true
        navigation.currentView = .claude
        open()
    }

    /// A past turn was pressed in the 기록 tab (ArisController.resume): the notch on the pointer's display opens on
    /// it without taking the keyboard.
    func historyRestored() {
        guard pointerIsHere, !approvalsPending, !hidden else { return }
        navigation.currentView = .home
        if closed { open() }
    }

    func clipboardHotKey() {
        // The 클립보드 tab turned off in settings: its shortcut opens nothing.
        guard pointerIsHere, ArisSidePanels.shared.shows(.clipboard) else { return }
        ArisSidePanels.shared.show(.left, tab: .clipboard, keyboard: true)
    }

    func claudeAnswerHotKey() {
        guard pointerIsHere else { return }
        navigation.currentView = .claude
        if closed { open() }
        guard approvalsPending else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            KeyboardFocus.arm(true, byHotkey: true)
        }
    }

    var turnNeedsPanel: Bool {
        ArisNotchDecisions.turnNeedsPanel(training: aris.isTraining, dictating: aris.isDictating, phase: aris.phase,
                                          dictationCopied: aris.dictationCopied)
    }

    func arisActiveChanged(_ active: Bool) {
        if active {
            endTask?.cancel()
            endTask = nil
            if pointerIsHere { Self.turnDisplay = displayUUID }
            guard !approvalsPending else { return }
            if pageBeforeAris == nil { pageBeforeAris = navigation.currentView }
            if arisOpenedNotch == nil { arisOpenedNotch = closed }
            navigation.currentView = .aris
            if closed && turnNeedsPanel { open() }
            return
        }
        guard arisOpenedNotch != nil else { return }
        endTask?.cancel()
        endTask = Task { @MainActor in
            let controller = ArisController.shared
            let wait: Duration = controller.endedDictation ? .zero : ArisNotch.readingTime(for: controller.session.reply)
            try? await Task.sleep(for: wait)
            await ArisWidgetModel.shared.holdWhileShown()
            // The receipt under the answer keeps its five seconds (ArisReceiptModel).
            await ArisReceiptModel.shared.holdWhileShown()
            // A card still up keeps the notch open until it's answered or its time is up, whatever the pointer does.
            let held = Date()
            while ArisNotchDecisions.endWaitsForCard(cardWaiting: aris.cardWaiting, waited: Date().timeIntervalSince(held)), !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
            }
            let started = ContinuousClock.now
            while hovering, ContinuousClock.now - started < ArisNotch.longestHover, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled, !aris.isActive else { return }
            let opened = arisOpenedNotch ?? false
            arisOpenedNotch = nil
            // Nothing holds the notch now: with the pointer off it, it closes whoever opened it (ArisNotch.Ending.whenFree).
            let away = ArisNotch.pointerAway(free: mayCloseAutomatically, measured: surfaceFrame.width > 0 && windowFrame != nil,
                                             onNotch: pointerOnNotch(slack: ArisNotchPointer.slack))
            switch ArisNotch.ending(openedNotch: opened, isOpen: isOpen).whenFree(pointerAway: away) {
            case .close: vm.close()
            case .restoreTab: navigation.currentView = pageBeforeAris ?? .home
            case .stay: break
            }
            if closed && navigation.currentView == .aris { navigation.currentView = pageBeforeAris ?? .home }
            pageBeforeAris = nil
        }
    }

    func cardWaitingChanged(_ waiting: Bool) {
        guard waiting else {
            guard openedForCard else { return }
            openedForCard = false
            if !aris.isActive && !hovering && isOpen { vm.close() }
            return
        }
        guard ArisNotchDecisions.cardOpens(waiting: waiting, closed: closed, hidden: hidden, here: displayUUID,
                                           turnDisplay: Self.turnDisplay, mainDisplay: NSScreen.main?.displayUUID) else { return }
        navigation.currentView = .aris
        // Only shown: the notch opens without taking the keyboard (the panel isn't made key, Aris isn't brought
        // forward); the user's app keeps it, and the card's Y/N go through its own key tap.
        guard open() else { return }
        // During a turn, its end puts the notch away (after the card); after one, the card's answer does.
        if aris.isActive { if arisOpenedNotch == nil { arisOpenedNotch = true } } else { openedForCard = true }
    }

    func arisPhaseChanged() {
        guard aris.isActive, arisOpenedNotch == true, closed, turnNeedsPanel, !approvalsPending else { return }
        navigation.currentView = .aris
        open()
    }

    /// A press in this notch opened the Settings window (ArisStepAside): the notch closes out of its way.
    func settingsOpened() {
        guard ArisNotchDecisions.stepsAsideForSettings(open: isOpen, cardWaiting: aris.cardWaiting, approvalsPending: approvalsPending) else { return }
        hoverTask?.cancel()
        vm.close()
    }

    func notchStateChanged(_ state: NotchState) {
        if state == .open {
            let speed = max(Defaults[.animationSpeedMultiplier], 0.01)
            openingUntil = Date().addingTimeInterval(0.28 / speed)
            watchOpen()
            return
        }
        openedForApproval = false
        openedForNotice = false
        guard arisOpenedNotch != true else { return }
        let page = navigation.currentView
        if page == .shelf || (page == .claude && !approvalsPending) { navigation.currentView = .home }
    }
}

/// The notch's own reactions to state and app events.
struct ArisNotchBehaviour: ViewModifier {
    let root: ArisNotchRoot

    func body(content: Content) -> some View {
        content
            .animation(.smooth, value: root.claude.approvals)
            .onReceive(root.claude.$approvals) { approvals in
                let first = approvals.first.map { "\($0.id)" }
                DispatchQueue.main.async { root.approvalsChanged(first) }
            }
            .onChange(of: root.claude.transientPeek?.id) { _, id in root.noticeChanged(id) }
            .onReceive(NotificationCenter.default.publisher(for: .clipboardHotKey)) { _ in root.clipboardHotKey() }
            .onReceive(NotificationCenter.default.publisher(for: .arisHistoryRestored)) { _ in root.historyRestored() }
            .onReceive(NotificationCenter.default.publisher(for: .claudeAnswerHotKey)) { _ in root.claudeAnswerHotKey() }
            .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in root.closeUnlessHovering() }
            .onReceive(NotificationCenter.default.publisher(for: .arisSettingsOpenedByPress)) { _ in root.settingsOpened() }
            .onChange(of: root.vm.isPopoverActive) { root.closeUnlessHovering() }
            // Initial too: the first-run guide hands the notch back as a turn starts, so this view tree appears with the
            // turn already active, and a plain onChange would never open the notch for it (bug hunt 2026-11-08).
            .onChange(of: root.aris.isActive, initial: true) { _, active in root.arisActiveChanged(active) }
            .onChange(of: root.aris.phase) { root.arisPhaseChanged() }
            .onChange(of: root.aris.cardWaiting, initial: true) { _, waiting in root.cardWaitingChanged(waiting) }
            .onChange(of: root.vm.notchState) { _, state in root.notchStateChanged(state) }
            .onChange(of: root.vm.dropInteraction.anyDropZoneTargeting) { _, active in root.dropTargetingChanged(active) }
            // The files given to Aris were used or cleared: the notch closes as usual again.
            .onReceive(ArisAttachments.shared.$pending) { if $0.files.isEmpty { root.vm.dropInteraction.arisDropHold = false } }
    }
}

/// Pointer, tap, menu, swipes and drops on the notch itself.
struct ArisNotchInput: ViewModifier {
    let root: ArisNotchRoot

    func body(content: Content) -> some View {
        content
            .onHover { root.hoverChanged($0) }
            .onTapGesture {
                guard root.closed, !root.noticeActive else { return }
                root.open()
            }
            .contextMenu {
                Button("Settings") { ArisSettingsWindow.shared.show() }
                    .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            }
            .sensoryFeedback(.alignment, trigger: root.haptic)
            .panGesture(direction: .down, enabled: root.swipeDownEnabled) { root.swipeDown($0, $1) }
            .panGesture(direction: .up, enabled: root.swipeUpEnabled) { root.swipeUp($0, $1) }
            .panGesture(direction: .left, enabled: root.mediaSwipeEnabled) { root.swipeMedia($0, $1, next: true) }
            .panGesture(direction: .right, enabled: root.mediaSwipeEnabled) { root.swipeMedia($0, $1, next: false) }
            .onDrop(of: ArisNotchRoot.dropTypes, delegate: ArisNotchDropDelegate(root: root))
            .background(alignment: .top) {
                if root.shelfOn && root.closed && !root.noticeActive {
                    Rectangle().fill(.clear)
                        .frame(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
                        // Clear pixels let a drag through to the window below: during a content drag only, a strip the
                        // window server can hit reaches dragHoverDepth down (BUG-24c). Pointer hover never sees it.
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.black.opacity(0.001))
                                .frame(width: openNotchSize.width,
                                       height: root.vm.dropInteraction.dragNear ? ArisNotchDecisions.dragHoverDepth : 0)
                        }
                        .contentShape(Rectangle())
                        .onDrop(of: ArisNotchRoot.dropTypes, isTargeted: Binding(
                            get: { root.vm.dropInteraction.dragDetectorTargeting },
                            set: { root.vm.dropInteraction.dragDetectorTargeting = $0 })) { providers in
                            root.vm.dropInteraction.dropEvent = true
                            ShelfStateViewModel.shared.load(providers)
                            return true
                        }
                }
            }
    }
}

/// Drops on the notch's own layout: on the open home (or Aris) page the left half goes to the shelf and the right
/// half to Aris (the user's ArisDropZones); elsewhere it is refused.
struct ArisNotchDropDelegate: DropDelegate {
    let root: ArisNotchRoot

    private var interaction: DropInteractionState { root.vm.dropInteraction }
    private var onHome: Bool { root.isOpen && [.home, .aris].contains(root.navigation.currentView) }
    private var inset: CGFloat { cornerRadiusInsets.opened.top + ArisGlass.inset }

    private func side(_ info: DropInfo) -> ArisDropZones.Side {
        ArisNotchDecisions.homeDropSide(x: info.location.x - inset, contentWidth: ArisGlass.contentWidth)
    }

    /// A drag over a page without drop zones (Claude's) switches to home's, which has them (BUG-24b).
    private func showDropZones() {
        guard root.isOpen, let page = ArisNotchDecisions.dropPage(root.navigation.currentView) else { return }
        root.navigation.currentView = page
    }

    func dropEntered(info: DropInfo) {
        interaction.generalDropTargeting = true
        showDropZones()
        if onHome { interaction.homeDropSide = side(info) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        showDropZones()
        guard ArisNotchDecisions.acceptsDrop(isOpen: root.isOpen, onHome: onHome) else { return DropProposal(operation: .cancel) }
        interaction.homeDropSide = side(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        interaction.generalDropTargeting = false
        interaction.homeDropSide = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        interaction.generalDropTargeting = false
        defer { interaction.homeDropSide = nil }
        // While the notch is still opening (a quick drop, about a second after the drag came in) the zones are where they
        // will be: the drop is taken by its side, never lost (QA VM: no chip, no file, the notch closed).
        guard ArisNotchDecisions.acceptsDrop(isOpen: root.isOpen, onHome: onHome) else { return false }
        interaction.dropEvent = true
        ArisDropZones.deliver(info, to: side(info), interaction: interaction)
        return true
    }
}
