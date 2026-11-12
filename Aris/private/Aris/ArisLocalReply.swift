//
//  ArisLocalReply.swift
//  Aris
//
//  What Aris says after an everyday request it does itself, worked out from what really happened (audit turn-1:
//  "할 일 추가해 우유 사기" answered "할 일에 넣었어요" with Reminders off and nothing saved; "타이머 멈춰" answered
//  "잠깐 멈췄어요" with no timer running). A reply must be true: done only when it was done, and otherwise what
//  stopped it and what the user can do. Foundation only, so it is tested.
//

import Foundation

/// How adding a to-do ended.
enum ArisTodoAdded: Equatable {
    case saved(title: String)
    /// Aris may not use Reminders (never asked from a turn: the guide and Settings ask).
    case noAccess
    /// The side panels' demo is showing: nothing real is written while it is.
    case demo
    /// The words named nothing to add.
    case noTitle
    /// Reminders did not save it; `why` is its own line when it gave one.
    case failed(why: String?)
}

enum ArisLocalReply {
    static func noRemindersAccess(korean: Bool) -> String {
        // The place is named as the settings window names it on this Mac (ArisSettingsPath), whatever the reply's language.
        let place = ArisSettingsPath.path(.todo, "미리 알림 접근")
        if korean { return "미리 알림 접근이 꺼져 있어요. \(place)에서 켜 주세요." }
        // On a Korean Mac the window's own names are Korean: the English sentence still says it is Settings.
        return "Aris can't use Reminders yet. Turn it on in " + (place.hasPrefix("Settings") ? place : "Settings (\(place))") + "."
    }

    /// "할 일에 넣었어요: 우유 사기" only for an item that was saved; otherwise why it wasn't.
    static func todoAdded(_ outcome: ArisTodoAdded, korean: Bool) -> String {
        switch outcome {
        case .saved(let title): return ArisIntent.addTodo(title).acknowledgement(korean: korean) ?? ""
        case .noAccess: return (korean ? "할 일에 넣지 못했어요. " : "I couldn't add it. ") + noRemindersAccess(korean: korean)
        case .demo: return korean ? "지금은 데모 화면이라 할 일에 넣지 않았어요." : "The demo is showing, so I didn't add it."
        case .noTitle: return korean ? "넣을 할 일을 못 알아들었어요. 다시 말해 주세요." : "I didn't catch what to add. Please say it again."
        case .failed(let why):
            // Reminders' own reason is written in Korean (ArisReminders.lastError); in English only that it failed.
            return korean ? "할 일에 넣지 못했어요." + (why.map { " " + $0 } ?? "") : "I couldn't add it to your to-dos."
        }
    }

    /// "할 일 뭐 있어" without Reminders access: never "할 일은 비어 있어요" for a list Aris could not read.
    static func todosUnread(korean: Bool) -> String {
        (korean ? "할 일을 읽지 못했어요. " : "I couldn't read your to-dos. ") + noRemindersAccess(korean: korean)
    }

    /// The item was found but Reminders would not tick it.
    static func todoNotTicked(_ title: String, why: String?, korean: Bool) -> String {
        korean ? "체크하지 못했어요: \(title)." + (why.map { " " + $0 } ?? "") : "I couldn't tick off \(title)."
    }

    /// "되돌려 줘" when aris-agent did not answer: not "되돌릴 일이 없어요", which Aris cannot know then.
    static func undoUnknown(korean: Bool) -> String {
        korean ? "한 일 기록을 읽지 못해서 되돌리지 못했어요. 잠시 뒤에 다시 말해 주세요."
            : "I couldn't read what I've done, so nothing was undone. Please try again in a moment."
    }

    static func noTimer(korean: Bool) -> String { korean ? "돌아가는 타이머가 없어요." : "No timer is running." }

    /// macOS did not open the app.
    static func appNotOpened(_ name: String, korean: Bool) -> String {
        korean ? "\(name) 앱을 열지 못했어요." : "I couldn't open \(name)."
    }
}

/// What a spoken change to the timer comes to, given the timer as it is now: whether anything is done, what Aris
/// says, and the activity log's line (so "방금 거 되돌려" takes back only a change that happened).
struct ArisTimerChange: Equatable {
    struct Logged: Equatable {
        let kind: String
        let summary: String
    }

    let applies: Bool
    let reply: String
    let logged: Logged?

    /// `running`: a timer exists (counting or paused); `paused`: it is paused. Nil for anything that isn't a timer request.
    static func plan(_ intent: ArisIntent, running: Bool, paused: Bool, korean: Bool) -> ArisTimerChange? {
        let said = intent.acknowledgement(korean: korean) ?? ""
        let none = ArisTimerChange(applies: false, reply: ArisLocalReply.noTimer(korean: korean), logged: nil)
        switch intent {
        case .timer(let seconds, _):
            return ArisTimerChange(applies: true, reply: said, logged: Logged(kind: "timer-set", summary: "타이머: \(max(1, seconds / 60))분"))
        case .pomodoro:
            return ArisTimerChange(applies: true, reply: said, logged: Logged(kind: "timer-set", summary: "뽀모도로"))
        case .cancelTimer:
            return running ? ArisTimerChange(applies: true, reply: said, logged: Logged(kind: "timer-cancel", summary: "타이머 끔")) : none
        case .pauseTimer:
            guard running else { return none }
            if paused { return ArisTimerChange(applies: false, reply: korean ? "타이머는 이미 멈춰 있어요." : "The timer is already paused.", logged: nil) }
            return ArisTimerChange(applies: true, reply: said, logged: nil)
        case .resumeTimer:
            guard running else { return none }
            if !paused { return ArisTimerChange(applies: false, reply: korean ? "타이머는 멈춰 있지 않아요. 그대로 가고 있어요." : "The timer isn't paused. It's still running.", logged: nil) }
            return ArisTimerChange(applies: true, reply: said, logged: nil)
        case .addTime:
            return running ? ArisTimerChange(applies: true, reply: said, logged: nil) : none
        default:
            return nil
        }
    }
}
