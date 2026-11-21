//
//  ArisWorldSnapshot.swift
//  Aris
//
//  What is going on around Aris (ARCHITECTURE.md 3.5), as one value: the app in front, the screen, the displays, the
//  audio route, who is talking, another app on the microphone, the calendar, deadlines, running work and Claude Code's
//  last hook event. ArisWorld (the app) keeps one observer per source and folds each change in here with `reduce`; a
//  turn and the interruption policy read the result. What is expensive or private (the selection, the screen's text,
//  the clipboard) is not here: it is read on demand where it is needed. Foundation only.
//

import Foundation

/// Where the Mac's sound goes.
enum ArisAudioOutputKind: String, Equatable, Sendable, CaseIterable {
    case builtIn = "built-in"
    case wiredHeadphones = "wired headphones"
    case bluetoothHeadset = "Bluetooth headset"
    case bluetoothSpeaker = "Bluetooth speaker"
    case other

    /// How the output device is connected, as Core Audio's transport type says.
    enum Transport: Equatable, Sendable { case builtIn, bluetooth, other }

    /// `dataSource`: the built-in output's ("ispk" the speakers, "hdpn" the jack). `hasInput`: the device has a
    /// microphone side too (a Bluetooth headset worn, not a loudspeaker).
    static func of(transport: Transport, dataSource: String?, hasInput: Bool) -> ArisAudioOutputKind {
        switch transport {
        case .builtIn: dataSource == "hdpn" ? .wiredHeadphones : .builtIn
        case .bluetooth: hasInput ? .bluetoothHeadset : .bluetoothSpeaker
        case .other: .other
        }
    }

    /// Sound that only the wearer hears.
    var isHeadphones: Bool { self == .wiredHeadphones || self == .bluetoothHeadset }
}

struct ArisWorldSnapshot: Equatable, Sendable {
    struct App: Equatable, Sendable {
        var name: String?
        var bundleID: String?
        var pid: Int32
    }

    struct Display: Equatable, Sendable {
        var id: UInt32
        var builtIn: Bool
    }

    struct AudioRoute: Equatable, Sendable {
        var output: ArisAudioOutputKind
        var outputName: String?
        var inputName: String?
    }

    struct Event: Equatable, Sendable {
        var start: Date
        var end: Date
        var title: String
        var allDay: Bool
    }

    struct Deadline: Equatable, Sendable {
        var title: String
        var at: Date
    }

    struct ClaudeEvent: Equatable, Sendable {
        var name: String
        var sessionId: String
        var at: Date
    }

    var frontApp: App?
    /// The front window's title, read on demand only (it can name a private document): nil until asked.
    var windowTitle: String?
    var locked = false
    var displaysAsleep = false
    var systemAsleep = false
    var displays: [Display] = []
    var audio: AudioRoute?
    /// Music or a video plays (Now Playing says so).
    var otherAudioPlaying = false
    /// The user's voice, as the wake detector's gate heard it last, and when (seconds of system uptime).
    var userTalking = false
    var userVoiceAt: Double?
    var arisSpeaking = false
    /// Another app has a microphone open (a call, most likely): its name, or its bundle id.
    var otherAppRecording: String?
    var nextEvents: [Event] = []
    var deadlines: [Deadline] = []
    var runningJobs = 0
    /// The teammates working now, by name.
    var teammatesWorking: [String] = []
    var lastClaude: ClaudeEvent?

    /// Nobody is at the screen to see or hear anything: it is locked, its displays sleep, or the Mac does.
    var screenAway: Bool { locked || displaysAsleep || systemAsleep }

    /// A voice gate stuck open (the detector stopped mid-word) stops counting after this long.
    static let talkingStaleAfter: Double = 60

    /// The user is talking, or was a moment ago (ArisPause.afterVoice), at `now` (seconds of system uptime).
    func userSpeaking(now: Double, afterVoice: Double = 1.0) -> Bool {
        guard let at = userVoiceAt else { return userTalking }
        let since = now - at
        return userTalking ? since < Self.talkingStaleAfter : since < afterVoice
    }

    /// Folds `change` in. `publish`: whether subscribers and the kernel hear of it. A notice from the system (a lock,
    /// a wake, a display change, the device list, a hook event) is published every time it comes, as each observer
    /// heard it before; a value that is read (the front app, the route, the calendar) only when it changed.
    static func reduce(_ snapshot: ArisWorldSnapshot, _ change: ArisWorldChange) -> (ArisWorldSnapshot, publish: Bool) {
        var next = snapshot
        switch change {
        case .frontApp(let app):
            next.frontApp = app
            if app?.pid != snapshot.frontApp?.pid { next.windowTitle = nil }
        case .windowTitle(let title): next.windowTitle = title
        case .screenLocked(let locked): next.locked = locked
        case .displaysAsleep(let asleep): next.displaysAsleep = asleep
        case .systemWillSleep: next.systemAsleep = true
        case .systemDidWake: next.systemAsleep = false
        case .displays(let displays): next.displays = displays
        case .audioRoute(let route): next.audio = route
        case .audioDevices: break
        case .otherAudio(let playing): next.otherAudioPlaying = playing
        case .userVoice(let talking, let at):
            next.userTalking = talking
            next.userVoiceAt = at
        case .arisSpeaking(let speaking): next.arisSpeaking = speaking
        case .recorder(let app): next.otherAppRecording = app
        case .calendar(let events): next.nextEvents = events
        case .deadlines(let deadlines): next.deadlines = deadlines
        case .work(let jobs, let teammates):
            next.runningJobs = jobs
            next.teammatesWorking = teammates
        case .claude(let event): next.lastClaude = event
        }
        if change.isNotice { return (next, true) }
        // A voice event always moves its clock; it is news only when the gate opened or closed.
        if case .userVoice = change { return (next, next.userTalking != snapshot.userTalking) }
        return (next, next != snapshot)
    }
}

/// One change to the world, as ArisWorld publishes it (and the kernel keeps it in its ring, ArisEvent.world).
enum ArisWorldChange: Equatable, Sendable {
    case frontApp(ArisWorldSnapshot.App?)
    case windowTitle(String?)
    /// com.apple.screenIsLocked / screenIsUnlocked.
    case screenLocked(Bool)
    /// The displays went to sleep or woke (NSWorkspace screensDidSleep / screensDidWake).
    case displaysAsleep(Bool)
    case systemWillSleep
    case systemDidWake
    /// The screens' parameters changed (added, removed, moved, resized): the displays as they are now.
    case displays([ArisWorldSnapshot.Display])
    case audioRoute(ArisWorldSnapshot.AudioRoute?)
    /// The audio device list or the default input changed (one call after a burst settles, as ArisMicWatch did).
    case audioDevices
    case otherAudio(Bool)
    case userVoice(talking: Bool, at: Double)
    case arisSpeaking(Bool)
    case recorder(String?)
    case calendar([ArisWorldSnapshot.Event])
    case deadlines([ArisWorldSnapshot.Deadline])
    case work(jobs: Int, teammates: [String])
    case claude(ArisWorldSnapshot.ClaudeEvent)

    /// What a subscriber asks for.
    var topic: ArisWorldTopic {
        switch self {
        case .frontApp, .windowTitle: .frontApp
        case .screenLocked, .displaysAsleep, .systemWillSleep, .systemDidWake: .screen
        case .displays: .displays
        case .audioRoute, .audioDevices: .audio
        case .otherAudio, .userVoice, .arisSpeaking, .recorder: .activity
        case .calendar, .deadlines: .agenda
        case .work: .work
        case .claude: .claude
        }
    }

    /// The system told of it (it is published each time it comes), as against a value read and compared.
    var isNotice: Bool {
        switch self {
        case .screenLocked, .displaysAsleep, .systemWillSleep, .systemDidWake, .displays, .audioDevices, .claude: true
        default: false
        }
    }

    /// Changes that come several times a second (a voice gate, Claude Code's tool hooks) stay out of the kernel's
    /// ring, which would otherwise lose the turns' stages to them within minutes; subscribers still hear them.
    var isChatter: Bool {
        switch self {
        case .userVoice: true
        case .claude(let event): !Self.claudeMilestones.contains(event.name)
        default: false
        }
    }

    /// The hook events worth a place in the ring: a session starting, stopping, asking or ending.
    static let claudeMilestones: Set<String> = ["SessionStart", "Stop", "SubagentStop", "Notification", "SessionEnd"]
}

enum ArisWorldTopic: Hashable, Sendable, CaseIterable {
    case frontApp, screen, displays, audio, activity, agenda, work, claude
}
