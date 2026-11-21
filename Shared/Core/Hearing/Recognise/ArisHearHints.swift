//
//  ArisHearHints.swift
//  Aris (Shared/Core, Foundation only)
//
//  The short list of words every recogniser that takes hints is told to expect: Aris's own name and the owner's, the
//  words he listed (Settings › 단어장) and those dictation learned from his fixes, the names he gave his saved steps,
//  and the names of the apps on this Mac (the running ones first). Only names Aris already keeps as names go in: text
//  read from an app or the screen is content, never the owner's words, and is never a hint.
//

import Foundation

enum ArisHearHints {
    struct Sources: Equatable, Sendable {
        var assistant: [String] = ["Aris", "아리스"]
        var owner: String?
        /// The owner's own list, then the words learned from his corrections.
        var words: [String] = []
        /// The names he gave his saved steps.
        var lessons: [String] = []
        var runningApps: [String] = []
        var installedApps: [String] = []
    }

    /// What one engine takes.
    struct Bounds: Equatable, Sendable {
        let count: Int
        let length: Int

        /// ElevenLabs realtime: 50 keyterms of at most 20 characters (docs/overview/capabilities/speech-to-text).
        static let scribe = Bounds(count: 50, length: 20)
        /// Soniox context.terms: "long lists are fine", 8,000 tokens in all; kept far below.
        static let soniox = Bounds(count: 200, length: 40)
        /// OpenAI gpt-transcribe `keywords`: no published cap; kept short.
        static let openAI = Bounds(count: 100, length: 40)
        /// The repair pass names fewer: it reads them all on every turn.
        static let repair = Bounds(count: 60, length: 40)
    }

    /// The hints, most important first, each once (however it is capitalised), within `bounds`.
    static func build(_ sources: Sources, bounds: Bounds) -> [String] {
        let ordered = sources.assistant + [sources.owner].compactMap { $0 } + sources.words + sources.lessons
            + sources.runningApps + sources.installedApps
        var seen = Set<String>()
        var hints: [String] = []
        for raw in ordered {
            guard hints.count < bounds.count else { break }
            guard let term = clean(raw, length: bounds.length), seen.insert(term.lowercased()).inserted else { continue }
            hints.append(term)
        }
        return hints
    }

    /// A term as an engine takes it: one line, trimmed, not empty, not longer than `length`, and with a letter or a
    /// digit in it. Too long is left out, never cut: half a name is a wrong hint.
    static func clean(_ raw: String, length: Int) -> String? {
        let term = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !term.isEmpty, term.count <= length, !raw.contains(where: \.isNewline),
              term.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) else { return nil }
        return term
    }

    /// The names in aris-agent's taught.json (ArisTeachStore), read without its steps: only what the owner called them.
    static func lessonNames(in data: Data?, most: Int = 50) -> [String] {
        guard let data, let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return Array(entries.compactMap { ($0 as? [String: Any])?["name"] as? String }.prefix(most))
    }
}
