//
//  ArisLearnedDictionary.swift
//  Aris (and aris-agent)
//
//  Words dictation learned from the user's own corrections: when they fixes one misheard word in what Aris just typed,
//  aris-agent proposes it; the same fix twice adds it. At most 100 words. They go to the recognizer as hints and to
//  polish as spellings. A word the user dismissed or deleted is never learned again. Kept in
//  ~/.config/aris/aris/dictionary.json (0600), written only by aris-agent (the app is sandboxed: it reads it, and asks
//  the agent to change it). Foundation only (tested).
//

import Foundation

struct ArisLearnedWord: Codable, Equatable {
    /// How it's written.
    var text: String
    /// How the recognizer got it wrong.
    var heard: [String]
    /// Added by itself (the same fix twice), not by the user's yes.
    var auto: Bool
    var added: Date
}

struct ArisWordProposal: Codable, Equatable {
    var text: String
    var heard: String
    var count: Int
    var seen: Date
}

struct ArisLearnedDictionary: Codable, Equatable {
    static let limit = 100
    static let proposalLimit = 20
    static let autoAddAfter = 2
    private static let heardLimit = 5
    private static let dismissedLimit = 200

    var words: [ArisLearnedWord] = []
    var proposals: [ArisWordProposal] = []
    /// Words the user said no to or deleted.
    var dismissed: [String] = []

    enum Outcome: Equatable { case proposed, added, known, ignored, full }

    init() {}

    /// A list missing from the file reads as empty, so later fields never break an older file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        words = try container.decodeIfPresent([ArisLearnedWord].self, forKey: .words) ?? []
        proposals = try container.decodeIfPresent([ArisWordProposal].self, forKey: .proposals) ?? []
        dismissed = try container.decodeIfPresent([String].self, forKey: .dismissed) ?? []
    }

    /// The words, as the recognizer's hints.
    var texts: [String] { words.map(\.text) }

    /// The user changed `heard` (what Aris typed) to `meant`.
    mutating func record(heard: String, meant: String, at date: Date) -> Outcome {
        guard !dismissed.contains(meant) else { return .ignored }
        if let index = words.firstIndex(where: { $0.text == meant }) {
            if !words[index].heard.contains(where: { $0.caseInsensitiveCompare(heard) == .orderedSame }) {
                words[index].heard = Array((words[index].heard + [heard]).suffix(Self.heardLimit))
            }
            return .known
        }
        if let index = proposals.firstIndex(where: { $0.text == meant && $0.heard.caseInsensitiveCompare(heard) == .orderedSame }) {
            proposals[index].count += 1
            proposals[index].seen = date
            guard proposals[index].count >= Self.autoAddAfter else { return .proposed }
            guard words.count < Self.limit else { return .full }
            proposals.remove(at: index)
            words.append(ArisLearnedWord(text: meant, heard: [heard], auto: true, added: date))
            return .added
        }
        proposals.append(ArisWordProposal(text: meant, heard: heard, count: 1, seen: date))
        if proposals.count > Self.proposalLimit { proposals.removeFirst(proposals.count - Self.proposalLimit) }
        return .proposed
    }

    /// The user's yes to a proposal; false when there's none for `text` or the dictionary is full.
    mutating func accept(_ text: String, at date: Date) -> Bool {
        guard let index = proposals.firstIndex(where: { $0.text == text }), words.count < Self.limit else { return false }
        let proposal = proposals.remove(at: index)
        words.append(ArisLearnedWord(text: text, heard: [proposal.heard], auto: false, added: date))
        return true
    }

    mutating func dismiss(_ text: String) {
        proposals.removeAll { $0.text == text }
        remember(text)
    }

    mutating func remove(_ text: String) {
        words.removeAll { $0.text == text }
        remember(text)
    }

    private mutating func remember(_ text: String) {
        guard !dismissed.contains(text) else { return }
        dismissed = Array((dismissed + [text]).suffix(Self.dismissedLimit))
    }

    // MARK: - The file

    static func file(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/aris/aris/dictionary.json")
    }

    /// What's saved, or an empty dictionary (no file, or one that doesn't read).
    static func load(from file: URL) -> ArisLearnedDictionary {
        guard let data = try? Data(contentsOf: file) else { return ArisLearnedDictionary() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var dictionary = try? decoder.decode(ArisLearnedDictionary.self, from: data) else { return ArisLearnedDictionary() }
        dictionary.words = Array(dictionary.words.prefix(limit))
        return dictionary
    }

    /// Written whole (atomically), readable only by the user. False when it couldn't be.
    func save(to file: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return false }
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return true
        } catch {
            return false
        }
    }
}
