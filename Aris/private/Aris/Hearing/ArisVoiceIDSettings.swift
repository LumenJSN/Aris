//
//  ArisVoiceIDSettings.swift
//  Aris
//
//  Settings › Aris와 말하기 › 부르기, after 내 목소리 익히기 (F1): the switch (`arisOwnerVoice`, off by default), the enrolment sheet
//  (ArisVoiceEnrolSheet: five short sentences, about a minute) and 목소리 정보 지우기 (asked twice). What they show comes
//  in as plain values (ArisVoiceIDSummary); every line has its English beside it. Foundation only (tested).
//

import Foundation

/// What the rows need to know.
struct ArisVoiceIDSummary: Equatable {
    var on = false
    var enrolled = false
    /// Utterances the print was made from.
    var samples = 0
    /// The speaker model is in the app and loads.
    var available = true
    /// 지우기 was pressed once: the second press deletes.
    var confirmingForget = false

    var hasPrint: Bool { samples > 0 }
}

enum ArisVoiceIDRows {
    /// The rows, in 부르기's own section (호출어 녹음 stays right under it). One row teaches Aris the voice, both ways it
    /// learns it: the five sentences for 내 목소리만 듣기, and the wake word said a few times (`wakeTrained`). They were
    /// two rows, 내 목소리 익히기 and 내 목소리 등록하기, that read as the same thing (VM run 2026-11-18).
    static func rows(_ s: ArisVoiceIDSummary, busy: Bool, wakeTrained: Bool = false) -> [ArisSettingItem] {
        [
            ArisSettingItem(id: "aris.voiceID", icon: .symbol("person.wave.2"), title: "내 목소리만 듣기",
                            desc: switchLine(s), control: .toggle(.voiceID, s.on)),
            ArisSettingItem(id: "aris.voiceEnrol", icon: .symbol("mic"), title: learnTitle, desc: learnLine(s, wakeTrained: wakeTrained),
                            control: .buttons([ArisSettingButton(title: s.enrolled ? "더 들려주기" : "등록하기", action: .enrolVoice,
                                                                 enabled: s.on && s.available && !busy),
                                               ArisSettingButton(title: wakeTrained ? "호출어 다시 익히기" : "호출어 익히기", action: .trainVoice,
                                                                 enabled: !busy)])),
            ArisSettingItem(id: "aris.voiceForget", icon: .symbol("trash-2"), title: "목소리 정보 지우기",
                            desc: s.hasPrint ? "이 Mac의 키체인에만 있어요. 지우면 처음처럼 돼요." : "저장된 목소리 정보가 없어요.",
                            control: s.confirmingForget
                                ? .buttons([ArisSettingButton(title: "취소", action: .keepVoice),
                                            ArisSettingButton(title: "정말 지우기", action: .forgetVoice, kind: .danger)])
                                : .buttons([ArisSettingButton(title: "지우기", action: .forgetVoice, kind: .danger, enabled: s.hasPrint)]),
                            danger: true),
        ]
    }

    /// The one row's name.
    static let learnTitle = "내 목소리 익히기"

    /// What the row has learned so far, in one line.
    static func learnLine(_ s: ArisVoiceIDSummary, wakeTrained: Bool) -> String {
        switch (s.enrolled, wakeTrained) {
        case (true, true): "목소리를 등록했고 호출어도 익혔어요. 단축키를 누른 채 말할 때마다 조금씩 더 익혀요."
        case (true, false): "목소리를 등록했어요. 호출어도 익히면 내 목소리로 더 잘 깨어나요."
        case (false, true): "호출어는 익혔어요. 짧은 문장 다섯 개를 읽으면 내 목소리만 들을 수 있어요."
        case (false, false): "짧은 문장 다섯 개를 읽어 등록하고, 호출어를 몇 번 말해 익혀요. 1분이면 돼요."
        }
    }

    static func switchLine(_ s: ArisVoiceIDSummary) -> String {
        if !s.available { return "이 Mac에서 목소리 모델을 열지 못했어요." }
        if !s.on { return "켜면 이름을 부를 때와 ‘응’이라고 답할 때 내 목소리인지 확인해요." }
        return s.enrolled ? "다른 사람 목소리나 영상 소리로는 깨어나지 않고, ‘응’도 받지 않아요." : "목소리를 등록하면 확인하기 시작해요."
    }


    static let forgottenToast = "목소리 정보를 지웠어요"
    static let enrolledToast = "목소리를 등록했어요"

    // MARK: - The sheet's words

    enum Sheet {
        static let title = "내 목소리 등록하기"
        static let intro = "화면에 나오는 문장을 평소 말투로 하나씩 읽어 주세요. Mac 앞, 평소 자리에서 하면 돼요."
        static let introPrivacy = "녹음은 남기지 않아요. 목소리의 특징만 숫자로 이 Mac의 키체인에 저장하고, 어디로도 보내지 않아요. 내 목소리를 녹음해 틀면 통과할 수 있어서 잠금 장치는 아니에요."
        static let start = "시작하기"
        static let ready = "준비하세요"
        static let listening = "지금 읽어 주세요"
        static let saved = "좋아요"
        static let again = "잘 안 들렸어요. 한 번 더 읽어 주세요."
        static let stop = "멈추기"
        static let close = "닫기"
        static let learning = "목소리를 익히는 중이에요…"
        static let done = "등록했어요. 고마워요!"
        static let doneLine = "이제 다른 목소리로 부르거나 ‘응’이라고 해도 넘어가지 않아요. 단축키를 누른 채 말할 때마다 더 정확해져요."
        static let failed = "목소리를 익히지 못했어요. 조용한 곳에서 다시 해 주세요."
        static let micFailed = "마이크를 열지 못했어요. 시스템 설정 › 개인정보 보호 및 보안 › 마이크에서 Aris를 켜 주세요."
        static let busy = "Aris가 다른 일을 하는 중이에요. 끝난 뒤에 해 주세요."
    }

    /// The sentences read aloud: a call, requests and a spoken yes, the kinds of speech the print is compared with.
    static let sentences = [
        "아리스, 오늘 일정 알려 줘",
        "내일 아침 일곱 시에 알람 맞춰 줘",
        "엄마한테 조금 늦는다고 문자 보내 줘",
        "응, 그렇게 해 줘",
        "다운로드 폴더에 있는 사진 정리해 줘",
    ]

    static let englishSentences = [
        "Aris, what's on my calendar today",
        "Set an alarm for seven tomorrow morning",
        "Text Mom that I'm running a little late",
        "Yes, go ahead",
        "Tidy up the photos in my Downloads folder",
    ]

    // MARK: - English

    static let english: [String: String] = [
        "내 목소리만 듣기": "Only my voice",
        "이 Mac에서 목소리 모델을 열지 못했어요.": "Couldn't open the voice model on this Mac.",
        "켜면 이름을 부를 때와 ‘응’이라고 답할 때 내 목소리인지 확인해요.": "When on, Aris checks it is your voice when you call it and when you say yes.",
        "다른 사람 목소리나 영상 소리로는 깨어나지 않고, ‘응’도 받지 않아요.": "Other voices and video sound don't wake Aris, and their yes doesn't count.",
        "목소리를 등록하면 확인하기 시작해요.": "Checking starts once your voice is enrolled.",
        "내 목소리 등록하기": "Enroll my voice",
        learnTitle: "Learn my voice",
        "목소리를 등록했고 호출어도 익혔어요. 단축키를 누른 채 말할 때마다 조금씩 더 익혀요.":
            "Your voice is enrolled and the wake word learned. It learns a little more each time you talk holding the shortcut.",
        "목소리를 등록했어요. 호출어도 익히면 내 목소리로 더 잘 깨어나요.": "Your voice is enrolled. Learn the wake word too and Aris wakes to your voice better.",
        "호출어는 익혔어요. 짧은 문장 다섯 개를 읽으면 내 목소리만 들을 수 있어요.":
            "The wake word is learned. Read five short sentences and Aris can listen to your voice only.",
        "짧은 문장 다섯 개를 읽어 등록하고, 호출어를 몇 번 말해 익혀요. 1분이면 돼요.":
            "Read five short sentences to enroll, and say the wake word a few times to learn it. It takes a minute.",
        "호출어 익히기": "Learn the wake word", "호출어 다시 익히기": "Learn the wake word again",
        "등록했어요. 단축키를 누른 채 말할 때마다 조금씩 더 익혀요.": "Enrolled. It learns a little more each time you talk holding the shortcut.",
        "짧은 문장 다섯 개를 소리 내어 읽어 주세요. 1분이면 돼요.": "Read five short sentences aloud. It takes a minute.",
        "더 들려주기": "Add more", "등록하기": "Enroll",
        "목소리 정보 지우기": "Delete voice information",
        "이 Mac의 키체인에만 있어요. 지우면 처음처럼 돼요.": "It is only in this Mac's Keychain. Deleting it puts Aris back as it was.",
        "저장된 목소리 정보가 없어요.": "No voice information is saved.",
        "지우기": "Delete", "정말 지우기": "Really delete", "취소": "Cancel",
        forgottenToast: "Deleted your voice information", enrolledToast: "Your voice is enrolled",
        Sheet.intro: "Read each sentence on screen the way you normally talk, from where you usually sit at the Mac.",
        Sheet.introPrivacy: "Nothing is recorded. Only the voice's features are kept, as numbers, in this Mac's Keychain, and never sent anywhere. A recording of your voice can pass it, so it is not a lock.",
        Sheet.start: "Start", Sheet.ready: "Get ready", Sheet.listening: "Read it now", Sheet.saved: "Got it",
        Sheet.again: "I couldn't hear that. Once more, please.", Sheet.stop: "Stop", Sheet.close: "Close",
        Sheet.learning: "Learning your voice…", Sheet.done: "Enrolled. Thank you!",
        Sheet.doneLine: "Other voices calling Aris or saying yes won't get through now. It gets more accurate each time you talk holding the shortcut.",
        Sheet.failed: "Couldn't learn your voice. Try again somewhere quiet.",
        Sheet.micFailed: "Couldn't open the microphone. Turn Aris on in System Settings › Privacy & Security › Microphone.",
        Sheet.busy: "Aris is busy with something else. Try again when it's done.",
    ]
}
