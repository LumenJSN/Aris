//
//  ArisFailure.swift
//  Aris
//
//  A failure Aris words itself. A LocalizedError, so wherever its localizedDescription reaches the notch it is the
//  message, never Foundation's "작업을 완료할 수 없습니다.(Aris.ArisFailure 오류 1.)" (QA BUG-3). And what the notch says
//  when listening couldn't start, in the UI's language (ArisUIWords). Pure, so the tests run it.
//

import Foundation

struct ArisFailure: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

enum ArisStartFailure {
    static var tookTooLong: String { tookTooLong(english: ArisUIWords.english) }
    static func tookTooLong(english: Bool) -> String {
        ArisUIWords.text("마이크를 여는 데 너무 오래 걸렸어요. 다시 해 주세요.", "The microphone took too long to open. Please try again.", english: english)
    }

    /// The notch's line when the microphone couldn't start; nil when the start was abandoned (the turn was cancelled
    /// meanwhile, as when a ⌥⇧ press turned out to be typing): nothing went wrong that the user should hear about.
    static func line(_ error: Error, timedOut: Bool, abandoned: Bool, english: Bool = ArisUIWords.english) -> String? {
        guard !abandoned else { return nil }
        // "I can't find a microphone. …" is the whole of it (ArisListenStart).
        if !timedOut, ArisListenStart.standsAlone(error.localizedDescription) { return error.localizedDescription }
        return timedOut ? tookTooLong(english: english)
            : ArisUIWords.text("듣기를 시작하지 못했어요: ", "I couldn't start listening: ", english: english) + error.localizedDescription
    }
}

/// The listener's own failure lines.
enum ArisListenerWords {
    /// macOS's speech model for the language is still downloading (a first run).
    static func modelPreparing(english: Bool = ArisUIWords.english) -> String {
        ArisListenStart.line(.modelPreparing, english: english)
    }

    /// This Mac has no audio input device: what it is, and what to do.
    static func noMicrophone(english: Bool = ArisUIWords.english) -> String {
        ArisListenStart.line(.noMicrophone, english: english)
    }
}

/// What the notch says when a turn can't start for want of a permission or a newer macOS, in the UI's language
/// (they used to be English only, and one Korean only).
enum ArisPermissionWords {
    static func turnOn(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("시스템 설정 › 개인정보 보호 및 보안에서 Aris의 마이크와 음성 인식을 켜 주세요.",
                         "Turn on Microphone and Speech Recognition for Aris in System Settings › Privacy & Security.", english: english)
    }
    static var turnOn: String { turnOn() }

    static func ready(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("준비됐어요. ⌥Space를 누르고 말해 주세요.", "Ready. Press ⌥Space and talk.", english: english)
    }
    static var ready: String { ready() }

    static func needsNewerMac(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("Aris는 macOS 26부터 쓸 수 있어요.", "Aris needs macOS 26 or later.", english: english)
    }
    static var needsNewerMac: String { needsNewerMac() }

    /// Training "아리스" before macOS has asked for the microphone.
    static func pressKeyFirst(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("먼저 ⌥Space를 한 번 눌러 주세요. macOS가 마이크 권한을 물어봐요.",
                         "Press ⌥Space once first, so macOS can ask for the microphone.", english: english)
    }
}
