//
//  ArisNotchDecisions.swift
//  Aris
//
//  The root notch view's decisions as plain functions: what the closed notch shows, how wide the hover strip under
//  it is, when an Aris turn needs (and holds) the open notch, how the hover and gesture rules come out, and which half
//  of the home page a drop lands on.
//

import CoreGraphics
import Foundation

enum ArisNotchDecisions {
    /// A drop on the notch is taken on the open home page's zones, and while the notch is still opening (its zones are
    /// arming): a quick drop is never lost (QA VM). Elsewhere (an open page with no zones) it is refused.
    static func acceptsDrop(isOpen: Bool, onHome: Bool) -> Bool { onHome || !isOpen }

    /// What the closed notch shows, first match wins.
    enum Closed: Equatable {
        case notice, star(ArisStarBand.Mode), dueAlert, timer, claude, music, empty
    }

    struct ClosedInputs {
        var notice = false
        var starMode: ArisStarBand.Mode?
        var dueAlert = false
        var timer = false
        var claude = false
        var music = false
    }

    static func closedContent(_ i: ClosedInputs) -> Closed {
        if i.notice { return .notice }
        if let mode = i.starMode { return .star(mode) }
        if i.dueAlert { return .dueAlert }
        if i.timer { return .timer }
        if i.claude { return .claude }
        if i.music { return .music }
        return .empty
    }

    /// Music shows in the closed notch: the live activity is on and something plays (or hasn't gone idle), unless
    /// another inline expansion is up — or the inline music peek is expanding.
    static func musicShowing(liveActivity: Bool, playing: Bool, idle: Bool, expansionShown: Bool, expansionIsMusic: Bool) -> Bool {
        (liveActivity && (playing || !idle) && (!expansionShown || expansionIsMusic)) || (expansionShown && expansionIsMusic)
    }

    /// Claude's ear: a live session, or sessions while no music holds the band.
    static func claudeShowing(live: Bool, sessions: Bool, liveActivity: Bool, playing: Bool, idle: Bool) -> Bool {
        live || (sessions && !(liveActivity && (playing || !idle)))
    }

    /// The width of the almost-transparent hover strip under a closed notch.
    static func chinWidth(closedWidth: CGFloat, notice: Bool, wide: Bool, ear: CGFloat, inlineMusic: Bool) -> CGFloat {
        if notice { return 330 }
        guard wide else { return closedWidth }
        return closedWidth + 2 * ear + (inlineMusic ? 2 * 110 : 0)
    }

    /// An Aris turn opens the notch: training the wake word, a turn past listening that isn't dictation, or dictation
    /// that had nowhere to type and was copied (ArisDictationCopy).
    static func turnNeedsPanel(training: Bool, dictating: Bool, phase: ArisSession.Phase, dictationCopied: Bool = false) -> Bool {
        training || (dictating && dictationCopied) || (!dictating && phase != .listening && phase != .idle)
    }

    /// A card waiting for the user opens this display's notch, wherever the pointer is (QA retest on 8e236bff: with the
    /// pointer on the desktop the card showed only on hover): on the display the turn happened on, else the main one.
    static func cardOpens(waiting: Bool, closed: Bool, hidden: Bool, here: String?, turnDisplay: String?, mainDisplay: String?) -> Bool {
        guard waiting, closed, !hidden, let here else { return false }
        return here == (turnDisplay ?? mainDisplay)
    }

    /// The longest the turn's end waits for a card: its own limit, then a margin (a card that never clears can't hold the
    /// notch open for good).
    static let cardHoldCap: TimeInterval = ArisCardEdit.questionTimeout + 15

    /// The turn's end doesn't put the notch away while a card still waits: it waits for the answer or the card's time,
    /// never longer than `cardHoldCap`.
    static func endWaitsForCard(cardWaiting: Bool, waited: TimeInterval) -> Bool { cardWaiting && waited < cardHoldCap }

    /// Whether a hover-exit (or "close unless hovering", or a drop leaving) may close the notch now. `dropHold`: files
    /// were just given to Aris (the composer waits for what to do with them).
    static func automaticCloseAllowed(open: Bool, hovering: Bool, popover: Bool, sharing: Bool, approvalsPending: Bool, turnHolds: Bool,
                                      dropHold: Bool = false) -> Bool {
        open && !hovering && !popover && !sharing && !approvalsPending && !turnHolds && !dropHold
    }

    /// A press in the open notch has just opened Aris's Settings: the notch gets out of the window's way, unless
    /// something in it still waits for the user (a card to answer, a Claude approval).
    static func stepsAsideForSettings(open: Bool, cardWaiting: Bool, approvalsPending: Bool) -> Bool {
        open && !cardWaiting && !approvalsPending
    }

    /// The hold after a drop on Aris's half, as the pointer moves: it ends once the pointer, having come onto the notch,
    /// leaves it (a hover-exit right after the drop, with no hover since, doesn't count).
    static func dropHold(_ held: Bool, hoverInside: Bool, wasHovering: Bool) -> Bool {
        held && (hoverInside || !wasHovering)
    }

    /// The page a drag over the open notch switches to, so the drop zones show: home, from any page that has none of its
    /// own (the shelf page is a drop target itself); nil to stay.
    static func dropPage(_ current: NotchViews) -> NotchViews? {
        switch current {
        case .claude: return .home
        case .home, .aris, .shelf: return nil
        }
    }

    /// How far below the top of the screen a content drag finds the closed notch (its pointer hover is unchanged).
    static let dragHoverDepth: CGFloat = 56

    /// Hover opens a closed notch after the minimum hover time, when nothing is shown over it.
    static func hoverOpens(closed: Bool, notice: Bool, peek: Bool, openOnHover: Bool) -> Bool {
        closed && !notice && !peek && openOnHover
    }

    /// A gesture's progress (the notch scales and fades with it).
    static func progress(translation: CGFloat, sensitivity: CGFloat) -> CGFloat {
        guard sensitivity > 0 else { return 0 }
        return translation / sensitivity * 20
    }

    /// The notch's scale while a gesture is in progress (anchored at the top).
    static func gestureScale(progress: CGFloat) -> CGFloat {
        max(0.6, 1 + progress * 0.01)
    }

    /// Header and page opacity while a gesture is in progress.
    static func gestureOpacity(progress: CGFloat) -> Double {
        1 - min(Double(abs(progress)) * 0.1, 0.3)
    }

    /// The home page's drop halves: left of the middle is the shelf, right is Aris.
    static func homeDropSide(x: CGFloat, contentWidth: CGFloat) -> ArisDropZones.Side {
        x < contentWidth / 2 ? .shelf : .aris
    }

    /// The closed radii: scaled with the drawn height when corner scaling is on.
    static func closedRadii(base: (top: CGFloat, bottom: CGFloat), displayedHeight: CGFloat, scaling: Bool) -> (top: CGFloat, bottom: CGFloat) {
        guard displayedHeight > 0 else { return (0, 0) }
        guard scaling else { return base }
        let factor = max(0, displayedHeight / 38)
        return (base.top * factor, base.bottom * factor)
    }
}
