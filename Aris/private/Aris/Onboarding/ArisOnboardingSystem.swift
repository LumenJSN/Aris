//
//  ArisOnboardingSystem.swift
//  Aris
//
//  What the onboarding asks macOS: each permission's state now (never asking) and the card's 허용 for it. Accessibility
//  and Screen Recording go through ArisPermissionGuide (System Settings opens on the right list with the drag panel
//  docked under it; macOS's own Screen Recording request is never raised, fresh install F8). The mic and speech
//  recognition show macOS's own dialogs; one already refused opens its System Settings list instead (macOS won't ask
//  twice). ArisDiagnostics reads the same states.
//

import AVFoundation
import AppKit
import Carbon
import EventKit
import KeyboardShortcuts
import ServiceManagement
import Speech

@MainActor
enum ArisOnboardingSystem {
    typealias Step = ArisOnboardingStep

    static let live = ArisOnboardingModel.Actions(grant: grant, request: ask, stop: stop, talkKeys: talkKeys,
                                                  firstCapture: firstCapture, captureAllowed: captureAllowed)

    /// The Screen Recording card's second question from macOS (ArisFirstCapture): the app's first real capture, the
    /// frame dropped at once. A yes is remembered, so the setup never captures for it again.
    static func firstCapture() async -> ArisFirstCapture.Outcome {
        let outcome = await ArisScreenCapture.shared.firstCapture()
        if outcome == .allowed { ArisAppCaptureFirst.allowed() }
        return outcome
    }

    static func captureAllowed() -> Bool { UserDefaults.standard.bool(forKey: ArisFirstCapture.allowedKey) }

    /// A card's 허용: macOS's dialog, or its System Settings list when it was refused before.
    static func ask(_ step: Step) async {
        if grant(step) == .denied { return openSettings(step) }
        await request(step)
    }

    /// 나중에 while System Settings is open: the drag panel goes.
    static func stop(_ step: Step) {
        if step == .accessibility || step == .screen { ArisPermissionGuide.shared.close() }
    }

    /// Automation is checked against the Music app (Aris's own Apple Events go to music players and terminals); the
    /// answer is kept, since asking TCC blocks.
    private static var automation: ArisGrant = .undecided
    private static let automationTarget = "com.apple.Music"
    /// aris-agent's Full Disk Access as the agent last said (the app is sandboxed and can't tell on its own); asked
    /// again at most every 3 s while the guide polls.
    private static var diskAccess: ArisGrant = .undecided
    private static var diskAccessAsked = Date.distantPast

    private static func refreshDiskAccess() {
        guard Date().timeIntervalSince(diskAccessAsked) >= 3 else { return }
        diskAccessAsked = Date()
        Task { @MainActor in diskAccess = await ArisAgentClient.agentHasDiskAccess() == true ? .granted : .undecided }
    }

    static func grant(_ step: Step) -> ArisGrant {
        switch step {
        case .mic: return av(AVCaptureDevice.authorizationStatus(for: .audio))
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            default: return .undecided
            }
        // No prompt to answer: either on or not yet.
        case .accessibility: return AXIsProcessTrusted() ? .granted : .undecided
        case .screen: return CGPreflightScreenCaptureAccess() ? .granted : .undecided
        case .calendar: return events(EKEventStore.authorizationStatus(for: .event))
        case .reminders: return events(EKEventStore.authorizationStatus(for: .reminder))
        case .automation: return automation
        case .fullDisk:
            refreshDiskAccess()
            return diskAccess
        case .login: return ArisLoginItem.isEnabled ? .granted : .undecided
        }
    }

    static func request(_ step: Step) async {
        switch step {
        case .mic: _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .speech:
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        case .accessibility: ArisPermissionGuide.shared.show(.accessibility)
        case .screen: ArisPermissionGuide.shared.show(.screen)
        case .calendar: await ArisCalendarStore.shared.requestAccess()
        case .reminders: await ArisReminders.shared.requestAccess()
        case .automation: automation = await askAutomation()
        case .fullDisk: openSettings(.fullDisk)
        case .login: break
        }
    }

    static func openSettings(_ step: Step) {
        let pane: String
        switch step {
        case .mic: pane = "Privacy_Microphone"
        case .speech: pane = "Privacy_SpeechRecognition"
        case .accessibility: return ArisPermissionGuide.shared.show(.accessibility)
        case .screen: return ArisPermissionGuide.shared.show(.screen)
        case .calendar: pane = "Privacy_Calendars"
        case .reminders: pane = "Privacy_Reminders"
        case .automation: pane = "Privacy_Automation"
        case .fullDisk: pane = "Privacy_AllFiles"
        case .login: return SMAppService.openSystemSettingsLoginItems()
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    /// The talk shortcut as key caps ("⌥", "Space").
    static func talkKeys() -> [String] {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .talkToAris) else { return ["⌥", "Space"] }
        let text = shortcut.description
        let modifiers = text.filter { "⌃⌥⇧⌘".contains($0) }.map(String.init)
        let key = String(text.drop { "⌃⌥⇧⌘".contains($0) })
        return modifiers + [key == " " || key.isEmpty ? "Space" : key]
    }

    /// macOS's Automation dialog for Music; off the main thread (AEDeterminePermissionToAutomateTarget blocks).
    private static func askAutomation() async -> ArisGrant {
        let target = automationTarget
        return await Task.detached(priority: .userInitiated) {
            let descriptor = NSAppleEventDescriptor(bundleIdentifier: target)
            guard let desc = descriptor.aeDesc else { return ArisGrant.undecided }
            let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true)
            return ArisGrant.automation(status: status)
        }.value
    }

    private static func av(_ status: AVAuthorizationStatus) -> ArisGrant {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        default: .undecided
        }
    }

    private static func events(_ status: EKAuthorizationStatus) -> ArisGrant {
        switch status {
        case .fullAccess: .granted
        case .denied, .restricted, .writeOnly: .denied
        default: .undecided
        }
    }
}
