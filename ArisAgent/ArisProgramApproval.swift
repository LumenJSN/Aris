//
//  ArisProgramApproval.swift
//  aris-agent
//
//  The AI programs Aris starts (claude, codex, agy) are found in the user's own folders (~/.local/bin first), where any
//  of their programs can write, and whatever is found runs as the helper's child with everything Aris was granted
//  (security review 4, H1). So the helper writes down what it started the first time an AI is used, and looks again
//  at every start, in the one place all its starts go through (ArisChildren):
//
//   · a signed program (the native Claude Code, the Codex inside ChatGPT.app): its signing team and identifier. An
//     update by the same signer runs without a question, wherever its new file is. A different signer, or a signed
//     program that is unsigned now, is not started: the notch says "Claude Code가 바뀌었어요. 계속 쓸까요?" with a button,
//     and only the Aris app's own press of it accepts the new one;
//   · an unsigned one (an npm-installed launcher script, a Homebrew build): where it really is and whose it is. It is
//     asked about again only when its real file moves to another install folder (a new version's folder of the same
//     install is the same folder) or becomes writable by others.
//
//  What this cannot close: another program of the same user can still change an unsigned launcher in place, or this
//  list itself. A signed program's file is verified whenever its size or date differ from what was written down.
//
//  A loose copy of the helper (a developer's build, the tests) keeps no list and asks nothing.
//  The rule is pure (tested); the probes read the file's place, owner and signature, never its content.
//

import Foundation
import Security

/// What is known about one AI program's file.
struct ArisProgramFacts: Codable, Equatable {
    /// Where it was found, and the real file behind any links.
    var path: String
    var real: String
    var size: Int64
    var modified: Double
    /// Of the real file.
    var owner: UInt32
    var mode: UInt16
    /// Its signing team and identifier, when it is validly signed by a team (ad-hoc and unsigned: nil).
    var team: String?
    var identifier: String?

    var isSigned: Bool { !(team ?? "").isEmpty }
}

enum ArisProgramApproval {
    /// Why a program is not started without a yes.
    enum Reason: String, Equatable {
        /// Signed by someone else than before.
        case signer
        /// It was signed and is not any more.
        case unsigned
        /// An unsigned program whose real file is in another install folder now (or that is signed now, by anyone).
        case moved
        /// An unsigned program that others can write.
        case writable
    }

    enum Verdict: Equatable {
        /// What was approved, unchanged in what counts.
        case run
        /// Run, and write down what is there now (the first use, or an update that needs no question).
        case record
        case ask(Reason)
    }

    /// The AI a program's file name stands for; nil for any other program.
    static func brain(ofProgram path: String) -> ArisBrain? {
        switch (path as NSString).lastPathComponent {
        case "claude": return .claude
        case "codex": return .codex
        case "agy": return .antigravity
        default: return nil
        }
    }

    /// The folder an install lives in, with each version-numbered part made the same ("…/Cellar/codex/0.42.0/bin",
    /// "…/claude/versions", "…/node/v22.1.0/lib/node_modules/…"): an update of the same install stays in "the same
    /// folder", a file somewhere else does not.
    static func installFolder(_ real: String) -> String {
        let parts = ((real as NSString).deletingLastPathComponent as NSString).pathComponents
        return NSString.path(withComponents: parts.map { isVersion($0) ? "*" : $0 })
    }

    /// "1.2.3", "v22.1.0", "0.42.0_1", "2.1.0-beta.3": digits and dots first, a digit in it, no letters before them
    /// but one "v".
    static func isVersion(_ part: String) -> Bool {
        let body = part.hasPrefix("v") ? String(part.dropFirst()) : part
        guard let first = body.first, first.isNumber, body.contains(".") else { return false }
        return body.allSatisfy { $0.isASCII && ($0.isNumber || $0.isLetter || $0 == "." || $0 == "_" || $0 == "-" || $0 == "+") }
    }

    /// Whether only the user (or root) can change the file.
    static func isOwnersOnly(_ facts: ArisProgramFacts, user: UInt32) -> Bool {
        (facts.owner == user || facts.owner == 0) && facts.mode & 0o022 == 0
    }

    /// The rule.
    static func verdict(approved: ArisProgramFacts?, now: ArisProgramFacts, user: UInt32) -> Verdict {
        guard let approved else { return .record }
        if approved.isSigned {
            guard now.isSigned else { return .ask(.unsigned) }
            guard now.team == approved.team, now.identifier == approved.identifier else { return .ask(.signer) }
            return now == approved ? .run : .record
        }
        if now.isSigned { return .ask(.moved) }
        guard installFolder(now.real) == installFolder(approved.real) else { return .ask(.moved) }
        guard isOwnersOnly(now, user: user) || !isOwnersOnly(approved, user: user) else { return .ask(.writable) }
        return now == approved ? .run : .record
    }

    /// The line the notch says when a changed program was not started, and the one a press of its button earns.
    static func changedLine(_ brain: ArisBrain, korean: Bool) -> String {
        korean ? "\(programName(brain))가 바뀌었어요. 계속 쓸까요?" : "\(programName(brain)) has changed. Keep using it?"
    }

    /// The program's own name, as its maker calls it.
    static func programName(_ brain: ArisBrain) -> String {
        switch brain {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        case .api: return "API"
        }
    }

    // MARK: The list (only inside an app)

    struct Changed: Error, Equatable {
        let brain: ArisBrain
        let reason: Reason
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var waiting: [String: (facts: ArisProgramFacts, reason: Reason)] = [:]

    /// In Aris's own data folder (which no AI may write: ArisProtectedPlaces).
    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris/approved-programs.json")
    }

    static func load(_ file: URL = file) -> [String: ArisProgramFacts] {
        guard let data = try? Data(contentsOf: file), data.count <= 65_536,
              let found = try? JSONDecoder().decode([String: ArisProgramFacts].self, from: data) else { return [:] }
        return found
    }

    static func save(_ list: [String: ArisProgramFacts], to file: URL = file) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(list) else { return false }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: file, options: .atomic)) != nil else { return false }
        return chmod(file.path, 0o600) == 0
    }

    /// Before the helper starts `executable`: nothing for a program that is no AI's, or for a loose copy of the
    /// helper. Throws when it is an AI's program that changed in a way that needs a yes.
    static func check(_ executable: URL?, app: String? = ArisAppBundle.path, file: URL = file,
                      probe: (String, ArisProgramFacts?) -> ArisProgramFacts? = probe, user: UInt32 = getuid(),
                      enforcing: Bool = ArisRollout.enforcing) throws {
        guard app != nil, let path = executable?.path, let brain = brain(ofProgram: path) else { return }
        try lock.withLock {
            var list = load(file)
            let approved = list[brain.rawValue]
            guard let now = probe(path, approved) else { return }
            switch verdict(approved: approved, now: now, user: user) {
            case .run:
                waiting[brain.rawValue] = nil
            case .record:
                waiting[brain.rawValue] = nil
                list[brain.rawValue] = now
                if !save(list, to: file) { FileHandle.standardError.write(Data("aris-agent: couldn't write down the \(brain.rawValue) program that was started\n".utf8)) }
            case .ask(let reason):
                // Until the new checks are enforced (ArisRollout) it is written down, started as before, and the list
                // keeps what was approved.
                guard enforcing else { return ArisRollout.wouldRefuse("starting \(brain.rawValue): its program changed (\(reason.rawValue))") }
                waiting[brain.rawValue] = (now, reason)
                FileHandle.standardError.write(Data("aris-agent: \(brain.rawValue) was not started: its program changed (\(reason.rawValue)); waiting for a yes in the notch\n".utf8))
                throw Changed(brain: brain, reason: reason)
            }
        }
    }

    /// Whether the last start of this AI was held back for a yes.
    static func isWaiting(_ brain: ArisBrain) -> Bool {
        lock.withLock { waiting[brain.rawValue] != nil }
    }

    /// The owner's yes (only the Aris app's own press reaches here): the program that was held back is written down
    /// as the approved one. False when nothing was waiting or the list could not be written.
    static func accept(_ brain: ArisBrain, file: URL = file) -> Bool {
        lock.withLock {
            guard let held = waiting[brain.rawValue] else { return false }
            var list = load(file)
            list[brain.rawValue] = held.facts
            guard save(list, to: file) else { return false }
            waiting[brain.rawValue] = nil
            return true
        }
    }

    // MARK: Probes

    /// The file's facts now. Its signature is verified when the file is new or its size or date differ from what was
    /// approved; an unchanged file keeps the signer that was verified then.
    static func probe(_ path: String, approved: ArisProgramFacts?) -> ArisProgramFacts? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        let real = String(cString: resolved)
        var info = stat()
        guard stat(real, &info) == 0 else { return nil }
        var facts = ArisProgramFacts(path: path, real: real, size: Int64(info.st_size),
                                     modified: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000,
                                     owner: info.st_uid, mode: UInt16(info.st_mode & 0o7777), team: nil, identifier: nil)
        if let approved, approved.real == real, approved.size == facts.size, approved.modified == facts.modified {
            facts.team = approved.team
            facts.identifier = approved.identifier
            return facts
        }
        let signer = signer(ofFile: real)
        facts.team = signer?.team
        facts.identifier = signer?.identifier
        return facts
    }

    /// The team and identifier a file is validly signed with; nil when it is unsigned, ad-hoc, or does not verify.
    static func signer(ofFile path: String) -> (team: String, identifier: String)? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let found = info as? [String: Any], let team = found[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
              let identifier = found[kSecCodeInfoIdentifier as String] as? String else { return nil }
        return (team, identifier)
    }
}
