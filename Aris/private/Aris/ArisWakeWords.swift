//
//  ArisWakeWords.swift
//  Aris
//
//  What the notch says while Aris learns its name (VM run, bug 4: on an English Mac the training's lines were Korean
//  under an English heading). Nobody asked anything just then, so the lines follow the Mac's language. The name is
//  written “아리스” in Korean and “Aris” in English: the same sound, in letters the reader knows; a name chosen in
//  Settings (ArisWakeName) is written as it was typed. Foundation only (tested).
//

import Foundation

enum ArisWakeWords {
    /// The first line: what to say.
    /// The name as the lines write it: “아리스” and “Aris”, or the one chosen in Settings (ArisWakeName) in both.
    private static func shown(english: Bool) -> String {
        let name = ArisWakeName.current
        return name.isDefault ? (english ? "Aris" : "아리스") : name.name
    }

    static func start(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("“\(shown(english: false))” 라고 불러줘", "Say “\(shown(english: true))”", english: english)
    }

    /// A phrase too short to be the name (too quiet), or too long.
    static func unclear(tooShort: Bool, english: Bool = ArisUIWords.english) -> String {
        tooShort ? ArisUIWords.text("잘 안 들렸어요. 조금 더 크게요.", "I couldn't hear that. A little louder.", english: english)
            : ArisUIWords.text("“\(shown(english: false))” 만 짧게 불러줘", "Say just “\(shown(english: true))”, short", english: english)
    }

    /// One more recording is needed.
    static func again(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("좋아요! 한 번 더요.", "Good! Once more.", english: english) }

    /// The recordings couldn't be made into a model: from the start.
    static func restart(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("다시 해볼게요. “\(shown(english: false))” 라고 불러줘", "Let's try again. Say “\(shown(english: true))”", english: english)
    }

    /// Trained: the notch's line, and the one Aris says out loud.
    static func done(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("다 됐어요! 이제 “\(shown(english: false))” 라고 불러줘", "All set! Now say “\(shown(english: true))”", english: english)
    }

    static func doneSpoken(english: Bool = ArisUIWords.english) -> String {
        ArisWakeName.current.isDefault ? ArisUIWords.text("다 됐어요! 이제 아리스라고 불러주세요.", "All set! Now just say Aris to call me.", english: english)
            : ArisUIWords.text("다 됐어요! 이제 \(shown(english: false)), 하고 불러주세요.", "All set! Now just say \(shown(english: true)) to call me.", english: english)
    }
}
