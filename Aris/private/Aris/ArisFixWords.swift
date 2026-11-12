//
//  ArisFixWords.swift
//  Aris
//
//  The words on a failure's button (ArisFix), Korean and English. Foundation only (tested).
//

import Foundation

/// The buttons under the reply: one that fixes, and at most a quiet "try again" beside it.
struct ArisFixOffer: Equatable {
    let fix: ArisFix
    /// The quiet second button.
    let again: Bool
}

enum ArisFixWords {
    /// The button's words, without its "›".
    static func title(_ fix: ArisFix, english: Bool) -> String {
        func say(_ korean: String, _ inEnglish: String) -> String { english ? inEnglish : korean }
        switch fix.kind {
        case .pane:
            switch fix.pane {
            case .disk: return say("전체 디스크 접근 권한 열기", "Open Full Disk Access")
            case .screen: return say("화면 기록 권한 열기", "Open Screen Recording")
            // The list's name as this macOS shows it (macOS 27: "Device Control and Data Access").
            case .accessibility: return say("\(ArisFix.Pane.accessibility.title(english: false)) 권한 열기", "Open \(ArisFix.Pane.accessibility.title(english: true))")
            case .automation: return say("자동화 권한 열기", "Open Automation")
            case .contacts: return say("연락처 권한 열기", "Open Contacts access")
            case .calendars: return say("캘린더 접근 허용하기", "Allow Calendar access")
            case .reminders: return say("미리 알림 접근 허용하기", "Allow Reminders access")
            case .microphone: return say("마이크 권한 열기", "Open Microphone access")
            case .speech: return say("음성 인식 권한 열기", "Open Speech Recognition")
            case .folders: return say("파일 및 폴더 권한 열기", "Open Files & Folders")
            case nil: return say("시스템 설정 열기", "Open System Settings")
            }
        case .settings:
            switch fix.row {
            case .brain, nil: return ArisBrainTrouble.settingsButton(english: english)
            case .key: return say("API 키 넣기", "Add the API key")
            case .services: return say("서비스 연결하기", "Connect a service")
            case .todoAccess: return say("미리 알림 접근 켜기", "Turn on Reminders access")
            case .calendarAccess: return say("캘린더 접근 켜기", "Turn on Calendar access")
            case .skills: return say("스킬 켜기", "Turn skills on")
            case .team: return say("팀원 설정 열기", "Open teammate settings")
            // Only the helper is restarted here, not all of Aris (the ✦ menu's "Aris 다시 시작" does that).
            case .helper: return say("에이전트 다시 시작하기", "Restart the helper")
            case .control: return say("컴퓨터 제어 설정 열기", "Open Computer control")
            case .memory: return say("기억 설정 열기", "Open Memory settings")
            }
        case .login:
            let name = brainName(fix.target, english: english)
            return say("\(name) 로그인하기", "Log in to \(name)")
        case .retry: return again(english: english)
        case .otherBrain:
            let name = brainName(fix.target, english: english)
            return say("\(name)에게 다시 물어보기", "Ask \(name) instead")
        case .copy: return say("명령 복사하기", "Copy the command")
        case .showApp: return say("Finder에서 Aris 보기", "Show Aris in Finder")
        case .acceptProgram: return say("계속 쓰기", "Keep using it")
        }
    }

    /// The quiet second button, and the first one once its fix has been used.
    static func again(english: Bool) -> String { english ? "Try again" : "다시 해보기" }

    /// What the button says for a moment after a command went to the clipboard.
    static func copied(english: Bool) -> String { english ? "Copied. Paste it in Terminal" : "복사했어요. 터미널에 붙여 넣어 주세요" }

    /// The login couldn't open Terminal, so its command was copied instead.
    static func loginCopied(english: Bool) -> String {
        english ? "Couldn't open Terminal. The command is copied" : "터미널을 못 열어서 명령을 복사했어요"
    }

    /// On the helper's button for a moment after a press: it is being restarted; or it had come back by itself before
    /// the press (Aris restarts it quietly), so there is nothing to restart and "다시 해보기" beside it asks again.
    static func helperRestarting(english: Bool) -> String { english ? "Restarting the helper…" : "에이전트를 다시 시작하는 중이에요…" }
    static func helperBack(english: Bool) -> String { english ? "The helper is running again" : "에이전트가 다시 켜졌어요" }
    /// The line in place of "the helper isn't running" once it answers again and the question is not asked again by
    /// Aris itself (the lost turn may already have done something): what is true now, and what he can do.
    static func helperBackLine(english: Bool) -> String {
        english ? "The helper is running again. Ask again if you still need it." : "에이전트가 다시 켜졌어요. 필요하면 다시 물어봐 주세요."
    }

    /// What a press on the helper's button says: `answering`: the helper answered when it was asked just now.
    /// The longest the button reads "Restarting the helper…": a restart takes about twenty seconds; past this it is
    /// the button again, to be pressed once more.
    static let restartLimit: TimeInterval = 60
    /// How often the helper is asked whether it is back meanwhile.
    static let restartLook: TimeInterval = 1.5

    /// Whether the button still reads "Restarting the helper…" (third VM run: it went back to "Restart the helper ›"
    /// after a few seconds with the restart still fifteen seconds from done): until the helper answers, or the limit.
    static func stillRestarting(answering: Bool, waited: TimeInterval) -> Bool { !answering && waited < restartLimit }

    static func helperPress(answering: Bool, english: Bool) -> String {
        answering ? helperBack(english: english) : helperRestarting(english: english)
    }

    /// The status shown while Aris asks the same thing again by itself after the fix.
    static func asksAgain(english: Bool) -> String { english ? "Fixed. Asking again" : "해결됐어요. 다시 물어볼게요" }

    /// An AI's name on a button: the short one the settings use; the API brain by what it is.
    static func brainName(_ raw: String, english: Bool) -> String {
        guard let brain = ArisBrain(rawValue: raw) else { return "AI" }
        return brain == .api ? (english ? "the API model" : "API 모델") : brain.shortTitle
    }

    /// The command a login runs, for the clipboard when Terminal can't be opened (the settings page's own words).
    static func loginCommand(_ raw: String) -> String? {
        switch ArisBrain(rawValue: raw) {
        case .claude: "claude"
        case .codex: "codex login"
        case .antigravity: "agy"
        case .api, nil: nil
        }
    }
}
