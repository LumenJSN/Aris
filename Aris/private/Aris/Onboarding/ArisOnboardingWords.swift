//
//  ArisOnboardingWords.swift
//  Aris
//
//  The setup's lines added after the VM run of 2026-11-11, each written in Korean and English where it is said (as
//  ArisPrerequisites' and ArisScreenPermissionNotice's are), in the onboarding's language (ArisOnboardingCopy.language).
//  They are not in Localizable.xcstrings: the catalog was being translated while these were written; they can move
//  there with ArisOnboardingCopy's. Here: the helper panel's; the Screen Recording card's are in
//  ArisOnboardingFirstCapture, the AI page's in ArisOnboardingBrainHelp. Pure, so the tests read both languages.
//

import Foundation

enum ArisSetupWords {
    /// The onboarding's language is anything but Korean.
    static var english: Bool { ArisOnboardingCopy.language != "ko" }

    static func say(_ korean: String, _ english: String, _ inEnglish: Bool) -> String { inEnglish ? english : korean }

    // MARK: - The helper panel beside System Settings

    /// The preview's own small copy of the panel: what to do with the row.
    static func dragShort(english: Bool = english) -> String { say("Aris를 목록으로 끌어다 놓기", "Drag Aris into the list", english) }

    // MARK: - The way back to a setup that was put off

    /// The ✦ menu's entry while the setup waits to be continued (its ×, Esc or 나중에 할게요 put it off).
    static func continueSetup(english: Bool = english) -> String { say("설정 안내 이어서 하기", "Continue setup", english) }
}
