//
//  ArisCharacter.swift
//  Aris
//
//  The characters' rules, pure (no BotAvatarsKit here, so the tests build it): what mood Aris's star is in (upstream's
//  three states), the 1.5-point lift while listening, and which character a teammate's rows show. ArisCharacterView
//  draws them with upstream's own motion.
//

import Foundation

/// What the star is doing, as a BotAvatarState raw value ("default", "working", "sleeping").
enum ArisCharacterMood {
    /// Idle this long and it dozes off.
    static let sleepAfter: TimeInterval = 600
    /// The night hours (0–5) it sleeps through when nothing runs.
    static let nightHours = 0...5

    /// A running job (or Aris thinking) is work; listening and speaking keep it awake; otherwise it sleeps after 10
    /// minutes idle or at night, unless a job still waits for the user.
    static func state(phase: ArisMainPhase, jobs: [ArisJob], idleFor: TimeInterval, hour: Int) -> String {
        if jobs.contains(where: isRunning) { return "working" }
        switch phase {
        case .thinking, .searching: return "working"
        case .listening, .speaking: return "default"
        case .idle: break
        }
        if jobs.contains(where: isWaiting) { return "default" }
        return idleFor >= sleepAfter || nightHours.contains(hour) ? "sleeping" : "default"
    }

    /// The voice session's phase as the main turn's (a failed turn is over: idle).
    static func mainPhase(_ phase: ArisSession.Phase) -> ArisMainPhase {
        switch phase {
        case .idle, .failed: .idle
        case .listening: .listening
        case .thinking: .thinking
        case .speaking: .speaking
        }
    }

    private static func isRunning(_ job: ArisJob) -> Bool {
        switch job.state {
        case .queued, .running: true
        case .awaitingApproval, .done, .failed, .cancelled: false
        }
    }

    private static func isWaiting(_ job: ArisJob) -> Bool {
        if case .awaitingApproval = job.state { return true }
        return false
    }
}

/// Aris's own touch on top of the character: the lift while listening (a view offset, not the character's motion).
enum ArisCharacterMotion {
    /// Listening: up 1.5 points and held (the open notch's rim sweep is the listening signal, not the star).
    static func lift(phase: ArisMainPhase) -> Double {
        phase == .listening ? 1.5 : 0
    }
}

/// What the star does is upstream's Bot Avatars, as libraries.dev/bots shows it (ArisSpritePlay):
/// - idle (a job waiting for the user too: upstream has no waiting state): upstream's idle — the head looks to a corner and
///   swings across, blinks, darts, a flip now and then — and the face toward the pointer when it comes near;
/// - working: upstream's working state — the hops, every third one spinning, the laughs;
/// - a job done: upstream's poke, once (what a click does to an interactive avatar on the site);
/// - asleep after a long idle: upstream's sleeping state.
/// Every motion is the kit's Sim baked into sprites played on the render server (ArisSprite): drawn live, one fabric
/// star cost ~3.5 ms of main thread a frame. 모션 줄이기 (or the system's Reduce Motion) holds the state's rest pose.
enum ArisCharacterPlan {
    /// How many jobs finished done between two looks at the list (a job first seen already done doesn't count).
    static func newlyDone(before: [ArisJob], after: [ArisJob]) -> Int {
        let was = Dictionary(before.map { ($0.id, $0.state) }, uniquingKeysWith: { $1 })
        return after.filter { job in
            guard case .done = job.state, let old = was[job.id] else { return false }
            if case .done = old { return false }
            return true
        }.count
    }
}

extension ArisCharacterLook {
    /// Who a row's name shows: Aris its own face (`aris`); anyone else a character fixed by their name, the same every
    /// launch, from the pool that leaves out Aris's type (so a name keeps its face unless Aris took it: then the star).
    static func forName(_ name: String, aris: ArisCharacterLook = .main) -> ArisCharacterLook {
        guard name != ArisActivityTab.mainName else { return aris }
        let type = ArisFace.pool(aris: aris.type)[ArisActivityTab.paletteIndex(name, count: teammateTypes.count)]
        return ArisCharacterLook(type: type, colorHex: nil, shading: Self.star.shading)
    }

    /// The face a teammate shows anywhere (the notch, a window, the 한 일 tab): the look the owner picked, found by id, else
    /// by name (the 한 일 tab knows only names); Aris its own face; Claude Code the ghost until the list is in; anyone
    /// else the character fixed by their name. Never Aris's type (ArisFace.shown): a look stored before Aris took it
    /// shows its replacement.
    static func of(teammateId: String?, name: String, in team: [ArisTeammate], aris: ArisCharacterLook = .main) -> ArisCharacterLook {
        guard name != ArisActivityTab.mainName || teammateId != nil else { return aris }
        let stored: ArisCharacterLook
        if let teammateId, let mate = team.first(where: { $0.id == teammateId }) {
            stored = mate.look
        } else if let mate = team.first(where: { $0.name == name }) {
            stored = mate.look
        } else if teammateId == ArisTeammate.claudeCodeId {
            stored = ArisTeammate.claudeCodeLook
        } else {
            return forName(name, aris: aris)
        }
        return ArisFace.shown(stored, name: name, aris: aris)
    }
}

/// The closed band Aris's star lives in: one band, one star, whatever holds it (fix round 1). The main turn, the
/// background jobs, a parked answer and the star at rest all draw the same band, so the star is never drawn twice and
/// never fades in again when one gives way to another.
enum ArisStarBand {
    enum Mode: Equatable { case turn, tasks, parked, home }

    /// What holds the band, in ContentView's order: the turn first; a due alert or a timer before the jobs; Claude or
    /// music before a parked answer and the resting star. Nil: something else draws the closed notch.
    static func mode(turn: Bool, dueAlert: Bool, timer: Bool, tasks: Bool, claude: Bool, music: Bool, parked: Bool, home: Bool) -> Mode? {
        if turn { return .turn }
        if dueAlert || timer { return nil }
        if tasks { return .tasks }
        if claude || music { return nil }
        if parked { return .parked }
        return home ? .home : nil
    }

    /// The star at rest: a closed notch on a display with a camera (not the flat stand-in), nothing else showing, and
    /// never in full screen, whatever the hide option says. `filesWaiting`: files given for the next request show their
    /// paperclip and count on any display, the flat stand-in's too (the third VM run, A6: a display without a camera
    /// housing showed only the sliver).
    static func showsHome(closed: Bool, hidden: Bool, fullscreen: Bool, hasNotch: Bool, flat: Bool, busy: Bool, filesWaiting: Bool = false) -> Bool {
        closed && !hidden && !fullscreen && ((hasNotch && !flat) || filesWaiting) && !busy
    }

    /// At rest the band's black ears are only the star's room: hovering or tapping them doesn't open the notch, the
    /// camera's width does. Nil: the whole band.
    static func hitWidth(mode: Mode?, notchWidth: CGFloat) -> CGFloat? {
        mode == .home ? notchWidth : nil
    }

    /// The dozing star's hover target (audit ① B): its ear, at rest only; the camera's width keeps opening the notch.
    static func agentHotWidth(mode: Mode?, dozing: Bool, ear: CGFloat) -> CGFloat {
        mode == .home && dozing ? ear : 0
    }

    /// The jobs' count in the right ear, plain text from two on (no ring: the hopping star says it's working).
    static func taskCount(running: Int) -> String? {
        running > 1 ? "\(running)" : nil
    }
}

/// Where Aris's one star sits (the user's A6, mockups/7-character.html): beside the camera in the band, or down in the
/// pill's face slot, working there, while the pill shows and the job is Aris's own (the user's B, mockups/pill-oneline.html).
enum ArisStarSeat: Equatable {
    case band, pill

    /// The pill takes the star whenever it shows with the star as its face (the jobs run, wait, or have just finished),
    /// except during the main turn: then the star listens and answers beside the camera. A pill whose face slot a
    /// teammate holds (`pillTaken`) means no star at all: the teammate stands in its place, never both. Otherwise the
    /// band, if one is drawn. Nil: no star.
    static func seat(mode: ArisStarBand.Mode?, band: Bool, pill: Bool, pillTaken: Bool = false) -> ArisStarSeat? {
        if mode == .turn { return band ? .band : nil }
        if pill { return .pill }
        if pillTaken { return nil }
        return band ? .band : nil
    }
}

/// The star's hop between the band and the pill (A6). The notch is at the very top of the screen, so it never rises
/// above the band: down is a drop from rest (톡, a parabola with its vertex at the band's seat), up the same parabola
/// backwards, rising to arrive at rest. x moves evenly.
enum ArisStarHop {
    static let duration = 0.42
    /// The pill comes in first (280 ms on the open curve), then the star drops into it.
    static let delay = 0.28
    /// The squash on landing, either way.
    static let land = 0.26

    /// A hop turned back `elapsed` seconds into its flight: the way back is the same parabola backwards, so it starts
    /// at `progress` (where the star is now) and takes `remaining`, as long as it has flown. Before the flight there's
    /// nothing to undo; after it, a whole hop back.
    static func reversal(elapsed: Double) -> (progress: Double, remaining: Double) {
        let flown = min(1, max(0, elapsed / duration))
        return (1 - flown, flown * duration)
    }

    /// The star's scale on the way from a seat of one size to another (the band's 20, the pill's 22 or 18): even, as x.
    static func scale(from: CGFloat, to: CGFloat, progress: Double) -> CGFloat {
        from + (to - from) * CGFloat(min(1, max(0, progress)))
    }

    static func point(band: CGPoint, pill: CGPoint, progress: Double, down: Bool) -> CGPoint {
        let p = CGFloat(min(1, max(0, progress)))
        let dy = pill.y - band.y
        return down
            ? CGPoint(x: band.x + (pill.x - band.x) * p, y: band.y + dy * p * p)
            : CGPoint(x: pill.x + (band.x - pill.x) * p, y: band.y + dy * (1 - p) * (1 - p))
    }
}

/// Who draws in the one place under the closed notch (bandHeight + 6): the jobs' pill when it has a line (it holds
/// the star, A6), else the agent chip (① B), else the first listen's prep line, and the speech model's card (③ B) only
/// when none of them shows: it waits, it's never covered and never covers.
enum ArisUnderNotch: Equatable {
    case pill, agentChip, prep, offer

    static func owner(pill: Bool, agentChip: Bool, prep: Bool, offer: Bool) -> Self? {
        if pill { return .pill }
        if agentChip { return .agentChip }
        if prep { return .prep }
        return offer ? .offer : nil
    }
}
