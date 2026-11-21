//
//  ArisController+TurnRuns.swift
//  Aris
//
//  What each claim of the answer() funnel does (ArisTurnFunnel): the branches of answer()'s old chain, one case each,
//  as they were. Each says what it understood first (the turn's record), then does it; the reply it returns is
//  recorded by answer(). Nil: the turn ended inside it (it failed, was stopped, or ended the turn itself).
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// The to-do replies (added, ticked, read, why not) are Aris's own lines, in the language of the request like the rest.
    static var todoKorean: Bool { replyKorean }

    /// Every line Aris says for a claim it answers itself (the timer, the time, an app opened, undo, a hand-off's
    /// line…) is in the language of the request, as the model's answers are (tenth VM run, English UI: "지금 몇 시야?"
    /// was answered "It's 3:10 AM.", "볼륨 30으로 해 줘" "Volume set to 30."); a request that shows no language, and
    /// anything shown with the UI's own buttons (a card), keeps the UI's (ArisReplyLanguage). His own titles, names
    /// and values stay as given.
    static var replyKorean: Bool { ArisReplyLanguage.korean(uiEnglish: ArisUIWords.english) }

    func run(_ claim: ArisTurnClaim, _ request: ArisTurnRequest) async -> String? {
        // The turn's own words decide the language of every line said for it (replyKorean).
        ArisReplyLanguage.heard(request.heard?.unmarked ?? request.said)
        if case .practice = claim { return await runPractice(request.said) }
        guard let heard = request.heard else { return nil }
        if case .done = claim { return runDone(heard) }
        let reading = request.reading ?? ArisTurnRequest.Reading.make(heard, routed: nil)
        let text = heard.text, unmarked = heard.unmarked, tier = reading.tier, korean = Self.replyKorean
        switch claim {
        case .practice, .done:
            return nil
        case .madeCard(let yes):
            // "응" or "아니" while the new-teammate card is up answers the card, never the brain (BUG-25c).
            understood(text, path: "local", tier: tier)
            return await answerMadeCard(yes)
        case .skillLink(let link):
            // "이 링크 스킬 추가해줘 <link>": Aris does it itself, no brain; the notch shows each step (ArisSkillFlowCard), and
            // the check goes on in aris-agent when the notch closes (the inbox says how it ended).
            understood(text, path: "local", tier: tier)
            let line = korean ? "스킬을 확인할게요." : "I'll check that skill."
            ArisSkillsModel.shared.startNotchFlow(request: session.heard, link: link)
            let reply = korean ? "스킬 추가를 시작했어요." : "Started adding the skill."
            await sayLocal(reply, heard: unmarked, showing: line)
            return reply
        case .removeTeammate(let removal):
            // "큐에이봇 팀원 지워 줘": asked with the settings' 빼기 card, removed only on yes; never a job (BUG-26).
            understood(text, path: "local", tier: tier)
            return await removeTeammate(removal)
        case .makeTeammate(let making):
            // "문서 정리하는 팀원 하나 만들어줘, 이름은 코디": made here, no brain; the notch shows it (ArisTeammateMadeCard).
            understood(text, path: "local", tier: tier)
            return await makeTeammate(making)
        case .handOff(let handing):
            // "아니 그냥 클로드 시켜": that AI (or teammate) takes the request as a background job; an AI that isn't set up
            // here is said as exactly that (ArisController+BrainHandOff).
            understood(text, path: "task:handoff", tier: tier)
            return await handOver(handing, words: unmarked, whole: heard.whole, tier: tier, brain: heard.brain, korean: korean)
        case .teammate(let job):
            // "큐에이봇, 17 곱하기 23은?": the teammate called by name takes it, on its own brain (BUG-25b), with the files
            // The user gave.
            understood(text, path: "task:teammate", tier: tier)
            return await handOutNow([job], words: unmarked, recorded: unmarked, brain: heard.brain, tier: tier, korean: korean, browser: false)
        case .currency(let fx):
            // The rate of exactly that pair, read through aris-agent; the line and the card are one number (ArisController+Currency).
            understood(text, path: "local", tier: tier)
            return await answerCurrency(fx, heard: unmarked, korean: korean)
        case .memoryImport(let asked):
            // "다른 AI에서 기억 가져올래": the import opens in Settings › 기억 (no AI); a named AI only fills in where it comes from.
            understood(text, path: "local", tier: tier)
            ArisMemoryImportModel.openFromWords(source: asked.source)
            let reply = ArisMemoryImportWords.reply(korean: korean)
            await sayLocal(reply, heard: unmarked)
            return reply
        case .modelChange(let command):
            // The 대화 model or effort, set on the Mac (ArisController+ModelVoice).
            return await changeModel(command, text: text, heard: unmarked, brain: heard.brain, tier: tier, korean: korean)
        case .timerLeft:
            understood(text, path: "local", tier: tier)
            let reply = ArisTimerModel.shared.leftLine(korean: korean)
            await sayLocal(reply, heard: unmarked)
            return reply
        case .listTodos:
            understood(text, path: "local", tier: tier)
            // The to-do lines are Aris's own, whole in one language (third VM run: an English Mac asked in Korean
            // said the Reminders path in English inside a Korean sentence): the request's. Titles stay as written.
            let korean = Self.todoKorean
            // The first use asks macOS (its line of why in the turn, then the dialog) before the list is read.
            await ArisTodoModel.shared.askFirstIfNeverAsked()
            // Nil: the list could not be read (Reminders is off for Aris), and Aris says that, never "비어 있어요".
            let read = await ArisTodoModel.shared.summary(korean: korean)
            guard !Task.isCancelled else { return nil }
            // Canvas titles are other people's words: what's remembered for the AI is just that the list was read.
            let reply = read == nil ? ArisLocalReply.todosUnread(korean: korean) : korean ? "할 일 목록을 읽어 줬어요." : "Read out the to-do list."
            await sayLocal(reply, heard: unmarked, showing: read)
            return reply
        case .addTodo(let item):
            understood(text, path: "local", tier: tier)
            let korean = Self.todoKorean
            // Said from what Reminders did with it (audit turn-1), and logged with its undo only when it was saved, so
            // "방금 한 거 되돌려" takes it back (QA BUG-18). The first use asks macOS first (VM run 2026-11-19, A3).
            await ArisTodoModel.shared.askFirstIfNeverAsked()
            let reply = ArisLocalReply.todoAdded(await addTodo(item), korean: korean)
            guard !Task.isCancelled else { return nil }
            await sayLocal(reply, heard: unmarked)
            return reply
        case .finishTodo(let found):
            understood(text, path: "local", tier: tier)
            return await finishTodo(found, heard: unmarked, korean: Self.todoKorean)
        case .brief:
            understood(text, path: "local", tier: tier)
            guard await showBrief(inTurn: true) != nil else { return nil }
            // Canvas titles are other people's words: they stay out of the history the AI reads later.
            return ArisBrief.remembered(english: ArisUILanguage.english)
        case .dayEnd:
            // "오늘 정리해 줘": the day-end card, made here from the day's own records (ArisController+DayEnd).
            understood(text, path: "local", tier: tier)
            return await showDayEnd(heard: unmarked)
        case .undo:
            understood(text, path: "local", tier: tier)
            // Its one card names exactly what is undone (the newest of the kind the user named), on every path.
            answeredUndo = true
            return await undoLast(korean: korean, heard: unmarked)
        case .readAgain:
            understood(text, path: "local", tier: tier)
            return await readLastAnswer(heard: unmarked, korean: korean)
        case .saveAnswer(let save):
            understood(text, path: "local", tier: tier)
            return await saveLastAnswer(save, heard: unmarked, korean: korean)
        case .arrange(let app, let count):
            understood(text, path: "local", tier: tier)
            return await arrange(app, count: count, korean: korean)
        case .media(let media):
            // What Aris says comes from the player's answer: never "틀게요" when it didn't (QA BUG-37's follow-up).
            understood(text, path: "local", tier: tier)
            let done = await performMedia(media)
            guard !Task.isCancelled else { return nil }
            if done { resumeMusic = false }
            let reply = media.reply(done: done, korean: korean)
            await sayLocal(reply, heard: unmarked)
            return reply
        case .whatsPlaying:
            // "지금 무슨 노래야?": from what is playing, here (never the AI).
            understood(text, path: "local", tier: tier)
            let now = await ArisNowPlaying.shared.currentPlayback()
            guard !Task.isCancelled else { return nil }
            let reply = ArisIntent.nowPlayingLine(title: now?.title ?? "", artist: now?.artist ?? "", playing: now?.isPlaying ?? false, korean: korean)
            await sayLocal(reply, heard: unmarked)
            return reply
        case .control(let control):
            // Volume and brightness: said and logged from whether anything really moved (audit platform-1).
            understood(text, path: "local", tier: tier)
            let reply = await performControl(control, korean: korean)
            guard !Task.isCancelled else { return nil }
            await sayLocal(reply, heard: unmarked)
            return reply
        case .onMac(let intent):
            // The time, the date, the timer, opening an app: done here, and said from what happened (audit turn-1).
            // Nil only for an app gone since it was claimed: the brain's, as it was when the Mac had no such app.
            guard let said = await doOnMac(intent, korean: korean) else { return await run(.brain, request) }
            understood(text, path: "local", tier: tier)
            guard !Task.isCancelled else { return nil }
            await sayLocal(said, heard: unmarked)
            return said
        case .background(let browser):
            // "해 놔", "끝나면 알려줘", or several steps on websites (for Aside): the work goes to the background and
            // the conversation is free again.
            understood(text, path: browser ? "task:browser" : "task", tier: tier)
            return await handOutNow([], words: text, recorded: unmarked, brain: heard.brain, tier: tier, korean: korean, browser: browser)
        case .screen:
            log.notice("asking about the screen (\(tier.rawValue, privacy: .public))")
            understood(text, path: "screen", tier: tier)
            return await answerAboutScreen(text, tier: tier, brain: heard.brain)
        case .brain:
            let brain = heard.brain
            // Website work that names a service Aris reaches without a browser: the brain takes it with the order to try
            // (Aris's own tool, a connected service, Aside last) in its context (ArisServiceReach).
            if let line = ArisServiceReach.contextLine(reading.reached) {
                log.notice("website work by a service: \(reading.reached.map { "\($0.route.rawValue):\($0.name)" }.joined(separator: ","), privacy: .public)")
                turnPrograms = [turnPrograms, line].compactMap { $0 }.joined(separator: "\n")
            }
            // "sent", not "asking": aris-agent may still answer this one itself (it then says so: "aris-agent answers this itself").
            log.notice("sent to aris-agent for \(brain.rawValue, privacy: .public) (\(tier.rawValue, privacy: .public))")
            understood(text, path: "brain:\(brain.rawValue)", tier: tier)
            // With markers in the words, the agent matches policy against the unmarked ones.
            return await askAndSpeak(text, tier: tier, brain: brain, request: heard.shots ? heard.whole : nil)
        }
    }

    /// The onboarding's 물어보기: answered read-only here, nothing routed or done (QA BUG-31); files given to Aris stay
    /// pending for a real turn.
    private func runPractice(_ said: String) async -> String? {
        await answerPractice(said)
        return nil
    }

    /// A follow-up like "됐어" or "고마워" just ends the conversation; the answer before it stays parked.
    private func runDone(_ heard: ArisTurnRequest.Heard) -> String? {
        log.notice("follow-up: done")
        understood(heard.text, path: "done", tier: .quick)
        finishTurn("ok")
        // The answer before "됐어" stays parked, as after a follow-up that never came.
        if let answer = answerBeforeFollowUp { setSession(.parked(heard: answer.heard, reply: answer.reply)) } else { setSession(session.done()) }
        answerBeforeFollowUp = nil
        closeConversation(.donePhrase)
        resumeMusicIfPaused()
        return nil
    }

    /// Hands the work to the background (a teammate's job, or Aris's own) and says the line at once.
    private func handOutNow(_ jobs: [ArisJobSpec], words: String, recorded: String, brain: ArisBrain, tier: ArisTier, korean: Bool,
                            browser: Bool) async -> String {
        // Website work with no Aside on this Mac: not started, said at once with how to get it (twelfth VM run, A1: the
        // job waited ten minutes on a card nobody saw).
        if browser, await ArisAgentClient.asideInstalled() == false {
            let line = ArisHandoffLine.asideMissingLine(korean: korean)
            stats?.firstSound(at: .now)
            setSession(session.answering(line))
            recordTurn(heard: recorded, reply: line, job: nil)
            await speak { await self.speaker.speak(line) }
            return line
        }
        stats?.firstSound(at: .now)
        let handed = handOut(jobs, turn: ArisHandOutPlan.Turn(words: words, brain: brain, turnId: nil, screenConversation: screenConversation,
                                                              outsideConversation: outsideConversation, handsFree: turnHandsFree),
                             tier: tier, korean: korean, browser: browser)
        setSession(session.answering(handed.line))
        // One 기록 entry, updated with the job's result (BUG-21).
        recordTurn(heard: recorded, reply: handed.line, job: handed.job)
        await speak { await self.speaker.speak(handed.line) }
        return handed.line
    }
}
