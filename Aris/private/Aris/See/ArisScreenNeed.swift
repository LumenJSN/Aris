//
//  ArisScreenNeed.swift
//  Aris
//
//  Whether a turn's ask carries the screenshot (the owner, 2026-11-10): only when their words point at the screen ("이거
//  뭐야", "이 메일 답장 써줘", "화면 봐 줘", "여기 뭐야", "what's on my screen", "look at this"). A plain question
//  ("프랑스 수도가 어디야") captures nothing: no ScreenCaptureKit call, so no macOS notice and no recording dot, and
//  its request goes out without an image, so the brain that answers it isn't sealed for that. "이 노래", "이번 주",
//  "this week" and "이거 말고 타이머" are not the screen (ArisDeixis). Shots the user circled go as they always did and
//  stand in for the screenshot; files given to Aris are what "이거" means. With "질문할 때 화면 같이 보기" off, never.
//  A brain that needs the screen on any other turn looks for itself (aris-tools screen, desktop see).
//  Pure, so the tests run its table.
//

import Foundation

enum ArisScreenNeed {
    /// Whether the words point at what is on screen: a pointing word ("이거", "this") or asking Aris to look.
    static func pointsAtScreen(_ words: String) -> Bool {
        ArisDeixis.refersToScreen(words) || ArisDeixis.asksToLook(words)
    }

    /// Whether this turn takes the screenshot. `setting`: "질문할 때 화면 같이 보기". `drew`: the turn holds circled
    /// shots or a drawing, which go instead of it.
    static func captures(words: String, setting: Bool, drew: Bool) -> Bool {
        setting && !drew && pointsAtScreen(words)
    }
}
