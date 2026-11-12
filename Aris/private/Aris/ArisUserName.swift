//
//  ArisUserName.swift
//  Aris
//
//  What the user asked Aris to call them (the onboarding's name step; Settings › 일반 edits or clears it), and where it is
//  used, sparingly (the owner's N10, 2026-11-08): the onboarding's next line and its finish line, the pill's 끝났어요, and
//  every brain's <context> (their prompts say to use it now and then, never in every answer). Foundation only (tested).
//

import Foundation

enum ArisUserName {
    /// The onboarding's key (ArisOnboarding.nameKey).
    static let key = "arisOnboardingName"
    /// The longest name kept (the onboarding's field cuts at the same).
    static let maxLength = 24

    /// Where it is kept (the tests use their own).
    nonisolated(unsafe) static var store: UserDefaults = .standard

    /// The name now: what was given, if it is still a plain short name; nil otherwise.
    static var current: String? { store.string(forKey: key).flatMap(clean) }

    /// Keeps `name` (trimmed); an empty or unusable one clears it.
    static func set(_ name: String?) {
        if let name = name.flatMap(clean) { store.set(name, forKey: key) } else { store.removeObject(forKey: key) }
    }

    /// One line of plain letters, at most `maxLength`; nil for anything else (a tag, an invisible or control letter).
    static func clean(_ raw: String) -> String? {
        let name = raw.precomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !name.isEmpty, name.count <= maxLength, !name.contains("<"), !name.contains(">"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format })
        else { return nil }
        return name
    }

    /// The <context> line naming the user (the brains' nameRule says how to use it); nil without a name.
    static func contextLine(_ name: String?) -> String? {
        name.flatMap(clean).map { "user's name: \($0)" }
    }
}
