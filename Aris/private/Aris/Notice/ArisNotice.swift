//
//  ArisNotice.swift
//  Aris
//
//  One piece of news on the pill under the notch (the owner's pick D, 2026-11-16): a job or a teammate finished, a
//  schedule's result, a timer that ran out, a problem with the one thing that fixes it, a deadline coming up, a Claude
//  Code session done. What it says, whose it is (its mark), what its buttons and a click on it do, and how long it
//  stays. Values only, so the tests build every one; ArisNoticeCenter shows them. Foundation only (tested).
//

import Foundation

/// What a piece of Aris's own news is about. On the notice pill a teammate's question (incoming) wears the mail mark;
/// the rest are Aris's own and wear its star (ArisNoticeMark).
enum ArisNoticeKind: String, CaseIterable, Sendable {
    /// A timer or anything else that was due now.
    case reminder
    /// Someone has something for the user (a teammate's question).
    case incoming
    /// Work finished.
    case done
    /// Something went wrong or needs him.
    case problem
    /// Aris's own word about itself.
    case system
}

/// Whose news it is: Aris's own (its kind says what), a Claude Code session's, or a deadline coming up (24 h or 3 h
/// before, ArisDueAlert).
enum ArisNoticeSource: Equatable, Sendable {
    case aris
    case claude
    case deadline(ArisDueAlert)
}

/// The mark at the pill's left: Aris's star, Claude Code's ghost, the mail glyph, or a deadline's calendar in its colour.
enum ArisNoticeMark: Equatable, Sendable {
    case star, ghost, mail
    case deadline(ArisDueAlert)
}

/// A button on a card. What it does is named, never a closure, so a card can be compared and tested.
struct ArisNoticeAction: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        /// The fixes of a problem line, pressed one after another (most lines have one): ArisFixModel does each.
        case fixes([ArisFix])
        /// The helper is restarted, as the dozing star's 다시 시작 does.
        case restartHelper
        /// A handed-out job's result: its saved file in the reader, or its answer.
        case openJob(UUID)
        /// A scheduled job's saved result in the reader.
        case openFile(String)
        /// An answer with nothing saved, in the reader.
        case openAnswer(question: String, text: String)
        /// A job reported as not done, handed out again (ArisJobVerdict).
        case retryJob(UUID)
        /// A deadline's own page (ArisTodoModel.open); its alert is dismissed.
        case openDue(ArisDue)
        /// A Claude Code session's terminal brought forward (TerminalFocus); its notice is dismissed.
        case focusClaude(sessionId: String)
        /// A new version of Aris: download and install it now, or not now (ArisUpdater).
        case installUpdate, laterUpdate
        /// A permission that is off: its System Settings pane (ArisPermissionCenter; the drag panel for the two lists
        /// that have one).
        case permissionPane(ArisPermission)
        /// A switch turned on that this copy of Aris sees only after it reopens: quit and open again, one press.
        case relaunchApp
    }

    let title: String
    /// The main button (the last, at the right edge); the others are quieter.
    let primary: Bool
    let role: Role
}

struct ArisNotice: Equatable, Identifiable, Sendable {
    let id: UUID
    /// One card per key: a newer one with the same key takes the place of the one up (the helper's state).
    var key: String?
    var kind: ArisNoticeKind
    var source: ArisNoticeSource
    var title: String
    /// The text under the title (for an incoming one, its snippet).
    var body: String
    /// An incoming one's second line (what it is about).
    var subtitle: String?
    var actions: [ArisNoticeAction]
    var posted: Date
    /// A card that waited longer than this to be shown is dropped (its 기록 entry keeps it): a timer's line long after
    /// it rang would only confuse. Nil: it waits for as long as it takes.
    var showsWithin: TimeInterval?
    /// Once up, it goes by itself after this long (a deadline's alert, a Claude Code notice), held while the pointer is
    /// on it. Nil: it stays until it is closed or acted on.
    var showsFor: TimeInterval?
    /// What a click on its body does (a deadline opens, a Claude Code notice brings its terminal forward). Nil: nothing,
    /// as a card's body did nothing.
    var tap: ArisNoticeAction.Role?
    /// An update downloading or installing: a quiet bar at the line's right, 0 to 1. Nil: none.
    var progress: Double?

    init(id: UUID = UUID(), key: String? = nil, kind: ArisNoticeKind, source: ArisNoticeSource = .aris, title: String, body: String,
         subtitle: String? = nil, actions: [ArisNoticeAction] = [], posted: Date = Date(), showsWithin: TimeInterval? = nil,
         showsFor: TimeInterval? = nil, tap: ArisNoticeAction.Role? = nil, progress: Double? = nil) {
        self.id = id
        self.key = key
        self.kind = kind
        self.source = source
        self.title = title
        self.body = body
        self.subtitle = subtitle
        self.actions = actions
        self.posted = posted
        self.showsWithin = showsWithin
        self.showsFor = showsFor
        self.tap = tap
        self.progress = progress.map { min(1, max(0, $0)) }
    }

    /// A notice that goes by itself (showsFor) is gone this long after it was posted, however often it stepped aside
    /// meanwhile (fourteenth VM run: a timer's "2 minutes is up" came back under the notch for 16 minutes, its clock
    /// starting over each time a turn made it step aside).
    static let longestUp: TimeInterval = 300

    /// Whether it goes by itself and has been about longer than `longestUp` at `now`.
    func outlived(at now: Date) -> Bool {
        showsFor != nil && now.timeIntervalSince(posted) > Self.longestUp
    }

    /// Whether it waited too long to be shown at `now`.
    func expired(at now: Date) -> Bool {
        guard let showsWithin else { return false }
        return now.timeIntervalSince(posted) > showsWithin
    }

    /// The buttons as drawn: the quieter ones first, the main one last (at the right edge).
    var orderedActions: [ArisNoticeAction] { actions.filter { !$0.primary } + actions.filter(\.primary) }

    /// Its mark on the pill.
    var mark: ArisNoticeMark {
        switch source {
        case .claude: .ghost
        case .deadline(let alert): .deadline(alert)
        case .aris: kind == .incoming ? .mail : .star
        }
    }
}
