//
//  ArisWakeArm.swift
//  Aris
//
//  Why the wake word (or listening between turns) isn't armed right now, said once per change (QA BUG-38: for hours
//  every guard returned in silence, so nothing in the log said which one). And how long the microphone stays closed
//  when a check can't work (fresh install F4: with no speech model on the Mac a check failed every 5 s for good, the
//  microphone on all the while): it isn't opened until the model is there, and a check that couldn't listen closes it
//  for longer each time, then for good. Pure, so it's tested.
//

import Foundation

enum ArisWakeArm {
    enum Blocker: String, Equatable {
        case settingOff = "the wake word setting is off"
        case busy = "a turn is under way"
        case training = "the wake word is being trained"
        case listenerOpen = "a turn's microphone is still open"
        case screenAway = "the screen is locked or asleep"
        case permission = "microphone or speech permission isn't given"
        case otherAudio = "another app plays or records"
        case onboarding = "the first-run guide isn't finished (permissions are asked there, never by the wake word)"
        case speechModel = "the speech recognition model isn't on this Mac yet (the microphone stays closed until it is)"
        case headsetOnly = "the only microphone is a Bluetooth headset's (it stays closed, so the headset stays in music mode)"
        case lidClosed = "the lid is closed and no other display is in use"
        case micInUse = "another app is using a microphone (a call or a recording)"
        case lowPower = "the Mac is on battery in Low Power Mode"
    }

    /// Nothing asks macOS for a permission before the first-run guide's permission page (QA BUG-55: the wake word, on by
    /// default, opened the microphone at launch and its system prompt stalled the main thread 15 s). Pure.
    static func mayTouchPermissions(onboardingSeen: Bool) -> Bool { onboardingSeen }

    struct State: Equatable {
        var settingOn = true
        var conversationOpen = false
        var idle = true
        var training = false
        var listenerOpen = false
        var screenAway = false
        var permissionOK = true
        var otherAudio = false
        var onboardingSeen = true
        /// macOS's speech model for Aris's language is installed: without it no check can hear the name.
        var speechReady = true
        /// The only microphone there is belongs to a Bluetooth headset (ArisMicPlan): opening it for hours would keep
        /// the headset in call mode, so the wake word and a conversation's listening between turns wait.
        var headsetOnly = false
        /// The lid is closed with no other display in use, another app is using a microphone, the Mac is on battery
        /// in Low Power Mode (ArisWakeRest): nobody can be calling Aris, or it must not listen.
        var lidClosed = false
        var micInUse = false
        var lowPower = false
    }

    /// The first guard that holds the microphone back, in the order they are checked; nil: arm it.
    static func blocker(_ state: State) -> Blocker? {
        if !state.settingOn && !state.conversationOpen { return .settingOff }
        if !state.onboardingSeen { return .onboarding }
        if !state.idle { return .busy }
        if state.training { return .training }
        if state.listenerOpen { return .listenerOpen }
        if state.screenAway { return .screenAway }
        if state.lidClosed { return .lidClosed }
        if !state.permissionOK { return .permission }
        if !state.speechReady { return .speechModel }
        if state.headsetOnly { return .headsetOnly }
        if !state.conversationOpen && state.micInUse { return .micInUse }
        if !state.conversationOpen && state.lowPower { return .lowPower }
        if state.conversationOpen && state.otherAudio { return .otherAudio }
        return nil
    }

    /// The waits while the speech model is still missing, and after a check that couldn't listen: half a minute, two
    /// minutes, ten.
    private static let pauses: [Duration] = [.seconds(30), .seconds(120), .seconds(600)]

    /// How long until the model is looked for again after `tries` looks that didn't find it (no microphone is open
    /// meanwhile); nil: no more looks until something changes (a turn, the setting, the screen coming back).
    static func speechRecheck(after tries: Int) -> Duration? {
        tries >= 0 && tries < pauses.count ? pauses[tries] : nil
    }

    /// How long the microphone stays closed after the `failures`th check in a row whose recognizer couldn't start;
    /// nil: it stays closed until something changes.
    static func pause(afterListenFailures failures: Int) -> Duration? {
        speechRecheck(after: max(0, failures - 1))
    }

    /// The last reason said: a line only when it changes (a turn under way is never worth a line).
    struct Log: Equatable {
        private(set) var last: Blocker?

        mutating func line(for blocker: Blocker?) -> String? {
            guard blocker != last else { return nil }
            last = blocker
            guard let blocker, blocker != .busy else { return nil }
            return "wake word not armed: \(blocker.rawValue)"
        }
    }
}
