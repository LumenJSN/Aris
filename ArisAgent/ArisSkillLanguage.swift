//
//  ArisSkillLanguage.swift
//  aris-agent
//
//  The language the skills' AI-written lines are asked for (VM run, bug 4: on an English Mac the 스킬 page's safety
//  findings and the skill maker's questions were Korean, because the helper's prompts asked for Korean). The helper
//  has no window and so no UI language of its own: the app says its language with every POST /skills ("lang": "en"
//  or "ko"), and the last one said is the one a review or a draft is written in, also for a check nobody asked for
//  just then (a folder that changed). Korean until the app has said otherwise, as it always was.
//

import Foundation

enum ArisSkillLanguage {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var saidEnglish = false

    /// "en" → true, "ko" → false; anything else says nothing.
    static func english(named raw: Any?) -> Bool? {
        switch raw as? String {
        case "en": true
        case "ko": false
        default: nil
        }
    }

    /// What the app's request says about its language, kept for the lines written after it.
    static func heard(_ raw: Any?) {
        guard let english = english(named: raw) else { return }
        lock.lock()
        defer { lock.unlock() }
        saidEnglish = english
    }

    /// The app reads English.
    static var english: Bool {
        lock.lock()
        defer { lock.unlock() }
        return saidEnglish
    }
}
