//
//  ArisOnboardingPreviewScore.swift
//  Aris
//
//  The permissions page's picture as a score (ArisOnboardingPreview draws it; mockups/onboarding2/js/dialogs.js
//  Stage.loop): which picture the stage shows for the cards as they are, and where everything in it is at each
//  millisecond of its loop. The stage is never empty grey (VM run 2026-11-11, new install, "smaller"): the picture
//  comes in once and stays between the loop's rounds, and while macOS's own prompt or System Settings is up for a card
//  the stage keeps that card's picture (the alert still, its button pressed, under the real one; the list still
//  showing the drag to do) instead of nothing. Pure, so the tests walk the loop.
//

import CoreGraphics
import Foundation

/// What the stage shows.
enum ArisStagePicture: Equatable {
    /// The system UI a card brings; `still`: one frame of it, not the loop.
    case preview(ArisPermissionCard, still: Bool)
    /// Every card is decided: Aris's star.
    case star

    /// `active`: the open card; `waiting`: the cards whose 허용 has macOS's prompt or System Settings up.
    /// The open card's picture loops. A card macOS is asking about keeps its picture: the alert as one still frame
    /// (the real alert is over the window), the System Settings list still looping (it shows what to do there).
    /// With nothing open and nothing asked, the star.
    static func of(active: ArisPermissionCard?, waiting: Set<ArisPermissionCard>) -> ArisStagePicture {
        guard let card = active ?? ArisPermissionCard.allCases.first(where: waiting.contains) else { return .star }
        return .preview(card, still: waiting.contains(card) && ArisPreviewKind.of(card) == .alertOnly)
    }
}

enum ArisPreviewKind: Equatable {
    case alertOnly, settingsOnly, alertThenSettings

    static func of(_ card: ArisPermissionCard) -> ArisPreviewKind {
        switch card {
        case .mic: .alertOnly
        // Screen Recording has no alert of macOS's any more (Aris opens the list itself, fresh install F8).
        case .accessibility, .screen: .settingsOnly
        }
    }
}

/// The loop's score in ms (dialogs.js Stage.loop): dialog in 200; cursor travel 760 on (.65, 0, .35, 1) along a slight
/// arc; 140 ms later a 180 ms press; out 150; Settings in 200, 500 later the cursor to Aris's switch, on, held 900;
/// the cursor fades 160; 350 ms before it plays again. The list alone (`settingsOnly`) is what the user does there:
/// the cursor goes to the helper panel's row, grabs it (1400), carries it into the list (1500 to 2300) where Aris then
/// appears, goes on to its switch and presses it (3400), on, held 900.
struct ArisPreviewScore {
    let kind: ArisPreviewKind

    /// The list alone: the row is grabbed, dropped, and its switch pressed and on at these times.
    static let grab = 1400.0, carry = 1500.0, drop = 2300.0, toSwitch = 2500.0, switchPress = 3400.0, switchOn = 3540.0
    /// The still frame Reduce Motion shows of the list: the row half-way from the panel to the list.
    static let dragStill = 1950.0

    var period: Double {
        switch kind {
        case .alertOnly: 2400
        case .settingsOnly: 5100
        case .alertThenSettings: 4990
        }
    }

    /// When Settings comes in (the alert is gone by then).
    var settingsIn: Double { kind == .settingsOnly ? 0 : 1890 }

    /// The picture stays up for as long as its card is open: it comes in once (200 ms) and is never taken away
    /// between the loop's rounds; only the cursor and what it pressed start over (VM run 2026-11-11, new install: the
    /// panel was empty grey for half a second of every round). `entered`: a round after the first.
    func alertOpacity(_ t: Double, entered: Bool = false) -> Double {
        switch kind {
        case .settingsOnly: 0
        case .alertOnly: entered ? 1 : ArisOnboardingMotion.span(t, 0, 200)
        case .alertThenSettings: ArisOnboardingMotion.span(t, 0, 200) * (1 - ArisOnboardingMotion.span(t, 1740, 1890))
        }
    }

    func alertScale(_ t: Double, entered: Bool = false) -> Double {
        if kind == .alertOnly { return entered ? 1 : 0.96 + 0.04 * ArisOnboardingMotion.settle(ArisOnboardingMotion.span(t, 0, 200)) }
        return t < 1740 ? 0.96 + 0.04 * ArisOnboardingMotion.settle(ArisOnboardingMotion.span(t, 0, 200)) : 1 - 0.02 * ArisOnboardingMotion.span(t, 1740, 1890)
    }

    func yesDown(_ t: Double) -> Bool { kind != .settingsOnly && t >= 1600 && t < 1740 }

    private var settingsOut: Double { kind == .settingsOnly ? Self.switchOn + 900 : settingsIn + 2440 }

    func settingsOpacity(_ t: Double, entered: Bool = false) -> Double {
        switch kind {
        case .alertOnly: 0
        // The list alone stays up too; at the round's end Aris's row leaves it and the drag starts over.
        case .settingsOnly: entered ? 1 : ArisOnboardingMotion.span(t, settingsIn, settingsIn + 200)
        case .alertThenSettings:
            ArisOnboardingMotion.span(t, settingsIn, settingsIn + 200) * (1 - ArisOnboardingMotion.span(t, settingsOut, settingsOut + 150))
        }
    }

    func settingsScale(_ t: Double, entered: Bool = false) -> Double {
        if kind == .settingsOnly { return entered ? 1 : 0.96 + 0.04 * ArisOnboardingMotion.settle(ArisOnboardingMotion.span(t, settingsIn, settingsIn + 200)) }
        return t < settingsOut ? 0.96 + 0.04 * ArisOnboardingMotion.settle(ArisOnboardingMotion.span(t, settingsIn, settingsIn + 200))
            : 1 - 0.02 * ArisOnboardingMotion.span(t, settingsOut, settingsOut + 150)
    }

    /// Whichever picture this kind shows, how much of it is there at `t` (the tests ask that it is never nothing
    /// once it has come in).
    func pictureOpacity(_ t: Double, entered: Bool) -> Double { max(alertOpacity(t, entered: entered), settingsOpacity(t, entered: entered)) }

    /// The frame a still picture of the alert shows: its button held down, the cursor on it.
    static let alertStill = 1650.0

    func toggleOn(_ t: Double) -> Bool {
        kind != .alertOnly && t >= (kind == .settingsOnly ? Self.switchOn : settingsIn + 1540) && t < settingsOut + 150
    }

    /// Aris is in the list: from the drop on (the list alone starts without it, as the real one does).
    func added(_ t: Double) -> Bool { kind != .settingsOnly || (t >= Self.drop && t < settingsOut + 150) }

    /// The row is in the cursor's hand, between the panel and the list.
    func carrying(_ t: Double) -> Bool { kind == .settingsOnly && t >= Self.grab && t < Self.drop }

    /// The cursor: where it is between `start`, the alert's button, the panel's row (`chip`), where it is dropped in
    /// the list (`slot`) and Aris's switch, its press scale and opacity.
    func cursor(_ t: Double, start: CGPoint, yes: CGPoint, toggle: CGPoint, chip: CGPoint = .zero, slot: CGPoint = .zero) -> (point: CGPoint, scale: Double, opacity: Double) {
        func travel(_ from: CGPoint, _ to: CGPoint, _ a: Double) -> (CGPoint, Double) {
            let p = ArisOnboardingMotion.move(ArisOnboardingMotion.span(t, a, a + 760))
            let mid = CGPoint(x: (from.x + to.x) / 2 + 26, y: (from.y + to.y) / 2 + 18)
            let point = p < 0.5 ? lerp(from, mid, p * 2) : lerp(mid, to, (p - 0.5) * 2)
            return (point, min(1, p * 2))
        }
        func press(_ a: Double) -> Double { t >= a && t < a + 180 ? 1 - 0.12 * sin(Double.pi * (t - a) / 180) : 1 }
        let fadeAt = kind == .alertOnly ? 1890 : settingsOut + 150
        let fade = 1 - ArisOnboardingMotion.span(t, fadeAt, fadeAt + 160)
        switch kind {
        case .alertOnly:
            let (p, o) = travel(start, yes, 700)
            return (p, press(1600), o * fade)
        case .settingsOnly:
            if t < Self.carry {
                let (p, o) = travel(start, chip, 500)
                return (p, press(Self.grab), o)
            }
            if t < Self.toSwitch {
                // Held down while it carries the row.
                let p = ArisOnboardingMotion.move(ArisOnboardingMotion.span(t, Self.carry, Self.drop))
                return (lerp(chip, slot, p), t < Self.drop ? 0.92 : 1, 1)
            }
            let (p, _) = travel(slot, toggle, Self.toSwitch)
            return (p, press(Self.switchPress), fade)
        case .alertThenSettings:
            if t < settingsIn + 500 {
                let (p, o) = travel(start, yes, 700)
                return (p, press(1600), o)
            }
            let (p, o) = travel(yes, toggle, settingsIn + 500)
            return (p, press(settingsIn + 1400), o * fade)
        }
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p) }
}
