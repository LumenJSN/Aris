//
//  ClaudeTabView.swift
//  Aris
//
//  The "Claude" tab: the Claude Code teammate's character, live Claude Code sessions, and approval cards. The
//  teammate's accent (ClaudeAccent, from its look in 팀원) lights the working chips, the panel's hairline and its wash.
//

import Defaults
import SwiftUI

struct ClaudeTabView: View {
    @ObservedObject private var store = ClaudeStore.shared
    @ObservedObject private var team = ArisTeamModel.shared
    @Default(.claudeRingMode) private var ringMode
    @Default(.claudeBudgetOn) private var budgetOn
    @Default(.claudeBudget) private var budget

    var body: some View {
        let palette = team.claudePalette
        let state = store.displayState
        // Aris's own claude has no listed session; its card shouldn't borrow another session's column.
        let focus = store.arisIsAsking ? nil : store.focusedSession
        HStack(alignment: .top, spacing: 12) {
            SessionColumn(session: focus, name: store.arisIsAsking ? "Aris" : "Claude Code",
                          state: state, usage: store.usage, meter: meter(focus), aris: store.arisIsAsking)
                .frame(width: 150)
            VStack(alignment: .leading, spacing: 6) {
                if store.sessions.count > 1 {
                    SessionChips(sessions: store.sessionList, focusedId: focus?.id, accent: Color(palette.accent)) { store.focus($0) }
                }
                Panel(rim: Color(palette.rim), wash: [.accent, .approval].contains(state.tone) ? Color(palette.wash) : .clear) {
                    if let approval = store.approvals.first {
                        ApprovalCard(approval: approval, flow: store.flows[approval.id], pending: store.approvals.count) { decision in
                            store.decide(approval.id, decision)
                        }
                    } else if let session = focus {
                        ActivityPanel(session: session)
                    } else {
                        EmptyHint()
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { if !store.approvals.isEmpty { KeyboardFocus.arm($0) } }
        .onDisappear { KeyboardFocus.arm(false) }
    }
}

extension ClaudeTabView {
    /// What the usage line shows: the plan's gauges with the ear's window lit, or an API key's spend.
    private func meter(_ focus: ClaudeSession?) -> SessionColumn.Meter {
        let mode = ClaudeRingMode(stored: ringMode)
        let reading = ClaudeRingNow.reading(store, mode: ringMode, budgetOn: budgetOn, budget: budget)
        if case .budget(let spent, let budget) = reading {
            return .spend(spent: spent, budget: budget, session: focus.flatMap { store.sessionSpend($0.id) })
        }
        let window = reading.window ?? .fiveHour
        return .limits(window, ClaudeUsageWords.ringMark(mode: mode, window: window))
    }
}

/// One chip per session; tapping focuses it.
private struct SessionChips: View {
    let sessions: [ClaudeSession]
    let focusedId: String?
    let accent: Color
    let onPick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(sessions) { session in
                    Button { onPick(session.id) } label: {
                        HStack(spacing: 4) {
                            Circle().fill(session.state.tone.color(accent: accent, rest: .gray)).frame(width: 6, height: 6)
                            Text(session.title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Color.white.opacity(session.id == focusedId ? 0.22 : 0.08)))
                    }
                    .buttonStyle(.plain)
                    // Double-click: go to that session's terminal tab.
                    .simultaneousGesture(TapGesture(count: 2).onEnded { TerminalFocus.focus(session, cwd: session.cwd) })
                    .accessibilityLabel(session.title)
                }
            }
        }
        .frame(height: 20)
    }
}

/// Dark rounded surface the right-hand content sits on.
private struct Panel<Content: View>: View {
    /// The hairline's lit top: the accent, faint.
    let rim: Color
    /// A faint light from the top while Claude works or waits; clear otherwise.
    let wash: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        content()
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The card surface (radius 24, a lit hairline), kept dark enough for diffs over a bright screen.
            .background(
                shape.fill(Color(white: 0.06).opacity(0.8))
                    .overlay {
                        // The mockup's wash: an ellipse 1.4 × the width and 0.9 × the height, its centre above the top.
                        GeometryReader { box in
                            EllipticalGradient(colors: [wash, .clear])
                                .frame(width: box.size.width * 1.4, height: box.size.height * 0.9)
                                .position(x: box.size.width / 2, y: -box.size.height * 0.15)
                        }
                        .clipShape(shape)
                        .allowsHitTesting(false)
                    }
                    .overlay(shape.strokeBorder(LinearGradient(colors: [rim, .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .animation(.easeOut(duration: 0.4), value: wash)
            )
    }
}

/// Left column: the Claude Code teammate, project name, context use, the recent tool steps and plan usage.
private struct SessionColumn: View {
    let session: ClaudeSession?
    /// Shown when there's no session to name.
    let name: String
    let state: ClaudeState
    let usage: ClaudeUsage?
    /// The usage line under the steps.
    enum Meter: Equatable {
        case limits(ClaudeLimitWindow, String)
        case spend(spent: Double, budget: Double?, session: Double?)
    }
    var meter = Meter.limits(.fiveHour, "")
    /// Aris's own Claude is asking: the column is Aris's, so it shows Aris's face, not Claude Code's (N8).
    var aris = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Group {
                    if aris {
                        ArisCharacterView(state: ClaudeCharacter.pose(state).mood, size: 44, isAris: true)
                    } else {
                        ClaudeCharacterView(state: state, size: 44, glows: true)
                    }
                }
                .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session?.title ?? name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(contextLine)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            if let session {
                Button { TerminalFocus.focus(session, cwd: session.cwd) } label: {
                    Label("Open terminal", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach((session?.steps ?? []).suffix(3)) { step in
                    HStack(spacing: 6) {
                        StepIcon(done: step.done)
                        Text(step.tool)
                            .font(.system(size: 11, weight: step.done ? .regular : .semibold))
                            .foregroundStyle(step.done ? .gray : .white)
                            .lineLimit(1)
                    }
                }
            }
            .animation(.snappy, value: session?.steps)
            // Account-wide, so shown once here rather than per session.
            switch meter {
            case .limits(let window, let mark):
                if let usage { UsageMeter(usage: usage, showing: window, mark: mark).padding(.top, 2) }
            case .spend(let spent, let budget, let session):
                SpendMeter(spent: spent, budget: budget, session: session).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Context 41%", led by "API 키 · " on an API key.
    private var contextLine: String {
        let context = session?.contextPercent.map { "Context \(Int($0.rounded()))%" }
        guard case .spend = meter else { return context ?? "Claude Code" }
        return ClaudeUsageWords.apiKey() + " · " + (context ?? "Claude Code")
    }
}

private struct StepIcon: View {
    let done: Bool

    var body: some View {
        if done {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .font(.system(size: 10))
        } else {
            ProgressView().controlSize(.mini).scaleEffect(0.6)
                .frame(width: 10, height: 10)
        }
    }
}

/// Right panel: the last edit as a diff, or a quiet placeholder.
private struct ActivityPanel: View {
    let session: ClaudeSession

    var body: some View {
        if let edit = session.edit {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(edit.file)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(edit.path.replacingOccurrences(of: session.cwd + "/", with: ""))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array((edit.removed.map { ("-", $0) } + edit.added.map { ("+", $0) }).prefix(7).enumerated()), id: \.offset) { _, row in
                        DiffRow(sign: row.0, text: row.1)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.state == .idle || session.state == .happy ? "Waiting for the next prompt" : "Working…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Text(session.lastMessage ?? "File changes show up here as a diff.")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .lineLimit(3)
            }
        }
    }
}

private struct DiffRow: View {
    let sign: String
    let text: String

    private var tint: Color { sign == "+" ? .green : .red }

    var body: some View {
        HStack(spacing: 6) {
            Text(sign).foregroundStyle(tint)
            Text(text.isEmpty ? " " : text)
                .foregroundStyle(sign == "+" ? .white : .white.opacity(0.55))
                .strikethrough(sign == "-", color: .red.opacity(0.5))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(tint.opacity(0.14))
    }
}

private struct EmptyHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No Claude Code sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Text("Start `claude` in a terminal and it shows up here.")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }
}

private struct ApprovalCard: View {
    let approval: ClaudeApproval
    let flow: QuestionFlow?
    let pending: Int
    let onDecide: (ClaudeDecision) -> Void

    var body: some View {
        switch approval.kind {
        case .question:
            if let flow { QuestionCard(id: approval.id, flow: flow) }
        case .plan(let plan):
            PlanCard(plan: plan, onDecide: onDecide)
        case .tool:
            toolCard
        }
    }

    private var toolCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(approval.toolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text((approval.cwd as NSString).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                if pending > 1 {
                    Text("+\(pending - 1)").font(.caption).foregroundStyle(Color(ClaudeAccent.approval))
                }
            }
            if let edit = approval.edit {
                VStack(alignment: .leading, spacing: 0) {
                    Text(edit.file)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.gray)
                        .padding(.bottom, 3)
                    ForEach(Array((edit.removed.map { ("-", $0) } + edit.added.map { ("+", $0) }).prefix(10).enumerated()), id: \.offset) { _, row in
                        DiffRow(sign: row.0, text: row.1)
                    }
                }
            } else if !approval.summary.isEmpty {
                Text(approval.summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
            }
            HStack(spacing: 8) {
                Button { onDecide(.deny) } label: { KeyHintLabel("Deny", key: "N") }
                    .buttonStyle(.notch(.secondary))
                if approval.canAlwaysAllow, let rules = approval.alwaysRules {
                    Button("Always allow") { onDecide(.allowAlways(rules: rules)) }
                        .buttonStyle(.notch(.secondary))
                }
                Button { onDecide(.allow) } label: { KeyHintLabel("Allow", key: "Y") }
                    .buttonStyle(.notch(.primary))
                Spacer(minLength: 0)
                Button("Terminal") { onDecide(.passthrough) }
                    .buttonStyle(.notch(.quiet))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
