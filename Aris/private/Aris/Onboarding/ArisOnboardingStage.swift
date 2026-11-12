//
//  ArisOnboardingStage.swift
//  Aris
//
//  The onboarding's window rules, pure so the tests check them: the beats, the veil's level and click-through per beat,
//  the setup window's level and its size on the display, which display hosts it, Esc and the exits, and when the guide
//  holds the real notch.
//
//  Window levels (CGWindowLevel), measured on this Mac rather than assumed: macOS's permission alert sits at layer 8,
//  centred, its top ~21% down the display; System Settings at 0; Aris's drag panel at 3 (.floating); the menu bar at 24,
//  the Dock at 20; Aris's notch panel at 27. So the veil sits at 26 (over the menu bar and Dock, under the notch) while
//  it leads, and at −1, passing every click, whenever it doesn't (Aris inactive, the handoff, the setup). The setup
//  window rides one level over the veil for the 0.8 s it lifts, then is an ordinary window (0): macOS's alerts and
//  System Settings always come above it, and nothing of the onboarding covers them.
//

import CoreGraphics
import Foundation

/// Where the onboarding is.
enum ArisOnboardingPhase: Equatable {
    /// The veil, the sunrise, the star, the name, 시작하기.
    case intro
    /// 시작하기: the star is thrown into the notch.
    case flight
    /// Aris speaks from the notch and asks the name.
    case talk
    /// The veil lifts while the setup window settles in.
    case handoff
    /// The setup window's pages, narrated by the notch.
    case setup
    /// The window closes and the notch is Aris's own again: it opens with three things to try (ArisFirstTries).
    case finish
    case closed
}

enum ArisOnboardingStage {
    /// The intro (flight, talk) needs a camera notch to land in; without one, the setup window carries the whole guide.
    static func introHost(hasNotch: Bool) -> Bool { hasNotch }

    /// The setup window's origin: centred in the visible frame, its left and top edges kept on screen.
    static func windowOrigin(size: CGSize, in frame: CGRect) -> CGPoint {
        let x = max(frame.minX, frame.midX - size.width / 2)
        let y = min(frame.midY - size.height / 2, frame.maxY - size.height)
        return CGPoint(x: x, y: max(frame.minY, y))
    }

    // MARK: - The setup window's size

    /// The window as designed.
    static let design = CGSize(width: 1080, height: 710)
    /// The smallest size its pages still lay out in; a display with less room than this draws it smaller instead.
    static let minimum = CGSize(width: 900, height: 620)
    /// Kept clear of the display's edges, the menu bar and the Dock.
    static let margin: CGFloat = 16

    /// How the setup window sits on a display.
    struct Fit: Equatable {
        /// The window's size on screen.
        let size: CGSize
        /// The size its content is laid out at (`size` unless it is drawn smaller).
        let layout: CGSize
        /// What the layout is drawn at: 1 unless the display has less room than `minimum`.
        let scale: CGFloat
        let origin: CGPoint
    }

    /// The window inside a display's visible frame (fresh install F6: on a 1024 × 768 display the 1080 × 710 window
    /// ran off the right edge and sat on the Dock). Never larger than designed; on a smaller display it is laid out
    /// narrower and shorter, down to `minimum`, and below that drawn smaller, whole; always centred.
    static func fit(in visible: CGRect) -> Fit {
        let room = CGSize(width: max(1, visible.width - 2 * margin), height: max(1, visible.height - 2 * margin))
        let scale = min(1, room.width / minimum.width, room.height / minimum.height)
        let layout = CGSize(width: min(design.width, (room.width / scale).rounded()), height: min(design.height, (room.height / scale).rounded()))
        let size = CGSize(width: min(room.width, (layout.width * scale).rounded()), height: min(room.height, (layout.height * scale).rounded()))
        return Fit(size: size, layout: layout, scale: scale, origin: windowOrigin(size: size, in: visible))
    }

    /// The window on a display it wasn't measured against yet: as designed.
    static let designFit = Fit(size: design, layout: design, scale: 1, origin: .zero)

    /// The permission page's picture as designed: its column's width in the designed window, 400 high.
    static let stageSize = CGSize(width: 492, height: 400)

    /// What the picture is drawn at in a column `column` wide: smaller in a narrower one, never larger.
    static func stageScale(column: CGFloat) -> CGFloat { min(1, max(0.1, column / stageSize.width)) }

    /// The width of one of the setup pages' two columns in a window laid out `layout` wide (the pages are inset 48).
    static func columnWidth(layout: CGFloat) -> CGFloat { max(0, (layout - 2 * pageInset) / 2) }
    static let pageInset: CGFloat = 48

    // MARK: - Levels

    /// kCGMainMenuWindowLevel.
    static let mainMenuLevel = 24
    /// Over the menu bar (24) and the Dock (20), under the notch panel (27).
    static let overlayLevel = mainMenuLevel + 2
    /// Under every ordinary window.
    static let yieldLevel = -1
    static let normalLevel = 0

    struct Window: Equatable {
        var level: Int
        var clickThrough: Bool
    }

    /// The veil's window: it leads in the intro and the talk while Aris is active; otherwise it is out of the way.
    static func overlay(phase: ArisOnboardingPhase, active: Bool) -> Window {
        switch phase {
        case .intro, .flight, .talk: active ? Window(level: overlayLevel, clickThrough: false) : Window(level: yieldLevel, clickThrough: true)
        default: Window(level: yieldLevel, clickThrough: true)
        }
    }

    /// The setup window: over the lifting veil for the handoff, then an ordinary window.
    static func windowLevel(handingOff: Bool) -> Int { handingOff ? overlayLevel + 1 : normalLevel }

    // MARK: - Coming forward

    /// Whether the setup window opens in front with the keyboard (fresh install F7: launched while another app was in
    /// front, it opened behind that app). Always, except a quiet resume at a later launch, which shows in front without
    /// taking the keyboard; a Quit & Reopen (`reopened`) is the user's own return, so it does.
    static func activates(quiet: Bool, reopened: Bool) -> Bool { !quiet || reopened }

    /// What may bring the setup window forward again.
    enum Forward: Equatable {
        /// macOS's own prompt (the microphone, speech recognition) was answered.
        case promptAnswered
        /// A permission just turned on.
        case granted
        /// System Settings was opened for a permission: it stays in front until the switch is on.
        case settingsOpened
    }

    /// After a system prompt or a grant the setup window is in front again with the keyboard (F7: another app came
    /// forward after the prompts and covered it); only while the setup window shows, so nothing takes the keyboard in
    /// normal use.
    static func comesForward(after event: Forward, phase: ArisOnboardingPhase) -> Bool {
        guard phase == .setup || phase == .handoff else { return false }
        return event != .settingsOpened
    }

    // MARK: - Esc, the exits, the corners

    /// Esc closes everything at any beat, only while the onboarding's own window is key.
    static func escapeCloses(phase: ArisOnboardingPhase, guideKey: Bool) -> Bool { phase != .closed && guideKey }

    /// The dim ✕ on the veil, mouse-reachable from the first frame.
    static func exitShown(phase: ArisOnboardingPhase) -> Bool { [.intro, .flight, .talk].contains(phase) }

    /// 건너뛰기 shows 12 s after the veil mounts, whatever beat it's on, until the window takes over.
    static func skipShown(phase: ArisOnboardingPhase, elapsedMs: Double) -> Bool {
        [.intro, .flight, .talk].contains(phase) && elapsedMs >= ArisOnboardingScore.skip
    }

    /// The mute, bottom-left, once the veil is in.
    static func muteShown(phase: ArisOnboardingPhase, veil: Double) -> Bool { [.intro, .flight, .talk].contains(phase) && veil > 0.5 }

    enum Next: Equatable { case talk, setup }

    /// 시작하기 throws the star into the notch, where it speaks first.
    static let ctaTarget = Next.talk

    /// Skipping goes straight to the app window.
    static func skipTarget(phase: ArisOnboardingPhase) -> Next { .setup }

    // MARK: - The star

    /// Where an onboarding star sits.
    enum StarSpot: Equatable { case intro, notch, stage, preview }

    /// Whether the star there wears the face picked on the 팀원 page (the owner's N1, ArisFace): the notch's docked star and the
    /// setup stage's 88-point one do; the intro's sunrise and the previews' small icons stay the star.
    static func wearsFace(_ spot: StarSpot) -> Bool { spot == .notch || spot == .stage }

    // MARK: - The notch

    /// A notch already open when the guide starts (an approval, an answer) is held as the real notch's until it closes
    /// (N3): its card is answered first, never taken over and dropped.
    static let holdingAtStart = true

    /// 시작 안내로 돌아가기 (the menu, Settings) during the finish beat brings the setup window back (N11); at any other
    /// beat it only brings the guide forward.
    static func surfaceReopensSetup(phase: ArisOnboardingPhase) -> Bool { phase == .finish }

    /// Aris's real notch is in use: a turn (listening, thinking, answering), a dictation, or the answer it leaves open.
    static func realHolds(active: Bool, dictating: Bool, notchOpen: Bool, holding: Bool = false) -> Bool {
        active || dictating || (holding && notchOpen)
    }

    /// The guide draws the notch from the intro to the last page, except while the real notch is in use. At the finish
    /// it lets go: what opens then is the real notch, with three things to try (the owner's pick 5-A).
    static func ownsNotch(phase: ArisOnboardingPhase, realActive: Bool) -> Bool { phase != .closed && phase != .finish && !realActive }

    // MARK: - The finish

    /// The setup window leaves in 240 ms ease-out (the picked mockup's click-through, `.win.ct.gone`), quicker
    /// than it came.
    static let windowOut: Double = 0.24
    /// Reduce Motion: a short fade.
    static let windowOutReduced: Double = 0.12
    /// The notch opens this long after the window is gone (the mockup's 260 ms from the press).
    static let notchAfterWindow: Double = 0.02
    /// The sound bed fades out under the open notch, then the guide is over.
    static let bedFade: Double = 2.5

    // MARK: - Display

    struct Display: Equatable {
        let uuid: String
        let hasNotch: Bool
    }

    /// The display with a notch when a notch window is there; else the notch-less display the primary notch window is
    /// on; nil when no notch window can host it (then the setup window opens alone).
    static func display(_ screens: [Display], windowed: Set<String>, primary: String?) -> String? {
        if let notched = screens.first(where: { $0.hasNotch && windowed.contains($0.uuid) }) { return notched.uuid }
        guard let primary, windowed.contains(primary), screens.contains(where: { $0.uuid == primary }) else { return nil }
        return primary
    }
}
