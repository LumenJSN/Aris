//
//  ArisSettingsSnapshot.swift
//  Aris
//
//  Every value the settings pages show, read at once from where the app keeps it (ArisLiveSettings), so the pages
//  are plain functions of it. The defaults are a fresh install's. Foundation only (tested).
//

import Foundation

enum ArisAccess: Equatable { case granted, undecided, blocked }

struct ArisSettingsSnapshot: Equatable {
    struct ColoredItem: Equatable {
        let id: String
        let name: String
        let source: String
        let colorHex: String
        let included: Bool
    }

    struct Service: Equatable {
        let id: String
        let title: String
        let detail: String
        let status: String
        let tone: ArisChipTone
    }

    struct Permission: Equatable {
        let id: String
        let title: String
        let desc: String
        let granted: Bool
    }

    /// The folders macOS guards per app (Desktop, Documents, Downloads), as rows in 권한 (the helper inside the app reads them, so macOS's question names Aris) (QA BUG-17).
    static let agentFolders = ["Desktop", "Documents", "Downloads"]

    /// A row per folder, granted as aris-agent last answered (허용하기 asks macOS; Full Disk Access covers all three).
    static func folderPermissions(granted: [String: Bool]) -> [Permission] {
        let names = ["Desktop": "데스크탑", "Documents": "문서", "Downloads": "다운로드"]
        return agentFolders.map { folder in
            Permission(id: "folder.\(folder)", title: "\(names[folder] ?? folder) 폴더",
                       desc: "파일 옮기기·변환·되돌리기에 써요.", granted: granted[folder] == true)
        }
    }

    struct Standing: Equatable {
        let id: String
        let title: String
        let desc: String
        let symbol: String
    }

    // 대화
    var wakeWord = true
    var hasVoiceModel = false
    var busy = false
    var talkCaps = ["⌥", "Space"]
    var minutes = 5
    /// The always-on conversation: seconds of silence that end it (0: off), and barge-in through the speakers.
    var silence = 30
    var bargeInSpeakers = true
    /// The output meter hears only zeros while an app plays: System Audio permission is likely missing.
    var systemAudioMissing = false
    var sounds = true
    /// The evening chip that offers the day-end summary (ArisDayEndSetting).
    var dayEndOffer = true
    /// Aris is muted; and the night part of quiet time as stored (ArisQuietHours).
    var muted = false
    var quietHours = ArisQuietHours.standard
    /// What the Claude ear's ring shows: "fiveHour", "sevenDay" or "auto" (ClaudeRingMode).
    var claudeRing = "fiveHour"
    var brain = "codex"
    var computerEngine = "peekaboo"
    var computerEngines: [ArisSettingOption] = [.init(id: "peekaboo", title: "Peekaboo (무료)"), .init(id: "codex", title: "GPT (Codex)")]
    var brains: [ArisSettingOption] = [.init(id: "claude", title: "Claude"), .init(id: "codex", title: "Codex"), .init(id: "antigravity", title: "Gemini")]

    // 기억 (ArisMemorySettingsRows): nil until the agent answers (or when it doesn't).
    var memories: [ArisMemoryItem]?
    var memoriesLoaded = false
    /// How many requests the dropped-file chips have learned (ArisDropLearned).
    var dropHabits = 0
    var memoryQuery = ""
    var autoMemory = true
    /// 매주 정리하기, what waits for the user's look, the people and project pages and the tidy-up's changes (ArisMemoryReviewRows).
    var consolidateMemory = true
    var memoryHeld: [ArisMemoryHeldItem] = []
    var memoryConflicts: [ArisMemoryConflictItem] = []
    var memoryEntities: [ArisMemoryEntityItem] = []
    var memoryChanges: [ArisMemoryChangeItem] = []
    /// 모두 지우기 was pressed once: the row asks again.
    var confirmingMemoryClear = false
    /// 일하면서 배운 것 (ArisWorkSettingsRows): the lessons (nil until the agent answers), how many episodes there are,
    /// the switch, and whether 배운 것 모두 지우기 was pressed once.
    var workLessons: [ArisWorkLessonItem]?
    var workEpisodes = 0
    var workMemory = true
    var confirmingWorkClear = false
    /// 저장된 단계 (ArisSavedStepsSettingsRows): the saved desktop steps (nil until the agent answers).
    var savedSteps: [ArisSavedStepsItem]?

    // 목소리 · 언어
    var languages: [ArisSettingOption] = [.init(id: "ko", title: "한국어"), .init(id: "en", title: "English")]
    var cloud = true
    var hasVoiceKey = false
    var voiceName = ""
    var speed = 1.0

    // 받아쓰기
    var words = 0
    /// A word dictation learned from the user's fix (or proposes, `proposed`), and how it was misheard.
    struct LearnedWord: Equatable {
        let text: String
        let heard: String
        let proposed: Bool
    }
    var pasteLastCaps = ["⌃", "⌘", "V"]
    var brainPolish = false
    /// 받아쓰기 알약 보이기 (ArisDictationPillCenter).
    var dictationPill = true
    /// 쉴 때도 보이기: the pill's idle sliver between dictations (ArisDictationPillRules showIdle).
    var dictationPillIdle = true
    /// The user's style picks by app kind (missing: the kind's default).
    var styles: [String: String] = [:]
    var learned: [LearnedWord] = []

    // 할 일
    var reminders = ArisAccess.undecided
    var reminderLists: [ColoredItem] = []
    var defaultList = ""
    var newListName = "Aris"
    var newListFailed = false

    // 일반: what Aris calls the user (ArisUserName).
    var userName = ""

    // 캘린더
    var calendarAccess = ArisAccess.undecided
    var calendars: [ColoredItem] = []
    var googleCalendars = 0
    var allDay = true
    var joinMeeting = true
    var openIn = "apple"

    // AI 서비스
    var services: [Service] = []

    // 컴퓨터 제어
    var permissions: [Permission] = []
    /// The dictation key as the row shows it (the right ⌥ unless another was picked).
    var dictationCaps = ["오른쪽 ⌥"]
    var seesScreen = true
    var circle = true
    var circleHint = "⌥⇧를 누른 채 화면에 동그라미를 그리면 그 부분을 같이 봐요"
    /// Nil until the agent answers (or when it doesn't).
    var standing: [Standing]?
    var standingLoaded = false

    // 노치 · 사이드 노치
    var hover = true
    var haptics = true
    var gestures = true
    /// "real", "menubar" or "custom".
    var heightMode = "real"
    var notchHeight = 32.0
    var hiddenSides = false
    /// The side notches' tabs turned off (ArisSideTab raw values).
    var hiddenSideTabs: Set<String> = []
    var clipCaps = ["⌃", "⌥", "V"]
    /// The right side notch's shortcut: none until one is picked.
    var rightPanelCaps: [String] = []

    // 모양
    var theme = "auto"
    var customAccent = false
    var accentHex: String?
    var reduceMotion = false
    var settingsIcon = true
    var alwaysTabs = true
    /// The notch's look: its theme (ArisNotchTheme's raw value, "" when the stored looks make none of them), the text
    /// backing, and the star at rest (on: ArisRestStar.standard).
    var notchTheme = ArisNotchTheme.standard.rawValue
    var textBacking = ArisTextBacking.standard
    var restStar = true

    // 일반
    var login = true
    var displayMode = "fallback"
    var displayModes: [ArisSettingOption] = [.init(id: "preferred", title: "선호하는 화면"), .init(id: "fallback", title: "선호하는 화면, 없으면 자동"),
                                             .init(id: "active", title: "포인터가 있는 화면"), .init(id: "all", title: "모든 화면")]
    var screens: [ArisSettingOption] = []
    var screen = ""
    var appLanguage = "system"
    var appLanguages: [ArisSettingOption] = [.init(id: "system", title: "시스템 언어"), .init(id: "ko", title: "한국어"), .init(id: "en", title: "English")]

    // 단축키
    var answerCaps = ["⌃", "⌥", "Space"]
    var notchCaps = ["⇧", "⌘", "I"]
    var peekCaps = ["⇧", "⌘", "H"]

    // 정보
    var versionLine = ""

    // 노치 · 노치 기능's further rows
    var more = ArisMoreSettings()

    var brainTitle: String { brains.first { $0.id == brain }?.title ?? (brain.isEmpty ? "없음" : brain) }
}
