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
import SwiftUI

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
    /// AI 서비스 (design D) draws from its own state (ArisAIServicesLive).
    @ObservedObject private var aiServices = ArisAIServicesLive.shared.model

    @Default(.arisWakeWord) private var wakeWord
    @Default(.arisConversationMinutes) private var minutes
    @Default(.arisConversationSilence) private var silence
    @Default(.arisBargeInOnSpeakers) private var bargeInSpeakers
    @Default(.claudeSounds) private var sounds
    @Default(.arisDayEndOffer) private var dayEndOffer
    @Default(.arisMuted) private var muted
    @Default(.arisQuietHours) private var quietHours
    @Default(.arisTeammateTerminal) private var teammateTerminal
    @Default(.claudeRingMode) private var claudeRing
    @Default(.arisBrain) private var brain
    @Default(.arisComputerEngine) private var computerEngine
    @Default(.arisLanguages) private var languages
    @Default(.arisCloudListening) private var cloud
    @Default(.arisVoiceSpeed) private var speed
    @Default(.arisVoiceName) private var voiceName
    @Default(.arisTodoDefaultList) private var defaultList
    @Default(.hideAllDayEvents) private var hideAllDay
    @Default(.joinMeetingOnEventTap) private var joinMeeting
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
    @Default(.arisDictationPill) private var dictationPill
    @Default(.arisDictationPillIdle) private var dictationPillIdle
    @Default(.arisDictationStyles) private var dictationStyles

    /// What the install itself lacks (ArisPrerequisites), read when the window opens and when Aris comes forward.
    @State private var missing = ArisPrerequisites.current()
    @State private var words = 0
    @State private var learned: [ArisSettingsSnapshot.LearnedWord] = []
    @State private var newListName = "Aris"
    /// What Aris calls the user (ArisUserName), saved as they types.
    @State private var userName = ArisUserName.current ?? ""
    @State private var newListFailed = false
    @State private var permissions: [ArisSettingsSnapshot.Permission] = ArisLiveSettings.readPermissions()
    /// aris-agent's Full Disk Access, as the agent last said (it reads Messages, Mail and Notes).
    @State private var agentDiskAccess = false
    @State private var standing: [ArisStandingPermission]?
    @State private var standingLoaded = false
    @State private var launchAtLogin = ArisLoginItem.isEnabled
    @State private var screens: [ArisSettingOption] = ArisLiveSettings.readScreens()
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
                          aiFix: (ArisUIWords.text("다시 확인", "Check again"), { recheckAI() }),
                          accessory: nav.page == .skills && !ArisSkillsOff.shown(enabled: skills.status.enabled, chatEmpty: skills.chat.isEmpty)
                              ? AnyView(ArisSkillsSwitch(model: skills).id("skills.feature").arisFlash("skills.feature")) : nil) {
            if nav.page == .team {
                ArisTeamPage(team: team, mainBrain: ArisBrain.named(Defaults[.arisBrain]).rawValue)
                // The terminal a Claude Code teammate opens in: one row of the settings' own (ArisTerminalSetting).
                ArisSettingsPageView(sections: wording.sections([ArisTerminalSetting.section(pinned: teammateTerminal, installed: Self.installedTerminals())]))
                    .padding(.top, 22)
            } else if nav.page == .skills {
                ArisSkillsPage(model: skills)
            } else if nav.page == .ai {
                ArisAIServicesPage(model: aiServices, sections: wording.sections(ArisSettingsBuilder.sections(.ai, s)))
            } else {
                ArisSettingsPageView(sections: wording.sections(ArisSettingsBuilder.sections(nav.page, s)))
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
        .task(id: nav.page == .control && window.visible) {
            guard nav.page == .control && window.visible else { return }
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
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions = Self.readPermissions(diskAccess: agentDiskAccess, folders: folderAccess)
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
    }

    // MARK: - Reading

    private var status: String {
        ArisSettingsCaption.greeting(agentDown: agent.link.dozes || !agent.answering, missingPermissions: permissions.filter { !$0.granted && $0.id != "fda" && !$0.id.hasPrefix("folder.") }.count,
                                     noAI: brainSetup.noneReady, aiUnchecked: brainSetup.needsCheck, quickKey: quickKey, missing: missing)
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

    private static func readPermissions(diskAccess: Bool = false, folders: [String: Bool] = [:]) -> [ArisSettingsSnapshot.Permission] {
        base(diskAccess: diskAccess) + ArisSettingsSnapshot.folderPermissions(granted: diskAccess ? Dictionary(uniqueKeysWithValues: ArisSettingsSnapshot.agentFolders.map { ($0, true) }) : folders)
    }

    private static func base(diskAccess: Bool) -> [ArisSettingsSnapshot.Permission] {
        [
            .init(id: "ax", title: ArisFix.Pane.accessibility.title(english: false), desc: "버튼·입력칸을 찾아 누르고 글자를 입력해요.", granted: AXIsProcessTrusted()),
            .init(id: "screen", title: ArisFix.Pane.screen.title(english: false), desc: "화면을 가리켜 말할 때 그 화면을 같이 봐요.", granted: CGPreflightScreenCaptureAccess()),
            .init(id: "mic", title: "마이크", desc: "말을 들어요.", granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized),
            .init(id: "fda", title: "전체 디스크 접근", desc: "메시지·메일·메모를 읽기만 해요.",
                  granted: diskAccess),
        ]
    }

    /// The terminals on this Mac a teammate can open in (looked up by their bundle ids; nothing is opened).
    private static func installedTerminals() -> [ArisTerminal] {
        ArisTerminal.allCases.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleId) != nil }
    }

    private static func readScreens() -> [ArisSettingOption] {
        NSScreen.screens.compactMap { screen in screen.displayUUID.map { ArisSettingOption(id: $0, title: screen.localizedName) } }
    }

    private static func caps(_ name: KeyboardShortcuts.Name) -> [String] {
        KeyboardShortcuts.getShortcut(for: name).map { ArisShortcutCaps.caps($0.description) } ?? []
    }

    private static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }

    private var accentHex: String? {
        accentData.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: $0) }.map(Self.hex)
    }

    private var snapshot: ArisSettingsSnapshot {
        _ = recorder.version
        var s = ArisSettingsSnapshot()
        s.wakeWord = wakeWord
        s.hasVoiceModel = aris.hasWakeModel
        s.busy = aris.isActive
        s.talkCaps = Self.caps(.talkToAris)
        s.minutes = minutes
        s.silence = silence
        s.bargeInSpeakers = bargeInSpeakers
        s.systemAudioMissing = aris.systemAudioMissing
        s.sounds = sounds
        s.dayEndOffer = dayEndOffer
        s.muted = muted
        s.quietHours = quietHours
        s.claudeRing = claudeRing
        s.brain = ArisBrainChoice.shown(brain, stored: ArisBrainSetup.stored, ready: brainSetup.ready)
        s.computerEngine = computerEngine
        s.computerEngines = ArisComputerEngine.allCases.map { .init(id: $0.rawValue, title: $0.title) }
        s.brains = ArisBrain.allCases.map { .init(id: $0.rawValue, title: $0.shortTitle) }
        s.languages = languages.map { .init(id: $0, title: ArisLanguages.named($0)?.native ?? $0) }
        s.cloud = cloud
        s.hasVoiceKey = hasVoiceKey
        s.voiceName = voiceName
        s.speed = speed
        s.words = words
        s.learned = learned
        s.brainPolish = brainPolish
        s.dictationPill = dictationPill
        s.dictationPillIdle = dictationPillIdle
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

    /// What a page needs fresh each time it opens.
    private func pageOpened(_ page: ArisSettingsPage) async {
        switch page {
        case .dictation:
            words = ArisVocabulary.loadOwn().count
            learned = Self.readLearned()
        case .todo:
            await reminders.reload()
            await calendar.loadIfAuthorized()
        case .about: await ArisDataModel.shared.reload()
        case .memory: await memory.reload()
        case .features: await more.pageOpened()
        case .ai:
            await services.reload()
            await ArisAIServicesLive.shared.reload()
        case .control:
            standing = await ArisAgentClient.standingPermissions()
            standingLoaded = true
        default: break
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
        case .dictationBrainPolish: brainPolish = on ?? brainPolish
        case .dictationPill: dictationPill = on ?? dictationPill
        case .dictationPillIdle: dictationPillIdle = on ?? dictationPillIdle
        case .dictationStyle(let kind): dictationStyles[kind] = text
        case .sounds: sounds = on ?? sounds
        case .dayEndOffer: dayEndOffer = on ?? dayEndOffer
        case .muted: ArisQuietLive.shared.setMuted(on ?? muted)
        case .quietHours: quietHours = ArisQuietSpan.choosing(text, current: quietHours)
        case .quietStart: quietHours = ArisQuietSpan.setting(start: text, current: quietHours)
        case .quietEnd: quietHours = ArisQuietSpan.setting(end: text, current: quietHours)
        case .claudeRing: claudeRing = ClaudeRingMode(stored: text).rawValue
        case .teammateTerminal: teammateTerminal = ArisTerminalMemory.pinned(text) ?? ArisTerminal.automatic
        case .brain: brain = text
        case .computerEngine: computerEngine = text
        case .apiBrain(let field):
            apiBrains.choose(field, text)
            return
        case .cloud: cloud = on ?? cloud
        case .speed: speed = Double(text) ?? speed
        case .todoList(let id):
            var ids = reminders.includedIDs
            if on == true, !ids.contains(id) { ids.append(id) } else if on == false { ids.removeAll { $0 == id } }
            reminders.setIncluded(ids)
        case .todoDefault: defaultList = text
        case .newListName:
            newListName = text
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
        case .editWords: ArisLiveSettings.openVocabulary()
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
            Task { if await memory.forgetSavedSteps(key: key) { overlay.show(ArisSavedStepsSettingsRows.forgotToast) } }
        case .importMemory:
            importer.open()
            overlay.sheet = .memoryImport
        case .feature(let feature):
            overlay.open(feature)
        case .forgetDropHabits: dropModel.forgetAllLearned()
        case .clearMemoryQuery: memory.query = ""
        case .unhideSides: for edge in ArisSidePanels.Edge.allCases { panels.unhide(edge) }
        case .go(let page, let anchor): nav.go(page, anchor: anchor)
        case .export: openData(.export)
        case .diagnostics: openData(.diagnostics)
        case .wipe: openData(.wipe)
        case .uninstall: openData(.uninstall)
        case .onboarding: ArisOnboardingGuide.shared.show(replay: true)
        case .clearName:
            userName = ""
            ArisUserName.set(nil)
        case .restart: ApplicationRelauncher.restart()
        case .quit: NSApp.terminate(nil)
        case .openFolder:
            NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris")])
        case .accent(let hex): if let hex, let color = Color(arisHexString: hex) { saveAccent(NSColor(color)) }
        case .pickAccent: ArisAccentPanel.shared.open { saveAccent($0) }
        case .sliding(let key, _):
            if key == .notchHeight || key == .more(.flatHeight) { NotificationCenter.default.post(name: .notchHeightChanged, object: nil) }
        case .clearShortcut(let name): recorder.clear(name)
        case .recheckNowPlaying: more.recheckNowPlaying()
        case .learnWord(let text): changeLearned("accept", text, done: "‘\(text)’ 단어장에 넣었어요")
        case .dismissWord(let text): changeLearned("dismiss", text, done: "‘\(text)’ 다시 묻지 않을게요")
        case .forgetWord(let text): changeLearned("remove", text, done: "‘\(text)’ 지웠어요")
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

    private static func openVocabulary() {
        let url = URL(fileURLWithPath: ArisVocabulary.path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: Data()) }
        NSWorkspace.shared.open(url)
    }

    /// Accessibility and Screen Recording have no prompt to answer: System Settings opens on the list with the drag
    /// panel beside it (ArisPermissionGuide). The microphone asks on its own.
    private func openPermission(_ id: String) {
        switch id {
        case "ax": ArisPermissionGuide.shared.show(.accessibility)
        case "screen": ArisPermissionGuide.shared.show(.screen)
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

    private func custom(_ item: ArisSettingItem) -> AnyView? {
        guard case .custom(let kind) = item.control else { return nil }
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
