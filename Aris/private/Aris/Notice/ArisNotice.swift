//
//  ArisNotice.swift
//  Aris
//
//  One piece of news on a card of its own under the notch (the owner's pick B, 2026-11-12): a job or a teammate finished,
//  a schedule's result, a timer that ran out, a problem with the one thing that fixes it. What it says, which kind it
//  is (its tile), and what its buttons do. Values only, so the tests build every card; ArisNoticeCenter shows them.
//  Foundation only (tested).
//

import Foundation

/// What a card is about: its tile's colours and its glyph.
enum ArisNoticeKind: String, CaseIterable, Sendable {
    /// A timer or anything else that was due now: orange bell.
    case reminder
    /// Someone has something for the user (a teammate's question): blue, a letter.
    case incoming
    /// Work finished: green check.
    case done
    /// Something went wrong or needs him: red warning.
    case problem
    /// Aris's own word about itself: dark.
    case system

    /// The tile's measured gradient: its top, at 55 %, and its bottom (sRGB, 0xRRGGBB).
    var tile: ArisNoticeTile {
        switch self {
        case .reminder: ArisNoticeTile(top: 0xFFB84D, mid: 0xF28C00, deep: 0xE07800)
        case .incoming: ArisNoticeTile(top: 0x58ABFF, mid: 0x2478F2, deep: 0x1B5FD6)
        case .done: ArisNoticeTile(top: 0x58DD7C, mid: 0x2EBD54, deep: 0x23A047)
        case .problem: ArisNoticeTile(top: 0xFF7A70, mid: 0xF0453A, deep: 0xD3352C)
        case .system: ArisNoticeTile(top: 0x2C2C31, mid: 0x1D1D21, deep: 0x121215)
        }
    }

    /// The white glyph on the tile (an SF Symbol, drawn by the system).
    var glyph: String {
        switch self {
        case .reminder: "bell.fill"
        case .incoming: "envelope.fill"
        case .done: "checkmark.circle.fill"
        case .problem: "exclamationmark.triangle.fill"
        case .system: "sparkle"
        }
    }
}

/// A tile's three stops.
struct ArisNoticeTile: Equatable, Sendable {
    let top: UInt32
    let mid: UInt32
    let deep: UInt32

    /// 0...1 sRGB components of one stop.
    static func components(_ hex: UInt32) -> (red: Double, green: Double, blue: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
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
    }

    let title: String
    /// The blue one (the card's main button); the others are grey.
    let primary: Bool
    let role: Role
}

struct ArisNotice: Equatable, Identifiable, Sendable {
    let id: UUID
    /// One card per key: a newer one with the same key takes the place of the one up (the helper's state).
    var key: String?
    var kind: ArisNoticeKind
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

    init(id: UUID = UUID(), key: String? = nil, kind: ArisNoticeKind, title: String, body: String, subtitle: String? = nil,
         actions: [ArisNoticeAction] = [], posted: Date = Date(), showsWithin: TimeInterval? = nil) {
        self.id = id
        self.key = key
        self.kind = kind
        self.title = title
        self.body = body
        self.subtitle = subtitle
        self.actions = actions
        self.posted = posted
        self.showsWithin = showsWithin
    }

    /// Whether it waited too long to be shown at `now`.
    func expired(at now: Date) -> Bool {
        guard let showsWithin else { return false }
        return now.timeIntervalSince(posted) > showsWithin
    }

    /// The buttons as drawn: the grey ones first, the blue one last (at the right edge).
    var orderedActions: [ArisNoticeAction] { actions.filter { !$0.primary } + actions.filter(\.primary) }
}
