//
//  ClaudeStore.swift
//  Aris
//
//  Observable state for the Claude Code tab: live sessions, pending approvals
//  and the transient banner shown under the closed notch.
//

import Combine
import Foundation

@MainActor
final class ClaudeStore: ObservableObject {
    static let shared = ClaudeStore(spendStore: .standard)

    @Published private(set) var sessions: [String: ClaudeSession] = [:] {
        didSet { if sessions.isEmpty != oldValue.isEmpty { watchSessions() } }
    }
    @Published private(set) var approvals: [ClaudeApproval] = [] {
        didSet { Self.hasPendingApproval = !approvals.isEmpty }
    }

    /// Readable from non-isolated code (e.g. opening the notch); written only on the main actor.
    nonisolated(unsafe) static var hasPendingApproval = false

    /// True while the pointer is over an approval card; lets the notch window take keyboard focus.
    nonisolated(unsafe) static var keyboardArmed = false
    @Published private(set) var transientPeek: ClaudePeek?
    @Published private(set) var focusedSessionId: String?
    /// Plan limits from the status line; nil until the first report.
    @Published private(set) var usage: ClaudeUsage?
    /// Today's API-key spend and the plan as the status line shows it (ClaudeSpend), saved across restarts.
    @Published private(set) var spend: ClaudeSpendLedger
    /// Answer state of each pending question card, by approval id.
    @Published private(set) var flows: [UUID: QuestionFlow] = [:]

    /// Called when a card is handed back to the terminal, to bring that terminal forward (set by the app).
    var onHandOff: ((ClaudeApproval) -> Void)?
    /// Every hook event as it arrives, with its time (set by the app: a teammate's job ends on its session's Stop).
    var onEvent: ((ClaudeHookEvent, Date) -> Void)?

    /// The bundle ids of the apps running now (set by the app; nil in the tests: no session is dropped for its terminal).
    var runningApps: (() -> Set<String>)?

    private var resolvers: [UUID: (ClaudeDecision) -> Void] = [:]
    /// What lets a card's held hook request go when the card is dropped without the user's answer (ClaudeStore.take).
    private var drops: [UUID: () -> Void] = [:]
    private var happyReset: [String: Task<Void, Never>] = [:]
    private var peekReset: Task<Void, Never>?
    /// Where the spend ledger is saved (nil: not saved, as in the tests), and the wake-up that redraws it at midnight.
    private let spendStore: UserDefaults?
    private var midnight: Task<Void, Never>?
    /// The once-a-minute look for sessions that are over (ClaudeSessionSweep), alive only while sessions are listed.
    private var sweeper: Task<Void, Never>?
    private var terminalSeen: Set<String> = []

    init(spendStore: UserDefaults? = nil) {
        self.spendStore = spendStore
        spend = ClaudeSpendLedger.decoded(spendStore?.data(forKey: ClaudeSpendLedger.defaultsKey))
    }

    private static let staleAfter = ClaudeSessionSweep.staleAfter
    private static let happyDuration: Duration = .seconds(4)
    private static let peekDuration: Duration = .seconds(6)

    var sessionList: [ClaudeSession] {
        sessions.values.sorted { $0.lastEvent > $1.lastEvent }
    }

    /// The session the tab shows: the user's pick, else the one awaiting approval, else the one that just finished
    /// or failed, else the latest.
    var focusedSession: ClaudeSession? {
        if let id = focusedSessionId, let session = sessions[id] { return session }
        if let id = approvals.first?.sessionId, let session = sessions[id] { return session }
        if let id = transientPeek?.sessionId, let session = sessions[id] { return session }
        return sessionList.first
    }

    func focus(_ sessionId: String) {
        focusedSessionId = sessionId
    }

    /// The single state the Claude Code teammate's character shows across all sessions.
    var displayState: ClaudeState {
        if !approvals.isEmpty { return .notification }
        return sessions.values.map(\.state).max { $0.priority < $1.priority } ?? .sleeping
    }

    /// Whether Claude should claim the closed notch (anything beyond idle).
    var isLive: Bool {
        displayState.priority >= ClaudeState.happy.priority
    }

    /// The card in front comes from Aris's own claude (its session isn't listed).
    var arisIsAsking: Bool {
        approvals.first.map { Self.isAris($0.cwd) } ?? false
    }

    /// Any Claude session open, even one resting and waiting for the next prompt.
    var hasSessions: Bool {
        !sessions.isEmpty || !approvals.isEmpty
    }

    /// The latest "done"/"error"/limit notice, shown in the Claude tab.
    var currentPeek: ClaudePeek? { transientPeek }

    /// A sample notice, without its sound (ArisPreview).
    func previewPeek(_ kind: ClaudePeek.Kind) {
        let session = sessionList.first
        switch kind {
        case .done:
            showPeek(kind: .done, title: "Done", detail: session?.title ?? "Aris",
                     message: "닫힌 노치 마감을 바꾸고, 승인 대기 아이콘을 ‖ 로 고정했어요. 테스트는 모두 통과했어요.",
                     sessionId: session?.id)
        case .error:
            showPeek(kind: .error, title: "Error", detail: session?.title ?? "Aris", message: "Bash failed.",
                     sessionId: session?.id)
        case .limit:
            showPeek(kind: .limit, title: "80% used", detail: "5-hour limit", message: "Resets at 7:10 PM")
        }
    }

    func dismissPeek() {
        peekReset?.cancel()
        transientPeek = nil
    }

    func apply(_ event: ClaudeHookEvent, now: Date = Date()) {
        onEvent?(event, now)
        if event.name == "SessionEnd" {
            sessions = sessions.filter { $0.key != event.sessionId }
            if focusedSessionId == event.sessionId { focusedSessionId = nil }
            happyReset[event.sessionId]?.cancel()
            return
        }
        dropAnsweredElsewhere(after: event)
        guard let state = event.claudeState, !Self.isAris(event.cwd) else { return }

        let previous = sessions[event.sessionId]
        let session = ClaudeSession(
            id: event.sessionId,
            cwd: event.cwd.isEmpty ? (previous?.cwd ?? "") : event.cwd,
            state: state,
            lastEvent: now,
            steps: Self.steps(after: event, from: previous?.steps ?? []),
            edit: event.edit ?? previous?.edit,
            lastMessage: Self.message(after: event, from: previous?.lastMessage),
            terminal: event.terminal ?? previous?.terminal,
            contextPercent: event.name == "SessionStart" ? nil : previous?.contextPercent,
            agent: event.agent
        )
        let fresh = sessions.filter { now.timeIntervalSince($0.value.lastEvent) < Self.staleAfter }
        sessions = fresh.merging([session.id: session]) { _, new in new }

        // A session heard for the first time: its terminal is noted as running from the start.
        if previous == nil { sweep(now: now) }

        happyReset[session.id]?.cancel()
        if state == .happy { scheduleIdle(for: session.id) }

        switch event.name {
        case "Stop":
            ClaudeSounds.play(.done)
            showPeek(kind: .done, title: "Done", detail: session.title, message: session.lastMessage, sessionId: session.id)
        case "PostToolUseFailure", "StopFailure":
            ClaudeSounds.play(.error)
            showPeek(kind: .error, title: "Error", detail: session.title, message: event.toolName.map { "\($0) failed." },
                     sessionId: session.id)
        default: break
        }
    }

    /// Drops the sessions that are over and rests the ones long silent (ClaudeSessionSweep: Codex never says it ended,
    /// and a force-closed terminal says nothing either).
    func sweep(now: Date = Date()) {
        let look = ClaudeSessionSweep.swept(sessions, now: now, runningApps: runningApps?(), terminalSeen: terminalSeen)
        terminalSeen = look.terminalSeen
        guard look.sessions != sessions else { return }
        let gone = Set(sessions.keys).subtracting(look.sessions.keys)
        gone.forEach { happyReset[$0]?.cancel() }
        if let focused = focusedSessionId, gone.contains(focused) { focusedSessionId = nil }
        sessions = look.sessions
    }

    /// The sweep runs once a minute while any session is listed, and stops with the last one.
    private func watchSessions() {
        guard !sessions.isEmpty else {
            sweeper?.cancel()
            sweeper = nil
            return
        }
        guard sweeper == nil else { return }
        sweeper = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ClaudeSessionSweep.every))
                guard !Task.isCancelled, let self else { return }
                self.sweep(now: Date())
            }
        }
    }

    /// Whether the once-a-minute look is running (it is only while sessions are listed).
    var isSweeping: Bool { sweeper != nil }

    /// Aris's own claude session runs here; it talks through the Aris pill, not the session list.
    static let arisDirectory = UserHome.path + "/.config/aris/aris"

    private static func isAris(_ cwd: String) -> Bool {
        cwd == arisDirectory || cwd.hasPrefix(arisDirectory + "/")
    }

    /// Recent tool calls (newest last, max 4): a call starts running on PreToolUse and finishes on PostToolUse/Stop.
    private static func steps(after event: ClaudeHookEvent, from steps: [ClaudeStep]) -> [ClaudeStep] {
        switch event.name {
        case "UserPromptSubmit":
            return []
        case "PreToolUse":
            guard let tool = event.toolName else { return steps }
            return Array((steps + [ClaudeStep(tool: tool, done: false)]).suffix(4))
        case "PostToolUse", "PostToolUseFailure":
            guard let index = steps.lastIndex(where: { $0.tool == event.toolName && !$0.done }) else { return steps }
            let finished = ClaudeStep(tool: steps[index].tool, done: true)
            return steps.enumerated().map { $0.offset == index ? finished : $0.element }
        case "Stop":
            return steps.map { ClaudeStep(tool: $0.tool, done: true) }
        default:
            return steps
        }
    }

    /// The assistant's final message sticks until the next prompt.
    private static func message(after event: ClaudeHookEvent, from previous: String?) -> String? {
        switch event.name {
        case "UserPromptSubmit": return nil
        case "Stop": return event.lastMessage ?? previous
        default: return previous
        }
    }

    private func showPeek(kind: ClaudePeek.Kind, title: String, detail: String, message: String? = nil, sessionId: String? = nil) {
        transientPeek = ClaudePeek(id: UUID().uuidString, kind: kind, title: title, detail: detail, message: message, sessionId: sessionId)
        peekReset?.cancel()
        peekReset = Task { [weak self] in
            try? await Task.sleep(for: Self.peekDuration)
            guard !Task.isCancelled else { return }
            self?.transientPeek = nil
        }
    }

    private func scheduleIdle(for sessionId: String) {
        happyReset[sessionId] = Task { [weak self] in
            try? await Task.sleep(for: Self.happyDuration)
            guard !Task.isCancelled, let self, let current = self.sessions[sessionId], current.state == .happy else { return }
            self.sessions = self.sessions.merging([sessionId: current.with(state: .idle)]) { _, new in new }
        }
    }

    // MARK: - Usage

    /// A status line update: account-wide limits, plus that session's context use.
    /// A limit passing 80% or 95% shows a banner that names it: the 5-hour or the weekly window, or the daily budget.
    func applyStatus(_ report: ClaudeStatusReport, now: Date = Date()) {
        let old = usage, spentBefore = spend.spent(at: now)
        let next = (usage ?? ClaudeUsage(updatedAt: now)).merging(report, now: now)
        usage = next
        recordSpend(report, now: now)
        if let id = report.sessionId, let percent = report.contextPercent, let session = sessions[id] {
            var updated = session
            updated.contextPercent = percent
            sessions = sessions.merging([id: updated]) { _, new in new }
        }
        let ringWindow = ringMode.window(fiveHour: next.fiveHour?.percent(at: now), sevenDay: next.sevenDay?.percent(at: now))
        if let reached = ClaudeLimitReached.find(old: old, report: report, spentBefore: spentBefore, spentAfter: spend.spent(at: now),
                                                 budget: spend.plan == .apiKey ? dailyBudget : nil, ringWindow: ringWindow, now: now) {
            showPeek(kind: .limit, title: reached.title, detail: reached.detail, message: reached.message())
        }
    }

    /// The saved picks of 설정 › 대화 › Claude Code, read where the spend is kept (the tests' store has none: the ring
    /// is the 5-hour one and the budget is the default $5, on).
    private var ringMode: ClaudeRingMode { ClaudeRingMode(stored: spendStore?.string(forKey: ClaudeRingMode.defaultsKey)) }

    private var dailyBudget: Double? {
        let on = spendStore?.object(forKey: ClaudeBudget.onKey) as? Bool ?? true
        let amount = spendStore?.object(forKey: ClaudeBudget.amountKey) as? Double ?? ClaudeBudget.fallback
        return on ? ClaudeBudget.stored(amount) : nil
    }

    /// Today's spend across sessions ($0 past local midnight until the next report).
    func spentToday(at now: Date = Date()) -> Double { spend.spent(at: now) }

    /// One session's own spend so far.
    func sessionSpend(_ id: String) -> Double? { spend.session(id) }

    private func recordSpend(_ report: ClaudeStatusReport, now: Date) {
        let old = spend, next = old.recording(report, now: now)
        guard next != old else { return }
        spend = next
        // A status line reports several times a second while Claude works: only a new amount, day, session or plan is written.
        if next.changedMoney(from: old) { spendStore?.set(next.encoded(), forKey: ClaudeSpendLedger.defaultsKey) }
        guard next.plan == .apiKey, midnight == nil else { return }
        // The ring reads $0 once the day turns, even with no session talking: redraw then, once.
        let wake = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 1), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        midnight = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, wake.timeIntervalSince(Date()))))
            guard !Task.isCancelled, let self else { return }
            self.midnight = nil
            self.objectWillChange.send()
        }
    }

    /// Queues an approval; `resolve` is called exactly once with the decision. A card dropped without one (answered
    /// in the terminal, its client gone) never sends a decision: `onDrop` is called then, once.
    func requestApproval(_ approval: ClaudeApproval, resolve: @escaping (ClaudeDecision) -> Void, onDrop: (() -> Void)? = nil) {
        if case .question(let questions) = approval.kind {
            flows = flows.merging([approval.id: QuestionFlow(questions: questions)]) { _, new in new }
        }
        approvals = approvals + [approval]
        ClaudeSounds.play(.approval)
        resolvers = resolvers.merging([approval.id: resolve]) { _, new in new }
        if let onDrop { drops = drops.merging([approval.id: onDrop]) { _, new in new } }
    }

    func decide(_ id: UUID, _ decision: ClaudeDecision) {
        guard let resolve = resolvers[id] else { return }
        if case .passthrough = decision, let approval = approvals.first(where: { $0.id == id }) { onHandOff?(approval) }
        resolvers = resolvers.filter { $0.key != id }
        drops = drops.filter { $0.key != id }
        approvals = approvals.filter { $0.id != id }
        flows = flows.filter { $0.key != id }
        resolve(decision)
    }

    // MARK: - Question cards

    func updateFlow(_ id: UUID, _ change: (QuestionFlow) -> QuestionFlow) {
        guard let flow = flows[id] else { return }
        flows = flows.merging([id: change(flow)]) { _, new in new }
    }

    /// Picks an option on the card's current question; a lone single-select question is answered right away.
    func pick(_ label: String, in id: UUID) {
        updateFlow(id) { $0.picking(label) }
        if flows[id]?.answersOnTap == true { submit(id) }
    }

    func pick(index: Int, in id: UUID) {
        updateFlow(id) { $0.picking(index: index) }
        if flows[id]?.answersOnTap == true { submit(id) }
    }

    /// Sends the answers once every question has one.
    func submit(_ id: UUID) {
        guard let flow = flows[id], flow.isComplete else { return }
        decide(id, .answer(flow.answers))
    }

    /// Number keys pick, arrows/Tab move, Return submits, Esc hands the question to the terminal.
    /// Only for a question card in front; false means the key wasn't used.
    func handleQuestionKey(_ keyCode: UInt16) -> Bool {
        guard let first = approvals.first, case .question = first.kind,
              flows[first.id] != nil, let key = QuestionFlow.Key(keyCode: keyCode) else { return false }
        switch key {
        case .option(let index): pick(index: index, in: first.id)
        case .next: updateFlow(first.id) { $0.moving(to: $0.current + 1) }
        case .previous: updateFlow(first.id) { $0.moving(to: $0.current - 1) }
        case .submit: submit(first.id)
        case .terminal: decide(first.id, .passthrough)
        }
        return true
    }

    /// Answers the oldest pending tool/plan approval (questions need a real choice); false if none.
    @discardableResult
    func decideFirstTool(_ decision: ClaudeDecision) -> Bool {
        guard let first = approvals.first(where: { if case .question = $0.kind { return false }; return true }) else { return false }
        // Claude Code ignores hook answers to plan approval; only the terminal can approve a plan.
        if case .plan = first.kind, case .allow = decision {
            decide(first.id, .passthrough)
        } else {
            decide(first.id, decision)
        }
        return true
    }

    /// The card is dropped without the user's answer: the client went away (timed out, or the session quit), it was
    /// answered in the terminal, or its time passed. No decision is sent; a held hook request is let go (`onDrop`),
    /// so Claude Code is never left waiting for a card that is gone.
    func cancelApproval(_ id: UUID) {
        let drop = drops[id]
        resolvers = resolvers.filter { $0.key != id }
        drops = drops.filter { $0.key != id }
        approvals = approvals.filter { $0.id != id }
        flows = flows.filter { $0.key != id }
        drop?()
    }

    /// A terminal answer leaves the hook request open, so the card is cleared by what happens next:
    /// the same call finishing, or the turn ending (which covers a terminal "No").
    private func dropAnsweredElsewhere(after event: ClaudeHookEvent) {
        let answered: (ClaudeApproval) -> Bool
        switch event.name {
        case "PostToolUse", "PostToolUseFailure": answered = { $0.isFinished(by: event) }
        case "Stop", "StopFailure": answered = { $0.sessionId == event.sessionId }
        default: return
        }
        approvals.filter(answered).forEach { cancelApproval($0.id) }
    }
}
