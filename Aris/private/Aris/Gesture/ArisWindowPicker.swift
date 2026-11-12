//
//  ArisWindowPicker.swift
//  Aris
//
//  Runs window picking for one turn (the owner's ①B; rules in ArisWindowPick): while armed, a pick overlay on every
//  display takes the clicks (nothing reaches the apps below), hit-tests the window under each one and toggles it.
//  A pick captures that window alone at once (ArisWindowCapture); a let-go one drops its capture. A private window
//  or the 9th shot gets the red refusal and nothing is captured. Disarmed, the overlays close and clicks pass through
//  again. At the end of the turn the picks are parked (≤ 30 s) until the turn collects them as numbered shots.
//  Idle cost is zero: nothing exists or runs between turns. Images stay in memory; no title or app name is logged.
//

import AppKit
import Carbon.HIToolbox
import os
import QuartzCore

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "gesture")

@MainActor
final class ArisWindowPicker {
    struct Dependencies {
        /// Displays by id with their Cocoa frames.
        var screens: () -> [(id: UInt32, frame: CGRect)]
        var nsScreen: (UInt32) -> NSScreen?
        /// The primary display's height (Cocoa ↔ Quartz).
        var primaryHeight: () -> CGFloat
        /// The window under a Quartz global point.
        var windowAt: @MainActor (CGPoint) -> ArisWindowHit?
        var capture: @Sendable (UInt32) async -> CGImage?
        var secureInput: () -> Bool
        var now: () -> Double
        var headless = false
        var parkFor: Duration = .milliseconds(Int(ArisGestureConstants.Session.collectMaxAgeMs))
    }

    typealias Speech = (startedAtMs: Double, endedAtMs: Double, totalVoicedMs: Double)

    private let deps: Dependencies
    private var state = ArisWindowPickState()
    private var overlays: [UInt32: ArisWindowPickOverlay] = [:]
    private var shots: [UInt32: Task<CGImage?, Never>] = [:]
    private var parked: (picks: [ArisWindowPickState.Pick], shots: [UInt32: Task<CGImage?, Never>], speech: Speech?)?
    private var expiry: Task<Void, Never>?
    private var closing: Task<Void, Never>?
    private var lastHoverAt = -Double.infinity

    /// Circled shots the turn holds (their share of the cap).
    var otherShots: () -> Int = { 0 }
    /// Voiced time now, for each pick's `[img N]` marker.
    var voicedMs: () -> Double = { 0 }
    /// The number of picks changed (the circle session counts them toward its cap).
    var onCountChanged: (Int) -> Void = { _ in }

    init(dependencies: Dependencies) {
        deps = dependencies
    }

    var isArmed: Bool { state.armed }
    var pickCount: Int { state.picks.count }
    var isIdle: Bool { overlays.isEmpty && !state.armed && state.picks.isEmpty && parked == nil && shots.isEmpty }
    func overlay(display: UInt32) -> ArisWindowPickOverlay? { overlays[display] }

    // MARK: - The turn

    /// A turn that may pick begins: whatever an earlier one left is dropped.
    func begin() {
        cancel()
    }

    /// Clicks pick windows from now on: an overlay on every display.
    func arm() {
        guard !state.armed else { return }
        closing?.cancel()
        closing = nil
        state.arm()
        for screen in deps.screens() where overlays[screen.id] == nil {
            let bounds = ArisWindowPickGeometry.quartzBounds(ofCocoa: screen.frame, primaryHeight: deps.primaryHeight())
            let overlay = ArisWindowPickOverlay(display: screen.id, screenFrame: screen.frame, quartzBounds: bounds,
                                                screen: deps.nsScreen(screen.id), headless: deps.headless, now: deps.now)
            overlay.view.onClick = { [weak self] in self?.click(at: $0) }
            overlay.view.onMove = { [weak self] in self?.move(to: $0) }
            for pick in state.picks { if let rect = overlay.local(pick.hit.frame) { overlay.view.addWash(id: pick.hit.id, rect: rect) } }
            overlay.show()
            overlays[screen.id] = overlay
        }
        overlays.values.forEach { $0.setInteractive(true) }
        log.notice("window pick armed on \(self.overlays.count, privacy: .public) display(s)")
    }

    /// Clicks reach the apps again; the picks stay for the turn.
    func disarm() {
        guard state.armed else { return }
        state.disarm()
        // Clicks reach the apps at once; the surfaces only fade out (QA BUG-44).
        overlays.values.forEach { $0.setInteractive(false); $0.view.removeAllWashes(); $0.view.setHover(id: nil, rect: nil) }
        let ms = Int(ArisWindowPickWash.fadeMs) + 20
        closing = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled, let self, !self.state.armed else { return }
            self.closeOverlays()
        }
    }

    /// The turn stopped listening: park the picks for it to collect.
    func finish(speech: Speech?) {
        disarm()
        guard !state.picks.isEmpty else { return reset(keepParked: false) }
        parked = (state.picks, shots, speech)
        state.reset()
        shots = [:]
        onCountChanged(0)
        log.notice("window pick: \(self.parked?.picks.count ?? 0, privacy: .public) window(s) parked for the turn")
        expiry?.cancel()
        let parkFor = deps.parkFor
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: parkFor)
            guard !Task.isCancelled, let self else { return }
            log.notice("window pick: not collected in time, dropped")
            self.dropParked()
        }
    }

    /// The turn is over however it ended: the surfaces go now; picks already parked wait for the turn to collect them.
    func putAway() {
        closing?.cancel()
        closing = nil
        if state.armed { state.disarm() }
        closeOverlays()
    }

    /// The surfaces up now, for the tests.
    var overlayCount: Int { overlays.count }

    /// The turn was dropped: everything goes.
    func cancel() {
        closing?.cancel()
        closing = nil
        closeOverlays()
        reset(keepParked: false)
    }

    /// The parked picks as numbered shots (circles' numbers in `taken` are skipped), waiting at most `timeout` for
    /// captures still coming. Nil when nothing was picked. Once collected they're gone.
    func collect(taken: Set<Int>, timeout: Duration = .milliseconds(Int(ArisGestureConstants.Session.shotWaitMs)))
        async -> (shots: [ArisGestureShot], speech: Speech?)? {
        guard let parked else { return nil }
        self.parked = nil // collected once; its captures are awaited below, not cancelled
        expiry?.cancel()
        expiry = nil
        var images: [(ArisWindowPickState.Pick, CGImage)] = []
        for pick in parked.picks {
            guard let task = parked.shots[pick.hit.id], let image = await ArisTaskRace.value(of: task, within: timeout) else { continue }
            images.append((pick, image))
        }
        guard !deps.secureInput() else {
            log.notice("window pick: secure input at send, nothing goes")
            return nil
        }
        let badges = ArisWindowPickMerge.badges(taken: taken, count: images.count)
        let work: [(pick: ArisWindowPickState.Pick, image: CGImage, badge: Int)] = zip(images, badges).map { ($0.0, $0.1, $1) }
        let made: [ArisGestureShot] = await Task.detached(priority: .userInitiated) { () -> [ArisGestureShot] in
            var out: [ArisGestureShot] = []
            for item in work {
                guard let shot = ArisWindowPickShots.compose(window: item.image, badge: item.badge) else { continue }
                out.append(ArisGestureShot(badge: item.badge, app: item.pick.hit.app, title: item.pick.hit.title, jpeg: shot.jpeg,
                                           thumb: shot.thumb, voicedMsAtCapture: item.pick.voicedMs, capturedAtMs: item.pick.at,
                                           display: item.pick.display))
            }
            return out
        }.value
        log.notice("window pick at send: \(made.count, privacy: .public) of \(parked.picks.count, privacy: .public) window(s)")
        guard !made.isEmpty else { return nil }
        let speech: Speech? = parked.speech
        return (shots: made, speech: speech)
    }

    // MARK: - Clicks

    func click(at cocoa: CGPoint) {
        guard state.armed else { return }
        guard !deps.secureInput() else {
            log.notice("window pick: secure input, click ignored")
            return
        }
        let quartz = ArisWindowPickGeometry.quartz(cocoa, primaryHeight: deps.primaryHeight())
        let display = deps.screens().first { $0.frame.contains(cocoa) }?.id ?? overlays.keys.sorted().first ?? 0
        let hit = deps.windowAt(quartz)
        switch state.toggle(hit, otherShots: otherShots(), voicedMs: voicedMs(), at: deps.now(), display: display) {
        case .added(let pick):
            overlays.values.forEach { overlay in
                if let rect = overlay.local(pick.hit.frame) { overlay.view.addWash(id: pick.hit.id, rect: rect) }
            }
            startCapture(pick.hit.id)
            log.notice("window pick: picked (\(self.state.picks.count, privacy: .public))")
        case .removed(let hit):
            overlays.values.forEach { $0.view.removeWash(id: hit.id) }
            shots.removeValue(forKey: hit.id)?.cancel()
            log.notice("window pick: let go (\(self.state.picks.count, privacy: .public))")
        case .refused(let hit):
            log.notice("window pick refused: private window")
            refuse(hit, click: quartz, text: ArisGestureChrome.refusalText(for: hit), icon: .lock)
        case .full(let hit):
            log.notice("window pick over the \(ArisWindowPick.maxShots, privacy: .public)-shot limit")
            let used = min(ArisWindowPick.maxShots, state.picks.count + otherShots())
            refuse(hit, click: quartz, text: ArisGestureChrome.limitText(shots: used, max: ArisWindowPick.maxShots), icon: .image)
        case .ignored:
            break
        }
        onCountChanged(state.picks.count)
    }

    /// The faint ring on the window under the pointer (one that can be picked), looked up at most every 50 ms.
    func move(to cocoa: CGPoint) {
        guard state.armed else { return }
        let t = deps.now()
        guard t - lastHoverAt >= 50 else { return }
        lastHoverAt = t
        let hit = deps.windowAt(ArisWindowPickGeometry.quartz(cocoa, primaryHeight: deps.primaryHeight()))
        let pickable = hit.flatMap { ArisGestureSession.refuses($0) || $0.bundleId == nil ? nil : $0 }
        for overlay in overlays.values {
            let rect = pickable.flatMap { overlay.local($0.frame) }
            overlay.view.setHover(id: rect == nil ? nil : pickable?.id, rect: rect)
        }
    }

    // MARK: - Helpers

    private func startCapture(_ id: UInt32) {
        let capture = deps.capture
        shots[id]?.cancel()
        let task = Task<CGImage?, Never> { await capture(id) }
        shots[id] = task
        Task { @MainActor [weak self] in
            let image = await task.value
            guard image == nil, let self, self.shots[id] == task, !task.isCancelled else { return }
            // Nothing came (the window closed, the grant went): the pick goes, its wash fades.
            log.notice("window pick: capture gave nothing, pick dropped")
            self.shots[id] = nil
            if self.state.drop(window: id) {
                self.overlays.values.forEach { $0.view.removeWash(id: id) }
                self.onCountChanged(self.state.picks.count)
            }
        }
    }

    private func refuse(_ hit: ArisWindowHit, click quartz: CGPoint, text: String, icon: ArisGestureChrome.Icon) {
        for overlay in overlays.values {
            guard let rect = overlay.local(hit.frame) else { continue }
            let p = CGPoint(x: quartz.x - overlay.quartzBounds.minX, y: quartz.y - overlay.quartzBounds.minY)
            let click = overlay.view.bounds.contains(p) ? p : CGPoint(x: rect.midX, y: rect.midY)
            overlay.view.showRefusal(rect: rect, click: click, text: text, icon: icon)
        }
    }

    private func closeOverlays() {
        overlays.values.forEach { $0.close() }
        overlays = [:]
    }

    private func reset(keepParked: Bool) {
        state.reset()
        shots.values.forEach { $0.cancel() }
        shots = [:]
        if !keepParked { dropParked() }
        onCountChanged(0)
    }

    private func dropParked() {
        parked?.shots.values.forEach { $0.cancel() }
        parked = nil
        expiry?.cancel()
        expiry = nil
    }
}
