//
//  ArisCharacterDirector.swift
//  Aris
//
//  The character director's rules, pure (the effects run in ArisDirector): what a teammate does when its window moves
//  or goes, when the displays change and when its job ends; which teammates go out to their windows (at most 3 at once,
//  the ones out keep their place) and which wait in the home slot (under the notch, where the status pill is); where
//  home is, and which app a job's hint names.
//

import CoreGraphics
import Foundation

enum ArisDirectorEvent: Equatable {
    case windowMoved(CGRect)
    case windowGone
    case screensChanged(perchStillValid: Bool)
    case jobFinished(ok: Bool)
}

enum ArisDirectorAction: Equatable {
    /// Sit on the window at its new frame (CG coordinates).
    case follow(CGRect)
    /// Glide back and wait in the home slot while the job runs on.
    case goToNotchSlot
    /// Back home at once (the display it sat on may be gone: no trip).
    case goHome
    /// "끝!" for `celebrate`, then home.
    case celebrateThenHome
    /// "못 끝냈어요" for `failHold`, then home.
    case failThenHome
    /// The displays changed and the window is still on one: sit on it again (in that display's new panel).
    case reperch
}

enum ArisCharacterDirector {
    static func react(_ event: ArisDirectorEvent) -> ArisDirectorAction {
        switch event {
        case .windowMoved(let frame): .follow(frame)
        case .windowGone: .goToNotchSlot
        case .screensChanged(let valid): valid ? .reperch : .goHome
        case .jobFinished(let ok): ok ? .celebrateThenHome : .failThenHome
        }
    }

    /// Teammates out on windows at once (the rest wait in the slot).
    static let maxOut = 3
    /// How long "끝!" shows before the trip home (plan), and "못 끝냈어요" (longer: it's worth reading).
    static let celebrate: TimeInterval = 0.8
    static let failHold: TimeInterval = 1.4
    /// Merging into the notch at the end of the trip home (mockup .bubble.out: 200 ms).
    static let mergeFade: TimeInterval = 0.2
    /// No teammate out this long: the overlay panels close (idle cost 0).
    static let panelsIdle: TimeInterval = 30
    /// The character on a window (mockup 10-bubble.html: 28 pt).
    static let perchSize: CGFloat = 28
    /// A window that moved further than this while its teammate was on the way gets a second glide; nearer, a step.
    static let retarget: CGFloat = 24

    struct StageJob: Equatable {
        let id: UUID
        let created: Date
        /// Not finished.
        let live: Bool
        /// The window it sits on, once resolved, still there and the job has started; nil otherwise.
        let window: ArisWindowKey?
    }

    struct Stage: Equatable {
        /// Out on their windows: those already out first, in their order, then new ones oldest first.
        let out: [UUID]
        /// Waiting in the home slot, oldest first.
        let slot: [UUID]
    }

    /// Who is out and who waits: `out` are the ones out now, `returning` how many are on their way home (they still
    /// take a place until they're in). One teammate per window: others on a taken window wait in the slot.
    static func stage(_ jobs: [StageJob], out current: [UUID], returning: Int, cap: Int = maxOut) -> Stage {
        let canGo = jobs.filter { $0.live && $0.window != nil }
        let byId = Dictionary(canGo.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var taken = Set<ArisWindowKey>()
        var out: [UUID] = []
        for id in current {
            guard let window = byId[id]?.window, taken.insert(window).inserted else { continue }
            out.append(id)
        }
        var room = max(0, cap - returning - out.count)
        for job in canGo.sorted(by: { $0.created < $1.created }) where room > 0 && !out.contains(job.id) {
            guard let window = job.window, taken.insert(window).inserted else { continue }
            out.append(job.id)
            room -= 1
        }
        let slot = jobs.filter { $0.live && !out.contains($0.id) }.sorted { $0.created < $1.created }.map(\.id)
        return Stage(out: out, slot: slot)
    }

    /// The pill's line: when the only job waits in the slot, what it does (the teammate's name is for VoiceOver: its
    /// face in the pill already says who); otherwise the status line (counts, approvals).
    static func pillLine(single: (name: String?, text: String)?, fallback: String?) -> ArisPillLine? {
        guard let fallback else { return nil }
        guard let single, !fallback.hasPrefix(approvalPrefix), !fallback.hasPrefix(approvalPrefixEnglish) else { return ArisPillLine(who: nil, text: fallback) }
        return ArisPillLine(who: single.name.map { "\($0) ·" }, text: single.text)
    }

    /// What happens when a teammate's window stops being on screen: closed (or its app quit) is for good, the job waits
    /// in the slot; minimised, hidden or on another Space parks it in the slot until the window shows again.
    static func whenGone(_ presence: ArisWindowPresence) -> ArisGoneAction {
        switch presence {
        case .onScreen: .stay
        case .offScreen: .park
        case .closed: .lose
        }
    }

    private static let approvalPrefix = "허락 기다리는 중"
    private static let approvalPrefixEnglish = "Waiting for your OK"

    /// Where a teammate leaves from and comes back to: under the notch, where the slot's faces sit (AppKit coordinates;
    /// `topInset` is the notch's or menu bar's height). The same spot whatever the character's `size`: it comes out of
    /// the slot.
    static func home(screen: CGRect, topInset: CGFloat, size: CGFloat) -> CGPoint {
        CGPoint(x: screen.midX, y: screen.maxY - topInset - 24)
    }
}

/// One window of one app: one teammate sits on it at a time.
struct ArisWindowKey: Hashable {
    let pid: Int32
    let number: Int
}

/// The pill's line: who (dimmed, as the mockup's `.who`), then what.
struct ArisPillLine: Hashable {
    let who: String?
    let text: String

    /// Read out whole.
    var spoken: String { who.map { "\($0) \(text)" } ?? text }
}

enum ArisGoneAction: Equatable { case stay, park, lose }

/// The director's bookkeeping, pure: which teammates are out and where they are in their trip. Landing, ending and
/// coming home are decided here, in an order that can't strand a figure (a job that ends on the way out ends when it
/// lands, and keeps its place among the 3 until it's home).
struct ArisCast: Equatable {
    enum Phase: Equatable { case goingOut, perched, returning }
    /// What to do on landing, in order.
    enum Landing: Equatable { case glideAgain, sit, end, showBubble }
    enum Ending: Equatable { case now, onLanding, ignored }

    private(set) var phases: [UUID: Phase] = [:]
    private var endsOnLanding: Set<UUID> = []

    /// Out on a window or on the way (not coming home).
    var out: Set<UUID> { Set(phases.filter { $0.value != .returning }.keys) }
    /// On the way home, or ending as soon as they land: they still take a place.
    var returning: Int { phases.values.filter { $0 == .returning }.count }

    func phase(of id: UUID) -> Phase? { phases[id] }

    mutating func goOut(_ id: UUID) {
        phases[id] = .goingOut
        endsOnLanding.remove(id)
    }

    /// The job ended: now when it sits, on landing when it's on its way, nothing when it's already coming home.
    mutating func end(_ id: UUID) -> Ending {
        switch phases[id] {
        case .perched?:
            phases[id] = .returning
            return .now
        case .goingOut?:
            phases[id] = .returning
            endsOnLanding.insert(id)
            return .onLanding
        case .returning?, nil:
            return .ignored
        }
    }

    /// It landed; `pendingMove` is how far its window moved meanwhile (nil: it didn't).
    mutating func landed(_ id: UUID, pendingMove: CGFloat?, retarget: CGFloat = ArisCharacterDirector.retarget) -> [Landing] {
        let near = pendingMove.map { $0 <= retarget } ?? false
        if endsOnLanding.remove(id) != nil { return (near ? [.sit] : []) + [.end] }
        guard let phase = phases[id], phase != .returning else { return [] }
        if let move = pendingMove, move > retarget { return [.glideAgain] }
        phases[id] = .perched
        return (near ? [.sit] : []) + [.showBubble]
    }

    /// Sent home (its window went, the job ended or left the list).
    mutating func goHome(_ id: UUID) {
        guard phases[id] != nil else { return }
        phases[id] = .returning
        endsOnLanding.remove(id)
    }

    /// Home and merged: its place is free.
    mutating func home(_ id: UUID) {
        phases[id] = nil
        endsOnLanding.remove(id)
    }
}

/// A running app, as far as a job's hint needs it.
struct ArisRunningApp: Equatable {
    let pid: Int32
    let bundleId: String?
    let name: String?
    /// The bundle's own file name ("TextEdit"): `name` is localised ("텍스트 편집기" on a Korean Mac), a hint seldom is.
    var bundleName: String? = nil
}

/// The app a job's `appHint` names (model-written): its bundle id, its name or its bundle's file name exactly, in any case; never Aris itself
/// and never a guess from part of a name.
enum ArisAppHint {
    static let maxLength = 128

    static func pid(for hint: String?, in apps: [ArisRunningApp], excluding own: Int32) -> Int32? {
        guard var wanted = hint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !wanted.isEmpty, wanted.count <= maxLength
        else { return nil }
        if wanted.hasSuffix(".app") { wanted.removeLast(4) }
        let others = apps.filter { $0.pid != own }
        return (others.first { $0.bundleId?.lowercased() == wanted } ?? others.first { $0.name?.lowercased() == wanted }
            ?? others.first { $0.bundleName?.lowercased() == wanted })?.pid
    }
}

enum ArisBubbleSide: Equatable { case right, left }

/// Where the bubble sits beside its character (AppKit coordinates): to its right, 8 pt clear and centred on it; to its
/// left, 4 pt clear, when the character sits inside a maximised window's corner (M2) or the right would leave the
/// screen (mockup 10-bubble.html). Always wholly on the screen.
enum ArisBubbleGeometry {
    static let height: CGFloat = 28
    static let gapRight: CGFloat = 8
    static let gapLeft: CGFloat = 4

    /// `width`: the widest the bubble may grow (its host's width).
    static func side(perch: CGPoint, size: CGFloat, width: CGFloat, window: CGRect, screen: CGRect) -> ArisBubbleSide {
        let insideWindow = perch.y + size / 2 <= window.maxY
        let rightEdge = perch.x + size / 2 + gapRight + width
        return insideWindow || rightEdge > screen.maxX ? .left : .right
    }

    static func frame(perch: CGPoint, size: CGFloat, width: CGFloat, side: ArisBubbleSide, screen: CGRect) -> CGRect {
        let x = side == .right ? perch.x + size / 2 + gapRight : perch.x - size / 2 - gapLeft - width
        let y = perch.y - height / 2
        return CGRect(x: min(max(x, screen.minX), screen.maxX - width), y: min(max(y, screen.minY), screen.maxY - height), width: width, height: height)
    }
}
