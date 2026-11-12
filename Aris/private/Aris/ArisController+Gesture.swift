//
//  ArisController+Gesture.swift
//  Aris
//
//  Circling while talking (plan D5), wired to its own key, ⌥⇧ held alone (ArisGestureKeyTap; ⌥ Space is voice only):
//  - a ⌥⇧ press whose turn really started listening begins a session (only with the setting on, the Screen Recording
//    grant and no secure input); held 200 ms it commits (hint, pump);
//  - a tap under the 350 ms limit makes it hands-free; a release after a hold, the hands-free pause or a second tap
//    finalizes it; a wake-word turn begins committed and hands-free; cancel and `fail` abort it;
//  - with the setting on and no grant, the once-per-launch line "화면을 보려면 화면 기록 권한이 필요해요 · 허용하기"
//    appears by the pointer instead (never `CGRequestScreenCaptureAccess` from a key press);
//  - while it draws, the turn's microphone feeds the voiced-time count for the `[img N]` markers.
//  The finalized result waits in `ArisGestureHooks.shared.capture` for the turn to collect it (P1.9), at most 30 s; a
//  new turn drops any result left over.
//  Picking windows (the owner's ①B, ArisWindowPicker): ⌥ Space held past the commit window, or the circle mode (⌥⇧ held
//  or hands-free), arms a pick overlay that takes the clicks; a talk-key tap (hands-free voice) disarms it. The picks
//  join the circled shots at send, sharing the 8-shot cap.
//

import AppKit
import Carbon.HIToolbox
import Defaults
import QuartzCore
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "gesture")

extension ArisScreenCapture: ArisGestureFrameSource {}

extension ArisWindowPicker.Dependencies {
    @MainActor static var live: Self {
        Self(screens: { NSScreen.screens.compactMap { screen in
                 (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { ($0.uint32Value, screen.frame) }
             } },
             nsScreen: { id in NSScreen.screens.first {
                 ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
             } },
             primaryHeight: { NSScreen.screens.first?.frame.maxY ?? 0 },
             windowAt: { ArisWindowAtPoint.hit(at: $0) },
             capture: { await ArisWindowCapture.shared.image(window: $0) },
             secureInput: { IsSecureEventInputEnabled() },
             now: { CACurrentMediaTime() * 1000 })
    }
}

extension ArisGestureCapture.Dependencies {
    @MainActor static var live: Self {
        Self(screen: ArisScreenCapture.shared,
             windowsAt: { ArisWindowAtPoint.hits(at: $0) },
             displayBounds: { CGDisplayBounds($0) },
             now: { CACurrentMediaTime() * 1000 },
             secureInput: { IsSecureEventInputEnabled() })
    }
}

/// The gesture's two objects, made the first time a turn may draw. Between turns nothing of theirs runs.
@MainActor
final class ArisGestureHooks {
    static let shared = ArisGestureHooks()

    private(set) var capture: ArisGestureCapture?
    private(set) var controller: ArisGestureController?
    /// Window picking (①B), made the first time a turn may pick.
    private(set) var picker: ArisWindowPicker?
    /// This turn picks: ⌥⇧'s circle mode (`pickByGestureKey`) or the talk key held.
    fileprivate var picking = false
    fileprivate var pickByGestureKey = false
    fileprivate var pickCommit: Task<Void, Never>?
    fileprivate var commit: Task<Void, Never>?
    /// D4: the chips' thumbnails go when the conversation would end (5 min), even if nothing else clears them.
    fileprivate var thumbsExpiry: Task<Void, Never>?
    /// The press now starting a turn is the gesture key's (⌥⇧): only it arms the ink, never ⌥ Space.
    fileprivate(set) var gestureKeyPress = false
    /// The listener whose chunks feed the voiced-time count (only while this turn draws).
    private weak var teed: AnyObject?

    /// A session for this turn, or nil (setting off, no grant, secure input). Drops any result an earlier turn left.
    fileprivate func begin(listener: AnyObject?) -> ArisGestureController? {
        let setting = Defaults[.arisCircleGesture], permission = CGPreflightScreenCaptureAccess()
        let secure = IsSecureEventInputEnabled()
        log.notice("gesture gate: setting \(setting, privacy: .public), screen recording \(permission, privacy: .public), secure input \(secure, privacy: .public)")
        capture?.dropParked()
        guard ArisGestureGate.allows(setting: setting, permission: permission, secureInput: secure) else {
            if ArisGestureGate.needsPermissionLine(setting: setting, permission: permission, secureInput: secure),
               let line = ArisScreenPermissionNotice.next() {
                ArisGesturePermissionChip.shared.showNearPointer(line)
            }
            return nil
        }
        let capture = self.capture ?? ArisGestureCapture(dependencies: .live)
        let controller = self.controller ?? ArisGestureController(capturer: capture, environment: .live)
        self.capture = capture
        self.controller = controller
        capture.startSpeech(at: CACurrentMediaTime() * 1000)
        tee(listener)
        Task { await ArisScreenCapture.shared.warm() } // the grant is already checked: no prompt
        beginPicker(gestureKey: true, controller: controller, capture: capture)
        return controller
    }

    /// The talk key's turn may pick windows while it's held (same gate as circling, no permission line: a turn that
    /// asks about the screen says it). The capture object only keeps the voiced time for the `[img N]` markers.
    fileprivate func beginTalkPicking(listener: AnyObject?) -> ArisWindowPicker? {
        guard ArisWindowPick.listens(setting: Defaults[.arisCircleGesture], permission: CGPreflightScreenCaptureAccess(),
                                     secureInput: IsSecureEventInputEnabled()) else { return nil }
        let capture = self.capture ?? ArisGestureCapture(dependencies: .live)
        self.capture = capture
        capture.startSpeech(at: CACurrentMediaTime() * 1000)
        tee(listener)
        return beginPicker(gestureKey: false, controller: nil, capture: capture)
    }

    @discardableResult
    private func beginPicker(gestureKey: Bool, controller: ArisGestureController?, capture: ArisGestureCapture) -> ArisWindowPicker {
        let picker = self.picker ?? ArisWindowPicker(dependencies: .live)
        self.picker = picker
        picker.begin()
        picking = true
        pickByGestureKey = gestureKey
        picker.voicedMs = { [weak capture] in capture?.voicedMsNow ?? 0 }
        picker.otherShots = { [weak controller] in controller?.shotCount ?? 0 }
        picker.onCountChanged = { [weak controller] in controller?.otherShots = $0 }
        return picker
    }

    /// Clicks pick windows now (the press committed, or the circle mode went hands-free).
    fileprivate func armPicker() {
        guard picking else { return }
        if pickByGestureKey { controller?.picking = true }
        picker?.arm()
    }

    /// The turn stopped listening: the picks wait for it.
    fileprivate func finishPicker() {
        pickCommit?.cancel()
        guard picking else { return }
        picking = false
        picker?.finish(speech: capture?.speechSummary())
    }

    fileprivate func cancelPicker() {
        pickCommit?.cancel()
        picking = false
        picker?.cancel()
    }

    fileprivate func end() {
        commit?.cancel()
        commit = nil
        pickCommit?.cancel()
        pickCommit = nil
        untee()
    }

    private func tee(_ listener: AnyObject?) {
        guard #available(macOS 26.0, *), let listener = listener as? ArisListener else { return }
        listener.onSpeechChunk = { samples in
            Task { @MainActor in
                ArisGestureHooks.shared.capture?.feedSpeech(samples, at: CACurrentMediaTime() * 1000)
            }
        }
        teed = listener
    }

    private func untee() {
        if #available(macOS 26.0, *), let listener = teed as? ArisListener { listener.onSpeechChunk = nil }
        teed = nil
    }
}

extension ArisController {
    /// The talk key went down and its turn is listening.
    func gestureKeyDown() {
        let hooks = ArisGestureHooks.shared
        guard ArisGestureKey.armsInk(gestureKey: hooks.gestureKeyPress) else {
            log.notice("gesture: mic opened by the talk key, voice only (no ink)")
            hooks.capture?.dropParked()
            beginTalkPicking()
            return
        }
        log.notice("gesture: mic opened by ⌥⇧, the turn is listening")
        guard let controller = hooks.begin(listener: listener) else { return }
        controller.keyDown()
        hooks.commit?.cancel()
        hooks.commit = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(ArisGestureConstants.Session.commitWindowMs)))
            guard !Task.isCancelled, let self, self.keyHeld, controller.phase == .provisional else { return }
            controller.held()
            if ArisWindowPick.arms(gestureKey: true, committed: controller.phase == .committed, handsFree: false) { hooks.armPicker() }
        }
    }

    /// ⌥ Space started a listening turn: held past the commit window, clicks pick windows until it's let go.
    private func beginTalkPicking() {
        let hooks = ArisGestureHooks.shared
        hooks.cancelPicker()
        guard hooks.beginTalkPicking(listener: listener) != nil else { return }
        hooks.pickCommit = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(ArisGestureConstants.Session.commitWindowMs)))
            guard !Task.isCancelled, let self, self.session.phase == .listening,
                  ArisWindowPick.arms(gestureKey: false, committed: self.keyHeld, handsFree: self.handsFree) else { return }
            hooks.armPicker()
        }
    }

    /// Whether a ⌥⇧ press waits the longer debounce now (a turn is answering: ArisGestureKey.waitsLonger).
    var gestureWaitsLonger: Bool { ArisGestureKey.waitsLonger(session.phase) }

    /// The gesture key (ArisGestureKeyTap): ⌥⇧ held starts a talk turn with the ink armed; letting go ends it by the
    /// talk key's release rules (a short press keeps listening hands-free); another key while held cancels it.
    func gestureKey(_ action: ArisGestureKey.Action) {
        switch action {
        case .start:
            guard training == nil else { return }
            let hooks = ArisGestureHooks.shared
            hooks.gestureKeyPress = true
            keyDown()
            hooks.gestureKeyPress = false
        case .finish(let ms):
            gestureKeyReleased(heldFor: .milliseconds(Int(ms.rounded())))
        case .cancel:
            keyHeld = false
            guard pressStartedTurn else { return }
            pressStartedTurn = false
            cancel()
        case .tap(let ms):
            // A tap that waited out the longer debounce (a turn was answering): its start and its release at once.
            gestureKey(.start)
            gestureKey(.finish(heldForMs: ms))
        case .none:
            break
        }
    }

    /// keyUp's rules, timed by the key's own events (the talk key's probe watches Space, not ⌥⇧).
    private func gestureKeyReleased(heldFor: Duration) {
        keyHeld = false
        guard pressStartedTurn, session.phase == .listening else {
            if pressStartedTurn { gestureKeyUpWithoutTurn() }
            return
        }
        pressStartedTurn = false
        switch ArisTalkKey.release(heldFor: heldFor) {
        case .finish:
            stopListening()
        case .keepListening:
            listenHandsFree()
            gestureTapped()
        }
    }

    /// Released under the tap limit: Aris listens hands-free, by voice only. A tap never arms the ink or window picking
    /// on every display (QA BUG-44: a 309 ms ⌥⇧ tap left full-screen surfaces up over every app); drawing and picking
    /// need the key held. The turn ends on a pause like any hands-free turn.
    func gestureTapped() {
        let hooks = ArisGestureHooks.shared
        hooks.commit?.cancel()
        hooks.pickCommit?.cancel()
        if hooks.pickByGestureKey { hooks.controller?.cancel() }
        hooks.cancelPicker()
        ArisOverlayCensus.closeAll()
    }

    /// The turn is over (the session went idle, however it ended): nothing it put on screen stays (QA BUG-44). A
    /// drawing session still live is dropped; picks already parked stay for the turn to collect.
    func closeGestureLeftovers() {
        let hooks = ArisGestureHooks.shared
        if let phase = hooks.controller?.phase, phase == .provisional || phase == .committed { hooks.controller?.cancel() }
        hooks.picker?.putAway()
        let left = ArisOverlayCensus.closeAll()
        if left > 0 { log.notice("gesture: put away \(left, privacy: .public) overlay(s) the turn left") }
    }

    /// The turn stops listening (a release after a hold, the hands-free pause, a second tap): finalize.
    func gestureFinished() {
        let hooks = ArisGestureHooks.shared
        hooks.controller?.release()
        hooks.finishPicker()
        hooks.end()
    }

    /// The turn was dropped or failed: abort, nothing is kept.
    func gestureCancelled() {
        let hooks = ArisGestureHooks.shared
        hooks.controller?.cancel()
        hooks.cancelPicker()
        hooks.end()
        ArisOverlayCensus.closeAll()
    }

    /// The press started a turn but listening never began: drop a live session (a finalized one is the turn's).
    func gestureKeyUpWithoutTurn() {
        guard session.phase != .listening, let phase = ArisGestureHooks.shared.controller?.phase,
              phase == .provisional || phase == .committed else { return }
        gestureCancelled()
    }

    /// The turn's finished drawing, waiting for it at most 2.5 s (`collectForTurn`); nil when the user didn't circle or draw.
    func collectGestureTurn() async -> ArisGestureTurn? {
        let hooks = ArisGestureHooks.shared
        guard let capture = hooks.capture else {
            log.notice("gesture at send: no session this launch, 0 shots")
            return nil
        }
        let drawn = await capture.collect()
        // The picked windows join the circled shots, numbered after them (ArisWindowPickMerge).
        let picked = await hooks.picker?.collect(taken: Set(drawn?.shots.map(\.badge) ?? []))
        let result = ArisWindowPickMerge.merge(drawn, picks: picked?.shots ?? [], speech: picked?.speech)
        log.notice("gesture at send: \(result?.shots.count ?? 0, privacy: .public) shot(s) (\(picked?.shots.count ?? 0, privacy: .public) picked), \(result?.references.count ?? 0, privacy: .public) reference(s)")
        return ArisGestureTurn(result: result)
    }

    /// The shots go with this turn's ask (replacing the screenshot); their thumbnails show as the prompt's chips.
    func attachGesture(_ gesture: ArisGestureTurn) {
        ArisTurnCapture.shared.attachGesture(gesture.images)
        shotThumbs = gesture.thumbs.compactMapValues { NSImage(data: $0) }
        let hooks = ArisGestureHooks.shared
        hooks.thumbsExpiry?.cancel()
        guard !shotThumbs.isEmpty else { return }
        let lasts = Self.conversationLasts
        hooks.thumbsExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: lasts)
            guard !Task.isCancelled else { return }
            self?.shotThumbs = [:]
        }
    }

}
