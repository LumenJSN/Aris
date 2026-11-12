//
//  ArisFixTurns.swift
//  aris-agent
//
//  The button a conversation turn's failure earns (ArisFix), worked out where the reason is known and sent on the
//  turn's /ask stream just before its last line:
//   · a turn that ends in one of the agent's own failure lines (an AI that needs a login, hit its limit, has a wrong
//     key, stopped, took too long): the line is one this file can make again from the same functions that made it
//     (ArisBrainFailure, ArisBrainTrouble), so which failure it is is known, not read out of its words;
//   · a turn whose tool call failed for something the user can fix (a permission of aris-agent's that is off, a service
//     that isn't connected): the tool, or the agent's own route that answered it, left a note (ArisFixDrop, `note`).
//     The brain then says it its own way, and the button is still the right one.
//  A background job's stream gets none (its failure is not under an answer in the notch). The rules are pure
//  (tested); the live half only holds when each stream began.
//

import Foundation

/// Which fix one of the agent's own failure lines earns.
enum ArisBrainFix {
    /// The fix for `line`, when it is a failure line the agent makes; nil for any other text. `another`: the AI that
    /// could take the same request now instead of the one named (ArisTurnFallback), nil when none can.
    static func fix(forLine line: String, another: (ArisBrain) -> ArisBrain?) -> ArisFix? {
        if let trouble = ArisBrainTrouble.named(in: line) {
            // Nothing to pick from: the row where a key or an AI is added.
            return .settings(trouble.missing == .key || trouble.missing == .setup ? .key : .brain)
        }
        for brain in ArisBrain.allCases {
            // Its program changed and was not started: the owner's yes, then the same request again.
            if brain != .api, [true, false].contains(where: { ArisProgramApproval.changedLine(brain, korean: $0) == line }) { return .acceptProgram(brain.rawValue) }
            if loginLines(brain).contains(line) { return brain == .api ? .settings(.key) : .login(brain.rawValue) }
            if limitLeads(brain).contains(where: line.hasPrefix) {
                // Another AI answers it this once; with none ready, the row where one is connected, and asking again
                // later is the other thing that works.
                return another(brain).map { .otherBrain($0.rawValue) } ?? .settings(.brain, again: true)
            }
            if passingLines(brain).contains(line) || stoppedLeads(brain).contains(where: line.hasPrefix) { return .retry }
        }
        return nil
    }

    /// "… 로그인이 필요해요 …" as every path words it (a failed call, a process that ended), and an API brain's wrong key.
    static func loginLines(_ brain: ArisBrain) -> Set<String> {
        var lines: Set<String> = [ArisBrainFailure.friendly("not logged in", brain: brain)]
        for korean in [true, false] {
            lines.insert(ArisBrainFailure.friendly("not logged in", brain: brain, korean: korean))
            if case .say(let line) = ArisBrainFailure.death(stderr: "not logged in", brain: brain, korean: korean, acted: true, isTask: false,
                                                            events: 1, retried: true) { lines.insert(line) }
        }
        return lines
    }

    /// The start of the limit line, before its reset time.
    static func limitLead(_ brain: ArisBrain, korean: Bool = true) -> String {
        let line = ArisBrainFailure.friendly("rate limit", brain: brain, korean: korean)
        return line.range(of: ". ").map { String(line[..<$0.lowerBound]) + "." } ?? line
    }

    /// In both languages the line is said in.
    static func limitLeads(_ brain: ArisBrain) -> [String] { [true, false].map { limitLead(brain, korean: $0) } }

    /// Lines for something that passes: the AI didn't start, took too long, said nothing, couldn't be reached, or
    /// stopped without a word.
    static func passingLines(_ brain: ArisBrain) -> Set<String> {
        var lines: Set<String> = []
        for korean in [true, false] {
            lines.insert(ArisBrainFailure.startLine(brain: brain, missing: nil, korean: korean))
            lines.insert(ArisBrainFailure.slowLine(brain: brain, korean: korean))
            lines.insert(ArisBrainFailure.silentLine(brain: brain, korean: korean))
            lines.insert(ArisBrainFailure.unreachableLine(brain: brain, korean: korean))
            if case .say(let line) = ArisBrainFailure.death(stderr: "", brain: brain, korean: korean, acted: true, isTask: false,
                                                            events: 1, retried: true) { lines.insert(line) }
        }
        return lines
    }

    /// "… 멈췄어요: " before the tool's own last words.
    static func stoppedLeads(_ brain: ArisBrain) -> [String] {
        let mark = "\u{1}"
        return [true, false].compactMap { korean in
            guard case .say(let line) = ArisBrainFailure.death(stderr: mark, brain: brain, korean: korean, acted: true, isTask: false,
                                                               events: 1, retried: true), let cut = line.range(of: mark) else { return nil }
            return String(line[..<cut.lowerBound])
        }
    }
}

/// What the brains are told, so a spoken answer never reads a path out (ArisAgentPrompt adds it).
enum ArisFixPrompt {
    static let rule = "When something fails for a reason the user can fix (a permission that is off, a login, a key, a service that isn't "
        + "connected), say in one short sentence what is missing and stop there: no path through Settings (never \"설정 › …\" or "
        + "\"System Settings › …\"), no terminal command and no list of steps. Aris puts the button that fixes it under your answer."
}

/// The conversation streams under way and what was noted for them.
final class ArisFixTurns: @unchecked Sendable {
    static let shared = ArisFixTurns()

    /// A stream that never ended (the app dropped it) is forgotten after this long.
    static let longestTurn: TimeInterval = 3_600

    private let lock = NSLock()
    private var began: [ObjectIdentifier: Date] = [:]
    private var notes: [(at: Date, fix: ArisFix)] = []

    /// What the look made just before a question found missing (aris-agent may not record the screen), until that
    /// question's stream starts.
    private var lookNeeds: (at: Date, fix: ArisFix)?
    /// A look older than this belongs to no question that is still to come.
    static let lookKept: TimeInterval = 120

    /// The app's look before a question (/look, ArisLook): `fix` when the screen couldn't be read for a permission
    /// that is off, nil when it could (an older look's note is dropped).
    func looked(_ fix: ArisFix?, now: Date = Date()) {
        lock.withLock { lookNeeds = fix.flatMap { $0.isValid ? (now, $0) : nil } }
    }

    /// A conversation's /ask stream starts; a background job's is not kept (it gets no button).
    /// `toldUnread`: the question carries the look's line that the screen couldn't be read (the app leaves it out when
    /// its own picture of the screen goes along): only then is the look's missing permission this turn's to fix.
    func began(_ stream: AnyObject, task: Bool, toldUnread: Bool = false, now: Date = Date()) {
        guard !task else { return }
        lock.withLock {
            began = began.filter { now.timeIntervalSince($0.value) < Self.longestTurn }
            notes = notes.filter { now.timeIntervalSince($0.at) < ArisFixDrop.kept }
            began[ObjectIdentifier(stream)] = now
            if toldUnread, let look = lookNeeds, now.timeIntervalSince(look.at) < Self.lookKept, now >= look.at { notes.append((now, look.fix)) }
            lookNeeds = nil
        }
    }

    /// One of the agent's own routes answered a tool call with a failure the user can fix (computer use without
    /// Accessibility, a service that isn't connected, an API key the provider refused).
    func note(_ fix: ArisFix, now: Date = Date()) {
        guard fix.isValid else { return }
        lock.withLock { notes.append((now, fix)) }
    }

    /// The fix to send before `reply`, when `reply` ends a conversation stream that earned one. A failure line of the
    /// agent's own decides first; otherwise the latest note of the turn (from the agent's routes or from aris-tools).
    /// Under an answer only a fix for something that stays wrong counts (a list, a row, a login): "try again" under
    /// an answer that came would be wrong.
    func closing(_ reply: ArisAgentReply, on stream: AnyObject, dropped: [ArisFixDrop.Entry], now: Date = Date(),
                 another: (ArisBrain) -> ArisBrain?) -> ArisFix? {
        guard reply.isLast else { return nil }
        let (since, own) = lock.withLock { (began.removeValue(forKey: ObjectIdentifier(stream)), notes) }
        guard let since else { return nil }
        let noted = Self.latest(own: own, dropped: dropped, since: since, until: now)
        switch reply {
        case .failure(let line): return ArisBrainFix.fix(forLine: line, another: another) ?? noted
        case .answer: return noted.flatMap { $0.kind == .retry || $0.kind == .otherBrain || $0.kind == .copy ? nil : $0 }
        default: return nil
        }
    }

    /// The newest note written while the turn ran, whoever wrote it.
    static func latest(own: [(at: Date, fix: ArisFix)], dropped: [ArisFixDrop.Entry], since: Date, until: Date) -> ArisFix? {
        let mine = own.filter { $0.at >= since && $0.at <= until }.max { $0.at < $1.at }
        let tools = dropped.filter { !$0.task && $0.at >= since && $0.at <= until }.max { $0.at < $1.at }
        switch (mine, tools) {
        case (let mine?, let tools?): return mine.at >= tools.at ? mine.fix : tools.fix
        case (let mine?, nil): return mine.fix
        case (nil, let tools?): return tools.fix
        case (nil, nil): return nil
        }
    }
}
