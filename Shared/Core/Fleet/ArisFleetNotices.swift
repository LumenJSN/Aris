//
//  ArisFleetNotices.swift
//  Shared/Core (app, tests)
//
//  Initiative: a session that starts waiting for the user (a permission, a question), fails, or finishes its turn
//  becomes one short spoken sentence ("3번 aris-jv-fleet 쪽이 권한을 기다려요: 테스트 실행", "2번 altswitch 쪽이 끝났어요").
//  Several within `window` seconds are one sentence; the same wait is never said twice (it is said again only after the
//  session worked in between). Said from structured fields only (the tool, the kind of command, the file's name), never
//  from a session's prose; what a command is said to be is only for the owner's ears (ArisFleetCommandWords). Sessions whose news Aris already says another way are left out: Aris's own teammates (their
//  job reports) and, for their finish, the sessions Aris typed a prompt into (ClaudeSessionWatch). Pure.
//

import Foundation

struct ArisFleetNotice: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case permission(ArisFleetPermission?)
        case question
        case failed
        case finished
    }
    let session: String
    let number: Int
    let project: String
    let kind: Kind
    /// What makes it the same news (never said twice).
    let key: String
}

/// What has been said and what waits to be said.
struct ArisFleetNoticeBook: Equatable, Sendable {
    /// Each session's last news said (its key).
    var said: [String: String] = [:]
    var pending: [ArisFleetNotice] = []
    var since: Date?
}

enum ArisFleetNotices {
    /// News this close together is said as one sentence.
    static let window: TimeInterval = 4

    /// The news in one step of the fleet. `quiet`: sessions whose news is said elsewhere; `quietFinish`: sessions whose
    /// finish is said elsewhere.
    static func news(from old: ArisFleet, to new: ArisFleet, home: String, quiet: Set<String> = [], quietFinish: Set<String> = []) -> [ArisFleetNotice] {
        new.live.compactMap { session in
            guard session.starter == .user, !quiet.contains(session.id) else { return nil }
            let before = old.session(session.id)
            let project = ArisFleetContext.project(session, home: home)
            func notice(_ kind: ArisFleetNotice.Kind, _ key: String) -> ArisFleetNotice {
                ArisFleetNotice(session: session.id, number: session.number, project: project, kind: kind, key: key)
            }
            switch session.state {
            case .waitingPermission:
                let fingerprint = session.pending?.fingerprint ?? "-"
                guard before?.state != .waitingPermission || before?.pending?.fingerprint != session.pending?.fingerprint else { return nil }
                return notice(.permission(session.pending), "permission:" + fingerprint)
            case .waitingInput:
                guard before?.state != .waitingInput else { return nil }
                return notice(.question, "question:" + (session.pending?.fingerprint ?? "\(session.lastActive.timeIntervalSince1970)"))
            case .failed:
                guard before?.state != .failed else { return nil }
                return notice(.failed, "failed:\(session.lastActive.timeIntervalSince1970)")
            case .idle:
                guard before?.state == .working, session.lastMessage != nil || session.heard, !quietFinish.contains(session.id) else { return nil }
                return notice(.finished, "finished:\(session.lastActive.timeIntervalSince1970)")
            case .working, .gone:
                return nil
            }
        }
    }

    /// The book with this news noted: a session's news already said or waiting is not taken again; a session that went
    /// back to work may be told about again.
    static func noting(_ news: [ArisFleetNotice], fleet: ArisFleet, at now: Date, in book: ArisFleetNoticeBook) -> ArisFleetNoticeBook {
        var next = book
        let working = Set(fleet.sessions.filter { $0.state == .working || $0.state == .gone }.map(\.id))
        next.said = book.said.filter { !working.contains($0.key) }
        // A session's older news still waiting gives way to its newer news.
        for notice in news where next.said[notice.session] != notice.key && !next.pending.contains(where: { $0.key == notice.key }) {
            next.pending = next.pending.filter { $0.session != notice.session } + [notice]
        }
        // News about a session that is working again or gone is stale before it is said.
        next.pending = next.pending.filter { notice in
            guard let session = fleet.session(notice.session) else { return false }
            return session.state.isLive && (session.state != .working)
        }
        next.since = next.pending.isEmpty ? nil : (book.since ?? now)
        return next
    }

    /// The sentence to say now (the window has passed since the first news waited), and the book after it is said.
    static func due(_ book: ArisFleetNoticeBook, at now: Date, korean: Bool) -> (sentence: String, book: ArisFleetNoticeBook)? {
        guard let since = book.since, !book.pending.isEmpty, now.timeIntervalSince(since) >= window else { return nil }
        var next = book
        for notice in book.pending { next.said[notice.session] = notice.key }
        next.pending = []
        next.since = nil
        return (sentence(book.pending, korean: korean), next)
    }

    // MARK: - Words

    static func sentence(_ news: [ArisFleetNotice], korean: Bool) -> String {
        let ordered = news.sorted { $0.number < $1.number }
        if ordered.count <= 2 {
            return ordered.map { korean ? full($0) : fullEnglish($0) }.joined(separator: korean ? ", " : "; ") + "."
        }
        let short = ordered.map { korean ? "\($0.number)번 \(shortKorean($0.kind))" : "number \($0.number) \(shortEnglish($0.kind))" }
        return korean ? "세션 \(ordered.count)개 소식이에요: " + short.joined(separator: ", ") + "."
            : "\(ordered.count) sessions: " + short.joined(separator: ", ") + "."
    }

    private static func full(_ notice: ArisFleetNotice) -> String {
        let who = "\(notice.number)번 \(notice.project) 쪽이"
        switch notice.kind {
        case .permission(let what):
            let said = describe(what, korean: true)
            return "\(who) 권한을 기다려요: \(said)" + (said.contains("요약할 수 없는") ? " (물어보시면 그대로 읽어 드릴게요)" : "")
        case .question: return "\(who) 답을 기다려요"
        case .failed: return "\(who) 오류로 멈췄어요"
        case .finished: return "\(who) 끝났어요"
        }
    }

    private static func fullEnglish(_ notice: ArisFleetNotice) -> String {
        let who = "Number \(notice.number) (\(notice.project))"
        switch notice.kind {
        case .permission(let what):
            let said = describe(what, korean: false)
            return "\(who) is waiting for permission: \(said)" + (said.contains("can't summarise") ? " (ask and I'll read it out)" : "")
        case .question: return "\(who) is waiting for your answer"
        case .failed: return "\(who) stopped on an error"
        case .finished: return "\(who) is done"
        }
    }

    private static func shortKorean(_ kind: ArisFleetNotice.Kind) -> String {
        switch kind {
        case .permission: return "권한 대기"
        case .question: return "답 대기"
        case .failed: return "오류"
        case .finished: return "끝남"
        }
    }

    private static func shortEnglish(_ kind: ArisFleetNotice.Kind) -> String {
        switch kind {
        case .permission: return "waits for permission"
        case .question: return "waits for an answer"
        case .failed: return "failed"
        case .finished: return "is done"
        }
    }

    /// What a permission is for, in a few words from the hook's structured fields: the kind of command, the file's name.
    static func describe(_ permission: ArisFleetPermission?, korean: Bool) -> String {
        guard let permission else { return korean ? "도구 사용" : "a tool" }
        switch permission.tool {
        case "Bash", "shell", "run_shell_command", "exec_command":
            return ArisFleetCommandWords.summary(permission.detail, korean: korean)
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            let file = ArisFleetContext.strict((permission.detail as NSString).lastPathComponent, limit: 40)
            return korean ? "파일 수정" + (file.isEmpty ? "" : " (\(file))") : "editing a file" + (file.isEmpty ? "" : " (\(file))")
        case "WebFetch", "WebSearch": return korean ? "웹 보기" : "a web lookup"
        case "ExitPlanMode": return korean ? "계획 승인" : "approving its plan"
        default: return ArisFleetContext.toolName(permission.tool, korean: korean)
        }
    }
}
