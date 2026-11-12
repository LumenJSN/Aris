//
//  ArisController+RoutineStep.swift
//  Aris
//
//  A routine's step, done by the app itself when the same words typed would have been (ArisRoutineStepRule): the timer,
//  the time and date, the volume and brightness, the music, opening an app, Aris's own mute, a to-do added or ticked.
//  aris-agent offers the step on the turn's stream and waits; the app does it through the same functions a typed turn
//  uses (so each change is logged for undo as usual), and answers what happened. Nothing is shown or said for the step
//  itself: the routine's one account at the end carries its line, as it does an AI step's answer.
//

import Foundation
import os

private let stepLog = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisAgentClient {
    private static let routineStepURL = URL(string: "http://127.0.0.1:23351/routine-step")!

    /// A step the agent offered (ArisAgentClient's /ask stream): done or not by the controller, then answered. Sent
    /// with this app's pid and start time, as every /confirm is: only the app itself may answer for a step (ArisPeer).
    static func answerRoutineStep(_ step: ArisRoutineLocalStep) async {
        let outcome = await ArisController.shared.doRoutineStep(step.words)
        guard let token = ClaudeHookToken.load() else { return }
        var request = URLRequest(url: routineStepURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        var body = outcome.json
        body["id"] = step.id
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(body))
        let status = ((try? await URLSession.shared.data(for: request))?.1 as? HTTPURLResponse)?.statusCode
        if status != 200 { stepLog.error("routine step: the agent didn't take the answer (\(status ?? 0, privacy: .public))") }
    }
}

extension ArisController {
    /// One step of the routine this turn is running. `.notLocal` hands it back for the AI: the words are not the app's
    /// own to do, the typed path would give them to someone else first (a skill link, a teammate), or no turn is at
    /// work any more (the user stopped it).
    func doRoutineStep(_ words: String) async -> ArisRoutineLocalOutcome {
        guard session.phase == .thinking, !Task.isCancelled, let intent = ArisRoutineStepRule.act(for: words) else { return .notLocal }
        guard ArisSkillIntent.link(in: words) == nil, ArisTeamMaking.parse(words) == nil else { return .notLocal }
        if await teammateRemoval(words) != nil { return .notLocal }
        if await teammateCalled(words) != nil { return .notLocal }
        guard session.phase == .thinking, !Task.isCancelled else { return .notLocal }
        let korean = ArisSpeech.language(of: words) == "ko-KR"
        let outcome = await doRoutineAct(intent, korean: korean)
        switch outcome {
        case .notLocal: stepLog.notice("routine step: not the app's own")
        case .done: stepLog.notice("routine step: done by the app")
        case .failed(let line):
            stepLog.notice("routine step: tried by the app, not done")
            // The button the same line earns when typed (Reminders access, for one) stays under the routine's account.
            if let fix = ArisAppFix.fix(forLine: line) { ArisFixModel.shared.noted(fix) }
        }
        return outcome
    }

    private func doRoutineAct(_ intent: ArisIntent, korean: Bool) async -> ArisRoutineLocalOutcome {
        switch intent {
        case .timerLeft:
            return .done(ArisTimerModel.shared.leftLine(korean: korean))
        case .whatsPlaying:
            let now = await ArisNowPlaying.shared.currentPlayback()
            return .done(ArisIntent.nowPlayingLine(title: now?.title ?? "", artist: now?.artist ?? "", playing: now?.isPlaying ?? false, korean: korean))
        case .addTodo(let item):
            return ArisRoutineStepRule.added(await addTodo(item), korean: korean)
        case .finishTodo(let item):
            // Heard hands-free a tick is asked on a card first: inside a routine that stays the AI's gated turn. Only
            // an open item those words name exactly is ticked here, as when typed.
            guard !turnHandsFree, let found = await ArisTodoModel.shared.finishable(item) else { return .notLocal }
            guard let ticked = await ArisTodoModel.shared.finish(found) else {
                return .failed(ArisLocalReply.todoNotTicked(found.shown, why: ArisReminders.shared.lastError, korean: korean))
            }
            if let id = ticked.id { ArisAgentClient.logLocalChange(kind: "todo-done", summary: "할 일 완료: \(ticked.title)", id: id) }
            return .done(ArisIntent.finishTodo(ticked.title).acknowledgement(korean: korean) ?? "")
        case .media(let media):
            let done = await performMedia(media)
            if done { resumeMusic = false }
            return ArisRoutineStepRule.played(media, done: done, korean: korean)
        default:
            if let control = ArisControl(intent) {
                return ArisRoutineStepRule.ended(intent, reply: await performControl(control, korean: korean), korean: korean)
            }
            // The time, the date, the timer, Aris's own mute, an app this Mac has; anything else is the AI's.
            guard let said = await doOnMac(intent, korean: korean) else { return .notLocal }
            return ArisRoutineStepRule.ended(intent, reply: said, korean: korean)
        }
    }
}
