//
//  ArisDictationPillRules.swift
//  Aris
//
//  The dictation pill's decisions as plain values (ArisDictationPillCenter applies them): what it shows for a dictation
//  stage (first match wins), each state's size and look, the inline error's width, where its window sits on a screen
//  (bottom centre, above a Dock that is showing), what the pointer counts on, how the hover follows it, how long a size
//  change takes (a reversal mid-way is shortened as CSS does), when a window counts as full screen, and when the top
//  notch stays quiet because the pill has the dictation. Pure, so it's tested.
//
//  Measured from the reference pill (its states sheet, bottom edge): the sliver 40 × 8 round 6 on black .5 inside a
//  1 px white .5 line; the hover 50 × 30, held 73 × 30, hands-free 102.5 × 30, writing 98 × 30, an error 30 high in a
//  1.5 px red line; every other state black in a 1 px #30302f line, round 22.5 (a capsule at 30). Every change of size,
//  colour and line runs 0.1 s on cubic-bezier(0.05, 0.6, 0.4, 0.95); showing and hiding is opacity alone, 0.1 s ease.
//  The pill stands 1 above the usable bottom (Aris's own place). The recovered words are a card fitted to them instead (the owner's pick B,
//  ArisDictationPillRecoveredLayout), standing where the pill stands.
//

import CoreGraphics
import Foundation

/// What the pill shows.
enum ArisDictationPillPhase: Equatable {
    /// Off, locked, or nothing to show in a full-screen app (or anywhere, with 쉴 때도 보이기 off).
    case hidden
    /// The 40 × 8 sliver: dictation is ready.
    case idle
    /// The pointer is on the sliver: the mic, and a click starts a dictation.
    case hover
    /// Listening: held (73 × 30, the level) or hands-free (102.5 × 30, ✕, the level, ■).
    case recording(handsFree: Bool)
    /// The words are being written down and typed: the still level and the spinner.
    case transcribing(ArisDictationPillSpinner.Stage)
    /// Nowhere took the words: they are on the clipboard and shown here to copy again.
    case recovered(String)
    /// A line of what went wrong, in place.
    case error(String)

    var shown: Bool { self != .hidden }
}

/// How the pill's body is drawn in a phase.
enum ArisDictationPillLookKind: Equatable {
    /// The sliver: black .5 in white .5.
    case sliver
    /// Under the pointer: #30302f in #5b5b59.
    case hovered
    /// Black in #30302f.
    case solid
    /// Black in 1.5 px #ee6a6a.
    case failed
}

enum ArisDictationPillRules {
    // MARK: - Sizes (measured from the reference pill, states.css, bottom edge)

    /// states.css:636.
    static let idleSize = CGSize(width: 40, height: 8)
    /// states.css:645.
    static let hoverSize = CGSize(width: 50, height: 30)
    /// states.css:642 (also the first instant, before the microphone is up).
    static let holdSize = CGSize(width: 73, height: 30)
    /// states.css:648.
    static let handsFreeSize = CGSize(width: 102.5, height: 30)
    /// states.css:651.
    static let transcribingSize = CGSize(width: 98, height: 30)
    /// states.css:671: 30 high and at least 91 wide; Aris says its line in it (the reference says it elsewhere), so it
    /// grows to the line, 12 in at each end, up to Aris's 280.
    static let errorHeight: CGFloat = 30
    static let errorMinWidth: CGFloat = 91
    static let errorMaxWidth: CGFloat = 280
    static let errorPadding: CGFloat = 24

    /// The sliver's corners (states.css:117; on its 8 high CSS shrinks them to 4, a capsule) and everyone else's
    /// (states.css:90, a capsule at 30 high).
    static let idleRadius: CGFloat = 6
    static let radius: CGFloat = 22.5
    /// The line: 1 (states.css:90, 117), an error's 1.5 (states.css:239).
    static let lineWidth: CGFloat = 1
    static let errorLineWidth: CGFloat = 1.5

    /// The corners at `size` as drawn: CSS moves the radius 6 → 22.5 with the height 8 → 30 on the same curve, so it
    /// is the height's share of the way; never more than half the short side (CSS clamps it so).
    static func cornerRadius(_ size: CGSize) -> CGFloat {
        let way = min(1, max(0, (size.height - idleSize.height) / (hoverSize.height - idleSize.height)))
        let r = idleRadius + (radius - idleRadius) * way
        return min(r, min(size.width, size.height) / 2)
    }

    static func look(_ phase: ArisDictationPillPhase) -> ArisDictationPillLookKind {
        switch phase {
        case .hidden, .idle: .sliver
        case .hover: .hovered
        case .error: .failed
        case .recording, .transcribing, .recovered: .solid
        }
    }

    // MARK: - Motion (measured from the reference pill)

    /// Size, colours and line: 0.1 s on cubic-bezier(0.05, 0.6, 0.4, 0.95) (states.css:102).
    static let sizeDuration = 0.1
    static let sizeCurve = ArisDictationPillCurve(0.05, 0.6, 0.4, 0.95)
    /// Showing and hiding: opacity alone, 0.1 s ease (states.css:81).
    static let showDuration = 0.1
    static let showCurve = ArisDictationPillCurve.ease
    /// The hover's tooltip: after 150 ms (status.js:13664), opacity 120 ms ease (states.css:509); a button's after 50 ms
    /// (status.js:8658).
    static let hintDelay = 0.15
    static let buttonHintDelay = 0.05
    static let hintFade = 0.12
    /// 4 above the pill, 10 above a button (status.js:10200, 8784).
    static let hintGap: CGFloat = 4
    static let buttonHintGap: CGFloat = 10
    /// Reduce Motion: sizes change at once and the content only fades, in the size's 0.1 s.
    static var reducedFade: Double { sizeDuration }
    /// The window: at most 540 × 700 (room for the recovered words' card); its bottom 5 under the usable bottom, the pill
    /// 6 above the window's bottom: the pill sits 1 above the Dock, where Aris always had it (the user kept Aris's place).
    static let windowSize = CGSize(width: 540, height: 700)
    static let bottomEdgeOffset: CGFloat = 5
    static let bottomPadding: CGFloat = 6
    /// A Dock set to hide still leaves this much at the screen's edge in the visible frame.
    static let hiddenDockReserve: CGFloat = 4
    /// Nothing to show for this long: the window goes off screen (parked) until there is.
    static let parkAfter: Duration = .seconds(12)
    /// The inline error's line stays this long (Aris's failure linger; the reference's red pill stays 500 ms).
    static let errorLinger: Duration = .seconds(4)

    /// A size change's length. CSS: a change that turns back to where the running one started takes only as long as
    /// the share already covered (the reversing shortening factor); any other starts afresh at 0.1 s.
    struct Reversal: Equatable {
        /// The running change's start and end, when it began, and its own factor.
        var from: ArisDictationPillPhase = .hidden
        var to: ArisDictationPillPhase = .hidden
        var began: Double = -.infinity
        var factor: Double = 1

        var duration: Double { sizeDuration * factor }

        /// A change from `to` to `next` at `now`.
        func changing(to next: ArisDictationPillPhase, at now: Double) -> Reversal {
            let elapsed = now - began
            let running = elapsed >= 0 && elapsed < duration
            guard running, next == from, size(next) != size(to) else {
                return Reversal(from: to, to: next, began: now, factor: 1)
            }
            let share = ArisDictationPillRules.sizeCurve.value(at: elapsed / duration)
            let shortened = min(1, max(0, share * factor + (1 - factor)))
            return Reversal(from: to, to: next, began: now, factor: shortened)
        }
    }

    // MARK: - The pointer (measured from the reference pill)

    /// What counts as on the pill: the pill and 10 / 6 around it (states.css:631, the hot area's padding); grown into
    /// the hover, 12 more each way (states.css:76), so a pointer at its edge doesn't flicker it back.
    static let hotPadding = CGSize(width: 10, height: 6)
    static let hoverHold: CGFloat = 12

    static func pointerZone(_ phase: ArisDictationPillPhase, size: CGSize) -> CGSize {
        let extra = phase == .hover ? hoverHold : 0
        return CGSize(width: size.width + 2 * (hotPadding.width + extra), height: size.height + 2 * (hotPadding.height + extra))
    }

    /// The zone's rect in the window: around the pill's.
    static func pointerRect(_ phase: ArisDictationPillPhase, size: CGSize) -> CGRect {
        let pill = pillRect(size)
        let zone = pointerZone(phase, size: size)
        return pill.insetBy(dx: -(zone.width - size.width) / 2, dy: -(zone.height - size.height) / 2)
    }

    /// The hover follows the pointer at once, then holds 100 ms (status.js:8659, 13103): a change in that time waits
    /// for 100 ms of quiet and then follows the pointer, so an edge that flickers never jolts the pill.
    struct HoverLock: Equatable {
        static let hold = 0.1

        private(set) var shown = false
        private(set) var pointer = false
        private(set) var lockedUntil: Double?
        /// The pointer moved during the hold: the hold restarted, and its end only follows it (no new hold).
        private var restarted = false

        /// The pointer is on (or off) at `now`; returns when `expire` is due, if it is.
        mutating func point(_ on: Bool, at now: Double) -> Double? {
            let moved = on != pointer
            pointer = on
            if let until = lockedUntil, now < until {
                guard moved else { return until }
                restarted = true
                lockedUntil = now + Self.hold
                return lockedUntil
            }
            lockedUntil = nil
            restarted = false
            guard shown != on else { return nil }
            shown = on
            lockedUntil = now + Self.hold
            return lockedUntil
        }

        /// The hold's end at `now`: it follows the pointer; a hold of its own holds again after a change.
        mutating func expire(at now: Double) -> Double? {
            guard let until = lockedUntil else { return nil }
            guard now >= until - 1e-9 else { return until }
            lockedUntil = nil
            let again = !restarted
            restarted = false
            guard shown != pointer else { return nil }
            shown = pointer
            guard again else { return nil }
            lockedUntil = now + Self.hold
            return lockedUntil
        }

        /// Nothing to hover (the pill went away).
        mutating func clear() { self = HoverLock() }
    }

    // MARK: - What it shows

    /// One dictation's stage, as the controller has it.
    enum Stage: Equatable {
        case none
        /// The key is down (or hands-free): the microphone is open.
        case listening
        /// Let go: Whisper writes the words down.
        case writing
        /// The words are cleaned, polished and typed.
        case cleaning
        /// Typed (or copied).
        case typed
    }

    struct Inputs: Equatable {
        /// Settings › 받아쓰기 › 받아쓰기 알약 보이기, on a Mac that dictates.
        var enabled = true
        /// Settings › 받아쓰기 › 쉴 때도 보이기: the idle sliver and its hover show between dictations (off: hidden, so
        /// nothing to click; a dictation, its copied words and its error still show).
        var showIdle = true
        var screenLocked = false
        /// The app in front is full screen: the idle sliver stays away (a dictation still shows).
        var fullScreen = false
        var stage: Stage = .none
        var handsFree = false
        var hovered = false
        /// The copied words while they show.
        var recovered: String?
        var error: String?
        /// Typed and still to be shown as such (offscreen renders; the reference pill goes straight back to the sliver,
        /// so the live pill never sets it).
        var typedHold = false
    }

    static func phase(_ i: Inputs) -> ArisDictationPillPhase {
        guard i.enabled, !i.screenLocked else { return .hidden }
        if let text = i.recovered, !text.isEmpty { return .recovered(text) }
        if let line = i.error, !line.isEmpty { return .error(line) }
        switch i.stage {
        case .listening: return .recording(handsFree: i.handsFree)
        case .writing: return .transcribing(.charging)
        case .cleaning: return .transcribing(.releasing)
        case .typed where i.typedHold: return .transcribing(.done)
        case .typed, .none: break
        }
        if i.fullScreen || !i.showIdle { return .hidden }
        return i.hovered ? .hover : .idle
    }

    // MARK: - Sizes

    /// The pill's size, or the recovered words' card's (ArisDictationPillRecoveredLayout: it hugs its words; the
    /// label is longer in English and after a copy).
    static func size(_ phase: ArisDictationPillPhase, english: Bool = false, again: Bool = false) -> CGSize {
        switch phase {
        case .hidden, .idle: idleSize
        case .hover: hoverSize
        case .recording(let handsFree): handsFree ? handsFreeSize : holdSize
        case .transcribing: transcribingSize
        case .error(let line): CGSize(width: errorWidth(line), height: errorHeight)
        case .recovered(let text): ArisDictationPillRecoveredLayout.size(text, english: english, again: again)
        }
    }

    /// The line's width at 14 semibold: 4 a space, 14 a CJK character (U+2E80 and up), 7.4 anything else.
    static func errorTextWidth(_ text: String) -> CGFloat {
        text.unicodeScalars.reduce(0) { sum, scalar in
            if scalar == " " { return sum + 4 }
            return sum + (scalar.value >= 0x2E80 ? 14 : 7.4)
        }
    }

    static func errorWidth(_ text: String) -> CGFloat {
        (min(errorMaxWidth, max(errorMinWidth, errorTextWidth(text) + errorPadding))).rounded(.up)
    }

    // MARK: - Where it sits (AppKit coordinates)

    /// The bottom the pill stands on: the Dock's top when it shows at the bottom (the visible frame's bottom), else the
    /// screen's own bottom (a hidden Dock, a Dock at the side).
    static func usableBottom(frame: CGRect, visible: CGRect) -> CGFloat {
        visible.minY - frame.minY > hiddenDockReserve ? visible.minY : frame.minY
    }

    /// The window: centred on the visible frame (the reference centres on the work area), its bottom on the usable
    /// bottom.
    static func windowFrame(frame: CGRect, visible: CGRect) -> CGRect {
        let x = (visible.midX - windowSize.width / 2).rounded()
        let y = (usableBottom(frame: frame, visible: visible) - bottomEdgeOffset).rounded()
        return CGRect(origin: CGPoint(x: x, y: y), size: windowSize)
    }

    /// The pill's bottom on screen: 1 above the usable bottom (6 padding, 5 under).
    static func pillBottom(frame: CGRect, visible: CGRect) -> CGFloat {
        windowFrame(frame: frame, visible: visible).minY + bottomPadding
    }

    /// The pill's rect in its window (origin bottom-left): centred, 6 up.
    static func pillRect(_ size: CGSize, in window: CGSize = windowSize) -> CGRect {
        CGRect(x: (window.width - size.width) / 2, y: bottomPadding, width: size.width, height: size.height)
    }

    /// The front window covers its whole screen (a full-screen app, or a full-screen video).
    static func isFullScreen(window: CGRect?, screen: CGRect) -> Bool {
        guard let window else { return false }
        return window.width >= screen.width - 1 && window.height >= screen.height - 1
    }

    /// The screen a window is on: the one with its centre, else the one it overlaps most; nil with none.
    static func screenIndex(for window: CGRect, screens: [CGRect]) -> Int? {
        let centre = CGPoint(x: window.midX, y: window.midY)
        if let index = screens.firstIndex(where: { $0.contains(centre) }) { return index }
        let overlaps = screens.enumerated().map { ($0.offset, $0.element.intersection(window)) }
            .filter { !$0.1.isNull && $0.1.width * $0.1.height > 0 }
        return overlaps.max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?.0
    }

    /// A CG window rect (top-left origin, from the primary display's top) in AppKit's coordinates.
    static func appKitRect(cg rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - The notch

    /// The top notch stays quiet for a dictation the pill shows (option A): while it runs, and once it ended until the
    /// next turn starts. Talking to Aris (any other turn) keeps the notch as it was.
    static func notchQuiet(pillOn: Bool, dictating: Bool, endedDictation: Bool, idle: Bool) -> Bool {
        pillOn && (dictating || (endedDictation && idle))
    }
}

