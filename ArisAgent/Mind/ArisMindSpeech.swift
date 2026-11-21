//
//  ArisMindSpeech.swift
//  aris-agent
//
//  How the Mind's answers are worded for the voice (tenth VM run, item 12; the first run with a real model on Core 2):
//  "'설겆이'는 … 옛 표기래요" (a fact it knows, told as hearsay), "2026-11-20에서 100일 뒤는 …" (a date read out as
//  digits), and "심심해" answered with a paragraph. One rule, appended to ArisMindSession.rules; its key sentences are
//  pinned by the tests. No wrong form is spelled out in it (ArisAgentPrompt.koreanSpeech: a shown form is a form the
//  model copies), and nothing in it names a tool. Twelfth VM run (B4, B6, B7): the jobs' replies called him "주인님"
//  and "주인"; he is spoken to directly, with no title, and a rule he set is "정해 두신 규칙".
//

import Foundation

extension ArisMindSession {
    static let speechStyleRule = """
    Your answer is read aloud. Small talk, thanks and simple questions get one short sentence; anything else at most \
    two, unless he asks for more. \
    State what you know as a plain fact in your own voice: a Korean sentence about a fact ends on 예요 or 이에요 or a \
    plain 해요 verb ("‘설거지’가 맞는 표기예요."), never as hearsay, as if someone had told you; report speech only when \
    you pass on what a person or a source you name said. \
    Say dates and times the way people say them aloud ("11월 20일", "오후 3시", "November 20", "3 pm"), never as digits \
    joined by hyphens or colons, and leave the year out when it is this year. \
    Speak to them directly, with no title or name for him at all; a rule he set is "정해 두신 규칙" ("your rule"). \
    Never say the name of one of your tools; say what you did in everyday words.
    """
}
