//
//  ArisPrerequisites.swift
//  Aris
//
//  What an install must have, checked instead of met as a silent failure (fresh install, no-agent-no-os-check):
//   · the helper (aris-agent). It lives inside Aris.app (Contents/MacOS) and the app installs it by itself at launch
//     (ArisHelperInstall). A build made in Xcode alone has none inside it: nothing answers then, and it says so.
//   Talking needs no newer macOS any more: on macOS 14 and 15 the listener hears with the older speech engine
//   (SFSpeechRecognizer; ArisListenEngine), so the talk key, the wake word and dictation work on every macOS the app
//   runs on (14 and later). Only things that are macOS 26's own (the notch glass) stay behind their own checks.
//  The words are said at launch (ArisPrerequisiteNotice), on the guide's first page and in the settings window's
//  status line, in the UI's language. Foundation only (tested).
//

import Foundation

enum ArisPrerequisites {
    enum Missing: String, Equatable, CaseIterable {
        /// The app has no aris-agent inside it.
        case helper
    }

    /// The helper's program, inside the app at `app`.
    static func helperPath(app: String) -> String { ArisAgentInstall.agentPath(app: app) }

    /// The app carries its helper (and the tools the helper runs).
    static func helperInstalled(app: String, exists: (String) -> Bool) -> Bool {
        exists(helperPath(app: app)) && exists(ArisAgentInstall.toolsPath(app: app))
    }

    /// What this install lacks, the most serious first. `osMajor` lacks nothing on any macOS the app runs on: both
    /// speech engines listen (ArisListenEngine).
    static func missing(osMajor: Int, helperInstalled: Bool) -> [Missing] {
        helperInstalled ? [] : [.helper]
    }

    /// What this Mac lacks right now.
    static func current() -> [Missing] {
        missing(osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                helperInstalled: helperInstalled(app: Bundle.main.bundlePath) { FileManager.default.fileExists(atPath: $0) })
    }

    /// The one said in the notch at a launch: a missing helper every time (nothing works without it).
    static func atLaunch(_ missing: [Missing]) -> Missing? {
        missing.contains(.helper) ? .helper : nil
    }

    /// The short line (the settings window's status).
    static func line(_ missing: Missing, english: Bool = ArisUIWords.english) -> String {
        switch missing {
        case .helper: ArisUIWords.text("이 Aris에는 도우미가 들어 있지 않아요", "This copy of Aris has no helper inside it", english: english)
        }
    }

    /// What to do about it.
    static func remedy(_ missing: Missing, english: Bool = ArisUIWords.english) -> String {
        switch missing {
        case .helper:
            ArisUIWords.text("개발용으로 만든 앱이라 답할 수 없어요. Aris를 다시 받아 설치해 주세요.",
                             "It is a developer build and can't answer: download Aris again and install that.", english: english)
        }
    }

    /// The line and what to do, as the notch and the guide say it.
    static func full(_ missing: Missing, english: Bool = ArisUIWords.english) -> String {
        line(missing, english: english) + ". " + remedy(missing, english: english)
    }
}
