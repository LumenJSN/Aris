//
//  ArisAgentPrompt+Converse.swift
//  aris-agent
//
//  How a conversation brain talks when it is heard, and how it keeps track of the work it handed out: the spoken
//  style (for turns the app marks `asked: by voice` in the context; typed turns keep the rules as they were), the
//  sentence it says when it hands work out, and the <work> block with the `task` commands. Conversation brains only:
//  a background task's own prompt has none of this. Kept short, since every process start pays for it.
//

import Foundation

extension ArisAgentPrompt {
    /// The context line the app puts first in a spoken turn's context, and in a typed one's (ArisContext.asked).
    static let spokenMark = "asked: by voice"
    static let typedMark = "asked: typed"

    /// The spoken style: heard, not read (the owner, 2026-11-18: "it feels like the system assistant").
    /// The answer is a whole sentence in the language's own order, never the answer word pushed to the front: asked to
    /// put "the answer first" and "never restate the question", DeepSeek answered "프랑스의 수도는 어디야?" with "파리의요.",
    /// "파리의 수도예요." and "파리의 수도는… 아니, …" (VM runs 2026-11-19): the answer first, the question's frame after it.
    static let spokenRule = "When the context says `\(spokenMark)` you are heard, not read: answer in one to three short " +
        "sentences unless asked for more. Never add a preamble or close with an offer (\"무엇을 도와드릴까요\", " +
        "\"더 궁금한 거 있으면…\", \"Let me know if…\"); no URLs, file paths or symbols; times, dates and amounts as people say them " +
        "(\"세 시 반\", \"이번 주 목요일\", \"이만 삼천 원\", \"half past three\"). Don't apologise for limits you don't have. If the " +
        "request is truly ambiguous, ask one short question rather than guess. When something will take a moment, first say in a few " +
        "words what you're doing (\"메일 확인해 볼게요.\"). `\(typedMark)` turns are read on screen and keep the rules above as they are."

    /// What a conversation brain says when it hands work out (the jobs block follows it): one natural sentence of what
    /// is starting, so the user hears it at once and can carry on talking.
    static let handOutSentence = "Before the block, say one short natural sentence, in the user's language, of what you are starting " +
        "and that you'll tell them when it's done (\"네, 세 군데 비교해 보고 알려 드릴게요.\", \"On it, I'll compare the three and let you " +
        "know.\"); name who takes it when it isn't you. Nothing after the block: that sentence is all you say, and Aris says the result when it's done."

    /// The <work> block and the `task` commands (agy, through its relay, only reads the block).
    static func workRule(_ tools: String, form: DesktopForm) -> String {
        let reading = "Background tasks you handed out are in the <work> block when any run or just ended (id, title, state, last step, " +
            "how long, a card they wait on). \"어디까지 했어?\", \"how's that going?\": answer from it in a sentence or two, where it is and " +
            "what it waits on, never the id. A change to a running task is never a new job."
        guard form != .relay else { return reading + " You can't change a task from here: the user can stop it from the notch." }
        return reading + " `\(tools) task status <id>` gives its latest steps; `\(tools) task add <id> \"<what the user added, in their " +
            "words>\"` gives a running task an added instruction (say what it answers: taken now, or after its current step); " +
            "`\(tools) task cancel <id>` stops one (\"그거 취소해\": the one the user means; if two could fit, ask which). A running task " +
            "can't be paused: say so in a few words and offer to cancel it or add an instruction."
    }
}
