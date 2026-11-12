//
//  ArisUsageTabState.swift
//  Aris
//
//  What the 사용량 tab shows when it has no limits to show. An empty list used to mean "still loading", so on a Mac
//  with no Claude Code, Codex or Antigravity the tab said "사용량을 불러오는 중…" for good (VM run 2026-11-10, bug 3).
//  Now the read itself has a state: it ends, with an answer or without one, and the tab says which.
//  Foundation only (tested).
//

import Foundation

/// How the latest read of the limits stands.
enum ArisUsageRead: Equatable {
    /// No read has ended yet, or the first answer still has an AI being asked.
    case waiting
    /// aris-agent answered and nothing is left to wait for.
    case answered
    /// aris-agent didn't answer within its limit (ArisUsagePatience.ask).
    case unanswered

    /// A new read begins: one that got no answer last time waits again (the tab says it is loading while "다시 읽기"
    /// works); one that settled stays as it is.
    var beginning: ArisUsageRead { self == .unanswered ? .waiting : self }

    /// After one ask. `asksAgain`: an AI was still pending and the app will ask once more (ArisUsagePatience.asksAgain).
    /// A read that had already settled stays settled while a later one waits, so the loading line never comes back.
    func after(answered: Bool, asksAgain: Bool) -> ArisUsageRead {
        guard answered else { return .unanswered }
        guard asksAgain else { return .answered }
        return self == .answered ? .answered : .waiting
    }
}

enum ArisUsageTabState: Equatable {
    /// The first read is on its way.
    case loading
    /// At least one AI's limits are known.
    case listed
    /// The read ended and no AI with a plan is on this Mac: one line and the way to Settings › AI 서비스.
    case none
    /// The read ended without an answer from aris-agent: one line and a way to try again.
    case unread

    static func of(hasProviders: Bool, read: ArisUsageRead) -> ArisUsageTabState {
        if hasProviders { return .listed }
        switch read {
        case .waiting: return .loading
        case .answered: return .none
        case .unanswered: return .unread
        }
    }
}

/// The tab's own lines, in the UI's language.
enum ArisUsageTabCopy {
    static func loading(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("사용량을 불러오는 중…", "Loading usage…", english: english)
    }

    static func none(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("이 Mac에 로그인된 Claude, Codex, Antigravity가 없어서 보여 줄 한도가 없어요.",
                         "Claude, Codex and Antigravity aren't signed in on this Mac, so there are no limits to show.", english: english)
    }

    static func unread(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("Aris 에이전트가 답하지 않아서 사용량을 읽지 못했어요.", "Aris's helper didn't answer, so the usage couldn't be read.", english: english)
    }

    static func retry(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("다시 읽기", "Read again", english: english)
    }
}
