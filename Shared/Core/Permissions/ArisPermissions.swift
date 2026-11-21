//
//  ArisPermissions.swift
//  Aris (ArisCore)
//
//  The one permission model every feature asks (aris-perms). For each permission: what macOS says now, and what Aris
//  already asked and told, so nothing is asked twice:
//   · `require(_:for:)` is a feature's question. Granted proceeds. Not asked says the feature's one sentence of why and
//     raises macOS's dialog then (or opens the pane, or lets macOS ask at the first touch), once. Refused, or asked
//     and still off, says so once with the pane's button; after that the feature does without, quietly.
//   · `updating(_:to:)` takes a live reading (on app activation, and every second while a pane is open). A switch
//     turned on in System Settings is noticed there; one this process can only use after a relaunch says so once. A
//     dialog permission macOS reports as never answered again (reset outside Aris) is asked again at its next use.
//   · Nothing here asks at launch: a permission is asked only by a feature that needs it, or by the setup for the
//     features the user chose (ArisPermissionSetup).
//  Immutable: every change returns a new model. Pure, so the tests walk every state.
//

import Foundation

/// What Aris asked and told about one permission, kept across launches.
struct ArisPermissionRecord: Codable, Equatable, Sendable {
    /// When Aris raised macOS's dialog, opened the pane, or let macOS ask at a first touch.
    var askedAt: Date?
    /// What came of that ask, as the next reading found it.
    var outcome: ArisPermissionState?
    /// When the user was told it is off (once).
    var toldOffAt: Date?
    /// When a relaunch was offered for a grant this process can't use yet (once per grant).
    var relaunchOfferedAt: Date?
}

/// A feature's answer from `require`.
enum ArisPermissionDecision: Equatable, Sendable {
    /// Go ahead.
    case proceed
    /// Say `reason` (the existing notice), then raise macOS's dialog now.
    case prompt(ArisPermissionKey, reason: String)
    /// Say `reason`, then open the pane at `link`; the feature waits for the switch (re-checked while it is open).
    case openPane(ArisPermissionKey, link: String, reason: String)
    /// Say `reason`, then go ahead: macOS asks by itself at the first touch (a folder, an app's first Apple Event).
    case proceedAfterSaying(ArisPermissionKey, reason: String)
    /// It is off: say `reason` once with a button to the pane at `link`; the feature does without.
    case tellOff(ArisPermissionKey, link: String, reason: String)
    /// Off and already told: do without, quietly (a degrading feature says what it did without, in its own words).
    case doWithout(ArisPermissionKey)
    /// On, but this process sees it only after a relaunch: offer one button for it (once).
    case offerRelaunch(ArisPermissionKey)
}

/// Something a reading changed that the user should hear about.
enum ArisPermissionChange: Equatable, Sendable {
    /// Turned on (in a dialog or in System Settings) since the last reading.
    case granted(ArisPermissionKey)
    /// Refused in macOS's dialog, or switched off.
    case refused(ArisPermissionKey)
    /// On, and this process needs a relaunch to use it: one button (`ArisPermissionDecision.offerRelaunch`).
    case relaunchNeeded(ArisPermissionKey)
}

struct ArisPermissions: Equatable, Sendable {
    private(set) var states: [ArisPermissionKey: ArisPermissionState] = [:]
    private(set) var records: [ArisPermissionKey: ArisPermissionRecord] = [:]
    /// Grants macOS has but this process can't use until it is reopened.
    private(set) var awaitingRelaunch: Set<ArisPermissionKey> = []

    init() {}

    func state(_ key: ArisPermissionKey) -> ArisPermissionState { states[key] ?? .unknown }
    func state(_ permission: ArisPermission) -> ArisPermissionState { state(ArisPermissionKey(permission)) }
    func record(_ key: ArisPermissionKey) -> ArisPermissionRecord { records[key] ?? ArisPermissionRecord() }

    /// Whether a feature has everything it needs now (Full Disk Access stands in for the three folders).
    func ready(_ feature: ArisPermissionFeature) -> Bool { keys(for: feature).allSatisfy { satisfied($0) } }

    /// The permissions a feature needs, keyed (one Automation key per target app).
    func keys(for feature: ArisPermissionFeature) -> [ArisPermissionKey] {
        feature.needs.flatMap { permission -> [ArisPermissionKey] in
            permission == .automation ? feature.automationTargets.map(ArisPermissionKey.automation) : [ArisPermissionKey(permission)]
        }
    }

    func satisfied(_ key: ArisPermissionKey) -> Bool {
        if awaitingRelaunch.contains(key) { return false }
        if state(key) == .granted { return true }
        return key.permission.isFolder && state(.fullDiskAccess) == .granted
    }

    // MARK: - A feature's question

    /// What `feature` should do about `key` now, and the model with the ask or the telling recorded.
    func require(_ key: ArisPermissionKey, for feature: ArisPermissionFeature, english: Bool = false, now: Date = Date()) -> (ArisPermissions, ArisPermissionDecision) {
        if satisfied(key) { return (self, .proceed) }
        var next = self
        var record = record(key)
        let reason = feature.reason(english: english)
        if awaitingRelaunch.contains(key) {
            guard record.relaunchOfferedAt == nil else { return (self, .doWithout(key)) }
            record.relaunchOfferedAt = now
            next.records[key] = record
            return (next, .offerRelaunch(key))
        }
        switch state(key) {
        case .granted:
            return (self, .proceed)
        case .notAsked where record.askedAt == nil, .unknown where record.askedAt == nil && key.permission.ask != .pane:
            record.askedAt = now
            next.records[key] = record
            switch key.permission.ask {
            case .prompt: return (next, .prompt(key, reason: reason))
            case .pane: return (next, .openPane(key, link: key.permission.paneLink, reason: reason))
            case .onUse, .consent: return (next, .proceedAfterSaying(key, reason: reason))
            }
        case .unknown:
            // A pane-kind permission whose state can't be read from here (the helper hasn't answered): try, and let
            // the call itself report what it lacked.
            return (self, .proceed)
        case .notAsked, .denied:
            guard record.toldOffAt == nil else { return (self, .doWithout(key)) }
            record.toldOffAt = now
            next.records[key] = record
            return (next, .tellOff(key, link: key.permission.paneLink, reason: reason))
        }
    }

    /// `require` for every key a feature needs: the first one that is not a plain go-ahead decides.
    func require(_ feature: ArisPermissionFeature, english: Bool = false, now: Date = Date()) -> (ArisPermissions, ArisPermissionDecision) {
        var model = self
        for key in keys(for: feature) {
            let (next, decision) = model.require(key, for: feature, english: english, now: now)
            model = next
            if decision != .proceed { return (model, decision) }
        }
        return (model, .proceed)
    }

    // MARK: - Readings

    /// The model after a live reading of `key`, and what changed that the user should hear about. A grant made in
    /// System Settings clears what was told, so a later refusal is told again.
    func updating(_ key: ArisPermissionKey, to reading: ArisPermissionReading) -> (ArisPermissions, [ArisPermissionChange]) {
        var next = self
        var changes: [ArisPermissionChange] = []
        let before = state(key)
        let wasWaiting = awaitingRelaunch.contains(key)
        // An unknown reading says nothing new: what was known stays.
        if reading.state != .unknown { next.states[key] = reading.state }
        var record = record(key)
        // macOS says it has never been answered, though it answered Aris's ask before (the user reset it, or removed
        // Aris's row, outside Aris): what Aris kept about asking is stale, so the first-use ask happens again instead of
        // "it is off, go to Settings" for a dialog macOS would show now (third VM run, D6). Only where macOS has a
        // dialog of its own to show again (a pane's switch reads "not asked" whenever it is off); an ask that got no
        // answer at all is still told, not asked again, and a refusal macOS still reports is kept as it was.
        if reading.state == .notAsked, key.permission.ask == .prompt, record.outcome != nil {
            record.askedAt = nil
            record.outcome = nil
            record.toldOffAt = nil
        }
        if record.askedAt != nil, record.outcome == nil, reading.state == .granted || reading.state == .denied {
            record.outcome = reading.state
        }
        if reading.state == .granted {
            if reading.needsRelaunch && key.permission.relaunchToSee {
                next.awaitingRelaunch.insert(key)
                if !wasWaiting { changes.append(.relaunchNeeded(key)) }
            } else {
                next.awaitingRelaunch.remove(key)
                if before != .granted || wasWaiting { changes.append(.granted(key)) }
            }
            record.toldOffAt = nil
        } else if reading.state != .unknown {
            next.awaitingRelaunch.remove(key)
            record.relaunchOfferedAt = nil
            if reading.state == .denied && before != .denied { changes.append(.refused(key)) }
        }
        next.records[key] = record == ArisPermissionRecord() ? nil : record
        return (next, changes)
    }

    /// Several readings at once (one pass of the live checks), changes in the order given.
    func updating(_ readings: [(ArisPermissionKey, ArisPermissionReading)]) -> (ArisPermissions, [ArisPermissionChange]) {
        readings.reduce((self, [ArisPermissionChange]())) { partial, item in
            let (next, changes) = partial.0.updating(item.0, to: item.1)
            return (next, partial.1 + changes)
        }
    }

    /// The model after a relaunch: what macOS says is read again from scratch, what was asked and told is kept.
    func relaunched() -> ArisPermissions {
        var next = self
        next.awaitingRelaunch = []
        next.states = [:]
        return next
    }

    /// The model with `key` marked as told it is off (a feature with its own line said it), so no other path says it
    /// again until the switch has been on.
    func notingToldOff(_ key: ArisPermissionKey, at now: Date = Date()) -> ArisPermissions {
        var next = self
        var record = record(key)
        record.toldOffAt = record.toldOffAt ?? now
        next.records[key] = record
        return next
    }

    /// The same for a relaunch offered by a feature's own line.
    func notingRelaunchOffered(_ key: ArisPermissionKey, at now: Date = Date()) -> ArisPermissions {
        var next = self
        var record = record(key)
        record.relaunchOfferedAt = record.relaunchOfferedAt ?? now
        next.records[key] = record
        return next
    }

    // MARK: - Kept across launches

    /// What is kept (the records; states are always read again).
    var saved: Data? {
        let list = records.map { Saved(key: $0.key, record: $0.value) }.sorted { $0.key.description < $1.key.description }
        return try? JSONEncoder().encode(list)
    }

    static func restored(from data: Data?) -> ArisPermissions {
        var model = ArisPermissions()
        guard let data, let list = try? JSONDecoder().decode([Saved].self, from: data) else { return model }
        for item in list { model.records[item.key] = item.record }
        return model
    }

    private struct Saved: Codable {
        let key: ArisPermissionKey
        let record: ArisPermissionRecord
    }
}
