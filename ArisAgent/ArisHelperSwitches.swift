//
//  ArisHelperSwitches.swift
//  aris-agent
//
//  The experimental switches as the helper holds them (ArisSwitchSet): what the Aris app itself last sent (with
//  /health, /warm or /ask), in memory only, all off until it does. A child the helper starts (`mind-brain`, the MCP
//  face's `hands-mcp` under Claude, an `api-brain`) takes them from its environment (ArisAgentRunner.environment puts
//  them there); the serving helper never reads them from its own environment or from any defaults file.
//

import Foundation

final class ArisHelperSwitches: @unchecked Sendable {
    static let shared = ArisHelperSwitches()

    private let lock = NSLock()
    private var current = ArisSwitchSet()

    init(_ start: ArisSwitchSet = ArisSwitchSet()) { current = start }

    var set: ArisSwitchSet { lock.withLock { current } }

    func isOn(_ name: ArisExperimentSwitch) -> Bool { lock.withLock { current.isOn(name) } }

    /// The app's field, taken only when the caller is the Aris app itself (`fromApp`). The switches that changed.
    @discardableResult
    func take(_ raw: Any?, fromApp: Bool) -> Set<ArisExperimentSwitch> {
        guard fromApp, let heard = ArisSwitchSet.from(raw) else { return [] }
        return lock.withLock {
            let changed = heard.changed(from: current)
            current = heard
            return changed
        }
    }

    /// A child the helper started: its switches are the ones the helper put in its environment.
    func adopt(environment: [String: String]) {
        let heard = ArisSwitchSet.from(environment: environment[ArisSwitchSet.environmentKey])
        lock.withLock { current = heard }
    }
}

/// What a change of the switches does to the helper's running brains: a conversation process (and its spare) chose
/// its driver, its tools and its MCP face when it started, so the brains Core 2 changes start again with the next
/// question (VM run 2026-11-19: a runner started before the switch kept the old API brain for its model).
enum ArisSwitchEffects {
    /// Core 2's live parts, started when its switch is heard on (ArisCore2Trust.start sets it).
    nonisolated(unsafe) static var core2On: () -> Void = {}

    static func brainsToRetire(_ changed: Set<ArisExperimentSwitch>) -> [ArisBrain] {
        changed.contains(.core2) ? [.api, .claude] : []
    }

    /// The app's switches from a request body (`object`), when the caller is the app; retires what a change needs.
    static func take(_ object: [String: Any], fromApp: Bool, switches: ArisHelperSwitches = .shared, retire: (ArisBrain) -> Void) {
        let changed = switches.take(object[ArisSwitchSet.field], fromApp: fromApp)
        guard !changed.isEmpty else { return }
        let names = changed.map(\.rawValue).sorted().joined(separator: ", ")
        try? FileHandle.standardError.write(contentsOf: Data("aris-agent: switches changed (\(names)): \(switches.set.environmentValue ?? "all off")\n".utf8))
        if changed.contains(.core2), switches.isOn(.core2) { core2On() }
        brainsToRetire(changed).forEach(retire)
    }
}
