//
//  ArisMicInterruption.swift
//  Aris
//
//  What happens when the microphone changes or goes away while Aris listens (a headset connects, a device is
//  unplugged, a third format change in one turn). A turn with Aris goes on with the words heard so far; with nothing
//  heard it fails with a reason. A dictation is never a turn: what was dictated is typed where the cursor is (or
//  copied), and never reaches the AI as a request (audit voice-1: "그 파일 지워도 돼요", dictated into a chat while
//  AirPods connected, was answered and acted on as the user's own request). Pure, so the rule is tested without audio
//  hardware.
//

import Foundation

enum ArisMicInterruption: Equatable {
    /// Dictating, something said: the words so far are typed as if the key had been let go.
    case typeDictation
    /// Dictating, nothing said yet: the dictation ends and the notch says why.
    case endDictation
    /// A turn with words: they go on as the turn.
    case endTurn
    /// A turn with nothing heard: a failure line that says why.
    case failTurn

    /// `dictating`: the right ⌥ opened this microphone. `heardWords`: a recogniser wrote something. `heardVoice`: the
    /// level meter counted voice (a dictation types on either, ArisDictationEnd).
    static func outcome(dictating: Bool, heardWords: Bool, heardVoice: Bool) -> ArisMicInterruption {
        if dictating {
            return ArisDictationEnd.saidSomething(heardVoice: heardVoice, wroteWords: heardWords) ? .typeDictation : .endDictation
        }
        return heardWords ? .endTurn : .failTurn
    }

    /// The dictation's line when nothing was said before the microphone changed.
    static var dictationLine: String { dictationLine(english: ArisUIWords.english) }
    static func dictationLine(english: Bool) -> String {
        ArisUIWords.text("마이크가 바뀌어서 받아쓰기를 멈췄어요. 다시 눌러 주세요.", "The microphone changed, so dictation stopped. Press the key again.", english: english)
    }
}
