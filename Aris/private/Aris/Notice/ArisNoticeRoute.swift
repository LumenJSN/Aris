//
//  ArisNoticeRoute.swift
//  Aris
//
//  Which notice each moment makes. Aris's own used to be a line in the notch (a job's result, a timer, a problem with
//  its button under it); now each is a notice on the pill under the notch, with the same words and, for a problem, the
//  same fix on its main button. A deadline's alert (24 h and 3 h before) and a Claude Code session's done, error or
//  limit notice are notices on the same pill, with the words they had and what a click on them did.
//  Confirm cards (send, write, delete) are not news: they stay in the notch. Foundation only (tested).
//

import Foundation

enum ArisNoticeRoute {
    /// The key of the helper's card: one at a time, gone once it answers again.
    static let helperKey = "helper"
    /// How long a timer's card may wait to be shown: as long as its line could (ArisTimerNews, ten minutes).
    static let timerShowsWithin = TimeInterval(ArisTimerNews.showsWithin.components.seconds)
    /// Once seen, a finished timer's card goes by itself after a minute (twelfth VM run: it stayed up over nine minutes).
    static let timerShowsFor: TimeInterval = 60

    /// The deadline alert's key: one at a time, as ArisTodoModel keeps one alert at a time.
    static let deadlineKey = "deadline"
    /// A deadline's alert goes by itself after 8 s up, as the alert under the notch did.
    static let deadlineShowsFor: TimeInterval = 8
    /// A Claude Code notice's key: a newer one takes the place of the one up.
    static let claudeKey = "claude"
    /// A Claude Code notice goes by itself after 6 s up, as the notch it opened did (ClaudeStore's peek).
    static let claudeShowsFor: TimeInterval = 6

    /// A deadline coming up (ArisDueAlert: 24 h before, blue; 3 h before, red): the time left as its title ("23시간
    /// 남았어요"), the course and that it isn't handed in as its subtitle, what and when as its body ("PS3 · 내일"). A click
    /// opens its page and dismisses it (열기 when it has one); it waits no longer than the deadline.
    static func deadline(_ due: ArisDue, _ alert: ArisDueAlert, now: Date = Date(), english: Bool) -> ArisNotice {
        let left = ArisTodoWords.left(minutes: max(1, Int(due.at.timeIntervalSince(now) / 60)), english: english)
        let tag = ArisTodoWords.alertTag(due, shortCourse: ArisDue.shortCourse(due.course), english: english)
        let body = "\(due.title) · \(ArisNoticeWords.dueWhen(due.at, now: now, english: english))"
        let opens = due.url.flatMap(URL.init(string:))?.scheme == "https"
        let actions = opens ? [ArisNoticeAction(title: ArisNoticeWords.open(english: english), primary: true, role: .openDue(due))] : []
        return ArisNotice(key: deadlineKey, kind: .reminder, source: .deadline(alert), title: left, body: body, subtitle: tag, actions: actions,
                          posted: now, showsWithin: max(0, due.at.timeIntervalSince(now)), showsFor: deadlineShowsFor, tap: .openDue(due))
    }

    /// A Claude Code session's done, error or limit notice: its tag's words as the title ("my-app · 끝났어요"), its last
    /// message (or a plain line) as the body. A click brings that session's terminal forward and dismisses it.
    static func claude(_ peek: ClaudePeek, english: Bool) -> ArisNotice {
        let focus = peek.sessionId.map { ArisNoticeAction.Role.focusClaude(sessionId: $0) }
        let actions = focus.map { [ArisNoticeAction(title: ArisNoticeWords.openTerminal(english: english), primary: true, role: $0)] } ?? []
        let kind: ArisNoticeKind = peek.kind == .done ? .done : .problem
        return ArisNotice(key: claudeKey, kind: kind, source: .claude, title: ClaudeNoticeLabel.text(for: peek, english: english),
                          body: plain(ClaudeNoticeLabel.body(for: peek, english: english)), actions: actions, showsFor: claudeShowsFor, tap: focus)
    }

    /// A handed-out job finished: its answer, and 보기 for the whole of it.
    static func jobDone(title: String, shown: String, job: UUID, english: Bool) -> ArisNotice {
        ArisNotice(kind: .done, title: title, body: plain(shown),
                   actions: [ArisNoticeAction(title: ArisNoticeWords.view(english: english), primary: true, role: .openJob(job))])
    }

    /// A job whose answer isn't a job done (it did nothing, only planned, or a step failed: ArisJobVerdict): a problem's
    /// card, never the green tick, with why and 다시 시도; `answered`: it said something, which 보기 opens whole (a real
    /// failure's answer stays readable, never only the failure line).
    static func jobNotDone(title: String, shown: String, job: UUID, english: Bool, answered: Bool = false) -> ArisNotice {
        let retry = ArisNoticeAction(title: ArisJobVerdict.retryTitle(english: english), primary: true, role: .retryJob(job))
        let view = ArisNoticeAction(title: ArisNoticeWords.view(english: english), primary: false, role: .openJob(job))
        return ArisNotice(kind: .problem, title: ArisJobVerdict.notDoneTitle(title, english: english), body: plain(shown),
                          actions: answered ? [retry, view] : [retry])
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
        ArisNotice(kind: .reminder, title: title, body: text, posted: date, showsWithin: timerShowsWithin, showsFor: timerShowsFor)
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

    // MARK: - What it asks the interruption policy

    /// The notice as the interruption policy sees it (ArisInterruption): its kind, how urgent, whether it waits on an
    /// answer, and whether it has a line to say (`spoken`). A timer and a deadline three hours off are urgent; Aris's
    /// own word about itself and an update can wait.
    static func want(_ notice: ArisNotice, spoken: Bool) -> ArisInterruption.Want {
        switch notice.source {
        case .claude:
            return .init(kind: notice.kind == .problem ? .problem : .jobDone, spoken: spoken)
        case .deadline(let alert):
            return .init(kind: .deadline, urgency: alert == .hoursBefore ? .high : .normal, spoken: spoken)
        case .aris:
            switch notice.kind {
            case .reminder: return .init(kind: .timer, urgency: .high, spoken: spoken)
            case .incoming: return .init(kind: .teammateAsks, needsAnswer: true, spoken: spoken)
            case .done: return .init(kind: .jobDone, spoken: spoken)
            case .problem: return .init(kind: .problem, spoken: spoken)
            case .system: return .init(kind: notice.key == updateKey ? .update : .news, urgency: .low, spoken: spoken)
            }
        }
    }

    /// The update's notice key (ArisUpdateWords.key).
    static let updateKey = "update"
}
