//
//  ArisWakeStatus.swift
//  Aris
//
//  Why the wake word is or isn't listening, in one plain line (2026-11-18 audit: there was no way to see it): in
//  Settings › 부르기 under "“아리스”라고 부르기", and in 진단 내보내기's info.txt. A pure function of the detector's state
//  (the reason it isn't armed, ArisWakeArm.Blocker; whether its microphone is down; whether this Mac plays, and the
//  rule that holds then), so it is tested; ArisWakeStatusLive keeps the latest state for the window.
//

import Foundation

enum ArisWakeStatus {
    struct State: Equatable {
        var settingOn = false
        /// Why waitForWakeWord didn't arm it last time; nil: armed.
        var blocker: ArisWakeArm.Blocker?
        /// The microphone wouldn't open, or its checks couldn't listen, and it is being tried again (ArisWakeDown).
        var micDown = false
        /// This Mac played media or carried a call when last looked (ArisOtherAudio.macPlays).
        var playing = false
        /// A voice print is trained (the playback rule then: only a strong print).
        var trained = false
        /// Whisper is on this Mac (untrained, over playback it is the second listener).
        var whisperReady = false
    }

    static func line(_ state: State, english: Bool) -> String {
        func t(_ korean: String, _ en: String) -> String { english ? en : korean }
        guard state.settingOn else { return t("꺼져 있어요", "Off") }
        switch state.blocker {
        case .settingOff?: return t("꺼져 있어요", "Off")
        case .screenAway?: return t("화면이 잠겨 있어서 쉬고 있어요", "Paused: the screen is locked")
        case .permission?: return t("마이크나 음성 인식 권한이 없어서 못 들어요", "Not listening: microphone or speech recognition permission is missing")
        case .micInUse?, .otherAudio?: return t("다른 앱이 마이크를 쓰는 중이라 쉬고 있어요", "Paused: another app is using the microphone")
        case .lidClosed?: return t("덮개가 닫혀 있어서 쉬고 있어요", "Paused: the lid is closed")
        case .lowPower?: return t("저전력 모드라 쉬고 있어요", "Paused: Low Power Mode is on")
        case .headsetOnly?: return t("블루투스 헤드셋 마이크만 있어서 쉬고 있어요", "Paused: the only microphone is a Bluetooth headset's")
        case .speechModel?: return t("음성 인식 모델을 기다리는 중이에요", "Waiting for the speech recognition model")
        case .onboarding?: return t("처음 안내를 마치면 들어요", "Listens once the first-run guide is done")
        case .busy?, .training?, .listenerOpen?: return t("지금은 대화 중이에요", "In a conversation now")
        case nil: break
        }
        if state.micDown { return t("마이크를 열지 못해서 다시 시도하는 중이에요", "The microphone won't open; trying again") }
        guard state.playing else { return t("듣고 있어요", "Listening") }
        if state.trained {
            return t("듣고 있어요 · 다른 소리가 나는 동안엔 내 목소리가 또렷할 때만 깨어나요", "Listening · while other audio plays, only your own clear voice wakes it")
        }
        return state.whisperReady
            ? t("듣고 있어요 · 다른 소리가 나는 동안엔 두 번 확인한 뒤에 깨어나요", "Listening · while other audio plays, it wakes only once the name is heard twice over")
            : t("다른 소리가 나는 동안엔 깨어나지 않아요 · 내 목소리를 익히거나 Whisper를 받으면 돼요",
                "Paused while other audio plays · learn your voice or download Whisper to fix it")
    }

    /// The lines in English, for the settings window (ArisSettingsCopyMore).
    static var english: [String: String] {
        let states: [State] = [State()] + ([.screenAway, .permission, .micInUse, .lidClosed, .lowPower, .headsetOnly, .speechModel, .onboarding, .busy] as [ArisWakeArm.Blocker]).map {
            State(settingOn: true, blocker: $0)
        } + [State(settingOn: true, micDown: true), State(settingOn: true), State(settingOn: true, playing: true, trained: true),
             State(settingOn: true, playing: true, whisperReady: true), State(settingOn: true, playing: true)]
        return Dictionary(states.map { (line($0, english: false), line($0, english: true)) }, uniquingKeysWith: { first, _ in first })
    }
}
