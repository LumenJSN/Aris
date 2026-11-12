//
//  ArisClaudeJobWords.swift
//  aris-agent
//
//  What a Claude Code job says when it can't open or doesn't go on, in English (VM run, bug 4: "Claude Code를 열지
//  않았어요." under an English request). The desk and the launcher write these lines in Korean where the reason is
//  found; every one leaves through the desk's one `finish`, which says it in English when the job's request has no
//  Korean (ArisGateWords.isEnglish, the rule every agent line follows: the agent can't know the Mac's language, so it
//  follows the request's). A folder's path, the system's own error text and a line this table doesn't know stay as
//  they are. Pure, so the tests run it.
//

import Foundation

enum ArisClaudeJobWords {
    /// Whole lines.
    static let lines: [String: String] = [
        "이 작업은 취소됐어요.": "This job was cancelled.",
        "Claude Code 프롬프트가 기호(-, !, / 같은)로 시작해서 열지 않았어요.": "Claude Code wasn't opened: its prompt starts with a symbol (such as -, ! or /).",
        "Claude Code 프롬프트가 프로젝트 밖 파일(@~, @/, @..)을 가리켜서 열지 않았어요. ‘@’ 없이 경로만 적어서 다시 맡겨 주세요.":
            "Claude Code wasn't opened: its prompt points at files outside the project (@~, @/, @..). Hand it over again with the paths written without “@”.",
        "Claude Code를 열지 않았어요.": "Claude Code wasn't opened.",
        "Claude Code가 그사이 바뀌어서 열지 않았어요. 다시 맡겨 주세요.": "Claude Code changed in the meantime, so it wasn't opened. Please hand the job over again.",
        "Claude Code 프롬프트가 가리키는 파일이 그사이 프로젝트 밖이 돼서 열지 않았어요.":
            "Claude Code wasn't opened: a file its prompt points at is now outside the project.",
        "하루가 지나서 이 Claude Code 작업은 더 기다리지 않아요.": "A day has passed, so Aris no longer waits for this Claude Code job.",
        "터미널을 열지 못했어요.": "Couldn't open the terminal.",
        "작업 폴더를 쓸 수 없어요.": "The work folder can't be used.",
        "터미널을 열 권한이 없어요. 시스템 설정 › 개인정보 보호 및 보안 › 자동화에서 Aris가 터미널을 제어하도록 켜 주세요.":
            "Aris isn't allowed to open the terminal. In System Settings › Privacy & Security › Automation, let Aris control the terminal.",
        "터미널을 찾지 못했어요.": "Couldn't find the terminal.",
        "터미널이 답하지 않아요. 자동화 권한 질문이 떠 있는지 확인해 주세요.": "The terminal isn't answering. Check whether a question about Automation is waiting on screen.",
    ]

    /// Lines that go on with a value (a path, the system's reason).
    static let leads: [(korean: String, english: String)] = [
        ("Claude Code를 열려던 폴더가 바뀌었거나 없어져서 열지 않았어요: ", "Claude Code wasn't opened: its folder changed or is gone: "),
        ("프롬프트 파일을 만들지 못했어요: ", "Couldn't make the prompt file: "), ("프롬프트 파일을 쓰지 못했어요: ", "Couldn't write the prompt file: "),
        ("터미널을 열지 못했어요: ", "Couldn't open the terminal: "),
    ]

    /// The one line with words on both sides of its value.
    private static let notAFolder = (lead: "Claude Code를 열 폴더가 아니에요: ", tail: " (없는 폴더이거나, 시스템 폴더나 Aris가 지키는 폴더예요)")

    static func english(_ korean: String) -> String {
        if let known = lines[korean] { return known }
        if korean.hasPrefix(notAFolder.lead), korean.hasSuffix(notAFolder.tail) {
            let folder = korean.dropFirst(notAFolder.lead.count).dropLast(notAFolder.tail.count)
            return "That isn't a folder Claude Code can open in: \(folder) (it doesn't exist, or it is a system folder or one Aris protects)"
        }
        if let lead = leads.first(where: { korean.hasPrefix($0.korean) }) { return lead.english + korean.dropFirst(lead.korean.count) }
        return korean
    }

    /// The line as the job's stream says it: in English for a request with no Korean.
    static func said(_ korean: String, english: Bool) -> String { english ? self.english(korean) : korean }
}
