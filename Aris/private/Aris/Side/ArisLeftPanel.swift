//
//  ArisLeftPanel.swift
//  Aris
//
//  The left side notch: 기록 (the AI sessions running now and past Aris conversations), 한 일 (what Aris and its
//  teammates did today, with 되돌리기), 클립보드 (the clipboard history) or 사용량 (plan limits).
//

import SwiftUI

struct ArisLeftPanel: View {
    @ObservedObject private var panels = ArisSidePanels.shared

    var body: some View {
        // The tabs left on in settings.
        let tabs = panels.shownTabs(.left)
        // Four tabs: the unselected ones shrink 34 -> 28 so the selected one keeps room for its label (mockup 5b).
        ArisSideTabs(edge: .left, tabs: tabs.map { ($0, $0.name()) }, current: $panels.leftTab, unselectedWidth: tabs.count > 3 ? 28 : 34)
        ArisTabSwap(index: tabs.firstIndex(of: panels.leftTab) ?? 0) {
            switch panels.leftTab {
            case .activity:
                ArisActivityView()
            case .clipboard:
                ArisClipboardView(onDone: { panels.collapse(.left) })
                    .padding(.horizontal, -16)
            case .usage:
                // Its own tab, so 기록 and 클립보드 keep the whole panel; the menu bar meter shows the fullest at a glance.
                ArisUsageCard()
            default:
                ArisSessionsAndHistory()
            }
        }
    }
}

/// What's running (Claude, Codex, Gemini sessions; tap to bring its terminal forward), then past Aris turns by day
/// (tap to see that conversation again in the notch as it was, or to open a task's saved result), as history rows.
struct ArisSessionsAndHistory: View {
    @ObservedObject private var claude = ClaudeStore.shared
    @ObservedObject private var aris = ArisController.shared
    /// The side panels' demo: its sample turns, no live sessions, and rows that resume or delete nothing.
    @ObservedObject private var demo = ArisSideDemo.shared

    private var turns: [ArisHistoryEntry] { demo.samples?.history ?? aris.pastTurns }
    private var sessions: [ClaudeSession] { demo.isOn ? [] : claude.sessionList }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                // What's running sits on top with no heading; past turns follow in sessions.
                ForEach(sessions, id: \.id) { session in sessionRow(session) }
                if turns.isEmpty && sessions.isEmpty {
                    ArisSideStyle.empty(ArisUIWords.text("아직 대화가 없어요", "No conversations yet"))
                }
                let groups = ArisHistory.sessions(Array(turns.prefix(40)))
                ForEach(Array(groups.enumerated()), id: \.element.start) { index, group in
                    ArisSideStyle.dayHeading(ArisHistory.sessionHeader(group.start), first: index == 0 && sessions.isEmpty)
                    ForEach(group.entries) { entry in historyRow(entry) }
                }
            }
            .padding(ArisSideStyle.listInsets(underHeader: true, toEdge: true))
        }
        // The list: behind the header and down to the panel's edge, fading in under the one and out at the other.
        .modifier(ArisSideListFrame(underHeader: true, toEdge: true))
        // After the mask: the mask must cover the rows widened by -7, or it cuts their rounded ends off.
        .padding(.horizontal, -(ArisSideLook.headerEdgeSide - ArisSideLook.listEdgeSide))
    }

    private func sessionRow(_ session: ClaudeSession) -> some View {
        ArisSideRow(action: { TerminalFocus.focus(session, cwd: session.cwd) }) {
            let busy = working(session.state)
            Image("ProviderBrand-claude").resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: 17, height: 17)
                .frame(width: 20, height: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    .modifier(ArisProcessingShimmer(on: busy))
                if let last = session.lastMessage {
                    Text(last).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.43)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let dot = dot(session.state) {
                Circle().fill(dot).frame(width: 7, height: 7).padding(.leading, 3)
            }
        }
    }

    private func historyRow(_ entry: ArisHistoryEntry) -> some View {
        ArisSideRow(action: { if !demo.isOn { aris.resume(entry) } }) {
            Group {
                if entry.file != nil {
                    Image(systemName: "doc.text.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.84))
                } else {
                    ArisCharacterView(size: 18, isAris: true)
                }
            }
            .frame(width: 20, height: 20)
            .padding(.top, 1)
            // A past chat shows as its title alone, on one line.
            Text(entry.heard).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.94)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .help(entry.file.map { ArisUIWords.text("저장한 결과 열기: \($0)", "Open the saved result: \($0)") } ?? ArisUIWords.text("그때 대화 다시 보기", "Show this conversation again"))
        .contextMenu {
            if !demo.isOn {
                Button(ArisUIWords.text("기록에서 삭제", "Delete from History"), role: .destructive) { aris.forgetPastTurns { $0.id == entry.id } }
            }
        }
    }

    private func working(_ state: ClaudeState) -> Bool {
        [.thinking, .typing, .building, .juggling].contains(state)
    }

    /// The unread dot: blue finished, the approval yellow waiting on you, red failed; nothing while it works or rests.
    private func dot(_ state: ClaudeState) -> Color? {
        switch state {
        case .notification: Color(ClaudeAccent.approval)
        case .error: Color(red: 0xef / 255, green: 0x44 / 255, blue: 0x44 / 255)
        case .happy: ArisSideStyle.unreadBlue
        default: nil
        }
    }
}
