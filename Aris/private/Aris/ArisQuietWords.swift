//
//  ArisQuietWords.swift
//  Aris
//
//  The words of the mute and of quiet time: what the user says to mute Aris or let it speak again, and every line Aris
//  shows about it, in Korean and English. "조용히 해 줘", "음소거", "mute" mute Aris's own voice and chimes;
//  "이제 말해도 돼", "음소거 해제", "unmute" bring them back. Only a sentence that asks nothing else counts
//  (ArisIntentScope): "볼륨 음소거" and "소리 꺼" are still the Mac's volume, and "조용한 음악 틀어 줘" is the AI's.
//  Foundation only, so it is tested.
//

import Foundation

enum ArisQuietPhrase {
    /// Checked first: "음소거 해제" also holds "음소거".
    private static let unmute = ["음소거 해제", "음소거 풀어", "음소거 풀고", "음소거 꺼", "음소거 끄", "음소거 그만",
                                 "말해도 돼", "말해도 되", "말해도 좋아", "말해도 괜찮아", "소리 내도 돼", "소리내도 돼", "목소리 켜",
                                 "unmute", "mute off", "you can talk", "you can speak", "you may speak", "speak again", "talk again", "start talking"]
    private static let mute = ["조용히 해", "조용히 하", "조용히 있어", "조용히", "조용", "음소거", "목소리 꺼", "말 그만", "그만 말해", "쉿",
                               "mute", "be quiet", "quiet", "stop talking", "stop speaking", "silence", "hush", "shut up", "be silent", "go quiet", "go silent"]
    /// What may stand around them: Aris's name, "이제", "잠깐", a request's ending.
    private static let small = ["아리스", "이제", "이젠", "이제는", "지금", "지금은", "지금부터", "다시", "잠깐", "잠깐만", "잠시", "잠시만", "좀",
                                "해", "해줘", "해봐", "해라", "줘", "주세요", "줄래", "주실래요", "주시겠어요", "줄", "수", "있어", "있어요", "하자",
                                "모드", "로", "으로", "켜", "켜줘", "야", "요", "돼", "돼요", "응", "그래", "너", "넌", "는", "은", "도",
                                "aris", "hey", "please", "now", "again", "yourself", "the", "your", "voice", "mode", "for", "a", "while",
                                "ok", "okay", "go", "ahead", "and", "can", "could", "would", "will", "you", "just"]

    /// True: mute Aris. False: let it speak again. Nil: the words ask something else. `phrase`: as ArisIntent reads
    /// them (lowercased, end marks off).
    static func parse(_ phrase: String) -> Bool? {
        if ArisIntentScope.isOnly(phrase, about: unmute, with: small) { return false }
        if ArisIntentScope.isOnly(phrase, about: mute, with: small) { return true }
        return nil
    }
}

/// Every line Aris shows or says about the mute and quiet time. `english`: the turn's language for a reply, the app's
/// language (ArisUILanguage) for a label.
enum ArisQuietCopy {
    private static func text(_ korean: String, _ english: String, _ inEnglish: Bool) -> String { inEnglish ? english : korean }

    // MARK: Replies to "조용히 해 줘" and "이제 말해도 돼"

    /// What Aris answers, from what the switch was before: never "음소거했어요" for a mute that was already on.
    static func reply(mute: Bool, was: Bool, english: Bool) -> String {
        switch (mute, was) {
        case (true, false): return text("음소거했어요. 이제 글로만 답할게요.", "Muted. I'll answer in text from now on.", english)
        case (true, true): return text("이미 음소거 중이에요. 글로만 답하고 있어요.", "Already muted. I'm answering in text.", english)
        case (false, true): return text("이제 다시 소리 내서 말할게요.", "I'll speak out loud again.", english)
        case (false, false): return text("지금도 소리 내서 말하고 있어요.", "I'm already speaking out loud.", english)
        }
    }

    /// "읽어줘" while muted: nothing is read, and Aris says how to get it read.
    static func cannotRead(english: Bool) -> String {
        text("음소거 중이라 소리 내서 읽지 못해요. “이제 말해도 돼”라고 하면 읽어 드릴게요.",
             "I'm muted, so I can't read it aloud. Say “unmute” and I will.", english)
    }

    // MARK: Labels

    /// The one-time note under a voice turn while muted.
    static func notice(english: Bool) -> String { text("음소거 중이라 글로 답할게요", "Muted, so I'll answer in text", english) }
    /// The ✦ menu's item (ticked while muted) and the notch switch's tooltip.
    static func menuItem(english: Bool) -> String { text("음소거", "Mute", english) }
    static func switchHelp(muted: Bool, english: Bool) -> String {
        muted ? text("음소거 풀기 · 다시 소리 내서 말해요", "Unmute · Aris speaks again", english)
            : text("음소거 · 글로만 답해요", "Mute · answers in text only", english)
    }
    static func mutedLabel(english: Bool) -> String { text("음소거 중", "Muted", english) }

    // MARK: Settings rows

    static func muteTitle(english: Bool) -> String { text("음소거", "Mute", english) }
    static func muteDesc(english: Bool) -> String {
        text("켜면 소리 내서 말하지 않고 글로만 답해요. 카드는 클릭이나 Y/N으로 답하고, 효과음도 나지 않아요.",
             "When on, Aris answers in text only. Cards wait for a click or Y/N, and nothing chimes.", english)
    }
    static func hoursTitle(english: Bool) -> String { text("밤에는 조용히", "Quiet at night", english) }
    static func hoursDesc(english: Bool) -> String {
        text("이 시간과 화면이 잠겨 있을 때는 Aris가 먼저 꺼내는 소식을 소리 내지 않고 노치에 남겨 둬요. 직접 물어본 답과 맞춰 둔 타이머는 그대로 소리가 나요.",
             "In these hours, and while the screen is locked, news Aris brings up by itself stays silent in the notch. Answers to what you ask, and timers you set, still sound.",
             english)
    }
    static func hoursLabel(_ choice: String, english: Bool) -> String {
        switch choice {
        case ArisQuietHours.off: return text("끄기", "Off", english)
        case "22-7": return text("22–7시", "10pm–7am", english)
        case "0-8": return text("0–8시", "12am–8am", english)
        default: return text("23–7시", "11pm–7am", english)
        }
    }
}
