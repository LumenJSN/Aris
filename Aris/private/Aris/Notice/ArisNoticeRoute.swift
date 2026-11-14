//
//  ArisNoticeRoute.swift
//  Aris
//
//  Which card each of Aris's own moments makes. These moments used to be a line in the notch (a job's result, a
//  timer, a problem with its button under it); now each is a card under the notch, with the same words and, for a
//  problem, the same fix on its blue button.
//  Confirm cards (send, write, delete) are not news: they stay in the notch. Foundation only (tested).
//

import Foundation

enum ArisNoticeRoute {
    /// The key of the helper's card: one at a time, gone once it answers again.
    static let helperKey = "helper"
    /// How long a timer's card may wait to be shown: as long as its line could (ArisTimerNews, ten minutes).
    static let timerShowsWithin = TimeInterval(ArisTimerNews.showsWithin.components.seconds)

    /// A handed-out job finished: its answer, and 보기 for the whole of it.
    static func jobDone(title: String, shown: String, job: UUID, english: Bool) -> ArisNotice {
        ArisNotice(kind: .done, title: title, body: plain(shown),
                   actions: [ArisNoticeAction(title: ArisNoticeWords.view(english: english), primary: true, role: .openJob(job))])
    }

    /// A job whose answer isn't a job done (it did nothing, only planned, or a step failed: ArisJobVerdict): a problem's
    /// card, never the green tick, with why and 다시 시도.
    static func jobNotDone(title: String, shown: String, job: UUID, english: Bool) -> ArisNotice {
        ArisNotice(kind: .problem, title: ArisJobVerdict.notDoneTitle(title, english: english), body: plain(shown),
                   actions: [ArisNoticeAction(title: ArisJobVerdict.retryTitle(english: english), primary: true, role: .retryJob(job))])
    }

    /// A job that didn't finish, with why.
    static func jobFailed(title: String, shown: String) -> ArisNotice {
        ArisNotice(kind: .problem, title: title, body: plain(shown))
    }

    /// Jobs the last run of the app left unfinished.
    static func lostJobs(title: String, said: String) -> ArisNotice {
        ArisNotice(kind: .problem, title: title, body: plain(said))
    }

    /// A teammate stopped on a question for the user.
    static func teammateAsks(title: String, said: String, english: Bool) -> ArisNotice {
        ArisNotice(kind: .incoming, title: title, body: plain(said), subtitle: ArisNoticeWords.asks(english: english))
    }

    /// What a scheduled job left in the inbox: a result (보기 for the saved rest, or the answer), a failure, a note.
    static func inbox(kind: String, title: String, shown: String, file: String?, english: Bool) -> ArisNotice {
        switch kind {
        case "failure":
            return ArisNotice(kind: .problem, title: title, body: plain(shown))
        case "result":
            let role: ArisNoticeAction.Role = file.map { .openFile($0) } ?? .openAnswer(question: title, text: shown)
            return ArisNotice(kind: .done, title: title, body: plain(shown),
                              actions: [ArisNoticeAction(title: ArisNoticeWords.view(english: english), primary: true, role: role)])
        default:
            return ArisNotice(kind: .system, title: title, body: plain(shown))
        }
    }

    /// A timer, a focus round or a break ran out.
    static func timer(title: String, text: String, at date: Date = Date()) -> ArisNotice {
        ArisNotice(kind: .reminder, title: title, body: text, posted: date, showsWithin: timerShowsWithin)
    }

    /// Something else Aris tells unasked (a teammate that couldn't be made).
    static func announcement(title: String, text: String, kind: ArisNoticeKind) -> ArisNotice {
        ArisNotice(kind: kind, title: title, body: plain(text))
    }

    /// One of the app's own lines with what fixes it (at launch: the helper's install, Full Disk Access after the
    /// switch, the old helper's rows, a build with no helper): the line as the body, the fix on the blue button (the
    /// same press the button under the line made). `title`: the line's own short form when it has one.
    static func problem(line: String, title: String? = nil, english: Bool) -> ArisNotice {
        // Asking again needs a request, and a card has none: only fixes that open or restart something.
        let fixes = ArisAppFix.fixes(forLine: line).filter { $0.kind != .retry && $0.kind != .otherBrain }
        let actions = fixes.first.map { [ArisNoticeAction(title: ArisFixWords.title($0, english: english), primary: true, role: .fixes(fixes))] } ?? []
        return ArisNotice(kind: .problem, title: title ?? ArisNoticeWords.needsYou(english: english), body: line, actions: actions)
    }

    /// The helper stopped answering and two quiet restarts didn't bring it back (the star dozes): 다시 시작 on the card.
    static func helperDown(english: Bool) -> ArisNotice {
        ArisNotice(key: helperKey, kind: .problem, title: english ? "Helper disconnected" : "에이전트 연결 끊김",
                   body: ArisNoticeWords.helperDownBody(english: english),
                   actions: [ArisNoticeAction(title: english ? "Restart" : "다시 시작", primary: true, role: .restartHelper)])
    }

    /// Whether the helper's link moving from `old` to `new` puts its card up (it began to doze), takes it away (it
    /// answers again), or leaves it.
    enum HelperCard: Equatable { case post, withdraw, keep }

    static func helperCard(from old: ArisAgentLink, to new: ArisAgentLink) -> HelperCard {
        if new.dozes && !old.dozes { return .post }
        if new == .up || new == .back { return .withdraw }
        return .keep
    }

    /// After a press on a problem's fix: the card with the next fix on its button, or nil when that was the last
    /// (the card goes, acted on).
    static func afterFix(_ notice: ArisNotice, pressed: Int, english: Bool) -> ArisNotice? {
        guard let action = notice.actions.first(where: { if case .fixes = $0.role { true } else { false } }),
              case .fixes(let fixes) = action.role, pressed < fixes.count else { return nil }
        var next = notice
        next.actions = notice.actions.map { $0 == action ? ArisNoticeAction(title: ArisFixWords.title(fixes[pressed], english: english), primary: true, role: action.role) : $0 }
        return next
    }

    /// Markdown as one paragraph for a card: no heading or list marks, no emphasis or code marks, lines joined.
    static func plain(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { line -> String in
            var line = line.trimmingCharacters(in: .whitespaces)
            while let first = line.first, "#>-*•".contains(first) { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty {
                line = String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            }
            return line
        }
        let joined = lines.filter { !$0.isEmpty }.joined(separator: " ")
        return joined.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "").replacingOccurrences(of: "`", with: "")
    }
}
