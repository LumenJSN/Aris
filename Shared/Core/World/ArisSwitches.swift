//
//  ArisSwitches.swift
//  Shared/Core (app, aris-agent, tests)
//
//  The experimental switches the helper obeys (Core 2 and "show it once"), as one setting the app owns. The app keeps
//  them in its own defaults (Settings › 할 수 있는 일 › 컴퓨터 제어 › 실험 기능) and sends them with every /health,
//  /warm and /ask; the helper keeps the last set it heard from the app itself in memory, and passes it to the children
//  it starts (the Mind's own loop, the MCP face's server) in their environment. A helper started without the app has
//  heard nothing: every switch is off.
//  Why not the defaults: the app is sandboxed, so its defaults live in its container, while the helper (not sandboxed,
//  with the app's bundle id) reads ~/Library/Preferences/com.lumenjsn.aris.plist; a `defaults write` reached one or the
//  other, never both (VM run 2026-11-19, D2). Foundation only.
//

import Foundation

enum ArisExperimentSwitch: String, CaseIterable, Sendable {
    /// The clean-slate core (ARCHITECTURE Part 2).
    case core2 = "arisCore2"
    /// Show it once (Part 3, F3); works only with Core 2 on.
    case teach = "arisTeach"
}

struct ArisSwitchSet: Equatable, Sendable {
    /// The request field the app sends them in.
    static let field = "switches"
    /// The environment variable the helper passes them to its children in.
    static let environmentKey = "ARIS_SWITCHES"

    private(set) var on: Set<ArisExperimentSwitch> = []

    init(_ on: Set<ArisExperimentSwitch> = []) { self.on = on }

    func isOn(_ name: ArisExperimentSwitch) -> Bool { on.contains(name) }

    /// `{"arisCore2": true, "arisTeach": false}`: every switch named, so an absent one is never read as "keep".
    var json: [String: Bool] {
        Dictionary(uniqueKeysWithValues: ArisExperimentSwitch.allCases.map { ($0.rawValue, on.contains($0)) })
    }

    /// From a request's field: nil unless it is an object; only the known names, only `true` turns one on.
    static func from(_ raw: Any?) -> ArisSwitchSet? {
        guard let object = raw as? [String: Any] else { return nil }
        return ArisSwitchSet(Set(ArisExperimentSwitch.allCases.filter { object[$0.rawValue] as? Bool == true }))
    }

    /// "arisCore2,arisTeach"; nil with none on.
    var environmentValue: String? {
        let names = ArisExperimentSwitch.allCases.filter(on.contains).map(\.rawValue)
        return names.isEmpty ? nil : names.joined(separator: ",")
    }

    static func from(environment value: String?) -> ArisSwitchSet {
        let words = Set((value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return ArisSwitchSet(Set(ArisExperimentSwitch.allCases.filter { words.contains($0.rawValue) }))
    }

    /// The app's own: what its Settings rows stored (its defaults, in its container). Only the app calls this.
    static func stored(in defaults: UserDefaults) -> ArisSwitchSet {
        ArisSwitchSet(Set(ArisExperimentSwitch.allCases.filter { defaults.bool(forKey: $0.rawValue) }))
    }

    /// The switches whose value differs between the two.
    func changed(from other: ArisSwitchSet) -> Set<ArisExperimentSwitch> { on.symmetricDifference(other.on) }
}
