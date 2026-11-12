// Acceptance tests for the clean-room root notch view's decisions (cleanroom-specs/05-notch-composition.md, N1).
import CoreGraphics

func runCompositionTests() {
    typealias D = ArisNotchDecisions
    // 1. Closed content, first match wins.
    check(D.closedContent(.init(notice: true, starMode: .turn, dueAlert: true, timer: true, claude: true, music: true)) == .notice, "closed: the notice wins")
    check(D.closedContent(.init(starMode: .tasks, dueAlert: true, claude: true, music: true)) == .star(.tasks), "closed: then the star band")
    check(D.closedContent(.init(dueAlert: true, timer: true, claude: true, music: true)) == .dueAlert
          && D.closedContent(.init(timer: true, claude: true, music: true)) == .timer
          && D.closedContent(.init(claude: true, music: true)) == .claude && D.closedContent(.init(music: true)) == .music
          && D.closedContent(.init()) == .empty, "closed: due alert, timer, Claude, music, nothing")
    check(D.musicShowing(liveActivity: true, playing: false, idle: false, expansionShown: false, expansionIsMusic: false)
          && !D.musicShowing(liveActivity: true, playing: false, idle: true, expansionShown: false, expansionIsMusic: false)
          && !D.musicShowing(liveActivity: false, playing: true, idle: false, expansionShown: false, expansionIsMusic: false)
          && D.musicShowing(liveActivity: false, playing: false, idle: true, expansionShown: true, expansionIsMusic: true),
          "music: playing or not yet idle with the live activity on, or the inline music peek")
    check(D.claudeShowing(live: true, sessions: false, liveActivity: true, playing: true, idle: false)
          && D.claudeShowing(live: false, sessions: true, liveActivity: true, playing: false, idle: true)
          && !D.claudeShowing(live: false, sessions: true, liveActivity: true, playing: true, idle: false), "Claude: live, or sessions while no music holds the band")
    check(D.chinWidth(closedWidth: 185, notice: true, wide: true, ear: 40, inlineMusic: true) == 330
          && D.chinWidth(closedWidth: 185, notice: false, wide: false, ear: 40, inlineMusic: false) == 185
          && D.chinWidth(closedWidth: 185, notice: false, wide: true, ear: 40, inlineMusic: false) == 265
          && D.chinWidth(closedWidth: 185, notice: false, wide: true, ear: 40, inlineMusic: true) == 485, "chin: notice, plain, with ears, with the inline peek")
    // 2. Aris needs the panel.
    check(D.turnNeedsPanel(training: true, dictating: true, phase: .idle), "panel: wake-word training")
    check(!D.turnNeedsPanel(training: false, dictating: false, phase: .listening) && !D.turnNeedsPanel(training: false, dictating: false, phase: .idle),
          "panel: not while listening or idle")
    check(D.turnNeedsPanel(training: false, dictating: false, phase: .thinking) && D.turnNeedsPanel(training: false, dictating: false, phase: .speaking)
          && !D.turnNeedsPanel(training: false, dictating: true, phase: .thinking), "panel: thinking and speaking, not dictation")
    // 3. Automatic close (N1).
    let allowed = { (hover: Bool, popover: Bool, sharing: Bool, approvals: Bool, holds: Bool) in
        D.automaticCloseAllowed(open: true, hovering: hover, popover: popover, sharing: sharing, approvalsPending: approvals, turnHolds: holds)
    }
    check(allowed(false, false, false, false, false), "hover exit: closes when nothing holds the notch")
    check(!allowed(true, false, false, false, false) && !allowed(false, true, false, false, false) && !allowed(false, false, true, false, false)
          && !allowed(false, false, false, true, false), "hover exit: not while hovering, a popover, a share or approvals")
    for phase in [ArisSession.Phase.listening, .thinking, .speaking, .failed] {
        check(!allowed(false, false, false, false, ArisNotchSnapshot.holds(phase: phase, questionPending: false)), "N1: a turn in \(phase) holds the notch")
    }
    check(!allowed(false, false, false, false, ArisNotchSnapshot.holds(phase: .idle, questionPending: true)), "N1: a pending confirmation holds the notch")
    check(allowed(false, false, false, false, ArisNotchSnapshot.holds(phase: .idle, questionPending: false)), "N1: once idle, hover exit closes again")
    check(!D.automaticCloseAllowed(open: false, hovering: false, popover: false, sharing: false, approvalsPending: false, turnHolds: false),
          "hover exit: a closed notch has nothing to close")
    check(D.hoverOpens(closed: true, notice: false, peek: false, openOnHover: true) && !D.hoverOpens(closed: true, notice: true, peek: false, openOnHover: true)
          && !D.hoverOpens(closed: true, notice: false, peek: true, openOnHover: true) && !D.hoverOpens(closed: true, notice: false, peek: false, openOnHover: false),
          "hover: opens unless a notice or peek shows, or hover opening is off")
    // 4. Gestures.
    for sensitivity in [CGFloat(100), 200, 300] {
        check(D.progress(translation: sensitivity, sensitivity: sensitivity) == 20 && D.progress(translation: sensitivity / 2, sensitivity: sensitivity) == 10,
              "gesture: progress at sensitivity \(Int(sensitivity))")
    }
    check(D.gestureScale(progress: 10) == 1.1 && D.gestureScale(progress: -60) == 0.6, "gesture: scale with a 0.6 floor")
    check(D.gestureOpacity(progress: 1) == 0.9 && D.gestureOpacity(progress: 20) == 0.7, "gesture: fade capped at 0.3")
    // 5. Home drop halves.
    check(D.homeDropSide(x: 100, contentWidth: 416) == .shelf && D.homeDropSide(x: 208, contentWidth: 416) == .aris, "drop: left half shelf, right half Aris")
    // Corner scaling (04).
    check(D.closedRadii(base: (13, 13), displayedHeight: 38, scaling: true) == (13, 13) && D.closedRadii(base: (13, 13), displayedHeight: 19, scaling: true) == (6.5, 6.5)
          && D.closedRadii(base: (13, 13), displayedHeight: 19, scaling: false) == (13, 13), "radii: scaled with the drawn height when scaling is on")
}
