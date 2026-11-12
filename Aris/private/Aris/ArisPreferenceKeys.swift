//
//  ArisPreferenceKeys.swift
//  Aris
//
//  Aris's own preferences (the brain, voice, languages, listening, to-dos, settings look). Key strings and defaults
//  are what earlier builds stored under. `arisReduceMotion` lives in ArisMotionSetting.swift.
//

import Defaults
import Foundation

extension Defaults.Keys {
    /// What answers while nothing is stored; a new install is given one that is set up here (ArisBrainSetup).
    static let arisBrain = Key<String>("arisBrain", default: ArisBrain.codex.rawValue)
    /// Who works other apps' windows (ArisComputerEngine): Peekaboo unless the user picks Codex's.
    static let arisComputerEngine = Key<String>(ArisComputerEngine.preferenceKey, default: ArisComputerEngine.peekaboo.rawValue)
    /// Off on a new install (the guide asks); an install from before keeps it on (ArisFirstRun pins it at launch).
    static let arisWakeWord = Key<Bool>("arisWakeWord", default: false)
    static let arisCircleGesture = Key<Bool>("arisCircleGesture", default: true)
    static let arisSeesScreen = Key<Bool>("arisSeesScreen", default: true)
    /// Until the user changes them: the Mac's own languages (Korean and English on a Mac that speaks Korean).
    static let arisLanguages = Key<[String]>("arisLanguages", default: ArisLanguages.starting(system: ArisLanguages.macLanguages))
    static let arisCloudListening = Key<Bool>("arisCloudListening", default: true)
    static let arisConversationMinutes = Key<Int>("arisConversationMinutes", default: 5)
    /// The always-on conversation: this many seconds without speech between turns ends it; 0 turns it off.
    static let arisConversationSilence = Key<Int>("arisConversationSilence", default: ArisConversation.defaultSilenceSeconds)
    /// Talking over Aris stops it through the Mac's speakers too (with headphones it always does).
    static let arisBargeInOnSpeakers = Key<Bool>("arisBargeInOnSpeakers", default: true)
    static let claudeSounds = Key<Bool>("claudeSounds", default: true)
    /// The user muted Aris: nothing is said and nothing chimes until they lets it speak again (ArisQuiet).
    static let arisMuted = Key<Bool>(ArisQuietGate.mutedKey, default: false)
    /// The night part of quiet time, "23-7" or "off" (ArisQuietHours).
    static let arisQuietHours = Key<String>(ArisQuietGate.hoursKey, default: ArisQuietHours.standard)
    /// The terminal a Claude Code teammate opens in: "auto", or one of ArisTerminal's raw values (Settings › 팀원).
    static let arisTeammateTerminal = Key<String>("arisTeammateTerminal", default: ArisTerminal.automatic)
    /// The terminal the user last ran Claude Code in themselves, as its hooks said ("" until one was heard): ArisTerminalMemory.
    static let arisClaudeTerminal = Key<String>("arisClaudeTerminal", default: "")
    static let arisVoiceID = Key<String>("arisVoiceID", default: ArisElevenLabs.voiceID)
    static let arisVoiceName = Key<String>("arisVoiceName", default: "Geaun")
    static let arisVoiceSpeed = Key<Double>("arisVoiceSpeed", default: 1.0)
    static let arisTodoLists = Key<[String]>("arisTodoLists", default: [])
    static let arisTodoListsConfigured = Key<Bool>("arisTodoListsConfigured", default: false)
    static let arisTodoDefaultList = Key<String>("arisTodoDefaultList", default: "")
    static let arisSettingsTheme = Key<String>("arisSettingsTheme", default: "auto")
    static let calendarOpenIn = Key<String>("calendarOpenIn", default: "apple")
    /// The side notches' tabs turned off (ArisSideTab raw values); none on a fresh install.
    static let arisSideHiddenTabs = Key<[String]>(ArisSideTabChoice.preferenceKey, default: [])
    /// The shelf on/off switch; the stored name is the old one.
    static let shelfEnabled = Key<Bool>("boringShelf", default: true)
}
