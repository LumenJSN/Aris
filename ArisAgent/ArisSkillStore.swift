//
//  ArisSkillStore.swift
//  aris-agent
//
//  What Aris knows about the user's skills, kept in its own folder (~/.config/aris/aris/skills.json, 0600): whether the
//  feature is on, and per skill its name, the title and line the user sees, where it came from, whether it's switched on,
//  the safety check's verdict with its findings, the fingerprint of the files that verdict was for, and which AIs it
//  was tried on. The skills themselves live in ~/Library/Application Support/Aris/Skills/<name>/. Pure apart from the file.
//

import Foundation

enum ArisSkillVerdict: String, Codable, Equatable {
    /// Not checked yet (or its files changed since).
    case unscanned
    case safe
    /// Findings the user should see; added only on their 그래도 추가.
    case caution
    /// Never added.
    case danger
}

/// One finding or one thing the check confirmed, in the user's words, with the file it is about.
struct ArisSkillFinding: Codable, Equatable {
    let text: String
    /// A path in the skill, or "전체".
    let file: String
    /// The reviewer's own word on the internet: true when the line is about reaching it, false when it confirmed the
    /// file stays on this Mac, nil when it didn't say (a line of the static scan, or a record made before this).
    var net: Bool? = nil

    /// As the app reads it (POST /skills).
    var json: [String: Any] {
        var object: [String: Any] = ["text": text, "file": file]
        if let net { object["net"] = net }
        return object
    }
}

/// One AI the skill was tried on ("모든 AI로 시험").
struct ArisSkillTrial: Codable, Equatable {
    let brain: String
    let model: String
    let ok: Bool
    let at: Date
}

struct ArisSkillRecord: Codable, Equatable {
    var name: String
    /// Its folder's name under Skills/ (the name, unless the user dropped a folder named otherwise).
    var folder: String
    var title: String
    /// One line on what it does (from the check's AI review, in Korean), or the description cut.
    var summary: String
    /// "folder", "github", "made" (말로 만들기) or "builtin".
    var source: String
    /// The link it came from, the GitHub owner, its version.
    var origin: String?
    var owner: String?
    var version: String?
    var enabled: Bool
    var verdict: ArisSkillVerdict
    /// The user's 그래도 추가 for a caution, and the findings they saw then (a rescan keeps it only for exactly those).
    var accepted: Bool
    var acceptedFindings: [ArisSkillFinding]?
    /// The files the check's reviewer saw whole: `skill read` and `skill run` serve only these (nil only for a built-in
    /// skill, which is Aris's own).
    var reviewed: [String]?

    /// Whether a brain may be given `path` of this skill.
    func serves(_ path: String) -> Bool { source == "builtin" || reviewed?.contains(path) == true }
    var findings: [ArisSkillFinding]
    var checked: [ArisSkillFinding]
    /// The files the verdict is for (ArisSkillFolder.fingerprint).
    var fingerprint: String?
    var scannedAt: Date?
    var tested: [ArisSkillTrial]
    var addedAt: Date

    /// Whether a brain may see it: switched on, checked for exactly these files, and safe (a caution only once the user
    /// added it anyway; a built-in skill is Aris's own).
    func usable(currentFingerprint: String?) -> Bool {
        guard enabled, let fingerprint, fingerprint == currentFingerprint else { return false }
        switch verdict {
        case .safe: return true
        case .caution: return accepted
        case .danger, .unscanned: return source == "builtin" && verdict != .danger
        }
    }
}

struct ArisSkillState: Codable, Equatable {
    /// 스킬 기능: off until the user says yes (its runtime is installed then).
    var enabled = false
    /// The brain the owner chose last (the check's AI review runs on it when files change on their own).
    var reviewBrain: String?
    /// Aris already asked "스킬 기능을 켤까요?" once and the user said 나중에.
    var deferred = false
    var skills: [ArisSkillRecord] = []

    func record(_ name: String) -> ArisSkillRecord? { skills.first { $0.name == name } }

    /// The record put in (replacing one of the same name).
    func with(_ record: ArisSkillRecord) -> ArisSkillState {
        var copy = self
        copy.skills.removeAll { $0.name == record.name }
        copy.skills.append(record)
        copy.skills.sort { $0.addedAt < $1.addedAt }
        return copy
    }

    func without(_ name: String) -> ArisSkillState {
        var copy = self
        copy.skills.removeAll { $0.name == name }
        return copy
    }
}

enum ArisSkillStore {
    static func file(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/aris/aris/skills.json")
    }

    /// The skills folder the user sees in Finder and the setup's runtime, both in Application Support (outside the app's container).
    static func skillsFolder(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Aris/Skills", isDirectory: true)
    }

    static func runtimeFolder(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Aris/skills-runtime", isDirectory: true)
    }

    private static let lock = NSLock()

    static func load(_ file: URL) -> ArisSkillState {
        lock.withLock { read(file) }
    }

    static let sizeLimit = 4 * 1_048_576

    /// The state, with what can't be read kept aside (ArisPrivateFile.setAside, skills.json.bad, the user told once) rather
    /// than lost at the next write: a record that doesn't decode is left out of the list; a file that isn't the
    /// state at all is kept whole. `writable`: false when what couldn't be read also couldn't be kept aside, so the
    /// file must not be written over.
    static func salvage(_ data: Data, file: URL) -> (state: ArisSkillState, writable: Bool) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if data.count <= sizeLimit, let state = try? decoder.decode(ArisSkillState.self, from: data) { return (state, true) }
        var state = ArisSkillState()
        var bad: [Any] = []
        if data.count <= sizeLimit, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            state.enabled = object["enabled"] as? Bool ?? false
            state.reviewBrain = object["reviewBrain"] as? String
            state.deferred = object["deferred"] as? Bool ?? false
            for entry in object["skills"] as? [Any] ?? [] {
                if JSONSerialization.isValidJSONObject(entry), let one = try? JSONSerialization.data(withJSONObject: entry),
                   let record = try? decoder.decode(ArisSkillRecord.self, from: one) {
                    state.skills.append(record)
                } else {
                    bad.append(entry)
                }
            }
            if object["skills"] != nil, !(object["skills"] is [Any]) { bad.append(["skills": object["skills"] ?? NSNull()]) }
        } else {
            bad.append(["unreadable store": String(decoding: data.prefix(sizeLimit), as: UTF8.self)])
        }
        guard !bad.isEmpty else { return (state, true) }
        guard let kept = ArisPrivateFile.setAside(bad, beside: file) else { return (state, false) }
        if kept > 0 { ArisPrivateFile.reportSetAside(kept, what: "스킬", file: file) }
        return (state, true)
    }

    private static func read(_ file: URL) -> ArisSkillState {
        readForChange(file).state
    }

    private static func readForChange(_ file: URL) -> (state: ArisSkillState, writable: Bool) {
        guard let data = FileManager.default.contents(atPath: file.path), !data.isEmpty else { return (ArisSkillState(), true) }
        return salvage(data, file: file)
    }

    /// Reads, changes and writes under one lock; returns what was written (a file that can't be read and couldn't be
    /// kept aside is left as it is).
    @discardableResult
    static func update(_ file: URL, _ change: (ArisSkillState) -> ArisSkillState) -> ArisSkillState {
        lock.withLock {
            let current = readForChange(file)
            let next = change(current.state)
            guard current.writable else {
                try? FileHandle.standardError.write(contentsOf: Data("aris-agent: \(file.lastPathComponent) can't be read and couldn't be kept aside: left as it is\n".utf8))
                return next
            }
            write(next, to: file)
            return next
        }
    }

    private static func write(_ state: ArisSkillState, to file: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let temporary = file.deletingLastPathComponent().appendingPathComponent(".skills.\(UUID().uuidString.prefix(6))")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
        if rename(temporary.path, file.path) != 0 { try? FileManager.default.removeItem(at: temporary) }
    }
}
