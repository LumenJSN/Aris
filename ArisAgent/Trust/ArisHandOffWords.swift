//
//  ArisHandOffWords.swift
//  aris-agent
//
//  A hand-off call as its card reads it back (ArisHandOffCard; twelfth VM run, B1: Core 2's Aside card read "보내기"
//  with no brief and the id "aris.aside_task"): where its words go, in plain words, and those words exactly as the
//  carrier hands them over, the rule about paying appended where it appends it:
//    aside <brief>                        ArisAsideTool: bounded, always
//    task add <id> <note>                 ArisTaskTool: the note as it is added to the job
//    schedule add --title --prompt <when> ArisScheduler: bounded, always (in the job's language)
//    routine add --name --step…           ArisRoutineTool: the steps as they are kept
//    session send <which> <text>          ArisSessionSend: the rule on the same line when it or the request is about paying
//    session start <folder> <text> --tool ArisTeammateGate.handed: bounded when it or the request is about paying
//  Nil for any other call. The card's lines are in the UI's language.
//

import Foundation

enum ArisHandOffWords {
    static func read(argv: [String]?, request: String, uiEnglish: Bool = ArisSkillLanguage.english, calendar: Calendar = .current,
                     now: Date = Date()) -> ArisHandOffFacts? {
        guard let argv, let tool = argv.first else { return nil }
        let rest = Array(argv.dropFirst())
        let english = ArisScheduleCard.isEnglish(request)
        func facts(_ korean: String, _ englishTarget: String, spoken: String, spokenEnglish: String, text: String, notes: [String] = []) -> ArisHandOffFacts {
            ArisHandOffFacts(target: uiEnglish ? englishTarget : korean, spoken: uiEnglish ? spokenEnglish : spoken, text: text, notes: notes, english: uiEnglish)
        }
        switch (tool, rest.first ?? "") {
        case ("aside", _):
            let brief = rest.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !brief.isEmpty else { return nil }
            return facts("브라우저 도우미 Aside에게 맡기기", "Hand to Aside, your browser helper", spoken: "Aside에게 이 일을 맡길까요?",
                         spokenEnglish: "Hand this to Aside?", text: ArisPaymentBoundary.bounded(brief, english: ArisDesktopCopy.isEnglish(request)))
        case ("task", "add"):
            guard rest.count >= 3 else { return nil }
            let note = rest.dropFirst(2).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return facts("진행 중인 백그라운드 작업에 지시 더하기", "Add to a background job's instructions", spoken: "진행 중인 작업에 이 지시를 더할까요?",
                         spokenEnglish: "Add this to the job's instructions?", text: note)
        case ("schedule", "add"):
            guard let parsed = try? ArisScheduleArguments.parse(Array(rest.dropFirst()), now: now, calendar: calendar) else { return nil }
            let korean = !ArisScheduleCard.isEnglish(parsed.title + " " + parsed.prompt)
            let when = ArisScheduleCard.when(parsed.rule, english: uiEnglish, calendar: calendar)
            return facts("예약하기 · " + when, "Schedule · " + when, spoken: "\(when)에 하도록 예약할까요?", spokenEnglish: "Schedule this for \(when)?",
                         text: ArisPaymentBoundary.taskWords(parsed.prompt, task: true, english: !korean),
                         notes: [(uiEnglish ? "Title: " : "예약 이름: ") + parsed.title])
        case ("routine", "add"):
            guard case .add(let name, let steps)? = ArisRoutineTool.parse(rest) else { return nil }
            let lines = steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
            return facts("루틴 ‘\(name)’ 만들기", "Make the routine “\(name)”", spoken: "‘\(name)’ 루틴을 만들까요?", spokenEnglish: "Make the routine “\(name)”?",
                         text: lines.joined(separator: "\n"))
        case ("session", "send"):
            guard rest.count >= 3 else { return nil }
            let which = rest[1], text = rest.dropFirst(2).joined(separator: " ")
            return facts("Claude Code 세션 ‘\(which)’에 입력하기", "Type into the Claude Code session “\(which)”", spoken: "‘\(which)’ 세션에 이대로 입력할까요?",
                         spokenEnglish: "Type this into the session “\(which)”?",
                         text: ArisPaymentHandOff.sessionWords(text, request: request, english: english))
        case ("session", "start"):
            guard rest.count >= 3 else { return nil }
            let folder = rest[1]
            var words = Array(rest.dropFirst(2))
            var codex = false
            if let flag = words.firstIndex(of: "--tool") {
                codex = words.indices.contains(flag + 1) && words[flag + 1] == "codex"
                words.removeSubrange(flag..<min(words.count, flag + 2))
            }
            let instruction = words.joined(separator: " ")
            let agent = codex ? "Codex" : "Claude Code"
            let paying = ArisPaymentBoundary.involves(instruction) || ArisPaymentBoundary.involves(request)
            return facts("‘\(folder)’ 폴더에서 새 \(agent) 세션 시작하기", "Start a new \(agent) session in “\(folder)”",
                         spoken: "‘\(folder)’ 폴더에서 \(agent)에게 이 일을 맡길까요?", spokenEnglish: "Start \(agent) in “\(folder)” with this?",
                         text: paying ? ArisPaymentBoundary.bounded(instruction, english: english) : instruction)
        default:
            return nil
        }
    }
}
