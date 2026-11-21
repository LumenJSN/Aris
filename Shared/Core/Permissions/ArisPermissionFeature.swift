//
//  ArisPermissionFeature.swift
//  Aris (ArisCore)
//
//  What Aris does that needs a permission, what each one needs, and the one sentence of why the user is told before
//  macOS asks. Where another way exists the feature asks for the smaller permission: reading what is on the screen
//  needs Accessibility (the front app's text), not Screen Recording, which only a picture of the screen needs; file
//  actions need each folder, or nothing more when Full Disk Access is already on. Pure.
//

import Foundation

enum ArisPermissionFeature: String, CaseIterable, Codable, Sendable {
    /// Hold the shortcut and speak.
    case talk
    /// "아리스" wakes it.
    case wakeWord
    /// Speech typed into the field in front.
    case dictation
    /// The right ⌥ key that starts dictation from any app.
    case dictationKey
    /// ⌥⇧ and a circle around something on the screen.
    case circleGesture
    /// "What's on my screen": the front app's text, read through Accessibility.
    case screenText
    /// A picture of the screen sent with a question.
    case screenPicture
    /// Clicking, typing and window moves in other apps.
    case appControl
    /// Music and Spotify from the notch.
    case music
    /// Claude Code and Codex teammates in Terminal or iTerm.
    case codingTeammates
    case calendar, reminders
    /// iMessages and Mail read back (their stores need Full Disk Access).
    case messagesRead, mailRead
    case sendMessages
    /// A contact looked up by name in Contacts, for a message to them.
    case findContact
    /// Notes made in Apple Notes.
    case notes
    /// Restart, shut down or log out (System Events; sleep needs nothing).
    case power
    /// Moving, converting and putting back files in Desktop, Documents and Downloads.
    case fileActions
    /// Directions from where the Mac is.
    case directionsFromHere
    case launchAtLogin
    /// Listening pauses while another app plays sound (it works without, counting any open sound stream).
    case roomListening

    /// The permissions it needs (all of them).
    var needs: [ArisPermission] {
        switch self {
        case .talk, .wakeWord: [.microphone, .speechRecognition]
        case .dictation: [.microphone, .speechRecognition, .accessibility]
        case .dictationKey: [.inputMonitoring]
        case .circleGesture: [.inputMonitoring, .screenRecording]
        case .screenText, .appControl: [.accessibility]
        case .screenPicture: [.screenRecording]
        case .music, .codingTeammates, .sendMessages, .findContact, .notes, .power: [.automation]
        case .calendar: [.calendars]
        case .reminders: [.reminders]
        case .messagesRead, .mailRead: [.fullDiskAccess]
        case .fileActions: [.desktopFolder, .documentsFolder, .downloadsFolder]
        case .directionsFromHere: [.location]
        case .launchAtLogin: [.loginItem]
        case .roomListening: [.systemAudio]
        }
    }

    /// What the setup leaves for the feature's first real use: Screen Recording for the circle gesture (on by
    /// default), asked the first time a circle is drawn, so a first setup asks nothing about the screen.
    var askedAtFirstUse: [ArisPermission] {
        self == .circleGesture ? [.screenRecording] : []
    }

    /// The apps it drives with Apple Events (one Automation grant each).
    var automationTargets: [String] {
        switch self {
        case .music: ["com.apple.Music", "com.spotify.client"]
        case .codingTeammates: ["com.apple.Terminal", "com.googlecode.iterm2"]
        case .sendMessages: ["com.apple.MobileSMS"]
        case .findContact: ["com.apple.AddressBook"]
        case .notes: ["com.apple.Notes"]
        case .power: ["com.apple.systemevents"]
        default: []
        }
    }

    /// Without the permission it still does part of its job (said as it does), instead of failing.
    var degrades: Bool {
        switch self {
        case .roomListening, .directionsFromHere, .screenPicture, .circleGesture, .fileActions: true
        default: false
        }
    }

    /// The one sentence said before macOS asks, and when it was refused.
    func reason(english: Bool) -> String {
        switch self {
        case .talk: english ? "Aris needs the microphone and speech recognition to hear you." : "말을 들으려면 마이크와 음성 인식이 필요해요."
        case .wakeWord: english ? "To wake when you say its name, Aris needs the microphone." : "이름을 부를 때 깨어나려면 마이크가 필요해요."
        case .dictation: english ? "To type what you say into the field in front, Aris needs Accessibility." : "말한 것을 앞의 입력칸에 쓰려면 손쉬운 사용이 필요해요."
        case .dictationKey: english ? "To hear the dictation key in every app, Aris needs Input Monitoring." : "어느 앱에서나 받아쓰기 키를 들으려면 입력 모니터링이 필요해요."
        case .circleGesture: english ? "To see what you circle, Aris needs Screen Recording." : "동그라미 친 곳을 보려면 화면 기록이 필요해요."
        case .screenText: english ? "To read the app in front, Aris needs Accessibility." : "앞에 있는 앱의 글을 읽으려면 손쉬운 사용이 필요해요."
        case .screenPicture: english ? "To send a picture of the screen, Aris needs Screen Recording." : "화면 사진을 보내려면 화면 기록이 필요해요."
        case .appControl: english ? "To click and type in other apps, Aris needs Accessibility." : "다른 앱을 누르고 입력하려면 손쉬운 사용이 필요해요."
        case .music: english ? "To play and pause your music, macOS asks once per music app." : "음악을 틀고 멈추려면 음악 앱마다 macOS가 한 번 물어봐요."
        case .codingTeammates: english ? "To open your coding agent's terminal, macOS asks once for that terminal." : "코딩 에이전트의 터미널을 열려면 macOS가 그 터미널에 대해 한 번 물어봐요."
        case .calendar: english ? "To show and answer about your events, Aris needs your calendars." : "일정을 보여 주고 답하려면 캘린더가 필요해요."
        case .reminders: english ? "To show and change your to-dos, Aris needs Reminders." : "할 일을 보여 주고 바꾸려면 미리 알림이 필요해요."
        case .messagesRead: english ? "To read your messages back, Aris needs Full Disk Access." : "메시지를 읽어 주려면 전체 디스크 접근 권한이 필요해요."
        case .mailRead: english ? "To read your mail back, Aris needs Full Disk Access." : "메일을 읽어 주려면 전체 디스크 접근 권한이 필요해요."
        case .sendMessages: english ? "To send a message for you, macOS asks once about Messages." : "메시지를 대신 보내려면 macOS가 메시지 앱에 대해 한 번 물어봐요."
        case .findContact: english ? "To find who to send it to, macOS asks once about Contacts." : "보낼 사람을 찾으려고 macOS가 연락처 앱에 대해 한 번 물어봐요."
        case .notes: english ? "To save notes for you, macOS asks once about Notes." : "메모를 저장하려면 macOS가 메모 앱에 대해 한 번 물어봐요."
        case .power: english ? "To restart, shut down or log out, macOS asks once about System Events." : "재시동, 종료, 로그아웃을 하려면 macOS가 System Events에 대해 한 번 물어봐요."
        case .fileActions: english ? "macOS asks once for each folder Aris works in." : "Aris가 일하는 폴더마다 macOS가 한 번 물어봐요."
        case .directionsFromHere: english ? "To start directions from here, Aris needs Location Services; without it they start from home." : "여기서 출발하는 길 안내에는 위치 서비스가 필요해요. 없으면 집에서 출발해요."
        case .launchAtLogin: english ? "Aris opens when you log in." : "로그인하면 Aris가 열려요."
        case .roomListening: english ? "To pause listening while another app plays sound, macOS asks about system audio." : "다른 앱 소리가 날 때 듣기를 멈추려고 macOS가 시스템 오디오에 대해 물어봐요."
        }
    }
}
