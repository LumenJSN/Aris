//
//  ArisPermission.swift
//  Aris (ArisCore: the app, the helper and the tests compile it by path)
//
//  Every macOS permission Aris can be asked for, what kind of ask it is, the exact System Settings link for it, and
//  where the work that needs it runs (aris-perms INVENTORY.md). Every process Aris starts is charged to the app
//  (the helper and its tools sit in Aris.app/Contents/MacOS, started by launchd, and nothing disclaims
//  responsibility), so each permission is one row named Aris whichever process does the work. Pure.
//

import Foundation

enum ArisPermission: String, CaseIterable, Codable, Sendable {
    case microphone, speechRecognition, accessibility, inputMonitoring, screenRecording, systemAudio, automation
    case calendars, reminders, contacts, location, fullDiskAccess, desktopFolder, documentsFolder, downloadsFolder
    case loginItem

    /// How macOS lets it be given.
    enum Ask: String, Codable, Sendable {
        /// A dialog Aris can raise itself (the microphone, speech recognition, calendars, reminders).
        case prompt
        /// A switch the user turns on in System Settings; Aris can only open the pane.
        case pane
        /// macOS asks by itself the first time the guarded thing is touched (a folder, an app driven by Apple Events,
        /// the system audio tap). Aris says why just before, and never asks up front.
        case onUse
        /// The user's own choice in Aris (open at login); macOS shows a notification, no question.
        case consent
    }

    /// Which process does the work that needs it. Both are charged to the app, so this decides nothing about rows;
    /// it says where a check must run to be true (a process asks macOS about itself).
    enum Home: String, Codable, Sendable {
        case app, helper
    }

    var ask: Ask {
        switch self {
        case .microphone, .speechRecognition, .calendars, .reminders: .prompt
        case .accessibility, .inputMonitoring, .screenRecording, .fullDiskAccess, .contacts, .location: .pane
        case .systemAudio, .automation, .desktopFolder, .documentsFolder, .downloadsFolder: .onUse
        case .loginItem: .consent
        }
    }

    /// The anchor of its list in System Settings › Privacy & Security; nil for open at login (its own pane).
    var anchor: String? {
        switch self {
        case .microphone: "Privacy_Microphone"
        case .speechRecognition: "Privacy_SpeechRecognition"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .screenRecording: "Privacy_ScreenCapture"
        case .systemAudio: "Privacy_AudioCapture"
        case .automation: "Privacy_Automation"
        case .calendars: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .contacts: "Privacy_Contacts"
        case .location: "Privacy_LocationServices"
        case .fullDiskAccess: "Privacy_AllFiles"
        case .desktopFolder, .documentsFolder, .downloadsFolder: "Privacy_FilesAndFolders"
        case .loginItem: nil
        }
    }

    static let privacyLink = "x-apple.systempreferences:com.apple.preference.security?"
    static let loginItemsLink = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

    /// The exact deep link to the pane that holds its switch.
    var paneLink: String { anchor.map { Self.privacyLink + $0 } ?? Self.loginItemsLink }

    /// macOS tells a running process the old answer until it restarts, so a switch turned on in System Settings
    /// counts only after Quit & Reopen (macOS offers it itself for these two; ArisScreenAccess's header).
    var relaunchToSee: Bool { self == .screenRecording || self == .inputMonitoring }

    /// Where the work that needs it runs (INVENTORY.md §2). Either way the row is Aris's.
    var home: Home {
        switch self {
        case .microphone, .speechRecognition, .inputMonitoring, .systemAudio, .calendars, .reminders, .loginItem: .app
        case .accessibility, .screenRecording, .automation, .contacts, .location, .fullDiskAccess,
             .desktopFolder, .documentsFolder, .downloadsFolder: .helper
        }
    }

    /// A folder macOS guards on its own; Full Disk Access covers all three.
    var isFolder: Bool { self == .desktopFolder || self == .documentsFolder || self == .downloadsFolder }

    /// Its name in a sentence, Korean first (the list's own name on this macOS is ArisFix.Pane's; these are the
    /// plain words for the ones it has no list for).
    func title(english: Bool) -> String {
        switch self {
        case .microphone: english ? "Microphone" : "마이크"
        case .speechRecognition: english ? "Speech Recognition" : "음성 인식"
        case .accessibility: english ? "Accessibility" : "손쉬운 사용"
        case .inputMonitoring: english ? "Input Monitoring" : "입력 모니터링"
        case .screenRecording: english ? "Screen Recording" : "화면 기록"
        case .systemAudio: english ? "System Audio Recording" : "시스템 오디오 녹음"
        case .automation: english ? "Automation" : "자동화"
        case .calendars: english ? "Calendars" : "캘린더"
        case .reminders: english ? "Reminders" : "미리 알림"
        case .contacts: english ? "Contacts" : "연락처"
        case .location: english ? "Location Services" : "위치 서비스"
        case .fullDiskAccess: english ? "Full Disk Access" : "전체 디스크 접근 권한"
        case .desktopFolder: english ? "Desktop folder" : "데스크탑 폴더"
        case .documentsFolder: english ? "Documents folder" : "문서 폴더"
        case .downloadsFolder: english ? "Downloads folder" : "다운로드 폴더"
        case .loginItem: english ? "Open at login" : "로그인 시 실행"
        }
    }
}

/// One permission as macOS keys it: Automation is one grant per target app, everything else one grant.
struct ArisPermissionKey: Hashable, Codable, Sendable, CustomStringConvertible {
    let permission: ArisPermission
    /// The target app's bundle id, for Automation only.
    let target: String?

    init(_ permission: ArisPermission) {
        self.permission = permission
        target = nil
    }

    static func automation(_ bundleId: String) -> ArisPermissionKey { ArisPermissionKey(permission: .automation, target: bundleId) }

    private init(permission: ArisPermission, target: String?) {
        self.permission = permission
        self.target = target
    }

    var description: String { target.map { "\(permission.rawValue):\($0)" } ?? permission.rawValue }
}

/// What macOS says about one permission now.
enum ArisPermissionState: String, Codable, Sendable {
    case granted
    /// Never answered: a dialog would come, or the switch was never turned on.
    case notAsked
    case denied
    /// Not known from here (the helper hasn't answered, the target app isn't running).
    case unknown
}

/// What a live check found: the state, and whether this process still needs a relaunch to use a grant that is on.
struct ArisPermissionReading: Equatable, Sendable {
    var state: ArisPermissionState
    var needsRelaunch = false

    static let unknown = ArisPermissionReading(state: .unknown)
}
