//
//  ArisPermissionSetup.swift
//  Aris (ArisCore)
//
//  The first run's one list: only what the chosen features need, each with its state as it changes, in the fewest
//  steps macOS allows. The dialogs Aris can raise come first, one after the other from one button; the panes that
//  need a switch come after, one at a time. A dialog refused before can't be raised again (macOS won't ask twice), so
//  it becomes its pane. What macOS asks by itself at a first touch (folders, an app's Apple Events, system audio) and
//  open at login (a choice, not a permission) are not on the list, nor what a feature asks at its first use
//  (ArisPermissionFeature.askedAtFirstUse: Screen Recording waits for the first circle). Also the live checks' seam and the pane watch.
//  Pure.
//

import Foundation

/// One line of the setup's list.
struct ArisSetupPermission: Equatable, Sendable {
    let permission: ArisPermission
    let state: ArisPermissionState
    /// The chosen features that need it, in ArisPermissionFeature's order.
    let features: [ArisPermissionFeature]
}

/// What the setup's button does next.
enum ArisSetupPermissionStep: Equatable, Sendable {
    /// Raise these dialogs one after the other.
    case prompts([ArisPermission])
    /// Open this pane and wait for its switch.
    case pane(ArisPermission)
}

enum ArisPermissionSetup {
    /// The order the list is shown and walked in: dialogs, then panes, most needed first.
    static let order: [ArisPermission] = [.microphone, .speechRecognition, .calendars, .reminders,
                                          .accessibility, .screenRecording, .inputMonitoring, .fullDiskAccess,
                                          .contacts, .location]

    /// The list for `chosen` features, as `model` has them now.
    static func list(for chosen: Set<ArisPermissionFeature>, in model: ArisPermissions) -> [ArisSetupPermission] {
        order.compactMap { permission in
            let features = ArisPermissionFeature.allCases.filter {
                chosen.contains($0) && $0.needs.contains(permission) && !$0.askedAtFirstUse.contains(permission)
            }
            guard !features.isEmpty else { return nil }
            return ArisSetupPermission(permission: permission, state: model.state(permission), features: features)
        }
    }

    /// The step the button takes next; nil once everything on the list is on (or the only ones left are dialogs
    /// already answered no, whose panes come one at a time like any other).
    static func next(for chosen: Set<ArisPermissionFeature>, in model: ArisPermissions) -> ArisSetupPermissionStep? {
        let open = list(for: chosen, in: model).filter { !model.satisfied(ArisPermissionKey($0.permission)) }
        let prompts = open.filter { $0.permission.ask == .prompt && $0.state != .denied }.map(\.permission)
        if !prompts.isEmpty { return .prompts(prompts) }
        return open.first.map { .pane($0.permission) }
    }

    /// Every permission on the list is on.
    static func done(for chosen: Set<ArisPermissionFeature>, in model: ArisPermissions) -> Bool { next(for: chosen, in: model) == nil }

    /// How many separate things the user does from here: one for the whole run of dialogs, one per pane.
    static func steps(for chosen: Set<ArisPermissionFeature>, in model: ArisPermissions) -> Int {
        let open = list(for: chosen, in: model).filter { !model.satisfied(ArisPermissionKey($0.permission)) }
        let prompts = open.contains { $0.permission.ask == .prompt && $0.state != .denied } ? 1 : 0
        return prompts + open.filter { $0.permission.ask != .prompt || $0.state == .denied }.count
    }
}

/// The live checks, behind a seam so the tests drive every state (ArisPermissionsLive in the app).
protocol ArisPermissionChecking: Sendable {
    /// What macOS says now. Never asks.
    func reading(_ key: ArisPermissionKey) async -> ArisPermissionReading
    /// Raises macOS's own dialog for a prompt-kind permission and returns its answer.
    func prompt(_ key: ArisPermissionKey) async -> ArisPermissionState
    /// Opens a pane by its deep link.
    func open(link: String) async
}

/// While a pane is open, its switch is read every second, for a while: System Settings tells Aris nothing, so a
/// switch turned on is noticed within a second without a relaunch (where macOS allows it).
struct ArisPaneWatch: Equatable, Sendable {
    static let interval: TimeInterval = 1
    /// How long after opening a pane it is still watched (long enough to find the switch and type a password).
    static let window: TimeInterval = 180

    private(set) var watching: [ArisPermissionKey: Date] = [:]

    func opened(_ key: ArisPermissionKey, at now: Date) -> ArisPaneWatch {
        var next = self
        next.watching[key] = now
        return next
    }

    /// The keys still watched at `now`, and the watch without those that ran out or are on now.
    func due(at now: Date, in model: ArisPermissions) -> ([ArisPermissionKey], ArisPaneWatch) {
        var next = self
        next.watching = watching.filter { key, since in now.timeIntervalSince(since) <= Self.window && !model.satisfied(key) }
        return (next.watching.keys.sorted { $0.description < $1.description }, next)
    }

    var isWatching: Bool { !watching.isEmpty }
}
