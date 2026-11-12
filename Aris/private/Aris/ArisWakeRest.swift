//
//  ArisWakeRest.swift
//  Aris
//
//  When the wake word does not listen at all. Siri's listener can wait without a microphone indicator because it is
//  part of macOS; an app's cannot, so Aris at least knows when nobody can be calling it and closes its microphone for
//  that time (the orange indicator goes away with it), and opens it again by itself when the reason ends:
//  - the screen is locked or the display asleep (ArisController.watchScreen, as before);
//  - the lid is closed and no other display is in use;
//  - another app is using a microphone, for a call or a recording: Aris must not listen in on a call, and never
//    holds a device a call is on;
//  - the Mac runs on battery in Low Power Mode;
//  - the only microphone is a Bluetooth headset's (ArisMicPlan, as before).
//  Being muted and the quiet hours are not on this list: they silence Aris's voice, and a muted Aris can still be
//  called (it answers in text), as before. A macOS Focus is not either: an app cannot learn it without asking for a
//  permission (ArisQuiet says why), so it is not guessed.
//  Everything here is read without any permission. Each rest and each return is one line in the log; nothing is said
//  or shown, except that the open notch and the ✦ menu say in a few words why it rests. Foundation only, so the
//  whole table is tested over recorded sequences of events.
//

import Foundation

enum ArisWakeRest {
    enum Reason: String, Equatable, CaseIterable {
        case screenAway, lidClosed, headsetOnly, micInUse, lowPower
    }

    // MARK: - The facts, as read

    /// What the Mac says about the moment (ArisWakeRestProbe reads it).
    struct Facts: Equatable, Sendable {
        /// The lid's switch; nil on a Mac without one, or when it cannot be read.
        var lidClosed: Bool?
        /// Displays in use that are not the Mac's own.
        var externalDisplays = 0
        var lowPowerMode = false
        var onBattery = false
        /// Another app runs a microphone now: its bundle id ("" when it has none) and its process.
        var recorder: String?
        var recorderPid: Int32?
    }

    /// A running app, as far as naming the one on the microphone needs.
    struct App: Equatable {
        let pid: Int32
        let bundle: String?
        let name: String?
        /// An app with a Dock icon (not a helper or an agent).
        let regular: Bool
    }

    /// The name the user knows the recorder by: the app itself, or for a helper process (a browser's, a call app's) the
    /// app it belongs to; nil when there is none to name.
    static func appName(recorder: String, pid: Int32?, among apps: [App]) -> String? {
        if let own = apps.first(where: { $0.pid == pid && $0.regular }) { return own.name }
        guard !recorder.isEmpty else { return nil }
        return apps.filter(\.regular).first { app in app.bundle.map { recorder == $0 || recorder.hasPrefix($0 + ".") } ?? false }?.name
    }

    /// The lid is closed and there is no other display to look at.
    static func lidRests(_ facts: Facts) -> Bool { facts.lidClosed == true && facts.externalDisplays == 0 }

    /// Low Power Mode counts only on battery: on the charger there is nothing to save.
    static func lowPowerRests(_ facts: Facts) -> Bool { facts.lowPowerMode && facts.onBattery }

    /// macOS's own listeners, which may hold a microphone all day (“Siri야”, sound recognition): they are not a call.
    static let systemListeners = ["com.apple.CoreSpeech", "com.apple.corespeechd", "com.apple.corespeechd_system", "com.apple.accessibility.heard"]

    /// The preference that turns the rest for another app's microphone off ("off"): for a Mac where some helper
    /// holds a microphone open all day, so the wake word would rest all day.
    static let otherAppsKey = "arisWakeRestsForOtherApps"

    static func restsForOtherApps(setting: String?) -> Bool { setting != "off" }

    /// The first process that records and is neither Aris's own nor one of macOS's listeners.
    static func recorder(_ processes: [ArisOtherAudio.Process], ownPid: Int32) -> ArisOtherAudio.Process? {
        processes.first { $0.input && !ArisOtherAudio.isOwn($0, ownPid: ownPid) && !ArisOtherAudio.matches($0.bundle, systemListeners) }
    }

    /// Another app's use of a microphone, steadied: it counts from the moment it is seen, and stops counting only
    /// after `resumeAfter` seconds without it (apps open and close a microphone in bursts when a call connects).
    struct MicUse: Equatable {
        static let resumeAfter: TimeInterval = 3

        private(set) var inUse = false
        private var clearSince: TimeInterval?

        /// `recording`: another app records now; `now`: seconds on any steady clock. Whether it counts as in use.
        mutating func note(recording: Bool, at now: TimeInterval) -> Bool {
            if recording {
                inUse = true
                clearSince = nil
            } else if inUse {
                let since = clearSince ?? now
                clearSince = since
                if now - since >= Self.resumeAfter {
                    inUse = false
                    clearSince = nil
                }
            }
            return inUse
        }

        /// Seconds until a clear microphone stops counting; nil when nothing is pending.
        func recheck(at now: TimeInterval) -> TimeInterval? {
            guard inUse, let since = clearSince else { return nil }
            return max(0, Self.resumeAfter - (now - since))
        }
    }

    /// The facts written into the wake word's state.
    static func apply(_ facts: Facts, micInUse: Bool, to state: inout ArisWakeArm.State) {
        state.lidClosed = lidRests(facts)
        state.lowPower = lowPowerRests(facts)
        state.micInUse = micInUse
    }

    // MARK: - Resting or not

    /// Why the wake word rests, whatever else is going on (a turn under way does not end a rest); nil when the wake
    /// word is off or may not run at all, and when nothing asks for a rest. A conversation the user opened themselves keeps
    /// listening between turns on battery, and pauses for another app's sound by its own rule (ArisOtherAudio).
    static func reason(_ state: ArisWakeArm.State) -> Reason? {
        guard mayRun(state) else { return nil }
        if state.screenAway { return .screenAway }
        if state.lidClosed { return .lidClosed }
        if state.headsetOnly { return .headsetOnly }
        if state.conversationOpen { return nil }
        if state.micInUse { return .micInUse }
        return state.lowPower ? .lowPower : nil
    }

    /// The wake word is switched on and allowed to run at all (set up, permissions given).
    static func mayRun(_ state: ArisWakeArm.State) -> Bool { state.settingOn && state.onboardingSeen && state.permissionOK }

    /// How often the facts are read again, in seconds. Armed, another app joining the microphone Aris itself has open
    /// is only seen by asking every audio process (about a millisecond of work), so that is asked rarely; resting for
    /// another app, the cheap question "is any microphone running" is asked often, so the return is prompt.
    static func recheckEvery(_ reason: Reason?) -> TimeInterval { reason == .micInUse ? 2 : 10 }

    // MARK: - The log

    /// One line per rest and per return (category `microphone`), never one per look.
    struct Log: Equatable {
        private(set) var last: Reason?

        /// `wakeWordOn`: false when the wake word is switched off or may not run: then there is no rest and no
        /// return to write, and the next rest starts afresh.
        mutating func line(for reason: Reason?, wakeWordOn: Bool = true) -> String? {
            guard wakeWordOn else {
                last = nil
                return nil
            }
            guard reason != last else { return nil }
            defer { last = reason }
            if let reason { return "wake word rests: \(why(reason)) (its microphone is closed)" }
            return last.map { "wake word listens again: \(ended($0))" }
        }

        private func why(_ reason: Reason) -> String {
            switch reason {
            case .screenAway: "the screen is locked or asleep"
            case .lidClosed: "the lid is closed and no other display is in use"
            case .headsetOnly: "the only microphone is a Bluetooth headset's"
            case .micInUse: "another app is using a microphone"
            case .lowPower: "Low Power Mode on battery"
            }
        }

        private func ended(_ reason: Reason) -> String {
            switch reason {
            case .screenAway: "the screen is back"
            case .lidClosed: "the lid is open, or a display is in use"
            case .headsetOnly: "another microphone is here"
            case .micInUse: "the other app let the microphone go"
            case .lowPower: "Low Power Mode ended, or the charger is in"
            }
        }
    }

    // MARK: - The words the user sees

    /// What the open notch and the ✦ menu say while the wake word rests. `app`: the app using the microphone, when
    /// its name is known.
    static func words(_ reason: Reason, app: String? = nil, english: Bool) -> String {
        switch reason {
        case .screenAway:
            return english ? "Not listening for “Aris”: the screen is locked" : "화면이 잠겨서 이름 듣기는 쉬는 중"
        case .lidClosed:
            return english ? "Not listening for “Aris”: the lid is closed" : "덮개가 닫혀서 이름 듣기는 쉬는 중"
        case .headsetOnly:
            return english ? "Not listening for “Aris”: only the headphones' microphone is here" : "헤드폰 마이크뿐이라 이름 듣기는 쉬는 중"
        case .micInUse:
            guard let app, !app.isEmpty else {
                return english ? "Not listening for “Aris”: another app is using the microphone" : "다른 앱이 마이크를 쓰는 중이라 이름 듣기는 쉬는 중"
            }
            return english ? "Not listening for “Aris”: \(app) is using the microphone" : "\(app)에서 마이크를 쓰는 중이라 이름 듣기는 쉬는 중"
        case .lowPower:
            return english ? "Not listening for “Aris”: Low Power Mode" : "저전력 모드라 이름 듣기는 쉬는 중"
        }
    }

    /// The symbol beside those words.
    static let symbol = "mic.slash"

    /// What the wake word's tuning log keeps of Whisper's text for a check that went down `path`: the words only when
    /// the name was heard; for a phrase that was not the name ("rejected") nothing of what was said.
    static func kept(_ heard: String?, path: String) -> String {
        path == "rejected" ? "" : heard ?? ""
    }
}

/// What turning the wake word on really means, in one sentence, wherever it is described.
enum ArisWakeHonesty {
    /// Settings › Aris › 부르기: the row's description.
    static let settingsLine = "말로 부르면 듣기 시작해요. 기다리는 동안에는 마이크가 켜져 있어서 macOS의 마이크 표시가 뜨고, 이름을 듣기 전에는 아무것도 보내거나 남기지 않으며, 화면이 잠기거나 다른 앱이 마이크를 쓰면 알아서 쉬어요."
    static let settingsLineEnglish = "Say the name and Aris starts listening. While it waits the microphone is on and macOS shows its indicator; nothing is sent or kept before it hears the name, and it rests by itself when the screen is locked or another app is using the microphone."

    /// Korean → English, for the settings pages' lookup (ArisSettingsCopyMore).
    /// Settings › 대화 › 부르기: the small line under the card (the row itself keeps one short sentence).
    static let note = "“아리스”는 이 Mac 안에서만 알아듣고 듣기 전에는 아무것도 보내거나 남기지 않으며, 기다리는 동안 macOS의 마이크 표시가 뜨고 화면이 잠기거나 다른 앱이 마이크를 쓰면 알아서 쉬어요."
    static let noteEnglish = "“Aris” is recognised on this Mac only and nothing is sent or kept before it is heard; while it waits macOS shows its microphone indicator, and it rests by itself when the screen is locked or another app is using the microphone."
    static let untrained = " 목소리를 익히기 전에는 “아리스”로 시작하는 말을 모두 확인해요."
    static let untrainedEnglish = " Until a voice is learned, everything that starts with “Aris” is checked."
    static let noteUntrained = note + untrained

    static let english: [String: String] = [settingsLine: settingsLineEnglish, note: noteEnglish, noteUntrained: noteEnglish + untrainedEnglish]

    /// The sentence alone (the notch, a tooltip, the first-run guide's page).
    static func line(english: Bool) -> String {
        english ? "While it waits the microphone is on and macOS shows its indicator; nothing is sent or kept before it hears the name, and it rests by itself when the screen is locked or another app is using the microphone."
            : "기다리는 동안에는 마이크가 켜져 있어서 macOS의 마이크 표시가 뜨고, 이름을 듣기 전에는 아무것도 보내거나 남기지 않으며, 화면이 잠기거나 다른 앱이 마이크를 쓰면 알아서 쉬어요."
    }
}
