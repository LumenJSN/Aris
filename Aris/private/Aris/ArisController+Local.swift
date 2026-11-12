//
//  ArisController+Local.swift
//  Aris
//
//  The everyday requests Aris does itself, each said from what really happened (audit turn-1; the lines are
//  ArisLocalReply's): the time and date, the timer, opening an app, a to-do added or ticked. Nothing here is said
//  before it was done, a change is logged for undo only when it happened, and a turn that was stopped while one of
//  these waited does nothing more (audit turn-2).
//

import AppKit
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisJobSpec {
    /// The same job with `request` as what it is asked: the user's words and the files they gave with them.
    func asking(_ request: String) -> ArisJobSpec {
        ArisJobSpec(title: title, prompt: request.trimmingCharacters(in: .whitespacesAndNewlines), assignee: assignee, cwd: cwd, appHint: appHint)
    }
}

extension ArisController {
    /// A local reply: on the notch, in the history the AI reads and the 기록 list, then said. `shown`: what the notch
    /// shows and the voice reads when it isn't what is remembered (the to-do list itself, whose titles stay out of
    /// the history).
    func sayLocal(_ reply: String, heard: String, showing shown: String? = nil) async {
        let said = shown ?? reply
        stats?.firstSound(at: .now)
        session = session.answering(said)
        recordTurn(heard: heard, reply: reply)
        // Said without its way through Settings when the line has a button for that (ArisFixSpeech).
        await speak { await self.speaker.speak(ArisFixSpeech.spoken(said)) }
    }

    /// The time, the date, a timer request or opening an app, done; what to say about it. Nil when it is none of
    /// these, or names an app this Mac doesn't have (the AI's, then).
    func doOnMac(_ intent: ArisIntent, korean: Bool) async -> String? {
        switch intent {
        case .tellTime, .tellDate:
            return intent.acknowledgement(korean: korean)
        case .openApp(let name):
            guard let url = Self.application(named: name) else { return nil }
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return intent.acknowledgement(korean: korean)
            } catch {
                log.error("couldn't open \(name, privacy: .public): \(String(describing: error), privacy: .public)")
                return ArisLocalReply.appNotOpened(ArisIntent.displayName(name, korean: korean), korean: korean)
            }
        case .arisMute(let mute):
            return switchMute(mute, korean: korean)
        case .quietHours(let stored):
            return setQuietHours(stored, korean: korean)
        default:
            return changeTimer(intent, korean: korean)
        }
    }

    /// A spoken timer request against the timer as it is (ArisTimerChange): "타이머 멈춰" with none running says so
    /// and changes nothing.
    private func changeTimer(_ intent: ArisIntent, korean: Bool) -> String? {
        let timer = ArisTimerModel.shared
        guard let change = ArisTimerChange.plan(intent, running: timer.isRunning, paused: timer.state?.isPaused == true, korean: korean) else { return nil }
        guard change.applies else { return change.reply }
        switch intent {
        case .timer(let seconds, let focus): timer.start(seconds: seconds, focus: focus)
        case .pomodoro: timer.startPomodoro()
        case .cancelTimer: timer.cancel()
        case .pauseTimer: timer.pause()
        case .resumeTimer: timer.resume()
        case .addTime(let seconds): timer.add(seconds)
        default: break
        }
        if let logged = change.logged { ArisAgentClient.logLocalChange(kind: logged.kind, summary: logged.summary) }
        return change.reply
    }

    /// "할 일 추가해 …": how it ended. A saved item is logged with its undo.
    func addTodo(_ item: String) async -> ArisTodoAdded {
        let outcome = await ArisTodoModel.shared.addSaying(item)
        if case .saved(let title, let id) = outcome {
            ArisAgentClient.logLocalChange(kind: "todo-add", summary: "할 일 추가: \(title)", id: id)
            return .saved(title: title)
        }
        return outcome.told
    }

    /// "<…> 다 했어" for the open item it names: on a hands-free turn asked on a card first (naming the item), then
    /// ticked, and said from whether it was.
    func finishTodo(_ found: ArisTodoModel.Finishable, heard: String, korean: Bool) async -> String {
        if turnHandsFree, !(await confirmHandsFree(korean ? "할 일 완료" : "Finish to-do", found.shown)) {
            return await saidNotDone(korean: korean)
        }
        guard !Task.isCancelled else { return "" }
        let reply: String
        if let ticked = await ArisTodoModel.shared.finish(found) {
            if let id = ticked.id { ArisAgentClient.logLocalChange(kind: "todo-done", summary: "할 일 완료: \(ticked.title)", id: id) }
            reply = ArisIntent.finishTodo(ticked.title).acknowledgement(korean: korean) ?? ""
        } else {
            reply = ArisLocalReply.todoNotTicked(found.shown, why: ArisReminders.shared.lastError, korean: korean)
        }
        guard !Task.isCancelled else { return "" }
        await sayLocal(reply, heard: heard)
        return reply
    }
}
