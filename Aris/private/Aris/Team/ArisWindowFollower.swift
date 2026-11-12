//
//  ArisWindowFollower.swift
//  Aris
//
//  Follows one window of another app while a teammate sits on it. Wake sources say when the window may have moved
//  (ArisWindowWakes.swift); a display link then reads its frame every frame until nothing has changed for 150 ms,
//  and stops. Nothing runs per frame while the window is still.
//
//  - Accessibility (when Aris is trusted and the target lets it observe): moved/resized wake the tracker,
//    destroyed/miniaturised end the follow, the app hiding or its focused window changing check once. No polling.
//  - Without it, as a last resort: one CGWindowList read every 0.5 s while following (about 0.1 ms each), so a
//    closed or moved window is still noticed.
//  - Always: a press on the window (or within 8 pt of it) arms drag tracking for that drag only; app hide, unhide
//    and activation, a Space change and display changes check once; the app quitting ends the follow.
//
//  `onChange(nil)` means the window is gone (closed, minimised, hidden, on another Space, or its app quit); nothing
//  is sent after it. Frames are CG coordinates. Releasing the follower (or `stop()`) stops everything.
//

import AppKit

@MainActor
final class ArisWindowFollower {
    /// Tracking stops once the frame hasn't changed for this long.
    static let settleTime: CFTimeInterval = 0.15
    /// A display link that hasn't ticked for this long is replaced on the next wake.
    static let staleTicker: CFTimeInterval = 0.25
    /// Seconds between checks when Accessibility can't wake the follower.
    static let pollInterval: TimeInterval = 0.5
    /// How far outside the window a press still arms drag tracking.
    static let dragSlop: CGFloat = 8

    let pid: Int32
    let windowNumber: Int
    /// True when Accessibility observes the window; false when the follower falls back to polling.
    private(set) var usesAccessibility = false

    private let onChange: (CGRect?) -> Void
    private var last: CGRect?
    private var ended = false
    private var wakes: [ArisWindowWake] = []
    private var ticker: ArisFrameTicker?
    private var lastChange: CFTimeInterval = 0
    private var dragArmed = false

    init(pid: Int32, windowNumber: Int, onChange: @escaping (CGRect?) -> Void) {
        self.pid = pid
        self.windowNumber = windowNumber
        self.onChange = onChange
        last = ArisWindowLocator.frame(pid: pid, windowNumber: windowNumber)
        let relay = ArisWakeRelay { [weak self] reason in self?.wake(reason) }
        if let ax = ArisAXWindowWake(pid: pid, windowNumber: windowNumber, frame: last, relay: relay) {
            wakes.append(ax)
            usesAccessibility = true
        } else {
            wakes.append(ArisPollWindowWake(every: Self.pollInterval, relay: relay))
        }
        wakes.append(ArisSystemWindowWake(pid: pid, relay: relay))
        NSLog("[Aris] following window %d of pid %d via %@", windowNumber, pid, usesAccessibility ? "Accessibility" : "polling")
        // A window that is already gone is reported after init returns, so the owner holds the follower by then.
        if last == nil { relay.post(.gone) }
    }

    /// Stops every wake source and the tracker; nothing is sent afterwards.
    func stop() {
        ended = true
        ticker?.stop()
        ticker = nil
        wakes.forEach { $0.stop() }
        wakes = []
    }

    private func wake(_ reason: ArisWindowWakeReason) {
        guard !ended else { return }
        switch reason {
        case .gone:
            finish()
        case .check:
            if read() { track(readFirst: false) }
        case .track:
            track(readFirst: true)
        case .pointerDown:
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            dragArmed = ArisFollowRules.armsDrag(pointer: NSEvent.mouseLocation, window: last,
                                                 primaryHeight: primaryHeight, slop: Self.dragSlop)
        case .pointerDragged:
            if dragArmed { track(readFirst: true) }
        case .pointerUp:
            if dragArmed { track(readFirst: true) }
            dragArmed = false
        case .screensChanged:
            ticker?.stop()
            ticker = nil
            if read() { track(readFirst: false) }
        }
    }

    /// Reads the frame and sends it when it changed. Returns whether it changed.
    private func read() -> Bool {
        guard let frame = ArisWindowLocator.frame(pid: pid, windowNumber: windowNumber) else {
            finish()
            return false
        }
        guard frame != last else { return false }
        last = frame
        onChange(frame)
        return true
    }

    /// Keeps the tracker running for another `settleTime`. A running, live tracker only has its settle clock reset;
    /// otherwise the frame is read once (when asked) and a new tracker starts on the window's display.
    private func track(readFirst: Bool) {
        guard !ended else { return }
        let now = CACurrentMediaTime()
        lastChange = now
        if let ticker, !ArisFollowRules.isStale(lastTick: ticker.lastTick, now: now, after: Self.staleTicker) { return }
        if readFirst { _ = read() }
        guard !ended else { return }
        startTicker()
    }

    private func startTicker() {
        ticker?.stop()
        let screen = Self.screen(showing: last)
        ticker = ArisFrameTicker(screen: screen) { [weak self] in self?.tick() ?? false }
    }

    /// One display frame while tracking. Returns false to stop this ticker: settled, ended, or replaced by one on the
    /// display the window moved to.
    private func tick() -> Bool {
        let now = CACurrentMediaTime()
        if read() {
            lastChange = now
            if let ticker, Self.screen(showing: last)?.frame != ticker.screenFrame {
                startTicker()
                return false
            }
        }
        guard !ended, !ArisFollowRules.settled(now: now, lastChange: lastChange, after: Self.settleTime) else {
            ticker = nil
            return false
        }
        return true
    }

    private func finish() {
        guard !ended else { return }
        stop()
        onChange(nil)
    }

    private static func screen(showing cgFrame: CGRect?) -> NSScreen? {
        let screens = NSScreen.screens
        guard let cgFrame, let primary = screens.first,
              let index = ArisFollowRules.screenIndex(windowCG: cgFrame, screens: screens.map(\.frame),
                                                      primaryHeight: primary.frame.height)
        else { return NSScreen.main }
        return screens[index]
    }
}

/// Calls `onTick` once per frame of `screen`'s display until it returns false or `stop()` is called. The display
/// link retains this object, not its owner, so a released owner just makes `onTick` return false.
@MainActor
final class ArisFrameTicker: NSObject {
    static let frameRates = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)

    /// The display this ticker runs on.
    let screenFrame: CGRect?
    /// When it last ticked (its creation time until the first tick).
    private(set) var lastTick = CACurrentMediaTime()
    private let onTick: () -> Bool
    private var link: CADisplayLink?

    init(screen: NSScreen?, onTick: @escaping () -> Bool) {
        self.onTick = onTick
        let screen = screen ?? NSScreen.main
        screenFrame = screen?.frame
        super.init()
        guard let screen else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = Self.frameRates
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        lastTick = CACurrentMediaTime()
        if !onTick() { stop() }
    }
}
