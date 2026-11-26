//
//  ArisLiveSettings.swift
//  Aris
//
//  The settings window wired to the app: reads every setting where the app keeps it (Defaults, Reminders, Calendar,
//  the usage model, the agent) into one ArisSettingsSnapshot, hands the page its rows, and writes a change back
//  where it belongs.
//

import AppKit
import AVFoundation
import Defaults
import KeyboardShortcuts
import Speech
import SwiftUI
import UniformTypeIdentifiers

struct ArisLiveSettings: View {
    @ObservedObject var nav = ArisSettingsNav.shared
    @ObservedObject private var overlay = ArisSettingsOverlay.shared
    @StateObject private var menus = ArisSettingMenus()
    @StateObject private var keys = ArisKeysModel(actions: .live)
    @ObservedObject private var services = ArisServicesModel.shared
    @ObservedObject private var apiBrains = ArisAPIBrainModel.shared
    @StateObject private var recorder = ArisShortcutRecorder()
    @ObservedObject private var aris = ArisController.shared
    @ObservedObject private var reminders = ArisReminders.shared
    @ObservedObject private var calendar = ArisCalendarStore.shared
    @ObservedObject private var usage = ArisUsageModel.shared
    @ObservedObject private var panels = ArisSidePanels.shared
    @ObservedObject private var coordinator = ArisNotchNavigation.shared
    @ObservedObject private var team = ArisTeamModel.shared
    @ObservedObject private var agent = ArisAgentMonitor.shared
    @ObservedObject private var brainSetup = ArisBrainSetup.shared
    @ObservedObject private var more = ArisMoreSettingsModel.shared
    @ObservedObject private var window = ArisSettingsWindow.shared
    @ObservedObject private var memory = ArisMemorySettingsModel.shared
    @ObservedObject private var importer = ArisMemoryImportModel.shared
    @ObservedObject private var skills = ArisSkillsModel.shared
    @ObservedObject private var dropModel = ArisDropModel.shared
    /// 호출어 녹음 and 하루 소리 모으기 (ArisWakeRecordRows).
    @ObservedObject private var wakeRecord = ArisWakeRecordLive.shared
    /// 내 목소리 (ArisVoiceIDRows, F1).
    @ObservedObject private var voiceID = ArisVoiceIDLive.shared
    /// AI 서비스 (design D) draws from its own state (ArisAIServicesLive).
    @ObservedObject private var aiServices = ArisAIServicesLive.shared.model

    @Default(.arisWakeWord) private var wakeWord
    @Default(.arisConversationMinutes) private var minutes
    @Default(.arisConversationSilence) private var silence
    @Default(.arisBargeInOnSpeakers) private var bargeInSpeakers
    /// 에코 제거 오디오 (새 엔진): the duplex engine's one switch (ArisDuplexSwitch), the same key `defaults write` set.
    @AppStorage(ArisDuplexSwitch.key) private var duplexAudio = false
    /// Nil until the switch is touched: then 들은 말 다듬기 follows the engine (on with 자동).
    @AppStorage(ArisHearRepairSetting.key) private var hearRepairStored: Bool?
    @AppStorage(ArisMicSetting.key) private var microphone = ArisMicSetting.thisMac.stored
    @AppStorage(ArisMicSetting.nameKey) private var microphoneName: String?
    @Default(.claudeSounds) private var sounds
    @Default(.arisDayEndOffer) private var dayEndOffer
    /// 하루 정리를 자세히 말하기: the day in review's switch (ArisRecapSwitch), the same key `defaults write` sets.
    @AppStorage(ArisRecapSwitch.key) private var recap = false
    /// 실험 기능: the helper's switches, kept here and sent with every /health, /warm and /ask (ArisAgentClient.switches).
    @AppStorage(ArisExperimentSwitch.core2.rawValue) private var core2 = false
    @AppStorage(ArisExperimentSwitch.teach.rawValue) private var teach = false
    @Default(.arisMuted) private var muted
    @Default(.arisQuietHours) private var quietHours
    @Default(.arisTeammateTerminal) private var teammateTerminal
    @Default(.claudeRingMode) private var claudeRing
    @Default(.arisBrain) private var brain
    @Default(.arisComputerEngine) private var computerEngine
    @Default(.arisLanguages) private var languages
    @Default(.arisVoiceSpeed) private var speed
    @Default(.arisVoiceName) private var voiceName
    @Default(.arisTodoDefaultList) private var defaultList
    @Default(.hideAllDayEvents) private var hideAllDay
    @Default(.joinMeetingOnEventTap) private var joinMeeting
    @Default(.arisBrainFallback) private var brainFallback
    @Default(.calendarOpenIn) private var openIn
    @Default(.arisSeesScreen) private var seesScreen
    @Default(.arisCircleGesture) private var circle
    @Default(.openNotchOnHover) private var hover
    @Default(.enableHaptics) private var haptics
    @Default(.enableGestures) private var gestures
    @Default(.notchHeightMode) private var heightMode
    @Default(.notchHeight) private var notchHeight
    @Default(.arisSettingsTheme) private var theme
    @Default(.useCustomAccentColor) private var customAccent
    @Default(.customAccentColorData) private var accentData
    @Default(.arisReduceMotion) private var reduceMotion
    @Default(.settingsIconInNotch) private var settingsIcon
    @Default(.arisTextBacking) private var textBacking
    @Default(.arisRestStar) private var restStar
    /// The two hidden looks a theme is made of (ArisNotchTheme), watched so the picker follows them.
    @AppStorage(ArisGlassLook.preferenceKey) private var glassLook: String?
    @AppStorage(ArisVoiceLook.key) private var voiceLook: String?
    @Default(.displayMode) private var displayMode
    @Default(.appLanguage) private var appLanguage
    @Default(.arisDictationBrainPolish) private var brainPolish
    @Default(.arisDictationOn) private var dictationOn
    @Default(.arisDictationPill) private var dictationPill
    @Default(.arisDictationPillIdle) private var dictationPillIdle
    @Default(.arisAutoUpdate) private var autoUpdate
    @Default(.arisDictationStyles) private var dictationStyles

    /// What the install itself lacks (ArisPrerequisites), read when the window opens and when Aris comes forward.
    @State private var missing = ArisPrerequisites.current()
    @State private var words = 0
    @State private var learned: [ArisSettingsSnapshot.LearnedWord] = []
    @State private var newListName = "Aris"
    /// What Aris calls the user (ArisUserName), saved as they types.
    @State private var userName = ArisUserName.current ?? ""
    /// Claude Code 연결's dot (ClaudeConnect, read through the folder's grant without asking).
    @State private var claudeConnected = ClaudeConnect.connectedNow ?? false
    /// The name that wakes Aris as typed (ArisWakeName keeps the cleaned one), and why it is or isn't listening.
    @State private var wakeName = ArisWakeName.load(.standard).name
    @ObservedObject private var wakeStatus = ArisWakeStatusLive.shared
    @State private var newListFailed = false
    @State private var permissions: [ArisSettingsSnapshot.Permission] = ArisLiveSettings.readPermissions()
    /// Rows the greeting never counts as missing: each is asked by the feature that needs it, the first time it is used.
    static let quietRows: Set<String> = ["fda", "speech", "input"]
    /// aris-agent's Full Disk Access, as the agent last said (it reads Messages, Mail and Notes).
    @State private var agentDiskAccess = false
    @State private var standing: [ArisStandingPermission]?
    @State private var standingLoaded = false
    @State private var launchAtLogin = ArisLoginItem.isEnabled
    @State private var screens: [ArisSettingOption] = ArisLiveSettings.readScreens()
    @State private var microphones = ArisMicDevices.all()
    @State private var hasVoiceKey = ArisElevenLabs.loadKey() != nil
    /// The quick commands' key's state (ArisRouterKeyHealth), seen as it changes.
    @AppStorage(ArisRouterKeyHealth.preferenceKey) private var quickKeyState: String?

    private let circleHint = ArisCircleHint.text(shortcut: ArisGestureKey.displayName)

    /// The page in Korean as written, or in English when the UI is and the whole page has its English (ArisSettingsCopy).
    private var wording: ArisSettingsWording { .make(page: nav.page, english: ArisUILanguage.english) }

    var body: some View {
        let s = snapshot
        ArisSettingsShell(nav: nav, menus: menus, status: status,
                          searchable: ArisSettingsBuilder.searchable(s),
                          helperFix: (ArisFixWords.title(.settings(.helper), english: ArisUIWords.english), { restartHelper() }),
                          aiFix: (ArisUIWords.text("다시 확인", "Check again"), { recheckAI() })) {
            // Option A: the page's parts one under the other, each under its title.
            ArisSettingsLongPage(nav: nav, parts: ArisSettingsBuilder.parts(nav.page, s).map { ArisPartSections(part: $0.part, sections: wording.sections($0.sections)) }) { part in
                ArisLivePart(part: part, ai: aiServices, engineLine: ArisSettingsBuilder.engineLine(s))
            } accessory: { part in
                part.sections.first.flatMap { $0.heading == nil ? $0.feature : nil }.map { AnyView(ArisFeatureLink(feature: $0)) }
            }
        }
        .environment(\.arisSettingsHandlers, handlers)
        .overlay { ArisAIServicesOverlay(model: aiServices) }
        .overlay { ArisSettingsModalHost(overlay: overlay) { sheet($0) } }
        // Everything drawn here, the sheets and toasts too, words itself for the page that is open.
        .environment(\.arisWords, wording)
        // Each time a page shows: switched to, or the window opened again on it (seventh VM pass: 기억 kept the list it
        // had when the window last closed until another page was picked).
        .task(id: "\(nav.page.rawValue)|\(window.visible)") {
            guard window.visible else { return }
            // Which AIs are set up may have changed since the page last showed (a tool installed, a key saved). Asked
            // on the side: an agent that is slow to answer never holds the page's own data back.
            Task { await brainSetup.refresh() }
            // A key saved on AI 서비스 since: 목소리 · 언어 shows its voice row at once, not after Aris next comes forward.
            hasVoiceKey = ArisElevenLabs.loadKey() != nil
            nav.markSeen(nav.page)
            await pageOpened(nav.page)
        }
        // Permissions change in System Settings while 컴퓨터 제어 is open: read them each second, only while it's seen.
        .task(id: nav.page == .app && window.visible) {
            guard nav.page == .app && window.visible else { return }
            var tick = 0
            while !Task.isCancelled {
                // The agent is asked every 3 s (M11); the app's own permissions every second.
                if tick % 3 == 0 { agentDiskAccess = await ArisAgentClient.agentHasDiskAccess() ?? false }
                tick += 1
                permissions = Self.readPermissions(diskAccess: agentDiskAccess, folders: folderAccess)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: nav.page) { _, _ in recorder.stop(); menus.close(); aiServices.menu = nil }
        .onAppear {
            menus.choose = { menu, id in set(menu.key, .text(id), menu.title) }
            nav.remember(in: .standard)
            ClaudeConnect.refreshConnected()
            claudeConnected = ClaudeConnect.connectedNow ?? false
            // 저장된 단계 is searchable from the start; its rows come with the helper's answer (sixth VM run, item 3).
            Task { await memory.loadSavedSteps() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions = Self.readPermissions(diskAccess: agentDiskAccess, folders: folderAccess)
            microphones = ArisMicDevices.all()
            hasVoiceKey = ArisElevenLabs.loadKey() != nil
            missing = ArisPrerequisites.current()
            Task { await calendar.loadIfAuthorized() }
            Task { await brainSetup.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = Self.readScreens() }
        // aris-agent learned or proposed a word while 받아쓰기 is open.
        .onReceive(DistributedNotificationCenter.default().publisher(for: .init("com.lumenjsn.aris.dictionary"))) { _ in
            if nav.page == .dictation { learned = Self.readLearned() }
        }
        // A memory written or forgotten while 기억 is open (a 기억해 in the notch, the agent's own learning): the page reads
        // the list again (ninth VM pass: it said "9가지" until it was opened again).
        .onReceive(DistributedNotificationCenter.default().publisher(for: .init(ArisMemorySettingsRows.changedNotification))) { _ in
            if ArisMemorySettingsRows.reloadsOnChange(page: nav.page) { Task { await memory.reload() } }
        }
        .onChange(of: nav.sheet) { _, sheet in if sheet == "language" { overlay.sheet = .languages } }
        // A link to a row only the 팀원 sheet draws opens the sheet on it.
        .onChange(of: nav.sheetPart) { _, part in
            guard let part else { return }
            openSheet(part)
            nav.sheetPart = nil
        }
    }

    // MARK: - Reading

    private var status: String {
        let missingRows = permissions.filter { !$0.granted && !Self.quietRows.contains($0.id) && !$0.id.hasPrefix("folder.") }
        return ArisSettingsCaption.greeting(agentDown: agent.link.dozes || !agent.answering, missingPermissions: missingRows.count,
                                            missingNames: missingRows.map(\.title), noAI: brainSetup.noneReady,
                                            aiUnchecked: brainSetup.needsCheck, quickKey: quickKey, missing: missing)
    }

    /// The quick commands' key as its last answers said (ArisRouterKeyHealth); nothing to say without a key.
    private var quickKey: ArisSettingsCaption.QuickKey {
        // Cleared when the key is removed (ArisAIServicesLive), so a state here always has a key behind it.
        switch quickKeyState.flatMap(ArisRouterKeyHealth.State.init(rawValue:)) {
        case .rejected?: return .refused
        case .unchecked?: return .unchecked
        case nil: return .fine
        }
    }

    /// aris-agent's Desktop, Documents and Downloads access as it last answered 허용하기 (QA BUG-17); asking again would
    /// put macOS's prompt up, so it is only asked on that button. Full Disk Access covers all three.
    private static let folderAccessKey = "arisAgentFolderAccess"

    private var folderAccess: [String: Bool] {
        (UserDefaults.standard.dictionary(forKey: Self.folderAccessKey) as? [String: Bool]) ?? [:]
    }

    private var accentHex: String? {
        accentData.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: $0) }.map(Self.hex)
    }

    private var snapshot: ArisSettingsSnapshot {
        _ = recorder.version
        var s = ArisSettingsSnapshot()
        s.wakeWord = wakeWord
        s.wakeName = wakeName
        s.wakeStatus = wakeStatus.line(english: false)
        s.hasVoiceModel = aris.hasWakeModel
        s.wakeRecord = wakeRecord.summary
        s.voiceID = voiceID.summary
        s.busy = aris.isActive
        s.talkCaps = Self.caps(.talkToAris)
        s.minutes = minutes
        s.silence = silence
        s.bargeInSpeakers = bargeInSpeakers
        s.duplexAudio = duplexAudio
        s.hearRepair = ArisHearRepairSetting.isOn(stored: hearRepairStored, choice: ArisHearSetup.choice)
        s.microphone = microphone
        s.microphoneName = microphoneName
        s.microphones = microphones
        s.teamCount = team.teammates.count
        s.skillCount = skills.status.skills.count
        // A key cleared while the page is open keeps its row (ArisSavedKeyRows), so the section keeps its heading.
        s.savedKeys = aiServices.keyRows.count(saved: aiServices.page.savedKeys)
        s.teammateTerminal = teammateTerminal
        s.terminals = Self.installedTerminals()
        s.systemAudioMissing = aris.systemAudioMissing
        s.systemAudioProven = ArisOutputMeter.tapProven
        s.sounds = sounds
        s.dayEndOffer = dayEndOffer
        s.recap = recap
        s.core2 = core2
        s.teach = teach
        s.muted = muted
        s.quietHours = quietHours
        s.claudeRing = claudeRing
        s.claudeConnected = claudeConnected
        s.brain = ArisBrainChoice.shown(brain, stored: ArisBrainSetup.stored, ready: brainSetup.ready)
        s.computerEngine = computerEngine
        s.computerEngines = ArisComputerEngine.allCases.map { .init(id: $0.rawValue, title: $0.title) }
        s.brains = ArisBrain.allCases.map { .init(id: $0.rawValue, title: $0.shortTitle) }
        s.languages = languages.map { .init(id: $0, title: ArisLanguages.named($0)?.native ?? $0) }
        s.hasVoiceKey = hasVoiceKey
        s.voiceName = voiceName
        s.speed = speed
        s.listenEngine = ArisHearingShown.line()
        // 부르기's note says where the wake check hears: Apple's servers on the older engine without an on-device model.
        ArisWakeHonesty.serverHearing = ArisHearingShown.wakeCheckOnServer()
        s.words = words
        s.learned = learned
        s.brainPolish = brainPolish
        s.dictationOn = dictationOn
        s.dictationPill = dictationPill
        s.dictationPillIdle = dictationPillIdle
        s.updates = ArisUpdater.shared.isOn
        s.autoUpdate = autoUpdate
        s.appVersion = Bundle.main.releaseVersionNumber ?? "?"
        s.styles = dictationStyles
        s.pasteLastCaps = Self.caps(.pasteLastDictation)
        s.dictationCaps = [ArisDictationKey.Choice.current.name(english: wording.pageEnglish)]
        s.reminders = reminders.authorized ? .granted : reminders.status == .denied || reminders.status == .restricted ? .blocked : .undecided
        let included = reminders.includedIDs
        s.reminderLists = reminders.lists.map { .init(id: $0.id, name: $0.name, source: $0.source, colorHex: $0.colorHex, included: included.contains($0.id)) }
        s.defaultList = reminders.defaultListID
        s.newListName = newListName
        s.userName = userName
        s.newListFailed = newListFailed
        let auth = calendar.access
        s.calendarAccess = auth == .fullAccess ? .granted : auth == .denied || auth == .restricted ? .blocked : .undecided
        s.calendars = calendar.eventCalendars.map {
            .init(id: $0.id, name: $0.title, source: $0.account, colorHex: Self.hex($0.color), included: calendar.isSelected($0))
        }
        s.googleCalendars = calendar.eventCalendars.filter { ArisAgenda.isGoogle(account: $0.account) }.count
        s.allDay = !hideAllDay
        s.joinMeeting = joinMeeting
        s.brainFallback = brainFallback
        s.openIn = openIn
        s.services = usage.providers.map { provider in
            let status = provider.note ?? (provider.lanes.isEmpty ? "연결 확인 중" : "연결됨")
            return .init(id: provider.id, title: provider.title, detail: [provider.account, provider.plan].compactMap { $0 }.joined(separator: " · "),
                         status: status, tone: provider.note != nil ? .warn : provider.lanes.isEmpty ? .plain : .ok)
        }
        s.permissions = permissions
        s.seesScreen = seesScreen
        s.circle = circle
        s.circleHint = circleHint
        s.standing = standing.map { list in
            list.map { .init(id: $0.id, title: ArisStandingPermissionText.title($0), desc: ArisStandingPermissionText.desc($0), symbol: ArisStandingPermissionText.symbol($0.kind)) }
        }
        s.standingLoaded = standingLoaded
        s.memories = memory.items
        s.memoriesLoaded = memory.loaded
        s.dropHabits = dropModel.learned.habits.count
        s.memoryQuery = memory.query
        s.autoMemory = memory.auto
        s.consolidateMemory = memory.consolidate
        s.memoryHeld = memory.held
        s.memoryConflicts = memory.conflicts
        s.memoryEntities = memory.entities
        s.memoryChanges = memory.changes
        s.confirmingMemoryClear = memory.confirmingClear
        s.workLessons = memory.workLessons
        s.workEpisodes = memory.workEpisodes
        s.workMemory = memory.workOn
        s.confirmingWorkClear = memory.confirmingWorkClear
        s.savedSteps = memory.savedSteps
        s.savedStepsConfirming = memory.confirmingForget
        s.savedStepsRenaming = memory.renaming
        s.savedStepsName = memory.renameText
        s.savedStepsRenameProblem = memory.renameProblem
        s.hover = hover
        s.haptics = haptics
        s.gestures = gestures
        s.heightMode = heightMode == .matchMenuBar ? "menubar" : heightMode == .custom ? "custom" : "real"
        s.notchHeight = notchHeight
        s.hiddenSides = panels.isHiddenAny
        s.hiddenSideTabs = panels.hiddenTabs
        s.clipCaps = Self.caps(.openClipboard)
        s.rightPanelCaps = Self.caps(.openRightPanel)
        s.theme = theme
        s.customAccent = customAccent
        s.accentHex = accentHex
        s.reduceMotion = reduceMotion
        s.settingsIcon = settingsIcon
        s.alwaysTabs = coordinator.alwaysShowTabs
        s.textBacking = textBacking
        s.restStar = restStar
        s.notchTheme = ArisNotchTheme.stored(glass: glassLook, voice: voiceLook)?.rawValue ?? ""
        s.login = launchAtLogin
        s.displayMode = Self.displayID(displayMode)
        s.screens = screens
        s.screen = coordinator.preferredScreenUUID ?? ""
        s.appLanguage = appLanguage.rawValue
        // 시스템 설정대로 is the settings catalog's (the app's own string for it had no Korean: item 17).
        s.appLanguages = AppLanguage.allCases.map { .init(id: $0.rawValue, title: $0 == .system ? "시스템 설정대로" : $0.displayName) }
        s.answerCaps = Self.caps(.answerClaude)
        s.notchCaps = Self.caps(.toggleNotchOpen)
        s.peekCaps = Self.caps(.toggleSneakPeek)
        let version = "버전 \(Bundle.main.releaseVersionNumber ?? "?") (\(ArisBuildInfo.buildDetail(number: Bundle.main.buildVersionNumber)))"
        s.versionLine = Defaults[.releaseName].isEmpty ? version : "\(Defaults[.releaseName]) · \(version)"
        s.more = more.values
        return s
    }

    private static let displayIDs: [(DisplayMode, String)] = [(.preferredDisplay, "preferred"), (.fallbackIfPreferredUnavailable, "fallback"),
                                                              (.activeDisplay, "active"), (.allDisplays, "all")]
    private static func displayID(_ mode: DisplayMode) -> String { displayIDs.first { $0.0 == mode }?.1 ?? "active" }

    /// What a page needs fresh each time it opens: what each of its parts shows.
    private func pageOpened(_ page: ArisSettingsPage) async {
        switch page {
        case .talk:
            // 호출어 녹음's counts and whether 하루 소리 모으기's day is over; the AI parts' services.
            wakeRecord.refresh()
            voiceID.refresh()
            await services.reload()
            await ArisAIServicesLive.shared.reload()
        case .able:
            words = ArisVocabulary.loadOwn().count
            learned = Self.readLearned()
            Task { await memory.reload() }
            standing = await ArisAgentClient.standingPermissions()
            standingLoaded = true
            await services.reload()
            await reminders.reload()
            await calendar.loadIfAuthorized()
        case .look: await more.pageOpened()
        case .app:
            await reminders.reload()
            await calendar.loadIfAuthorized()
            await ArisDataModel.shared.reload()
            await ArisAIServicesLive.shared.reload()
        }
    }

    // MARK: - Writing

    private var handlers: ArisSettingsHandlers {
        var h = ArisSettingsHandlers()
        h.set = { key, value, title in set(key, value, title) }
        h.perform = { perform($0) }
        h.record = { name in recorder.toggle(name) }
        h.recording = recorder.recording
        h.openMenu = { menu in menus.toggle(menu) }
        h.menuOpen = menus.openKey
        h.custom = { custom($0) }
        h.logo = { id in AnyView(UsageLogo(id: id, size: 20)) }
        return h
    }

    private func set(_ key: ArisSettingKey, _ value: ArisSettingValue, _ title: String) {
        let on: Bool? = if case .bool(let b) = value { b } else { nil }
        let text: String = if case .text(let t) = value { t } else { "" }
        let number: Double = if case .number(let n) = value { n } else { 0 }
        switch key {
        case .wakeWord: wakeWord = on ?? wakeWord
        case .minutes: minutes = Int(text) ?? minutes
        case .silence:
            silence = Int(text) ?? silence
            // Off now: an open conversation ends here.
            if silence == 0 { ArisController.shared.closeConversation(.dismissed) }
        case .bargeInSpeakers: bargeInSpeakers = on ?? bargeInSpeakers
        case .duplexAudio: duplexAudio = on ?? duplexAudio
        case .hearRepair: hearRepairStored = on ?? !ArisHearSetup.repairOn
        case .microphone:
            microphoneName = Self.microphoneName(choosing: text, among: microphones) ?? microphoneName
            microphone = text
            NotificationCenter.default.post(name: ArisMicSetting.changed, object: nil)
        case .voiceID: voiceID.setOn(on ?? !voiceID.summary.on)
        case .dictationBrainPolish: brainPolish = on ?? brainPolish
        case .dictationOn: dictationOn = on ?? dictationOn
        case .dictationPill: dictationPill = on ?? dictationPill
        case .dictationPillIdle: dictationPillIdle = on ?? dictationPillIdle
        case .autoUpdate: autoUpdate = on ?? autoUpdate
        case .dictationStyle(let kind): dictationStyles[kind] = text
        case .sounds: sounds = on ?? sounds
        case .dayEndOffer: dayEndOffer = on ?? dayEndOffer
        case .recap: recap = on ?? recap
        case .core2, .teach:
            if key == .core2 { core2 = on ?? core2 } else { teach = on ?? teach }
            // The helper hears it now, not at the next probe or question.
            Task { _ = await ArisAgentClient.reachable() }
        case .muted: ArisQuietLive.shared.setMuted(on ?? muted)
        case .quietHours: quietHours = ArisQuietSpan.choosing(text, current: quietHours)
        case .quietStart: quietHours = ArisQuietSpan.setting(start: text, current: quietHours)
        case .quietEnd: quietHours = ArisQuietSpan.setting(end: text, current: quietHours)
        case .claudeRing: claudeRing = ClaudeRingMode(stored: text).rawValue
        case .wakeCollect:
            wakeRecord.setCollecting(on ?? !wakeRecord.summary.collecting)
            if on == false { overlay.show(ArisWakeRecordRows.collectOffToast) }
        case .teammateTerminal: teammateTerminal = ArisTerminalMemory.pinned(text) ?? ArisTerminal.automatic
        case .brain: brain = text
        case .computerEngine: computerEngine = text
        case .apiBrain(let field):
            apiBrains.choose(field, text)
            return
        case .modelChoice(let field):
            ArisModelChoiceModel.shared.choose(field, text)
            return
        case .speed: speed = Double(text) ?? speed
        case .todoList(let id):
            var ids = reminders.includedIDs
            if on == true, !ids.contains(id) { ids.append(id) } else if on == false { ids.removeAll { $0 == id } }
            reminders.setIncluded(ids)
        case .todoDefault: defaultList = text
        case .newListName:
            newListName = text
            return
        case .savedStepsName:
            memory.renameText = text
            return
        case .wakeName:
            wakeName = String(text.prefix(ArisWakeName.longest))
            ArisWakeName.save(name: wakeName, to: .standard)
            return
        case .userName:
            userName = String(text.prefix(ArisUserName.maxLength))
            ArisUserName.set(userName)
            return
        case .memoryQuery:
            memory.query = text
            return
        case .autoMemory: Task { await memory.setAuto(on ?? true) }
        case .consolidateMemory: Task { await memory.setConsolidate(on ?? true) }
        case .workMemory: Task { await memory.setWork(on ?? true) }
        case .calendar(let id):
            if let entry = calendar.eventCalendars.first(where: { $0.id == id }) {
                Task { await calendar.setSelected(entry, on ?? true) }
            }
        case .allDay: hideAllDay = !(on ?? true)
        case .joinMeeting: joinMeeting = on ?? joinMeeting
        case .brainFallback: brainFallback = on ?? brainFallback
        case .openIn: openIn = text
        case .seesScreen: seesScreen = on ?? seesScreen
        case .circle: circle = on ?? circle
        case .hover:
            hover = on ?? hover
            if !hover { gestures = true }
        case .haptics: haptics = on ?? haptics
        case .sideTab(let id): if let tab = ArisSideTab(rawValue: id), let on { panels.setShown(tab, on) }
        case .gestures: gestures = on ?? gestures
        case .heightMode: setHeightMode(text)
        case .notchHeight:
            // The notch hears it when the drag starts and ends (.sliding), not at every step.
            notchHeight = number
        case .theme: theme = text
        case .accentCustom:
            customAccent = text == "custom"
            NotificationCenter.default.post(name: .accentColorChanged, object: nil)
        case .reduceMotion: reduceMotion = on ?? reduceMotion
        case .settingsIcon: settingsIcon = on ?? settingsIcon
        case .alwaysTabs: coordinator.alwaysShowTabs = on ?? coordinator.alwaysShowTabs
        case .textBacking: textBacking = on ?? textBacking
        case .restStar: restStar = on ?? restStar
        case .notchTheme: ArisNotchTheme(rawValue: text)?.write(to: .standard)
        case .login:
            ArisLoginItem.set(on ?? true)
            launchAtLogin = ArisLoginItem.isEnabled
        case .displayMode: displayMode = Self.displayIDs.first { $0.1 == text }?.0 ?? displayMode
        case .screen: coordinator.preferredScreenUUID = text
        case .appLanguage:
            let language = AppLanguage(rawValue: text)
            appLanguage = language
            language.applyAppleLanguagesOverride()
            overlay.sheet = .restart
        case .more(let key): more.set(key, value)
        }
    }

    private func setHeightMode(_ id: String) {
        switch id {
        case "menubar":
            heightMode = .matchMenuBar
            notchHeight = getMenuBarHeight(hasNotch: true)
        case "custom":
            heightMode = .custom
            notchHeight = 38
        default:
            heightMode = .matchRealNotchSize
            notchHeight = getRealNotchHeight()
        }
        NotificationCenter.default.post(name: .notchHeightChanged, object: nil)
    }

    private func perform(_ action: ArisSettingsAction) {
        switch action {
        case .trainVoice: aris.startTraining()
        case .listen:
            let speaker = aris.speaker
            speaker.stop()
            // The sample is read in the page's wording.
            let line = wording(ArisVoiceSample.line)
            Task { await speaker.speak(line, preview: true) }
        case .editWords: openVocabulary()
        case .voicePicker: nav.sheet = "voice"
        case .addLanguage: overlay.sheet = .languages
        case .remindersAccess: Task { await reminders.requestAccess() }
        case .createList:
            let name = newListName
            Task {
                if let list = await reminders.createList(named: name) {
                    newListFailed = false
                    reminders.setIncluded(Array(Set(reminders.includedIDs + [list.id])))
                    overlay.show("‘\(list.name)’ 목록을 만들고 포함했어요")
                } else {
                    newListFailed = true
                }
            }
        case .calendarRefresh: Task { await calendar.loadIfAuthorized() }
        case .calendarAccess: Task { await calendar.requestAccess() }
        case .internetAccounts:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") { NSWorkspace.shared.open(url) }
        case .permission(let id): openPermission(id)
        case .revokeStanding(let id): revoke(id)
        case .forgetMemory(let id):
            Task { if await memory.forget(id: id) { overlay.show("잊었어요") } }
        case .confirmMemory(let id):
            Task { if await memory.confirm(id: id) { overlay.show("확인했어요") } }
        case .forgetAllMemories:
            Task { if await memory.clearPressed() { overlay.show("기억을 모두 지웠어요") } }
        case .keepMemories: memory.cancelClear()
        case .keepHeldMemory(let id):
            Task { if await memory.keepHeld(id: id) { overlay.show(ArisMemoryReviewRows.keptToast) } }
        case .dropHeldMemory(let id):
            Task { if await memory.dropHeld(id: id) { overlay.show(ArisMemoryReviewRows.droppedToast) } }
        case .settleMemoryConflict(let id, let keep):
            Task { if await memory.settle(conflict: id, keep: keep) { overlay.show(ArisMemoryReviewRows.settledToast) } }
        case .forgetMemoryEntity(let id):
            Task { if await memory.forgetEntity(id: id) { overlay.show(ArisMemoryReviewRows.entityToast) } }
        case .undoMemoryChange(let id):
            Task { if await memory.undoChange(id: id) { overlay.show(ArisMemoryReviewRows.undoneToast) } }
        case .forgetWorkLesson(let id):
            Task { if await memory.forgetLesson(id: id) { overlay.show(ArisWorkSettingsRows.forgotToast) } }
        case .forgetAllWork:
            Task { if await memory.clearWorkPressed() { overlay.show(ArisWorkSettingsRows.clearedToast) } }
        case .keepWork: memory.cancelWorkClear()
        case .forgetSavedSteps(let key):
            Task { if await memory.forgetSavedStepsPressed(key: key) { overlay.show(ArisSavedStepsSettingsRows.forgotToast) } }
        case .keepSavedSteps: memory.cancelForgetSavedSteps()
        case .renameSavedSteps(let key): memory.startRename(key: key)
        case .saveSavedStepsName(let key):
            Task { if await memory.saveRename(key: key) { overlay.show(ArisSavedStepsSettingsRows.renamedToast) } }
        case .importMemory:
            importer.open()
            overlay.sheet = .memoryImport
        case .feature(let feature):
            overlay.open(feature)
        case .forgetDropHabits: dropModel.forgetAllLearned()
        case .clearMemoryQuery: memory.query = ""
        case .unhideSides: for edge in ArisSidePanels.Edge.allCases { panels.unhide(edge) }
        case .go(let page, let anchor): nav.go(page, anchor: anchor)
        case .openSheet(let part, _): openSheet(part)
        case .export: openData(.export)
        case .diagnostics: openData(.diagnostics)
        case .wipe: openData(.wipe)
        case .uninstall: openData(.uninstall)
        case .onboarding: ArisOnboardingGuide.shared.show(replay: true)
        case .resetWakeName:
            wakeName = ArisWakeName.defaultName
            ArisWakeName.save(name: wakeName, to: .standard)
        case .clearName:
            userName = ""
            ArisUserName.set(nil)
        case .restart: ApplicationRelauncher.restart()
        case .quit: NSApp.terminate(nil)
        case .checkUpdate: ArisUpdater.shared.checkNow()
        case .claudeConnect, .claudeDisconnect:
            let done = action == .claudeConnect ? ClaudeConnect.connect() : ClaudeConnect.disconnect()
            claudeConnected = ClaudeConnect.connectedNow ?? false
            overlay.show(done.line, tone: done.ok ? .ok : .bad)
        case .openFolder: openRecordsFolder()
        case .accent(let hex): if let hex, let color = Color(arisHexString: hex) { saveAccent(NSColor(color)) }
        case .pickAccent: ArisAccentPanel.shared.open { saveAccent($0) }
        case .sliding(let key, _):
            if key == .notchHeight || key == .more(.flatHeight) { NotificationCenter.default.post(name: .notchHeightChanged, object: nil) }
        case .clearShortcut(let name): recorder.clear(name)
        case .recheckNowPlaying: more.recheckNowPlaying()
        case .learnWord(let text): changeLearned("accept", text, done: "‘\(text)’ 단어장에 넣었어요")
        case .dismissWord(let text): changeLearned("dismiss", text, done: "‘\(text)’ 다시 묻지 않을게요")
        case .forgetWord(let text): changeLearned("remove", text, done: "‘\(text)’ 지웠어요")
        case .recordWakeCalls: overlay.sheet = .wakeRecord
        case .clearWakeRecordings:
            Task {
                guard await wakeRecord.clearPressed() else { return }
                overlay.show(ArisWakeRecordRows.clearedToast)
            }
        case .keepWakeRecordings: wakeRecord.cancelClear()
        case .enrolVoice: overlay.sheet = .voiceEnrol
        case .forgetVoice:
            Task {
                guard await voiceID.forgetPressed() else { return }
                overlay.show(ArisVoiceIDRows.forgottenToast)
            }
        case .keepVoice: voiceID.cancelForget()
        }
    }

    /// The learned dictionary is aris-agent's to write (the app only reads ~/.config/aris).
    private func changeLearned(_ op: String, _ text: String, done: String) {
        Task {
            let changed = await ArisAgentClient.dictionary(op, text: text)
            learned = Self.readLearned()
            words = ArisVocabulary.loadOwn().count
            overlay.show(changed ? done : "바꾸지 못했어요. Aris 도우미가 켜져 있는지 확인해 주세요.", tone: changed ? .ok : .bad)
        }
    }

    private static func readLearned() -> [ArisSettingsSnapshot.LearnedWord] {
        let dictionary = ArisLearnedDictionary.load(from: ArisLearnedDictionary.file(home: UserHome.path))
        return dictionary.proposals.reversed().map { .init(text: $0.text, heard: $0.heard, proposed: true) }
            + dictionary.words.reversed().map { .init(text: $0.text, heard: $0.heard.last ?? "", proposed: false) }
    }

    private func saveAccent(_ color: NSColor) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) else { return }
        accentData = data
        NotificationCenter.default.post(name: .accentColorChanged, object: nil)
    }

    /// ~/.config/aris in Finder: the real home's (homeDirectoryForCurrentUser is the sandbox's container, where there
    /// is no such folder, so the button opened nothing).
    private func openRecordsFolder() {
        let folder = URL(fileURLWithPath: ArisKeyFile.folder, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return overlay.show("기록 폴더가 아직 없어요. Aris 도우미가 처음 켜지면 생겨요.", tone: .bad)
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// The word list, opened in the text editor. The app may only read ~/.config/aris, so on a fresh install the empty
    /// file is made through a save panel on its place (the user's own Save gives the app the right to write it), then
    /// opened; it used to be "made" where the sandbox forbids it, and nothing opened.
    private func openVocabulary() {
        let url = URL(fileURLWithPath: ArisVocabulary.path)
        if FileManager.default.fileExists(atPath: url.path) { return openWords(url) }
        let panel = NSSavePanel()
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.message = ArisUIWords.text("내 단어장을 만들어요. 이 자리에 저장해야 Aris가 읽어요.", "Create your word list. Save it here so Aris can read it.")
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        guard chosen.resolvingSymlinksInPath().standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
            return overlay.show("단어장은 처음 보여 준 자리에 저장해야 Aris가 읽어요.", tone: .bad)
        }
        do {
            try Data(ArisVocabulary.fileStart(english: ArisUIWords.english).utf8).write(to: chosen, options: .withoutOverwriting)
        } catch {
            if !FileManager.default.fileExists(atPath: chosen.path) { return overlay.show("단어장을 만들지 못했어요.", tone: .bad) }
        }
        openWords(chosen)
    }

    private func openWords(_ url: URL) {
        if !NSWorkspace.shared.open(url) { overlay.show("단어장을 열지 못했어요.", tone: .bad) }
    }

    /// Accessibility and Screen Recording have no prompt to answer: System Settings opens on the list with the drag
    /// panel beside it (ArisPermissionGuide). The microphone asks on its own.
    private func openPermission(_ id: String) {
        switch id {
        case "ax": ArisPermissionGuide.shared.show(.accessibility)
        case "screen": ArisPermissionGuide.shared.show(.screen)
        // Through the permission layer (ArisPermissionCenter): macOS's own dialog where it has one and was never
        // answered, else the pane, watched until its switch is on.
        case "speech":
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                // The list is read again every second while the window is open.
                SFSpeechRecognizer.requestAuthorization { _ in }
            } else {
                ArisPermissionCenter.shared.openPane(.speechRecognition)
            }
        case "input": ArisPermissionCenter.shared.openPane(.inputMonitoring)
        case "fda":
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
        case "systemAudio":
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") { NSWorkspace.shared.open(url) }
        case "folders":
            // The one row for the three folders: each one still off is asked for in turn.
            let off = ArisSettingsSnapshot.agentFolders.filter { folder in permissions.first { $0.id == "folder." + folder }?.granted != true }
            Task {
                var known = folderAccess
                for folder in off {
                    guard let granted = await ArisAgentClient.touchFolder(folder) else { continue }
                    known[folder] = granted
                }
                UserDefaults.standard.set(known, forKey: Self.folderAccessKey)
                permissions = Self.readPermissions(diskAccess: agentDiskAccess, folders: known)
                // macOS asked nothing (a folder it was answered for once, or no answer from the helper): its Files and
                // Folders list opens, so the button always does something visible (fourteenth VM run: "3 file folders"
                // Allow did nothing).
                if off.contains(where: { known[$0] != true }),
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                    NSWorkspace.shared.open(url)
                }
            }
        case let folderID where folderID.hasPrefix("folder."):
            let folder = String(folderID.dropFirst("folder.".count))
            if permissions.first(where: { $0.id == folderID })?.granted == true {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") { NSWorkspace.shared.open(url) }
                return
            }
            // aris-agent reads the folder once: macOS asks the user now, not in the middle of an undo.
            Task {
                guard let granted = await ArisAgentClient.touchFolder(folder) else { return }
                var known = folderAccess
                known[folder] = granted
                UserDefaults.standard.set(known, forKey: Self.folderAccessKey)
                permissions = Self.readPermissions(diskAccess: agentDiskAccess, folders: known)
            }
        default:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
        }
    }

    private func revoke(_ id: String) {
        guard let permission = standing?.first(where: { $0.id == id }) else { return }
        Task {
            _ = await ArisAgentClient.revoke(permission)
            standing = await ArisAgentClient.standingPermissions()
            overlay.show("\(ArisParticle.attach(ArisStandingPermissionText.title(permission), .eunNeun)) 다시 물어볼게요")
        }
    }

    /// The status line pressed while the helper doesn't answer: the fix cards' own restart (ArisFixModel), asked first
    /// whether it answers now, and said in a toast either way.
    /// The status line while a saved key has never answered: the key's check is made again, and the line follows.
    private func recheckAI() {
        Task {
            let answers = await ArisBrainSetup.shared.recheck()
            overlay.show(answers ? "AI가 답해요" : ArisAIServicesBuilder.keyUnanswered, tone: answers ? .ok : .bad)
        }
    }

    private func restartHelper() {
        Task {
            let answering = await ArisAgentClient.probe() == .answered
            if !answering { ArisAgentMonitor.shared.restart(asked: true) }
            overlay.show(ArisFixWords.helperPress(answering: answering, english: ArisUIWords.english), tone: .info)
        }
    }

    private func openData(_ sheet: ArisSettingsOverlay.Sheet) {
        ArisDataModel.shared.resetSheet()
        overlay.sheet = sheet
        Task { await ArisDataModel.shared.reload() }
    }

    // MARK: - Parts

    /// 팀원 or 스킬, as a sheet over the window (they draw themselves as whole pages).
    private func openSheet(_ part: String) {
        overlay.sheet = part == "skills" ? .skills : .team
    }

    private func custom(_ item: ArisSettingItem) -> AnyView? {
        let kind: String
        switch item.control {
        case .custom(let named), .trailing(let named): kind = named
        default: return nil
        }
        if kind == "skills.switch" { return AnyView(ArisSkillsSwitch(model: skills)) }
        if kind == "voicePicker" {
            return AnyView(ArisVoiceMenu { _ in })
        }
        if kind == "about" {
            return AnyView(ArisAboutCard(version: item.desc ?? ""))
        }
        if kind.hasPrefix("apiKey:"), let key = ArisKeysModel.keys.first(where: { $0.name == kind.dropFirst(7) }) {
            return AnyView(ArisKeyRow(key: key, model: keys))
        }
        switch kind {
        case "mcp.composio": return AnyView(ArisComposioRow(model: services))
        case "mcp.servers": return AnyView(ArisMCPServerList(model: services))
        case "mcp.add": return AnyView(ArisMCPAddRow(model: services))
        case "apiBrain": return AnyView(ArisAPIBrainRow(model: apiBrains))
        case "claudeBudget": return AnyView(ClaudeBudgetRow(title: item.title))
        default: break
        }
        return nil
    }

    @ViewBuilder
    private func sheet(_ sheet: ArisSettingsOverlay.Sheet) -> some View {
        switch sheet {
        case .languages:
            ArisLanguageSheet(languages: $languages) { overlay.sheet = nil; if nav.sheet == "language" { nav.sheet = nil } }
        case .restart:
            ArisRestartSheet(later: { overlay.sheet = nil }, restart: { ApplicationRelauncher.restart() })
        case .memoryImport:
            ArisMemoryImportSheet(board: $importer.board, copied: importer.copied, actions: importer.actions) { overlay.sheet = nil }
        case .removeMate:
            ArisRemoveMateSheet(name: overlay.removal?.name ?? "팀원", cancel: { overlay.sheet = nil }) {
                let removal = overlay.removal
                overlay.sheet = nil
                overlay.removal = nil
                removal?.remove()
                if let name = removal?.name { overlay.show("\(ArisParticle.attach(name, .eulReul)) 팀에서 뺐어요") }
            }
        case .featureDetail:
            featureSheet(overlay.feature)
        case .wakeRecord:
            ArisWakeRecordSheet(model: .shared) { overlay.sheet = nil }
        case .voiceEnrol:
            ArisVoiceEnrolSheet(model: .shared) { overlay.sheet = nil }
        case .team:
            VStack(alignment: .leading, spacing: 22) {
                ArisFaceStageView()
                ArisTeamPage(team: team, mainBrain: ArisBrain.named(Defaults[.arisBrain]).rawValue)
            }
        case .skills:
            ArisSkillsPage(model: skills)
        default:
            ArisDataSheet(kind: sheet, model: .shared)
        }
    }

    /// A feature's detail sheet, its switch the feature's own setting: 질문할 때 화면 같이 보기, or the skills switch.
    @ViewBuilder
    private func featureSheet(_ feature: ArisFeature) -> some View {
        let close = { overlay.sheet = nil }
        switch feature {
        case .control:
            ArisFeatureSheet(feature: feature, isOn: seesScreen, toggle: { set(.seesScreen, .bool(!seesScreen), ArisFeature.control.content.title) }, close: close)
        case .skills:
            let on = skills.status.enabled
            ArisFeatureSheet(feature: feature, isOn: on, toggle: { on ? skills.turnOff() : skills.turnOn(saying: true) }, close: close)
        case .notify, .savedSteps:
            ArisFeatureSheet(feature: feature, close: close)
        }
    }
}

extension ArisTeamModel: ArisTeamSource {}
