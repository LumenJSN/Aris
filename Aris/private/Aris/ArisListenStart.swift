//
//  ArisListenStart.swift
//  Aris
//
//  Why listening can't start, said as what it really is (third VM run, new install, bug 4: on a Mac with no microphone
//  the try page said "The speech recognition model is still getting ready. Please say it again in a moment.", and the
//  Dictation page's button flipped to "Done talking" and back with no word). The model's line is true only when the
//  model is what is missing and a microphone is there to wait for it; with no input device at all, saying it again in
//  a moment changes nothing, so that is said first, with what to do. Foundation only, so it is tested.
//

import Foundation

enum ArisListenStart {
    enum Problem: Equatable {
        /// This Mac has no audio input device at all.
        case noMicrophone
        /// macOS's speech model for the language is still downloading.
        case modelPreparing
    }

    /// What stops a start. `usesMicrophone`: this start opens the microphone itself (false when it hears the wake
    /// detector's audio, which already has one). No microphone comes first: without one the model is no use yet.
    static func problem(usesMicrophone: Bool, hasMicrophone: Bool, modelMissing: Bool) -> Problem? {
        if usesMicrophone, !hasMicrophone { return .noMicrophone }
        return modelMissing ? .modelPreparing : nil
    }

    static func line(_ problem: Problem, english: Bool) -> String {
        switch problem {
        case .noMicrophone:
            return english ? "I can't find a microphone. Connect one, or pick one in System Settings › Sound › Input, and try again."
                : "마이크를 찾을 수 없어요. 마이크를 연결하거나 시스템 설정 › 사운드 › 입력에서 고른 뒤 다시 해 주세요."
        case .modelPreparing:
            return english ? "The speech recognition model is still getting ready. Please say it again in a moment."
                : "음성 인식 모델을 준비하는 중이에요. 잠시 뒤에 다시 말해 주세요."
        }
    }

    /// A line that is already a whole sentence of Aris's own about the microphone: shown without "I couldn't start
    /// listening: " in front of it.
    static func standsAlone(_ message: String) -> Bool {
        message == line(.noMicrophone, english: true) || message == line(.noMicrophone, english: false)
    }

    /// The sentence the setup's Dictation page shows under its note: what the notch says when a start failed, while
    /// it says so and no dictation runs; nil otherwise.
    static func shownOnPage(failed: Bool, reply: String, listening: Bool) -> String? {
        failed && !listening && !reply.isEmpty ? reply : nil
    }
}
