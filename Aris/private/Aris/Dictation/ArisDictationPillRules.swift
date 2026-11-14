//
//  ArisDictationPillRules.swift
//  Aris
//
//  The dictation pill's decisions as plain values (ArisDictationPillCenter applies them): what it shows for a dictation
//  stage (the measured size cascade, first match wins), each state's size, the inline error's width, where its window
//  sits on a screen (bottom centre, above a Dock that is showing), when a window counts as full screen, and when the top
//  notch stays quiet because the pill has the dictation. Pure, so it's tested.
//
//  Measured: radius 24 in every state; show/hide opacity + scale 0.8 → 1 from the centre,
//  0.15 s ease; size changes 0.15 s ease; idle 36 × 8, hover 50 × 30, hold recording 80 × 30, pill-click or hands-free
//  recording 102 × 30, transcribing / awaiting insertion 30 × 30, inline error ceil(clamp(136, textW + 44, 280)) × 38,
//  recovered transcript 282 / 326 / 364 × 92 / 110 / 130; window at most 540 × 700, its bottom 5 under the screen's
//  usable bottom and the pill 6 above the window's bottom; parked after 12 s with nothing to show.
//

import CoreGraphics
import Foundation

/// What the pill shows.
enum ArisDictationPillPhase: Equatable {
    /// Off, locked, or nothing to show in a full-screen app (or anywhere, with 쉴 때도 보이기 off).
    case hidden
    /// The 36 × 8 sliver: dictation is ready.
    case idle
    /// The pointer is on the sliver: the mic, and a click starts a dictation.
    case hover
    /// Listening: held (80 × 30, the app's icon and the level) or hands-free (102 × 30, ✕, the level, the lock / ↑).
    case recording(handsFree: Bool)
    /// The words are being written down and typed: the ring.
    case transcribing(ArisDictationPillRing.Stage)
    /// Nowhere took the words: they are on the clipboard and shown here to copy again.
    case recovered(String)
    /// A line of what went wrong, in place.
    case error(String)

    var shown: Bool { self != .hidden }
}

enum ArisDictationPillRules {
    // MARK: - Measured tokens

    static let radius: CGFloat = 24

    /// The radius drawn at `size`: 24, or half the short side when that is less (CSS clamps it so; a 30-tall pill is a
    /// capsule).
    static func cornerRadius(_ size: CGSize) -> CGFloat { min(radius, min(size.width, size.height) / 2) }
    /// Show/hide: opacity and scale from 0.8, from the centre, 0.15 s ease.
    static let showDuration = 0.15
    static let hiddenScale: CGFloat = 0.8
    /// Size, height, background, border and radius: 0.15 s ease (the default phase).
    static let sizeDuration = 0.15
    /// CSS `ease`.
    static let ease = (0.25, 0.1, 0.25, 1.0)
    /// The window: at most 540 × 700; its bottom 5 under the usable bottom, the pill 6 above the window's bottom.
    static let windowSize = CGSize(width: 540, height: 700)
    static let bottomEdgeOffset: CGFloat = 5
    static let bottomPadding: CGFloat = 6
    /// A Dock set to hide still leaves this much at the screen's edge in the visible frame.
    static let hiddenDockReserve: CGFloat = 4
    /// Nothing to show for this long: the window goes off screen (parked) until there is.
    static let parkAfter: Duration = .seconds(12)
    /// The inline error's line stays this long (Aris's failure linger).
    static let errorLinger: Duration = .seconds(4)

    static let idleSize = CGSize(width: 36, height: 8)
    static let hoverSize = CGSize(width: 50, height: 30)
    static let holdSize = CGSize(width: 80, height: 30)
    static let handsFreeSize = CGSize(width: 102, height: 30)
    static let transcribingSize = CGSize(width: 30, height: 30)
    static let errorHeight: CGFloat = 38
    static let errorMinWidth: CGFloat = 136
    static let errorMaxWidth: CGFloat = 280
    static let errorPadding: CGFloat = 44

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
        /// The ring's last 100 ms at full after the words went in.
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

    static func size(_ phase: ArisDictationPillPhase) -> CGSize {
        switch phase {
        case .hidden, .idle: idleSize
        case .hover: hoverSize
        case .recording(let handsFree): handsFree ? handsFreeSize : holdSize
        case .transcribing: transcribingSize
        case .error(let line): CGSize(width: errorWidth(line), height: errorHeight)
        case .recovered(let text): recoveredSize(text)
        }
    }

    /// The text's width as measured: 4 a space, 14 a CJK character (U+2E80 and up), 7.4 anything else.
    static func errorTextWidth(_ text: String) -> CGFloat {
        text.unicodeScalars.reduce(0) { sum, scalar in
            if scalar == " " { return sum + 4 }
            return sum + (scalar.value >= 0x2E80 ? 14 : 7.4)
        }
    }

    static func errorWidth(_ text: String) -> CGFloat {
        (min(errorMaxWidth, max(errorMinWidth, errorTextWidth(text) + errorPadding))).rounded(.up)
    }

    /// Shorter than 42 / 90 characters (UTF-16, as measured) or longer.
    static func recoveredSize(_ text: String) -> CGSize {
        let length = text.utf16.count
        if length < 42 { return CGSize(width: 282, height: 92) }
        if length < 90 { return CGSize(width: 326, height: 110) }
        return CGSize(width: 364, height: 130)
    }

    /// Solid 1 px white .18 with an error; the gradient ring otherwise.
    static func gradientBorder(_ phase: ArisDictationPillPhase) -> Bool {
        if case .error = phase { return false }
        return true
    }

    // MARK: - Where it sits (AppKit coordinates)

    /// The bottom the pill stands on: the Dock's top when it shows at the bottom (the visible frame's bottom), else the
    /// screen's own bottom (a hidden Dock, a Dock at the side).
    static func usableBottom(frame: CGRect, visible: CGRect) -> CGFloat {
        visible.minY - frame.minY > hiddenDockReserve ? visible.minY : frame.minY
    }

    /// The window: centred on the visible frame, its bottom 5 under the usable bottom.
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
