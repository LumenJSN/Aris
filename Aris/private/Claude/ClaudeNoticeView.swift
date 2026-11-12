//
//  ClaudeNoticeView.swift
//  Aris
//
//  "Done", an error or a plan limit, the way an Aris answer shows: the notch opens onto a tag saying whose and what
//  (the activity tag, settled) and the words in plain 15-point type, as tall as they need (long ones scroll).
//  A tap brings that session's terminal forward.
//

import SwiftUI

struct ClaudeNoticeView: View {
    let peek: ClaudePeek
    @ObservedObject private var store = ClaudeStore.shared
    @ObservedObject private var team = ArisTeamModel.shared

    /// One line that never wraps: a long session name is cut in the middle (ClaudeNoticeLabel).
    private var label: String { ClaudeNoticeLabel.text(for: peek) }

    private var text: String {
        if let message = peek.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty { return message }
        switch peek.kind {
        case .done: return ArisUIWords.text("작업을 마쳤어요.", "The job is done.")
        case .error: return ArisUIWords.text("작업 중에 오류가 났어요.", "The job hit an error.")
        case .limit: return ArisUIWords.text("한도가 얼마 안 남았어요.", "The limit is nearly used up.")
        }
    }

    private var session: ClaudeSession? { peek.sessionId.flatMap { store.sessions[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // About Claude Code, so it wears Claude Code's face (N8): the header keeps Aris's.
            ArisActivityTag(label: label, done: peek.kind == .done, failed: peek.kind == .error, look: team.claudeLook)
                .padding(.horizontal, ArisActivityTag.rowInset)
            ArisAnswerText(text: text, budget: 220)
        }
        .frame(width: ArisGlass.contentWidth, alignment: .leading)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let session else { return }
            TerminalFocus.focus(session, cwd: session.cwd)
            store.dismissPeek()
        }
    }
}
