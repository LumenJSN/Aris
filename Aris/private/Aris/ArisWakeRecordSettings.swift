//
//  ArisWakeRecordSettings.swift
//  Aris
//
//  Settings › 대화 › 호출어 녹음: the rows that record the user's own calls for the trained wake word (ArisWakeScript, the
//  sheet ArisWakeRecordSheet), the opt-in 하루 소리 모으기 switch (ArisWakeCollect: off unless turned on, says it is on
//  and for how long, one tap turns it off) and 다 지우기 (asked twice). What they show comes in as plain values
//  (ArisWakeRecordSummary), and every line here has its English beside it. Foundation only (tested).
//

import Foundation

/// What the rows need to know.
struct ArisWakeRecordSummary: Equatable {
    /// Takes of 호출어 녹음 recorded, of all the script has (ArisWakeScript.totalTakes).
    var takes = 0
    var total = 0
    /// Clips 하루 소리 모으기 kept.
    var ambient = 0
    var bytes = 0
    var collecting = false
    var hoursLeft = 0
    /// 다 지우기 was pressed once: the second press erases.
    var confirmingClear = false

    var isEmpty: Bool { takes == 0 && ambient == 0 }
}

enum ArisWakeRecordRows {
    static let sectionID = "aris.record"

    static func section(_ s: ArisWakeRecordSummary, busy: Bool) -> ArisSettingSection {
        ArisSettingSection(id: sectionID, heading: "호출어 녹음", note: note, rows: [
            ArisSettingItem(id: "aris.recordCalls", icon: .symbol("mic"), title: "내 호출 녹음하기",
                            desc: s.takes == 0 ? "부르는 말 100번과 헷갈리는 말 70번을 차례로 녹음해요." : "\(s.takes)/\(s.total)개 녹음했어요.",
                            control: .buttons([ArisSettingButton(title: s.takes == 0 ? "녹음하기" : s.takes >= s.total ? "다시 녹음하기" : "이어서 녹음하기",
                                                                 action: .recordWakeCalls, enabled: !busy)])),
            ArisSettingItem(id: "aris.collect", icon: .symbol("audio-lines"), title: "하루 소리 모으기",
                            desc: s.collecting ? "모으는 중 · \(s.hoursLeft)시간 남음 · 조각 \(s.ambient)개" : "켜면 하루 동안 말소리와 이름 후보 앞뒤 몇 초씩만 남겨요.",
                            control: .toggle(.wakeCollect, s.collecting)),
            ArisSettingItem(id: "aris.recordClear", icon: .symbol("trash-2"), title: "녹음 다 지우기",
                            desc: s.isEmpty ? "남은 녹음이 없어요." : "녹음 \(s.takes)개 · 조각 \(s.ambient)개 · \(megabytes(s.bytes))",
                            control: s.confirmingClear
                                ? .buttons([ArisSettingButton(title: "취소", action: .keepWakeRecordings),
                                            ArisSettingButton(title: "정말 지우기", action: .clearWakeRecordings, kind: .danger)])
                                : .buttons([ArisSettingButton(title: "다 지우기", action: .clearWakeRecordings, kind: .danger, enabled: !s.isEmpty)]),
                            danger: true),
        ])
    }

    static let note = "녹음은 이 Mac의 Aris 폴더에만 남고 어디로도 보내지 않아요. 새 호출어 모델을 만들고 지금 방식과 견주는 데만 써요."

    /// "5.2 MB", "0.3 MB".
    static func megabytes(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

    /// The sheet's toast after 다 지우기.
    static let clearedToast = "녹음을 다 지웠어요"
    static let collectOffToast = "하루 소리 모으기를 껐어요"

    /// The ✦ menu's line while 하루 소리 모으기 is on (choosing it turns it off).
    static func menuLine(english: Bool) -> String {
        english ? "Collecting a day of sound — turn off" : "하루 소리 모으는 중 — 끄기"
    }

    // MARK: - The sheet's words

    enum Sheet {
        static let title = "호출어 녹음"
        static let intro = "화면에 나온 말을 하나씩 말해 주세요. 한 번에 2~3초씩 녹음하고, 언제든 멈췄다가 이어서 할 수 있어요."
        static let introPrivacy = "녹음은 이 Mac의 Aris 폴더에만 남아요. 설정의 다 지우기로 언제든 지울 수 있어요."
        static let start = "시작하기"
        static let resume = "이어서 하기"
        static let listening = "지금 말해 주세요"
        static let ready = "준비하세요"
        static let saved = "좋아요"
        static let stop = "멈추기"
        static let skip = "이 묶음 건너뛰기"
        static let again = "다시 녹음"
        static let close = "닫기"
        static let done = "다 녹음했어요. 고마워요!"
        static let doneLine = "이제 새 호출어 모델과 지금 방식을 이 녹음으로 견줘 볼 수 있어요."
        static let noHeadset = "AirPods가 연결돼 있지 않아요. 연결하거나 이 묶음을 건너뛰어 주세요."
        static let micFailed = "마이크를 열지 못했어요. 시스템 설정 › 개인정보 보호 및 보안 › 마이크에서 Aris를 켜 주세요."
        static let saveFailed = "녹음을 저장하지 못했어요."
        static let busy = "Aris가 다른 일을 하는 중이에요. 끝난 뒤에 해 주세요."
    }

    // MARK: - English

    static let english: [String: String] = [
        "호출어 녹음": "Record the wake word",
        note: "Recordings stay in Aris's folder on this Mac and are never sent anywhere. They are only used to build a new wake-word model and compare it with today's.",
        "내 호출 녹음하기": "Record my calls",
        "부르는 말 100번과 헷갈리는 말 70번을 차례로 녹음해요.": "Records 100 calls of the name and 70 words that sound like it, one after another.",
        "%d/%d개 녹음했어요.": "%d of %d recorded.",
        "녹음하기": "Record", "다시 녹음하기": "Record again", "이어서 녹음하기": "Continue recording",
        "하루 소리 모으기": "Collect a day of sound",
        "모으는 중 · %d시간 남음 · 조각 %d개": "Collecting · %d h left · %d clips",
        "켜면 하루 동안 말소리와 이름 후보 앞뒤 몇 초씩만 남겨요.": "When on, for one day only a few seconds around speech and possible calls are kept.",
        "녹음 다 지우기": "Delete all recordings",
        "남은 녹음이 없어요.": "No recordings left.",
        "녹음 %d개 · 조각 %d개 · %@": "%d recordings · %d clips · %@",
        "다 지우기": "Delete all", "정말 지우기": "Really delete", "취소": "Cancel",
        clearedToast: "Deleted all recordings", collectOffToast: "Collect a day of sound is off",
        Sheet.intro: "Say each line as it appears. Each take records 2–3 seconds, and you can stop and pick up again at any time.",
        Sheet.introPrivacy: "Recordings stay in Aris's folder on this Mac. Delete all in Settings removes them at any time.",
        Sheet.start: "Start", Sheet.resume: "Continue", Sheet.listening: "Say it now", Sheet.ready: "Get ready", Sheet.saved: "Got it",
        Sheet.stop: "Stop", Sheet.skip: "Skip this group", Sheet.again: "Record again", Sheet.close: "Close",
        Sheet.done: "All recorded. Thank you!", Sheet.doneLine: "The new wake-word model and today's can now be compared on these recordings.",
        Sheet.noHeadset: "AirPods aren't connected. Connect them or skip this group.",
        Sheet.micFailed: "Couldn't open the microphone. Turn Aris on in System Settings › Privacy & Security › Microphone.",
        Sheet.saveFailed: "Couldn't save the recording.", Sheet.busy: "Aris is busy with something else. Try again when it's done.",
        // ArisWakeTake's retry lines.
        "잘 안 들렸어요. 한 번 더 불러 주세요.": "I couldn't hear that. Once more, please.",
        "소리가 너무 커서 깨졌어요. 조금 떨어져서 다시요.": "That was too loud and distorted. Step back a little and try again.",
        "말이 잘렸어요. 숫자가 바뀐 뒤에 짧게 말해 주세요.": "It got cut off. Say it briefly right after the prompt appears.",
        // ArisWakeScript's blocks.
        "평소처럼": "As usual", "Mac 앞에서 평소에 부르듯이 불러 주세요.": "Call it the way you usually would, in front of the Mac.",
        "편하게": "Casually", "앞에 말을 붙이거나 영어로, 편하게 불러 주세요.": "Call it casually, with a word in front or in English.",
        "작게": "Quietly", "옆 사람이 깨지 않을 만큼 작게 불러 주세요.": "Call it quietly enough not to wake someone next to you.",
        "멀리서": "From afar", "Mac에서 2~3미터 떨어져서 불러 주세요. 화면의 숫자가 바뀌면 말하면 돼요.": "Stand 2–3 metres from the Mac. Speak when the count on screen changes.",
        "음악 틀고": "With music", "스피커로 음악을 평소 크기로 틀어 두고 불러 주세요.": "Play music through the speakers at your usual volume and call it.",
        "AirPods로": "With AirPods", "AirPods를 끼고 불러 주세요. 이 묶음만 AirPods 마이크로 녹음해요.": "Wear your AirPods and call it. This group alone records through the AirPods' microphone.",
        "부르고 바로 말하기": "Call and ask", "이름을 부르고 쉬지 않고 바로 이어서 말해 주세요.": "Call the name and go straight on with the request, without a pause.",
        "헷갈리는 말": "Words like it", "이번엔 이름이 아니에요. 화면에 나온 말을 평소처럼 말해 주세요.": "These aren't the name. Say each word on screen as you normally would.",
    ]
}
