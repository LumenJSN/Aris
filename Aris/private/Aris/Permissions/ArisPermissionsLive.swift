//
//  ArisPermissionsLive.swift
//  Aris
//
//  The live checks behind ArisPermissions: what macOS says to this app now, never asking, and the dialogs it can raise.
//  What only the helper can see (Full Disk Access, the folders) is asked of the helper over the app-helper channel;
//  both are the same "Aris" row. Screen Recording is the one switch a running process can't see turned on: when the
//  app still says off but a fresh helper process says on, the reading is "on, needs a relaunch".
//

import AVFoundation
import AppKit
import ApplicationServices
import Contacts
import CoreGraphics
import EventKit
import IOKit.hid
import ServiceManagement
import Speech

struct ArisPermissionsLive: ArisPermissionChecking {
    func reading(_ key: ArisPermissionKey) async -> ArisPermissionReading {
        switch key.permission {
        case .microphone: return .init(state: Self.av(AVCaptureDevice.authorizationStatus(for: .audio)))
        case .speechRecognition: return .init(state: Self.speech(SFSpeechRecognizer.authorizationStatus()))
        // A switch, not a dialog: on, or not on yet (macOS can't say "refused" for these).
        case .accessibility: return .init(state: AXIsProcessTrusted() ? .granted : .notAsked)
        // This process's listen answer is fixed at its start: a grant given since (Accessibility counts) is on, needing
        // a reopen (ArisListenOutlook), so the one reopen card can say so.
        case .inputMonitoring: return ArisListenNow.outlook.reading(listenState: Self.listen(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)))
        case .screenRecording:
            if CGPreflightScreenCaptureAccess() { return .init(state: .granted) }
            // The helper asks through a new process each time (ArisScreenAccess), so its answer is current.
            guard let helper = await ArisAgentClient.agentHasScreenAccess() else { return .init(state: .notAsked) }
            return helper ? .init(state: .granted, needsRelaunch: true) : .init(state: .notAsked)
        case .automation:
            guard let target = key.target else { return .unknown }
            return .init(state: await Task.detached(priority: .utility) { ArisAutomationAccess.state(of: target) }.value)
        // With this run's yes kept (ArisEventGrants): a grant just given is never read back as "not asked", so no
        // "it is off" card follows the yes (VM run 2026-11-19, A2).
        case .calendars: return .init(state: Self.events(ArisEventGrants.shared.status(.events)))
        case .reminders: return .init(state: Self.events(ArisEventGrants.shared.status(.reminders)))
        case .contacts: return .init(state: Self.contacts(CNContactStore.authorizationStatus(for: .contacts)))
        case .fullDiskAccess:
            guard let helper = await ArisAgentClient.agentHasDiskAccess() else { return .unknown }
            return .init(state: helper ? .granted : .notAsked)
        case .loginItem: return .init(state: Self.login(SMAppService.mainApp.status))
        // No question macOS answers without asking (system audio, the folders, location for a bare tool).
        case .systemAudio, .location, .desktopFolder, .documentsFolder, .downloadsFolder: return .unknown
        }
    }

    func prompt(_ key: ArisPermissionKey) async -> ArisPermissionState {
        switch key.permission {
        case .microphone: _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .speechRecognition:
            _ = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        case .calendars: await ArisCalendarStore.shared.requestAccess()
        case .reminders: await ArisReminders.shared.requestAccess()
        default: break
        }
        return await reading(key).state
    }

    @MainActor
    func open(link: String) async {
        guard let url = URL(string: link), link.hasPrefix("x-apple.systempreferences:") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: macOS's answers as states

    static func av(_ status: AVAuthorizationStatus) -> ArisPermissionState {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notAsked
        @unknown default: .unknown
        }
    }

    static func speech(_ status: SFSpeechRecognizerAuthorizationStatus) -> ArisPermissionState {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notAsked
        @unknown default: .unknown
        }
    }

    static func events(_ status: EKAuthorizationStatus) -> ArisPermissionState {
        switch status {
        case .fullAccess: .granted
        case .denied, .restricted, .writeOnly: .denied
        case .notDetermined: .notAsked
        @unknown default: .unknown
        }
    }

    static func contacts(_ status: CNAuthorizationStatus) -> ArisPermissionState {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notAsked
        @unknown default: .unknown
        }
    }

    static func listen(_ access: IOHIDAccessType) -> ArisPermissionState {
        switch access {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .notAsked
        }
    }

    static func login(_ status: SMAppService.Status) -> ArisPermissionState {
        switch status {
        case .enabled: .granted
        case .requiresApproval: .denied
        case .notRegistered: .notAsked
        default: .unknown
        }
    }
}
