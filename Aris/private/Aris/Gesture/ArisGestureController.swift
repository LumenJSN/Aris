//
//  ArisGestureController.swift
//  Aris
//
//  Runs one drawing session on screen: the session reducer (P1.6), the 8 ms pointer pump, the mouse monitors, the
//  front-app observer, one ink overlay per drawn display (at most 3) and the hint chip. It turns reducer effects into
//  ink: an accepted loop seals (the owner's pick B), a private window or the 9th circle re-inks red with its capsule.
//
//  Entry points (wired from ArisController in ArisController+Gesture.swift):
//  - `keyDown()` when ⌥⇧ starts a turn (ArisGestureKey), `held()` 200 ms later, `tap()` for a release under the
//    350 ms tap limit, `release()` after a hold, `handsFreeEnd()` when hands-free listening ends (a wake-word turn
//    never arms the ink: only ⌥⇧ held does), `cancel()` for the pill, Esc or a new turn.
//  - Gate it yourself: with the gesture setting off or no Screen Recording grant, don't call `keyDown()` at all.
//  - Capture goes through `capturer`: `ArisGestureCapture` in the app (P1.8), `ArisGestureLogCapture` headless.
//
//  Idle cost is zero: nothing exists before `keyDown()`; the pump, monitors and observer start at commit; panels are
//  built when the pointer arms; everything is closed at finalize or abort.
//
//  Deviation from plan D5: instead of a 60 ms display poll, each pump tick checks whether the cursor is still inside
//  the current display's frame and looks the display up again only when it isn't (cheaper, and no 60 ms lag). A
//  screen-parameters observer closes the surfaces of displays that went away.
//
//  Every system callback (pump, monitors, observers) hops onto the main actor with a Task; nothing assumes it. A
//  hop that lands after teardown finds `running` false and does nothing.
//

import AppKit
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "gesture")

@MainActor
final class ArisGestureController {
    /// The world the controller reads. `.live` (ArisGestureController+Live) is the real one; renders pass a
    /// scripted pointer and clock with `headless` on (no panels, timers, monitors or display links).
    struct Environment {
        var now: () -> Double
        var pointer: () -> CGPoint
        var buttonDown: () -> Bool
        var screens: () -> [ArisGestureScreen]
        var nsScreen: (UInt32) -> NSScreen?
        var hintIcon: @MainActor () -> ArisGestureHint.Icon
        var headless: Bool
        /// Pointer positions read off the main thread since the last call (ArisPointerSampler), oldest first, global
        /// points stamped on `now`'s clock. Nil: each tick reads `pointer` at `now` (renders and tests).
        var samples: (() -> [ArisGesturePoint])? = nil
        /// The off-main sampler should run (the session started) or stop (it ended).
        var sampling: (Bool) -> Void = { _ in }
        /// An ad demo's session (ArisAdDemo): its ink and hint show in screen recordings. Never for a real one.
        var shownInCaptures = false
    }

    private struct Surface {
        let screen: ArisGestureScreen
        let overlay: ArisInkOverlay
        var detector: ArisGestureDetector
        var strokes: [[ArisGesturePoint]] = []
        var strokeOpen = false
        var last: CGPoint?
    }

    private struct Pending {
        let gesture: ArisGesture
        let screen: ArisGestureScreen
        let revision: Int
        let badge: Int
        var hit: ArisWindowHit?
    }

    let capturer: ArisGestureCapturing
    private let env: Environment
    private var session = ArisGestureSession()
    private var arming = ArisArming()
    private var bootRing = ArisBootRing()
    private var armed = false
    private var handsFree = false
    private var running = false
    private var buttonDown = false
    private var hint: ArisGestureHint?
    private var hintState = ArisGestureHintState()
    private var hintScreen: ArisGestureScreen?
    private var surfaces: [UInt32: Surface] = [:]
    private var pending: [Int: Pending] = [:]
    private var currentScreen: ArisGestureScreen?
    private var pump: DispatchSourceTimer?
    private var monitors: [Any] = []
    private var frontObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    /// When the session committed (the pump started), on `env.now`'s clock.
    private var committedAt = -Double.infinity

    /// `capturer` nil: P1.7's log-only stand-in.
    init(capturer: ArisGestureCapturing? = nil, environment: Environment) {
        self.capturer = capturer ?? ArisGestureLogCapture()
        env = environment
    }

    /// The gesture setting: off → circles are ignored (the ink still draws).
    var gesturesEnabled: Bool {
        get { session.gesturesEnabled }
        set { session.gesturesEnabled = newValue }
    }

    var phase: ArisGestureSession.Phase { session.phase }

    /// Clicks pick windows (ArisWindowPicker): the ink never takes the mouse, so a click reaches the pick overlay.
    var picking = false {
        didSet { if picking { surfaces.values.forEach { $0.overlay.setInteractive(false) } } }
    }

    /// Windows picked this turn, counted toward the 8-shot cap.
    var otherShots: Int {
        get { session.otherShots }
        set { session.otherShots = newValue }
    }

    /// Circled shots kept or on their way, for the picker's share of the cap.
    var shotCount: Int { session.badges.count + (session.busy ? 1 : 0) }

    /// The numbers the circled shots took, so picks never reuse one.
    var takenBadges: Set<Int> { Set(session.badges) }

    /// Nothing running and nothing on screen.
    var isIdle: Bool {
        !running && pump == nil && monitors.isEmpty && frontObserver == nil && screenObserver == nil
            && surfaces.isEmpty && hint == nil
    }

    /// Displays with an overlay up, and how many of them take the mouse (only in a held session after arming).
    var surfaceCount: Int { surfaces.count }
    var interactiveSurfaceCount: Int { surfaces.values.filter { $0.overlay.isInteractive }.count }
    /// The ink canvas on a display, if one is up.
    func inkView(display: UInt32) -> ArisInkView? { surfaces[display]?.overlay.view }

    // MARK: - Entry points

    func keyDown() { send(.keyDown(env.now())) }
    func held() { send(.held200) }
    func tap() { send(.tap) }
    func release() { send(.release) }
    func handsFreeEnd() { send(.handsFreeEnd) }
    func cancel() { send(.cancel) }

    /// Feeds the reducer and runs its effects. `display` is where a gesture came from (for the 8/8 reject).
    func send(_ event: ArisGestureSession.Event, display: UInt32? = nil) {
        for effect in session.handle(event) { run(effect, display: display) }
    }

    // MARK: - Pump

    /// One 8 ms step: keep the button state, then each pointer position since the last step, in order: place the hint,
    /// arm, then feed the ink and detector. Does nothing outside a committed session (a pump hop that lands after
    /// teardown).
    func pumpTick() {
        guard running else { return }
        let down = env.buttonDown()
        if down != buttonDown { setButton(down) } // backstop for a monitor event that never came
        let samples = env.samples.map { $0() } ?? [ArisGesturePoint(x: env.pointer().x, y: env.pointer().y, t: env.now())]
        for p in samples { step(CGPoint(x: p.x, y: p.y), at: p.t) }
    }

    /// One pointer position at its own time. One read before the session committed (inside the key's debounce and the
    /// commit wait) only joins the approach path the ink replays when it arms.
    private func step(_ global: CGPoint, at t: Double) {
        guard let screen = screen(at: global) else { return }
        let local = ArisGestureGeometry.panelLocal(global, screen: screen.frame)
        if t < committedAt {
            if !armed, !buttonDown { bootRing.push(local, t: t, display: screen.id) }
            return
        }
        followHint(local, screen: screen)
        if !armed {
            if buttonDown { bootRing.clear() } else { bootRing.push(local, t: t, display: screen.id) }
            guard arming.sample(global, at: t, buttonDown: buttonDown) else { return }
            arm(screen: screen, at: t)
        }
        feed(local, screen: screen, at: t)
    }

    // MARK: - Effects

    private func run(_ effect: ArisGestureSession.Effect, display: UInt32?) {
        switch effect {
        case .buildPanels:
            break // panels are built deferred when the pointer arms; nothing to warm before then
        case .showHint:
            showHint()
        case .startPump:
            start()
        case .enterHandsFree:
            handsFree = true
            surfaces.values.forEach { $0.overlay.setInteractive(false) }
            start()
        case .stopAll:
            capturer.abort()
            teardown()
        case .finalize:
            capturer.finalize(strokes: surfaces.mapValues(\.strokes), handsFree: handsFree)
            teardown()
        case .startCapture(let gesture, let display, let revision, let badge, let id):
            startCapture(gesture, display: display, revision: revision, badge: badge, id: id)
        case .proceed(let id):
            seal(id)
            proceed(id)
        case .refusePrivate(let gesture, let id):
            refuse(gesture, id: id)
        case .keepShot(let badge, let id):
            pending[id] = nil
            capturer.keep(captureId: id, badge: badge)
        case .dropShot(let id, let reason):
            if let p = pending.removeValue(forKey: id) {
                surfaces[p.screen.id]?.overlay.view.withdrawSeal(id: id)
            }
            capturer.drop(captureId: id, reason: reason)
        case .reject(let gesture):
            log.notice("gesture over the \(ArisGestureSession.maxShots, privacy: .public)-shot limit")
            guard let display, let surface = surfaces[display] else { return }
            surface.overlay.view.showReject(points: gesture.points,
                                            closed: gesture.kind == .circle, bbox: gesture.bbox,
                                            text: ArisGestureChrome.limitText(shots: session.badges.count,
                                                                              max: ArisGestureSession.maxShots),
                                            icon: .image)
        case .ignore(let reason):
            log.debug("gesture ignored: \(reason, privacy: .public)")
        case .markFramesStale:
            capturer.markFramesStale()
        }
    }

    private func startCapture(_ g: ArisGesture, display: UInt32, revision: Int, badge: Int, id: Int) {
        let b = g.bbox
        log.notice("gesture loop detected: \(g.kind.rawValue, privacy: .public) \(Int(b.minX), privacy: .public),\(Int(b.minY), privacy: .public) \(Int(b.width), privacy: .public)x\(Int(b.height), privacy: .public)")
        guard let screen = surfaces[display]?.screen ?? env.screens().first(where: { $0.id == display }) else {
            send(.captureDone(captureId: id, ok: false))
            return
        }
        pending[id] = Pending(gesture: g, screen: screen, revision: revision, badge: badge)
        capturer.pickWindow(captureId: id, for: g, on: screen, handsFree: handsFree) { [weak self] hit in
            guard let self else { return }
            self.pending[id]?.hit = hit
            self.send(.windowPicked(captureId: id, hit: hit))
        }
    }

    /// The window may be captured: the loop seals now, never before, so a private window never flashes blue.
    private func seal(_ id: Int) {
        guard let p = pending[id], let view = surfaces[p.screen.id]?.overlay.view else { return }
        view.clearTrail()
        view.seal(points: p.gesture.points, closed: p.gesture.kind == .circle, id: id)
    }

    private func proceed(_ id: Int) {
        guard let p = pending[id] else { return }
        let request = ArisGestureCaptureRequest(captureId: id, badge: p.badge, revision: p.revision, gesture: p.gesture,
                                                screen: p.screen, hit: p.hit, inkAfterMs: session.inkBoundaryMs,
                                                strokes: surfaces[p.screen.id]?.strokes ?? [], handsFree: handsFree)
        capturer.capture(request) { [weak self] ok in self?.send(.captureDone(captureId: id, ok: ok)) }
    }

    /// A private (or unresolved) window: the red loop and the refusal capsule (no seal was drawn). No app name or
    /// window title is logged.
    private func refuse(_ gesture: ArisGesture?, id: Int) {
        let p = pending.removeValue(forKey: id)
        capturer.drop(captureId: id, reason: "private") // forget its detection too
        log.notice("gesture refused: private window")
        guard let gesture, let p, let view = surfaces[p.screen.id]?.overlay.view else { return }
        view.showReject(points: gesture.points, closed: gesture.kind == .circle,
                        bbox: gesture.bbox, text: ArisGestureChrome.refusalText(for: p.hit), icon: .lock)
    }

    // MARK: - Session plumbing

    /// Commit: the pump, the mouse monitors and the front-app observer. Safe to call twice (a tap after commit).
    private func start() {
        guard !running else { return }
        running = true
        committedAt = env.now()
        arming.commit(at: committedAt, origin: env.pointer())
        env.sampling(true)
        guard !env.headless else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval = Int(ArisGestureConstants.Session.cursorPumpIntervalMs)
        timer.schedule(deadline: .now(), repeating: .milliseconds(interval), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in self?.pumpTick() }
        }
        timer.resume()
        pump = timer
        let handler: (NSEvent) -> Void = { [weak self] event in
            let down = event.type == .leftMouseDown
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.setButton(down)
            }
        }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp], handler: handler) as Any,
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
                handler(event)
                return event
            } as Any,
        ]
        frontObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.send(.frontAppChanged)
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.screensChanged() }
        }
    }

    /// Displays changed: close the overlays of displays that are gone or moved, and find the cursor's display again.
    func screensChanged() {
        guard running else { return }
        let now = env.screens()
        for (id, surface) in surfaces where !now.contains(surface.screen) {
            surface.overlay.close()
            surfaces[id] = nil
        }
        currentScreen = nil
        if let home = hintScreen, !now.contains(home), hintState.leftDisplay() == .hideInstantly { hint?.hideInstantly() }
    }

    /// Closes everything this session made. The button state is kept (it's the pointer's, not the session's).
    private func teardown() {
        pump?.cancel()
        pump = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if let frontObserver { NSWorkspace.shared.notificationCenter.removeObserver(frontObserver) }
        frontObserver = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        surfaces.values.forEach { $0.overlay.close() }
        surfaces = [:]
        hint?.close()
        hint = nil
        hintScreen = nil
        hintState = ArisGestureHintState()
        arming = ArisArming()
        bootRing = ArisBootRing()
        armed = false
        handsFree = false
        picking = false
        running = false
        committedAt = -.infinity
        env.sampling(false)
        pending = [:]
        currentScreen = nil
    }

    private func setButton(_ down: Bool) {
        guard down != buttonDown else { return }
        buttonDown = down
        for id in surfaces.keys {
            surfaces[id]?.detector.pointerDown = down
            if down {
                // A press ends the stroke and paints no comet: a drag is not a gesture.
                surfaces[id]?.strokeOpen = false
                surfaces[id]?.overlay.view.clearTrail()
            }
        }
        if down { bootRing.clear() }
        send(down ? .buttonDown : .buttonUp)
    }

    // MARK: - Drawing

    private func arm(screen: ArisGestureScreen, at t: Double) {
        armed = true
        log.notice("gesture armed on display \(screen.id, privacy: .public)")
        if hintState.firstStroke() == .hideInstantly { hint?.hideInstantly() }
        // The approach path, so the stroke starts where the movement began.
        for p in bootRing.replay(now: t, display: screen.id) {
            feed(CGPoint(x: p.x, y: p.y), screen: screen, at: p.t)
        }
    }

    private func feed(_ local: CGPoint, screen: ArisGestureScreen, at t: Double) {
        guard armed, var s = surfaces[screen.id] ?? makeSurface(screen) else { return }
        guard s.last != local else { return } // only moves reach the detector
        s.last = local
        let point = ArisGesturePoint(x: local.x, y: local.y, t: t)
        if !buttonDown {
            s.overlay.view.addTrailPoint(point)
            if s.strokeOpen, let previous = s.strokes.last?.last {
                // Points under 1 pt apart on both axes are skipped.
                if abs(previous.x - local.x) >= 1 || abs(previous.y - local.y) >= 1 {
                    s.strokes[s.strokes.count - 1].append(point)
                }
            } else {
                s.strokes.append([point])
                s.strokeOpen = true
            }
        }
        let gesture = s.detector.feed(x: local.x, y: local.y, t: t)
        surfaces[screen.id] = s
        if let gesture { send(.gesture(gesture, display: screen.id, at: t), display: screen.id) }
    }

    /// Raises an overlay on a display the cursor entered, up to 3.
    private func makeSurface(_ screen: ArisGestureScreen) -> Surface? {
        guard surfaces.count < ArisGestureConstants.Session.maxDrawnDisplays else { return nil }
        let overlay = ArisInkOverlay(display: screen.id, screenFrame: screen.frame, screen: env.nsScreen(screen.id),
                                     headless: env.headless, now: env.now, shownInCaptures: env.shownInCaptures)
        overlay.show()
        overlay.setInteractive(!handsFree && !picking)
        var detector = ArisGestureDetector(displaySize: screen.frame.size)
        detector.pointerDown = buttonDown
        let surface = Surface(screen: screen, overlay: overlay, detector: detector)
        surfaces[screen.id] = surface
        capturer.strokeStarted(on: screen)
        return surface
    }

    // MARK: - Hint

    private func showHint() {
        guard hint == nil, !armed, let screen = screen(at: env.pointer()) else { return }
        let local = ArisGestureGeometry.panelLocal(env.pointer(), screen: screen.frame)
        guard hintState.show(at: local, now: env.now()) else { return }
        let made = ArisGestureHint(icon: env.hintIcon(), headless: env.headless, now: env.now, shownInCaptures: env.shownInCaptures)
        hint = made
        hintScreen = screen
        let placement = hintPlacement(local, screen: screen)
        made.show(frame: placement.frame, chipOrigin: placement.chip)
    }

    private func followHint(_ local: CGPoint, screen: ArisGestureScreen) {
        guard let hint, let home = hintScreen else { return }
        let action: ArisGestureHintState.Action
        if screen.id != home.id {
            action = hintState.leftDisplay()
        } else if hintState.phase == .away {
            action = hintState.returned(at: local)
            if action == .follow { hint.reveal() }
        } else {
            action = hintState.moved(to: local)
        }
        switch action {
        case .none: break
        case .follow:
            let placement = hintPlacement(local, screen: home)
            hint.place(frame: placement.frame, chipOrigin: placement.chip)
        case .hideInstantly: hint.hideInstantly()
        case .fadeOut: hint.fadeOut()
        }
    }

    /// The hint window in Cocoa global points, and the chip's spot in it.
    private func hintPlacement(_ local: CGPoint, screen: ArisGestureScreen) -> (frame: CGRect, chip: CGPoint) {
        let window = ArisGestureMotion.hintWindow(cursor: local, display: screen.frame.size)
        let r = window.frame
        let frame = CGRect(x: screen.frame.minX + r.minX, y: screen.frame.maxY - r.maxY, width: r.width, height: r.height)
        return (frame, ArisGestureMotion.hintChipOrigin(chip: ArisGestureChrome.hintChipSize(), in: window))
    }

    // MARK: - Displays

    private func screen(at global: CGPoint) -> ArisGestureScreen? {
        if let current = currentScreen, current.frame.contains(global) { return current }
        let screens = env.screens()
        guard let id = ArisCaptureRules.display(containing: global, in: screens.map { ($0.id, $0.frame) }) else { return nil }
        currentScreen = screens.first { $0.id == id }
        return currentScreen
    }

    #if DEBUG
    // MARK: - Renders

    /// The overlay (and the hint, when it is on this display) as one image at `scale`, posed at the clock's time.
    /// For the offscreen renders only (headless).
    func renderForReview(display: UInt32, scale: CGFloat = 2) -> CGImage? {
        guard let screen = env.screens().first(where: { $0.id == display }) else { return nil }
        let size = screen.frame.size
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: ArisInkRenderer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if let view = surfaces[display]?.overlay.view {
            view.prepareSnapshot()
            if let image = Self.snapshot(view, scale: scale) {
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        if let hint, hintScreen?.id == display, !hint.view.isHidden {
            hint.prepareSnapshot()
            if let image = Self.snapshot(hint.view, scale: scale) {
                let f = hint.frame
                let local = CGRect(x: f.minX - screen.frame.minX, y: f.minY - screen.frame.minY, width: f.width, height: f.height)
                ctx.draw(image, in: CGRect(x: local.minX * scale, y: local.minY * scale,
                                           width: local.width * scale, height: local.height * scale))
            }
        }
        return ctx.makeImage()
    }

    private static func snapshot(_ view: NSView, scale: CGFloat) -> CGImage? {
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }
    #endif
}
