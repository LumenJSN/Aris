//
//  ArisWakeName.swift
//  Aris
//
//  The name that wakes Aris, chosen in Settings › 부르기 (2026-11-18 audit: it was fixed to 아리스|아리쓰|aris), and the
//  spellings the recognisers wrote when the user taught Aris their voice (the training's recordings, read once by
//  Whisper: ArisController.learnWakeVariants). Stored with the other wake settings (UserDefaults, beside
//  arisWakeWord). The detector's check (ArisWakeWord), the echo checks (ArisEchoGuard.namesAris) and Whisper's reading
//  of a candidate (ArisWakeEvidence, ArisWakeDoubt.checkPrompt) all read it from here. Foundation only (tested).
//

import Foundation

struct ArisWakeName: Equatable, Sendable {
    static let nameKey = "arisWakeName"
    static let learnedKey = "arisWakeLearned"
    /// The name a fresh install answers to.
    static let defaultName = "아리스"
    /// How the recognisers write the default name.
    static let defaultSpellings = ["아리스", "아리쓰", "aris"]
    /// A chosen name is at most this long, at least `shortest` letters.
    static let longest = 20
    static let shortest = 2
    /// Learned spellings kept (the newest first).
    static let mostLearned = 6

    /// The chosen name, cleaned (the default when what was typed can't be a name).
    let name: String
    /// What the recognisers wrote for the user saying it.
    let learned: [String]

    /// The default name as the UI writes it.
    static func defaultName(english: Bool) -> String { english ? "Aris" : defaultName }

    init(name: String?, learned: [String] = []) {
        // "Aris" (the English window's way of writing it) is the default name, with all its spellings.
        let cleaned = Self.cleaned(name)
        self.name = cleaned.map { $0.lowercased() == "aris" ? Self.defaultName : $0 } ?? Self.defaultName
        self.learned = Array(Self.unique(learned.compactMap(Self.cleaned)).prefix(Self.mostLearned))
    }

    var isDefault: Bool { name == Self.defaultName }

    /// Every spelling that counts as the name, lower-cased, longest first (so "아리스야" never reads as a shorter one).
    var spellings: [String] {
        let own = isDefault ? Self.defaultSpellings : [name.lowercased()]
        return Self.unique(own + learned.map { $0.lowercased() }).sorted { $0.count > $1.count }
    }

    /// The spellings as one regular-expression group's alternatives.
    var pattern: String { spellings.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") }

    /// The name as Whisper's prompt writes it: the default in each language's letters, a chosen one as typed.
    func prompt(language: String?) -> String { isDefault ? (language == "ko" ? "아리스" : "Aris") : name }

    /// A typed name trimmed; nil when it is too short or long, or has anything but letters and spaces.
    static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let letters = text.unicodeScalars.filter(CharacterSet.letters.contains).count
        guard letters >= shortest, text.count <= longest,
              text.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || $0 == " " }) else { return nil }
        return text
    }

    private static func unique(_ words: [String]) -> [String] {
        var seen = Set<String>()
        return words.filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: - Learning from the training's recordings

    /// A spelling heard in at least this many of the recordings is learned (one could be a mishearing).
    static let heardAtLeast = 2

    /// The spellings to learn from what the recogniser wrote for each recording of the user saying the name: the whole
    /// of a short reading (one or two words), heard at least twice, that isn't already a spelling. Kept with the ones
    /// learned before, the newest first.
    func learning(from transcripts: [String]) -> ArisWakeName {
        let known = Set(spellings)
        let heard = transcripts.compactMap { text -> String? in
            let words = text.lowercased().components(separatedBy: CharacterSet.letters.union(.whitespaces).inverted).joined()
                .split(separator: " ").map(String.init)
            guard (1...2).contains(words.count), let word = Self.cleaned(words.joined(separator: " ")) else { return nil }
            return word
        }
        let counts = Dictionary(heard.map { ($0, 1) }, uniquingKeysWith: +)
        let new = Self.unique(heard).filter { counts[$0, default: 0] >= Self.heardAtLeast && !known.contains($0) }
        return ArisWakeName(name: name, learned: new + learned)
    }

    // MARK: - Where it lives

    /// Set by the tests; nil: the stored settings.
    nonisolated(unsafe) static var overrideForTests: ArisWakeName?

    /// The name now, as stored.
    static var current: ArisWakeName { overrideForTests ?? load(.standard) }

    static func load(_ defaults: UserDefaults) -> ArisWakeName {
        ArisWakeName(name: defaults.string(forKey: nameKey), learned: defaults.stringArray(forKey: learnedKey) ?? [])
    }

    /// Stores a new chosen name; a different name forgets what was learned for the old one.
    static func save(name raw: String, to defaults: UserDefaults) {
        let next = ArisWakeName(name: raw)
        if next.name != load(defaults).name { defaults.removeObject(forKey: learnedKey) }
        if next.isDefault { defaults.removeObject(forKey: nameKey) } else { defaults.set(next.name, forKey: nameKey) }
    }

    static func save(learned: ArisWakeName, to defaults: UserDefaults) {
        defaults.set(learned.learned, forKey: learnedKey)
    }
}
